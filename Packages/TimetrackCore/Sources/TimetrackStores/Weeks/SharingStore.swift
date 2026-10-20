import Foundation
import Observation
import TimetrackCore

/// State of the plan shares (PL1, module `planning`): outgoing shares with their scopes, shares given to this account, and the
/// read-only view of one incoming share. Everything is private unless a scope is switched on; revoking acts at once.
@MainActor
@Observable
public final class SharingStore {
    public private(set) var outgoing: [Share] = []
    public private(set) var incoming: [IncomingShare] = []
    public private(set) var isLoading = false
    public private(set) var isBusy = false
    public private(set) var isUnavailable = false
    public private(set) var formProblem: ShareFormProblem?
    public var error: TimetrackError?

    // Incoming view
    public private(set) var selected: IncomingShare?
    public private(set) var view: SharedView?
    public private(set) var viewIsLoading = false
    public private(set) var rangeInvalid = false
    /// The selected share was revoked or is gone (404 on the view).
    public private(set) var viewGone = false
    public var viewError: TimetrackError?
    public var from: LocalDay
    public var to: LocalDay

    public var onOutcome: StoreOutcomeHandler?
    private let client: APIClient
    public let calendar: DayCalendar
    private let ownHandle: String?

    public init(client: APIClient, calendar: DayCalendar, ownHandle: String?, now: Date = .now) {
        self.client = client
        self.calendar = calendar
        self.ownHandle = ownHandle
        let monday = LocalDays.mondayOfWeek(containing: calendar.day(for: now)) ?? calendar.day(for: now)
        self.from = monday
        self.to = LocalDays.adding(27, to: monday) ?? monday
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let own = client.listShares()
            async let given = client.listIncomingShares()
            outgoing = try await own
            incoming = try await given
            isUnavailable = false
            error = nil
            if let selected, !incoming.contains(where: { $0.id == selected.id }) { clearSelection(gone: true) }
        } catch let failure as TimetrackError {
            guard failure != .cancelled else { return }
            if failure.status == 404, failure.knownCode != .moduleDisabled { isUnavailable = true } else { error = failure }
        } catch {
            return
        }
    }

    // MARK: Outgoing

    /// Creates a share; returns whether it worked. Local checks first (empty name, own account, no scope).
    @discardableResult
    public func create(handle: String, scopes: ShareScopes) async -> Bool {
        formProblem = SharePolicy.problem(handle: handle, scopes: scopes, ownHandle: ownHandle)
        guard formProblem == nil, !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.createShare(ShareCreateInput(recipientHandle: handle.trimmingCharacters(in: .whitespacesAndNewlines), scopes: scopes))
            error = nil
            onOutcome?(.saved)
            outgoing = (try? await client.listShares()) ?? outgoing
            return true
        } catch {
            fail(error)
            return false
        }
    }

    /// Switches one scope of a share; reloads the list when the server refuses so the switch shows the real state.
    public func setScope(_ scope: ShareScopes.Scope, to value: Bool, of share: Share) async {
        guard !isBusy else { return }
        var scopes = share.scopes
        scopes[scope] = value
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await client.updateShare(id: share.id, scopes: scopes)
            if let index = outgoing.firstIndex(where: { $0.id == share.id }) { outgoing[index] = updated }
            error = nil
            onOutcome?(.saved)
        } catch {
            fail(error)
            outgoing = (try? await client.listShares()) ?? outgoing
        }
    }

    @discardableResult
    public func revoke(_ share: Share) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.revokeShare(id: share.id)
            outgoing.removeAll { $0.id == share.id }
            error = nil
            onOutcome?(.saved)
            return true
        } catch let failure as TimetrackError where failure.status == 404 {
            // Already gone: the list was stale.
            outgoing.removeAll { $0.id == share.id }
            return true
        } catch {
            fail(error)
            return false
        }
    }

    // MARK: Incoming view

    public func select(_ share: IncomingShare) async {
        selected = share
        view = nil
        viewGone = false
        viewError = nil
        await loadView()
    }

    public func closeSelection() { clearSelection(gone: false) }

    public func loadView() async {
        guard let selected else { return }
        viewError = nil
        rangeInvalid = !(LocalDays.daysBetween(from, to).map { $0 >= 0 } ?? false)
        guard !rangeInvalid else { return }
        viewIsLoading = true
        defer { viewIsLoading = false }
        do {
            view = try await client.viewShared(shareId: selected.id, from: from, to: to)
        } catch let failure as TimetrackError {
            guard failure != .cancelled else { return }
            view = nil
            if failure.status == 404 {
                // Revoked at once: the share disappears from the list as well.
                clearSelection(gone: true)
                incoming.removeAll { $0.id == selected.id }
            } else {
                viewError = failure
            }
        } catch {
            return
        }
    }

    private func clearSelection(gone: Bool) {
        selected = nil
        view = nil
        viewGone = gone
    }

    private func fail(_ error: Error) {
        guard let failure = error as? TimetrackError, failure != .cancelled else { return }
        self.error = failure
        onOutcome?(.failed)
    }
}
