import Foundation
import Observation
import TimetrackCore

/// Editor state of one Berichtsheft entry with autosave (BH1). Every change starts a short debounce; then the entry is created
/// (first valid state: a learning field is set) or updated with its `version` (If-Match). The input is never dropped: a failed save
/// (offline, server error, conflict) keeps the text, shows the state and can be retried or resolved. Closing the editor calls
/// `flush()` first; only a state that is not `saved`/`idle` needs a decision from the user.
@MainActor
@Observable
public final class ReportEntryEditor {
    public enum SaveState: Equatable, Sendable {
        /// New entry, nothing to save yet (no learning field).
        case idle
        /// A change waits for the debounce.
        case pending
        case saving
        case saved
        /// Input fails a local check; nothing is sent.
        case invalid
        /// Saving failed; the input is kept. Retried on the next change or by `flush()`.
        case failed(TimetrackError)
        /// 412: the entry changed elsewhere. `current` is the server's version (nil if it could not be read).
        case conflict(current: ReportEntry?)
        /// 404 on update: the entry was deleted elsewhere.
        case gone
    }

    public struct Problems: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let fieldMissing = Problems(rawValue: 1)
        public static let fieldTooLong = Problems(rawValue: 2)
        public static let durationInvalid = Problems(rawValue: 4)
        public static let notesTooLong = Problems(rawValue: 8)
    }

    public static let maxFieldLength = 120
    public static let maxNotesLength = 4000

    public var date: LocalDay { didSet { if date != oldValue { inputChanged() } } }
    public var fieldName: String { didSet { if fieldName != oldValue { fieldNameChanged() } } }
    public private(set) var fieldId: UUID?
    public var durationText: String { didSet { if durationText != oldValue { inputChanged() } } }
    public var notes: String { didSet { if notes != oldValue { inputChanged() } } }
    public private(set) var entry: ReportEntry?
    public private(set) var state: SaveState
    public private(set) var lastSavedAt: Date?

    private let store: ReportsStore
    private let debounce: Duration
    private let sleeper: @Sendable (Duration) async throws -> Void
    private var lastSaved: ReportEntryInput?
    private var debounceTask: Task<Void, Never>?
    private var savingTask: Task<Void, Never>?
    private var applyingProgrammatically = false

    /// `entry == nil` starts a new entry on `day`.
    public init(store: ReportsStore, entry: ReportEntry?, day: LocalDay, debounce: Duration = .milliseconds(900),
                sleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.store = store
        self.entry = entry
        self.debounce = debounce
        self.sleeper = sleeper
        date = entry?.date ?? day
        fieldName = entry?.learningField ?? ""
        fieldId = entry?.learningFieldId
        durationText = entry.map { ReportDuration.inputValue($0.durationSeconds) } ?? ""
        notes = entry?.notes ?? ""
        lastSaved = entry?.input
        state = entry == nil ? .idle : .saved
    }

    public var isNew: Bool { entry == nil }

    // MARK: Validation

    public var parsedDuration: ReportDuration.Parsed? { ReportDuration.parse(durationText) }

    public var problems: Problems {
        var result: Problems = []
        let name = fieldName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { result.insert(.fieldMissing) }
        if name.count > Self.maxFieldLength { result.insert(.fieldTooLong) }
        if parsedDuration == nil { result.insert(.durationInvalid) }
        if notes.count > Self.maxNotesLength { result.insert(.notesTooLong) }
        return result
    }

    /// The input the editor would send now; nil while a local check fails.
    public var currentInput: ReportEntryInput? {
        guard problems.isEmpty, let duration = parsedDuration else { return nil }
        return ReportEntryInput(date: date, learningFieldId: fieldId, learningField: fieldName.trimmingCharacters(in: .whitespacesAndNewlines),
                                durationSeconds: duration.seconds, notes: notes)
    }

    /// True when something differs from what is stored (valid or not); a new entry with nothing typed has no changes.
    public var hasUnsavedChanges: Bool { hasEditedFields }

    private var hasEditedFields: Bool {
        guard entry != nil, let saved = lastSaved else {
            return !fieldName.isEmpty || !durationText.isEmpty || !notes.isEmpty
        }
        return fieldName.trimmingCharacters(in: .whitespacesAndNewlines) != saved.learningField
            || date != saved.date || notes != saved.notes || parsedDuration?.seconds != saved.durationSeconds
    }

    /// Matches typed text against the learning-field list; an exact (case-insensitive) hit links the field, anything else is free text.
    private func fieldNameChanged() {
        guard !applyingProgrammatically else { return }
        let typed = fieldName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        fieldId = typed.isEmpty ? nil : store.learningFields.first { $0.name.lowercased() == typed }?.id
        inputChanged()
    }

    /// Picks a field from the list (name and link together).
    public func select(_ field: LearningField) {
        applyingProgrammatically = true
        fieldName = field.name
        applyingProgrammatically = false
        fieldId = field.id
        inputChanged()
    }

    // MARK: Autosave

    /// Call after any input change (the property observers do it); restarts the debounce.
    public func inputChanged() {
        debounceTask?.cancel()
        debounceTask = nil
        guard !applyingProgrammatically else { return }
        switch state {
        case .conflict, .gone: return // resolved by the user first
        default: break
        }
        guard hasEditedFields else {
            if entry != nil { state = .saved }
            return
        }
        state = currentInput == nil ? .invalid : .pending
        guard currentInput != nil else { return }
        let wait = debounce
        let sleep = sleeper
        debounceTask = Task { [weak self] in
            do { try await sleep(wait) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Saves now (used by the debounce, by "Erneut versuchen" and before closing). Returns when nothing is pending any more.
    public func flush() async {
        debounceTask?.cancel()
        debounceTask = nil
        if let running = savingTask { await running.value }
        switch state {
        case .conflict, .gone: return
        default: break
        }
        let task = Task { await self.performSave() }
        savingTask = task
        await task.value
        savingTask = nil
    }

    private func performSave() async {
        while true {
            guard hasEditedFields else {
                state = entry == nil ? .idle : .saved
                return
            }
            guard let input = currentInput else {
                state = .invalid
                return
            }
            if input == lastSaved {
                state = entry == nil ? .idle : .saved
                return
            }
            state = .saving
            do {
                let stored = try await store.save(input, replacing: entry)
                entry = stored
                lastSaved = input
                lastSavedAt = .now
                if !hasEditedFields {
                    state = .saved
                    return
                }
                // The user kept typing while the request ran: go around once more.
            } catch let failure as TimetrackError {
                switch (failure.status, failure.knownCode) {
                case (412, _):
                    state = .conflict(current: nil)
                    if let entry { state = .conflict(current: await store.serverVersion(of: entry.id, on: entry.date)) }
                case (404, let code) where entry != nil && code != .moduleDisabled:
                    state = .gone
                default:
                    if failure != .cancelled { state = .failed(failure) }
                }
                return
            } catch {
                return
            }
        }
    }

    // MARK: Resolving problems

    /// Conflict: take the server's version and drop the local changes.
    public func useServerVersion() {
        guard case .conflict(let current) = state, let current else { return }
        apply(current)
        state = .saved
    }

    /// Conflict: keep the local input and save it over the server's version.
    public func keepMine() async {
        guard case .conflict(let current) = state else { return }
        var latest = current
        if latest == nil, let entry { latest = await store.serverVersion(of: entry.id, on: entry.date) }
        guard let latest else {
            state = .gone
            return
        }
        entry = latest
        lastSaved = latest.input
        state = .pending
        await flush()
    }

    /// Gone: store the local input as a new entry.
    public func saveAsNew() async {
        guard state == .gone else { return }
        entry = nil
        lastSaved = nil
        state = .pending
        await flush()
    }

    private func apply(_ source: ReportEntry) {
        applyingProgrammatically = true
        date = source.date
        fieldName = source.learningField
        durationText = ReportDuration.inputValue(source.durationSeconds)
        notes = source.notes
        applyingProgrammatically = false
        fieldId = source.learningFieldId
        entry = source
        lastSaved = source.input
    }

    /// Cancels pending work (the editor was discarded).
    public func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
    }
}
