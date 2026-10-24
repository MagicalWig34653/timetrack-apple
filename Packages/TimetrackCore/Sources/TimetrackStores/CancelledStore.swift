import Foundation
import Observation
import TimetrackCore

/// Why a restore did not go through, in terms the UI explains in German.
public enum RestoreFailure: Equatable, Sendable {
    /// 409 `segment_overlap`: the time is taken by another (not cancelled) entry.
    case overlap
    /// 409 `timer_already_running`: the cancelled entry was a running timer and another one runs now.
    case timerRunning
    /// 409 `segment_not_cancelled` / 404 / 412: changed elsewhere; the list was reloaded.
    case changedElsewhere
    case other(TimetrackError)

    init(_ error: TimetrackError) {
        switch (error.status, error.knownCode) {
        case (_, .segmentOverlap?): self = .overlap
        case (_, .timerAlreadyRunning?): self = .timerRunning
        case (_, .segmentNotCancelled?), (404?, _), (412?, _), (_, .staleVersion?): self = .changedElsewhere
        default: self = .other(error)
        }
    }
}

/// SG1: the "Storniert" bin. Lists cancelled entries page by page, restores them and deletes them permanently (single or in bulk,
/// always with a dry-run count first; the confirmation itself is the view's job).
@MainActor
@Observable
public final class CancelledStore {
    public private(set) var items: [CancelledSegment] = []
    public private(set) var total = 0
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public var error: TimetrackError?
    public private(set) var restoreFailure: RestoreFailure?
    public var onOutcome: StoreOutcomeHandler?

    public static let pageSize = 50

    private let client: APIClient
    private var loadGeneration = 0

    public init(client: APIClient) { self.client = client }

    public var hasMore: Bool { items.count < total }
    public var isEmpty: Bool { hasLoaded && items.isEmpty }

    /// Reloads from the start, keeping as many pages as were already visible (so a restore does not collapse the list).
    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let limit = min(200, max(Self.pageSize, items.count))
            let page = try await client.listCancelledSegments(limit: limit, offset: 0)
            guard generation == loadGeneration else { return }
            items = page.items
            total = page.total
            hasLoaded = true
            error = nil
        } catch let failure as TimetrackError {
            if generation == loadGeneration, failure != .cancelled { error = failure }
        } catch {
            if generation == loadGeneration { self.error = .cancelled }
        }
    }

    public func loadMore() async {
        guard hasMore, !isLoading else { return }
        let generation = loadGeneration
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await client.listCancelledSegments(limit: Self.pageSize, offset: items.count)
            guard generation == loadGeneration else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            total = page.total
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {}
    }

    /// Lifts the cancellation of one entry. On a conflict the entry stays in the bin and `restoreFailure` says why.
    @discardableResult
    public func restore(_ item: CancelledSegment, reason: String? = nil) async -> Bool {
        restoreFailure = nil
        do {
            _ = try await client.restoreSegment(id: item.id, reason: reason, ifMatchVersion: item.segment.version)
            error = nil
            onOutcome?(.saved)
            await load()
            return true
        } catch let failure as TimetrackError {
            guard failure != .cancelled else { return false }
            let classified = RestoreFailure(failure)
            restoreFailure = classified
            if classified == .changedElsewhere { await load() }
            if case .other = classified { error = failure }
            onOutcome?(.failed)
        } catch {}
        return false
    }

    public func clearRestoreFailure() { restoreFailure = nil }

    /// How many records a deletion would remove, without deleting anything (`dryRun`). `nil` when the count could not be read.
    public func preview(_ scope: PurgeScope) async -> PurgeSummary? {
        do {
            let summary = try await client.purgeCancelledSegments(scope, dryRun: true)
            error = nil
            return summary
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {}
        return nil
    }

    /// Deletes permanently. Callers confirm first (typed word) and show the `preview` numbers. A single id uses the single-entry call.
    @discardableResult
    public func purge(_ scope: PurgeScope) async -> PurgeSummary? {
        do {
            let summary: PurgeSummary
            if case .ids(let ids) = scope, ids.count == 1, let only = ids.first {
                summary = try await client.purgeSegment(id: only)
            } else {
                summary = try await client.purgeCancelledSegments(scope, dryRun: false)
            }
            error = nil
            onOutcome?(.deleted)
            await load()
            return summary
        } catch let failure as TimetrackError {
            guard failure != .cancelled else { return nil }
            if failure.knownCode == .segmentNotCancelled { await load() } // changed elsewhere: show the current bin
            error = failure
            onOutcome?(.failed)
        } catch {}
        return nil
    }
}
