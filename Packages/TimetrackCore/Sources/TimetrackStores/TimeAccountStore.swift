import Foundation
import Observation
import TimetrackCore

/// Manual adjustments of the time account (WM2): opening balance (at most one) and dated corrections with a reason.
/// The contract offers no list or delete endpoint for adjustments: only the sums (`openingSeconds`, `adjustmentSeconds`) are known,
/// so this store shows those and appends new bookings; a booked correction is undone with a counter-booking.
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
    public var error: TimetrackError?
    public var onOutcome: StoreOutcomeHandler?
    /// Called after a booking (the app refreshes the balance shown on Today).
    public var onSaved: (@MainActor () -> Void)?

    private let client: APIClient

    public init(client: APIClient) { self.client = client }

    /// An opening balance can be set while none exists (`openingSeconds == 0`, like the PWA); the server rejects a second one with 409.
    public var canSetOpening: Bool { account.map { $0.accountStart == nil || $0.openingSeconds == 0 } ?? false }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            account = try await client.getTimeAccount()
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {}
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
            return true
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure; onOutcome?(.failed) }
            return false
        } catch {
            return false
        }
    }
}
