#if DEBUG
import BackgroundTasks
import Foundation
import ObjectiveC

/// Test hook for `BackgroundLaunchTests` (not compiled into release builds). The simulator never runs `BGTask`s, so this
/// captures the launch handlers the app really registers and then calls one the way BackgroundTasks does: from a background
/// queue, with a `BGAppRefreshTask`. A handler that inherited main-actor isolation traps right there
/// (`_dispatch_assert_queue_fail`, TestFlight builds 26 and 31).
///
/// `TT_DEV_BG_LAUNCH=<task identifier>`; the Darwin notification `completedPrefix + identifier` is posted when the handler
/// has called `setTaskCompleted`.
enum BackgroundLaunchSimulation {
    static let completedPrefix = "de.linolaske.timetrack.dev.bgtask-completed."
    private static var wanted: String? { ProcessInfo.processInfo.environment["TT_DEV_BG_LAUNCH"] }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (BGTask) -> Void] = [:]
    /// Never released: the fake task was not set up by `BGTask`'s own initializer, so its `dealloc` must not run.
    nonisolated(unsafe) private static var retained: [AnyObject] = []

    /// Must run before the app registers its first background task.
    static func captureHandlersIfRequested() {
        guard wanted != nil,
              let original = class_getInstanceMethod(BGTaskScheduler.self, NSSelectorFromString("registerForTaskWithIdentifier:usingQueue:launchHandler:")),
              let capture = class_getInstanceMethod(BGTaskScheduler.self, #selector(BGTaskScheduler.tt_register(identifier:queue:handler:)))
        else { return }
        method_exchangeImplementations(original, capture)
    }

    /// Calls the captured handler off the main thread shortly after launch.
    static func runIfRequested() {
        guard let identifier = wanted else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            let handler = lock.withLock { handlers[identifier] }
            guard let handler, let task = makeTask(identifier: identifier) else {
                NSLog("TT bg launch: no handler or task for %@", identifier)
                return
            }
            NSLog("TT bg launch: calling handler for %@", identifier)
            handler(task)
        }
    }

    static func store(_ handler: @escaping @Sendable (BGTask) -> Void, for identifier: String) {
        lock.withLock { handlers[identifier] = handler }
    }

    /// A `BGAppRefreshTask` subclass built at runtime (the class has no public initializer) that only records the calls.
    private static func makeTask(identifier: String) -> BGAppRefreshTask? {
        let name = "TTSimulatedRefreshTask"
        var cls: AnyClass? = NSClassFromString(name)
        if cls == nil, let new = objc_allocateClassPair(BGAppRefreshTask.self, name, 0) {
            let setExpiration: @convention(block) (AnyObject, AnyObject?) -> Void = { _, _ in }
            class_addMethod(new, NSSelectorFromString("setExpirationHandler:"), imp_implementationWithBlock(setExpiration), "v@:@?")
            let completed: @convention(block) (AnyObject, Bool) -> Void = { _, success in
                guard let id = wanted else { return }
                NSLog("TT bg launch: setTaskCompleted(%d)", success ? 1 : 0)
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                     CFNotificationName((completedPrefix + id) as CFString), nil, nil, true)
            }
            class_addMethod(new, NSSelectorFromString("setTaskCompletedWithSuccess:"), imp_implementationWithBlock(completed), "v@:B")
            objc_registerClassPair(new)
            cls = new
        }
        guard let cls, let instance = class_createInstance(cls, 0) as AnyObject? else { return nil }
        lock.withLock { retained.append(instance) }
        return unsafeDowncast(instance, to: BGAppRefreshTask.self)
    }
}

extension BGTaskScheduler {
    /// Swapped with `register(forTaskWithIdentifier:using:launchHandler:)`; the inner call reaches the original.
    @objc fileprivate dynamic func tt_register(identifier: String, queue: DispatchQueue?, handler: @escaping @Sendable (BGTask) -> Void) -> Bool {
        BackgroundLaunchSimulation.store(handler, for: identifier)
        return tt_register(identifier: identifier, queue: queue, handler: handler)
    }
}
#endif
