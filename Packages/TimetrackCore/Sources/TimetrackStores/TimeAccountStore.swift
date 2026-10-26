import Foundation
import Observation
import TimetrackCore

/// Manual adjustments of the time account (WM2): opening balance (at most one) and dated corrections with a reason.
/// P15 (X3, contract 0.29.0): the adjustments are listed (newest first, paged) and can be deleted; the server answers a delete with the
/// recomputed account. Servers before 0.29.0 have no list (`listSupported == false`); then only the sums are known.
public struct AccountAdjustmentForm: Sendable, Equatable {
    public enum Field: Hashable, Sendable { case date, value, reason }

    public var kind: AccountAdjustmentInput.Kind
    public var date: LocalDay
    /// `h:mm`, negative with a minus sign.
    public var value: String
    public var reason: String

    public static let maxReasonLength = 200

    public init(kind: AccountAdjustmentInput.Kind, date: LocalDay, value: String = "", reason: String = "") {
        self.kind = kind
        self.date = date
        self.value = value
        self.reason = reason
    }

    public struct ValidationErrors: Error, Sendable, Equatable { public let fields: Set<Field> }

    public func build() -> Result<AccountAdjustmentInput, ValidationErrors> {
        var errors = Set<Field>()
        if LocalDays.parse(date) == nil { errors.insert(.date) }
        let seconds = DurationFormat.parse(value)
        if seconds == nil { errors.insert(.value) }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > Self.maxReasonLength { errors.insert(.reason) }
        guard errors.isEmpty, let seconds else { return .failure(ValidationErrors(fields: errors)) }
        return .success(AccountAdjustmentInput(kind: kind, date: date, seconds: seconds, reason: trimmed))
    }
}

@MainActor
@Observable
public final class TimeAccountStore {
    public private(set) var account: TimeAccount?
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var adjustments: [AccountAdjustment] = []
    public private(set) var adjustmentTotal = 0
    public private(set) var listSupported = true
    public private(set) var isLoadingMore = false
    /// Id of the adjustment being deleted (disables its row).
    public private(set) var deletingId: UUID?
    public static let pageSize = 50
    public var error: TimetrackError?
    public var onOutcome: StoreOutcomeHandler?
    /// Called after a booking (the app refreshes the balance shown on Today).
    public var onSaved: (@MainActor () -> Void)?

    private let client: APIClient

    public init(client: APIClient) { self.client = client }

    /// An opening balance can be set while none exists (`openingSeconds == 0`, like the PWA); the server rejects a second one with 409.
    public var canSetOpening: Bool { account.map { $0.accountStart == nil || $0.openingSeconds == 0 } ?? false }

    public var canLoadMore: Bool { listSupported && adjustments.count < adjustmentTotal }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            account = try await client.getTimeAccount()
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {}
        await loadAdjustments()
    }

    /// First page of the list. A 404 means an older server without the list (not an error); other failures keep the old list.
    public func loadAdjustments() async {
        do {
            let page = try await client.listAccountAdjustments(limit: Self.pageSize, offset: 0)
            adjustments = page.items
            adjustmentTotal = page.total
            listSupported = true
        } catch let failure as TimetrackError {
            if failure.status == 404 { listSupported = false; adjustments = []; adjustmentTotal = 0 }
            else if failure != .cancelled { error = failure }
        } catch {}
    }

    public func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.listAccountAdjustments(limit: Self.pageSize, offset: adjustments.count)
            let known = Set(adjustments.map(\.id))
            adjustments += page.items.filter { !known.contains($0.id) }
            adjustmentTotal = page.total
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {}
    }

    /// Deletes one adjustment; the server's recomputed account replaces the balance and the list is reloaded. Returns true on success.
    /// A 404 (already gone) reloads the list and reports the error once.
    @discardableResult
    public func delete(_ adjustment: AccountAdjustment) async -> Bool {
        guard deletingId == nil else { return false }
        deletingId = adjustment.id
        defer { deletingId = nil }
        do {
            account = try await client.deleteAccountAdjustment(id: adjustment.id)
            adjustments.removeAll { $0.id == adjustment.id }
            adjustmentTotal = max(0, adjustmentTotal - 1)
            error = nil
            onOutcome?(.deleted)
            onSaved?()
            await loadAdjustments()
            return true
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure; onOutcome?(.failed) }
            if failure.status == 404 { await loadAdjustments() }
            return false
        } catch {
            return false
        }
    }

    /// Books the adjustment; returns true on success. Validation errors are the caller's business (`form.build()`).
    @discardableResult
    public func book(_ form: AccountAdjustmentForm) async -> Bool {
        guard case .success(let input) = form.build(), !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            account = try await client.createAccountAdjustment(input)
            error = nil
            onOutcome?(.saved)
            onSaved?()
            await loadAdjustments()
            return true
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure; onOutcome?(.failed) }
            return false
        } catch {
            return false
        }
    }
}
