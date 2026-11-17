import Foundation

/// X4: the platform's sign-out cleanup (automation token, queue and places; Focus state). It runs when the model goes from signed in
/// to signed out. Work of the next account calls `wait()` first, so the cleanup of account A never deletes what account B has just
/// set up; cleanups are chained, never concurrent.
@MainActor
public final class SignOutCleanup {
    private let work: @MainActor () async -> Void
    private var task: Task<Void, Never>?

    public init(_ work: @escaping @MainActor () async -> Void) {
        self.work = work
    }

    /// Feed every phase change (`AppModel.onPhaseChange` or a view's `onChange`).
    public func phaseChanged(from old: AppModel.Phase, to new: AppModel.Phase) {
        guard old == .signedIn, new == .signedOut else { return }
        run()
    }

    public func run() {
        let previous = task
        task = Task { [work] in await previous?.value; await work() }
    }

    public func wait() async { await task?.value }
}
