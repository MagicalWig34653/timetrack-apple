import Foundation

/// Thread-safe bridge between a `BGTask` and the async work done for it. BackgroundTasks calls the launch handler and the
/// expiration handler on arbitrary queues, so this type is deliberately not actor-isolated. It guarantees that
/// `setTaskCompleted` is called exactly once, whichever of "work finished" and "expired" happens first.
public final class BackgroundTaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let completeTask: @Sendable (Bool) -> Void
    private let onExpire: @Sendable () -> Void
    private var work: Task<Void, Never>?
    private var completed = false
    private var expired = false

    /// - Parameters:
    ///   - complete: Marks the system task as completed (`BGTask.setTaskCompleted`).
    ///   - onExpire: Extra work when the system revokes the time budget (for example rescheduling).
    public init(complete: @escaping @Sendable (Bool) -> Void, onExpire: @escaping @Sendable () -> Void = {}) {
        completeTask = complete
        self.onExpire = onExpire
    }

    /// Hands over the work so that an expiration cancels it. If the task already expired, the work is cancelled at once.
    public func attach(_ work: Task<Void, Never>) {
        let cancelNow = lock.withLock { () -> Bool in
            self.work = work
            return expired
        }
        if cancelNow { work.cancel() }
    }

    /// Called from the expiration handler: cancels the work and runs the extra expiry action.
    public func expire() {
        let work = lock.withLock { () -> Task<Void, Never>? in
            expired = true
            return self.work
        }
        work?.cancel()
        onExpire()
    }

    /// Completes the system task once; later calls (or a call after an expiration that completed it) do nothing.
    /// Returns whether this call was the one that completed the task.
    @discardableResult
    public func finish(success: Bool) -> Bool {
        let first = lock.withLock { () -> Bool in
            if completed { return false }
            completed = true
            return true
        }
        if first { completeTask(success) }
        return first
    }
}
