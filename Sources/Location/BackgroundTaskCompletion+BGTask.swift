import BackgroundTasks
import Foundation
import TimetrackCore

extension BackgroundTaskCompletion {
    /// Wraps a system task: `finish` calls `setTaskCompleted` exactly once.
    convenience init(_ task: BGTask, onExpire: @escaping @Sendable () -> Void = {}) {
        nonisolated(unsafe) let task = task // BGTask is documented as callable from any queue
        self.init(complete: { task.setTaskCompleted(success: $0) }, onExpire: onExpire)
    }
}
