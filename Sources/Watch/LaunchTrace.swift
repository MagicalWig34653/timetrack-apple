import Foundation
import OSLog
import TimetrackCore

/// Launch timing for the watch app (A12). Logs `+<ms since process start> <event>` to the unified log
/// (subsystem `de.linolaske.timetrack`, category `launch`) so cold/warm launches can be measured with
/// `xcrun simctl spawn <udid> log stream --predicate 'subsystem == "de.linolaske.timetrack"'`.
/// Only event names and durations are logged, never URLs with ids, cookies or account data.
enum LaunchTrace {
    private static let logger = Logger(subsystem: "de.linolaske.timetrack", category: "launch")
    private static let marks = Marks()

    /// Seconds since the process was created by the kernel (includes dyld and static initialisers).
    static var sinceProcessStart: TimeInterval {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return 0 }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return Date().timeIntervalSince1970 - started
    }

    /// Logs an event once per name (SwiftUI may evaluate the same hook many times).
    static func mark(_ event: String) {
        guard marks.insert(event) else { return }
        logger.notice("+\(Int(sinceProcessStart * 1000), privacy: .public)ms \(event, privacy: .public)")
    }

    /// Free-form event, logged every time (background refresh, queue).
    static func event(_ text: String) {
        logger.notice("+\(Int(sinceProcessStart * 1000), privacy: .public)ms \(text, privacy: .public)")
    }

    static func network(_ label: String, milliseconds: Int, status: Int) {
        logger.notice("net \(label, privacy: .public) \(milliseconds, privacy: .public)ms status=\(status, privacy: .public) at +\(Int(sinceProcessStart * 1000), privacy: .public)ms")
    }

    private final class Marks: @unchecked Sendable {
        private let lock = NSLock()
        private var seen = Set<String>()
        func insert(_ event: String) -> Bool { lock.withLock { seen.insert(event).inserted } }
    }
}

/// Logs path (without query) and duration of every request; wraps the real transport.
struct TracingTransport: HTTPTransport, SessionCookieJar {
    let base: URLSessionTransport

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let started = ContinuousClock.now
        let label = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "?")"
        do {
            let result = try await base.send(request)
            LaunchTrace.network(label, milliseconds: Self.ms(since: started), status: result.1.statusCode)
            return result
        } catch {
            LaunchTrace.network(label, milliseconds: Self.ms(since: started), status: -1)
            throw error
        }
    }

    private static func ms(since start: ContinuousClock.Instant) -> Int {
        let d = start.duration(to: .now)
        return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }

    func sessionCookieValue(for baseURL: URL) -> String? { base.sessionCookieValue(for: baseURL) }
    func setSessionCookie(_ value: String, for baseURL: URL) { base.setSessionCookie(value, for: baseURL) }
    func clearSessionCookie(for baseURL: URL) { base.clearSessionCookie(for: baseURL) }
}
