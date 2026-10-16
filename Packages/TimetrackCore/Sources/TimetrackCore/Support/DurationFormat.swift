import Foundation

/// Display formatting for whole seconds. This is presentation only; evaluation and rounding stay in the backend.
public enum DurationFormat {
    /// 27720 -> "7:42"; negative keeps the sign: -1080 -> "-0:18"; sub-minute remainders are truncated (like the PWA).
    public static func hoursMinutes(_ seconds: Int) -> String {
        let totalMinutes = abs(seconds) / 60
        let sign = seconds < 0 && totalMinutes > 0 ? "-" : ""
        return "\(sign)\(totalMinutes / 60):\(String(format: "%02d", totalMinutes % 60))"
    }

    /// Like `hoursMinutes` with an explicit "+" for positive values (balances and deltas).
    public static func signed(_ seconds: Int) -> String {
        let text = hoursMinutes(seconds)
        return seconds > 0 && !text.hasPrefix("-") ? "+\(text)" : text
    }

    /// Running clock `h:mm:ss`, never negative.
    public static func clock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return "\(value / 3600):\(String(format: "%02d", value % 3600 / 60)):\(String(format: "%02d", value % 60))"
    }

    /// Parses "7:42", "-0:18", "+1:05" or a bare minute count ("45"). Decimal hours are rejected deliberately.
    public static func parse(_ input: String) -> Int? {
        let text = input.trimmingCharacters(in: .whitespaces)
        let pattern = #/^([+-])?(\d{1,4}):([0-5]\d)$|^([+-])?(\d{1,5})$/#
        guard let match = try? pattern.wholeMatch(in: text) else { return nil }
        if let hours = match.output.2, let minutes = match.output.3 {
            let sign = match.output.1 == "-" ? -1 : 1
            return sign * ((Int(hours) ?? 0) * 3600 + (Int(minutes) ?? 0) * 60)
        }
        guard let bare = match.output.5 else { return nil }
        return (match.output.4 == "-" ? -1 : 1) * (Int(bare) ?? 0) * 60
    }
}

/// Elapsed time of a running segment for display; the caller supplies `now` (a `TimelineView` tick in the UI).
public struct RunningTimerDisplay: Sendable, Hashable {
    public let startedAt: Date

    public init(startedAt: Date) { self.startedAt = startedAt }

    public func elapsedSeconds(at now: Date) -> Int { max(0, Int(now.timeIntervalSince(startedAt))) }
    public func clock(at now: Date) -> String { DurationFormat.clock(elapsedSeconds(at: now)) }
}
