import Foundation
import Observation
import TimetrackCore

/// Work model versions and their correction (contract v0.16.0): list, preview of the impact on the account balance, save.
/// Corrections overwrite a version (also retroactively), so saving requires a successful preview of exactly the same input.
@MainActor
@Observable
public final class WorkModelStore {
    public enum PreviewState: Equatable, Sendable {
        case idle
        /// The form has invalid fields; no request was made.
        case invalid
        case loading
        case ready(WorkModelPreview)
        case failed(TimetrackError)
    }

    public private(set) var models: [WorkModel] = []
    /// P15: profiles to choose from; the built-in fallback until `loadProfiles()` succeeds (servers before contract 0.29.0 have no list).
    public private(set) var profiles: [LegalProfile] = LegalProfile.fallback
    /// True once the server delivered the profile list (rule details and sources are only then available).
    public private(set) var profilesFromServer = false
    public private(set) var isLoading = false
    public private(set) var preview: PreviewState = .idle
    public var error: TimetrackError?
    public var onOutcome: StoreOutcomeHandler?
    /// Called after a saved correction (the app refreshes its current work model, balances and days).
    public var onSaved: (@MainActor () -> Void)?

    private let client: APIClient
    private var previewTask: Task<Void, Never>?
    /// The input the current `.ready` preview was computed for.
    private var previewedInput: WorkModelInput?

    public init(client: APIClient) { self.client = client }

    /// Newest version first.
    public var newestFirst: [WorkModel] { models.sorted { $0.validFrom > $1.validFrom } }
    public var supportsCorrection: Bool { models.supportsCorrection }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            models = try await client.listWorkModels()
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {
            self.error = .cancelled
        }
    }

    /// Loads the legal profiles. A failure keeps the fallback list (the choice still works; the server validates the id on save).
    public func loadProfiles() async {
        do {
            let loaded = try await client.listLegalProfiles()
            guard !loaded.isEmpty else { return }
            profiles = loaded
            profilesFromServer = true
        } catch {}
    }

    public func profile(id: String) -> LegalProfile? { profiles.first { $0.id == id } }

    /// Debounced preview of `form` for `model` (the user keeps typing); a new call cancels the pending one.
    public func updatePreview(for model: WorkModel, form: WorkModelForm, debounce: Duration = .milliseconds(350)) {
        previewTask?.cancel()
        previewedInput = nil
        switch form.build() {
        case .failure:
            preview = .invalid
        case .success(let input):
            preview = .loading
            previewTask = Task { [client] in
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
                do {
                    let result = try await client.previewWorkModelCorrection(id: model.id, input)
                    guard !Task.isCancelled else { return }
                    previewedInput = input
                    preview = .ready(result)
                } catch let failure as TimetrackError {
                    guard !Task.isCancelled, failure != .cancelled else { return }
                    preview = .failed(failure)
                } catch {}
            }
        }
    }

    public func waitForPreview() async { await previewTask?.value }

    public func resetPreview() {
        previewTask?.cancel()
        previewedInput = nil
        preview = .idle
    }

    /// True when the preview shown belongs to the current input, i.e. saving may be offered (after the user confirmed).
    public func canSave(form: WorkModelForm) -> Bool {
        guard case .ready = preview, case .success(let input) = form.build() else { return false }
        return input == previewedInput
    }

    /// Saves the correction. Only with a matching successful preview; returns the stored version, on failure `error` is set.
    @discardableResult
    public func save(model: WorkModel, form: WorkModelForm) async -> WorkModel? {
        guard canSave(form: form), case .success(let input) = form.build() else { return nil }
        do {
            let stored = try await client.correctWorkModel(id: model.id, input, ifMatchVersion: model.version)
            error = nil
            onOutcome?(.saved)
            resetPreview()
            await load()
            onSaved?()
            return stored
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure; onOutcome?(.failed) }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - New version and ending (WM2)

    /// Creates a new open-ended version from the form (validated locally against the timeline first). The running predecessor is closed
    /// by the server on the day before. Returns the stored version; on failure `error` is set.
    @discardableResult
    public func create(form: WorkModelForm) async -> WorkModel? {
        guard case .success(var input) = form.build() else { return nil }
        input.validTo = nil
        if case .overlaps = models.checkNewVersion(validFrom: input.validFrom) {
            error = .api(status: 409, code: APIErrorCode.modelOverlap.rawValue, message: "")
            onOutcome?(.failed)
            return nil
        }
        do {
            let stored = try await client.createWorkModel(input)
            error = nil
            onOutcome?(.saved)
            await load()
            onSaved?()
            return stored
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure; onOutcome?(.failed) }
            return nil
        } catch {
            return nil
        }
    }

    /// Ends `model` on `day` (last valid day, inclusive). Local checks mirror the server; history stays untouched.
    @discardableResult
    public func end(_ model: WorkModel, on day: LocalDay) async -> WorkModel? {
        if let issue = models.checkEnd(of: model, on: day) {
            error = issue == .invalidDate || issue == .beforeStart ? .api(status: 400, code: APIErrorCode.invalid.rawValue, message: "")
                : .api(status: 409, code: APIErrorCode.modelOverlap.rawValue, message: "")
            onOutcome?(.failed)
            return nil
        }
        do {
            let stored = try await client.endWorkModel(id: model.id, validTo: day)
            error = nil
            onOutcome?(.saved)
            await load()
            onSaved?()
            return stored
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure; onOutcome?(.failed) }
            return nil
        } catch {
            return nil
        }
    }
}
