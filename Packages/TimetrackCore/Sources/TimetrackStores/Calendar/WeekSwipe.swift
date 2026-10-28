import Foundation

/// Decides whether a horizontal drag in the week zoom switches the week (V5). Pure, so the thresholds are testable.
public enum WeekSwipe {
    /// Distance in points a drag must travel (or be predicted to travel) before it counts.
    public static let commitDistance: Double = 70
    public static let predictedDistance: Double = 140
    /// A drag counts as horizontal only when it is clearly wider than tall; vertical scrolling never switches the week.
    public static let dominance: Double = 1.6

    /// Week shift for a finished drag: +1 (next week, finger moved left), -1 (previous week), nil (not a week swipe).
    public static func shift(translationX dx: Double, translationY dy: Double, predictedEndX: Double? = nil) -> Int? {
        guard abs(dx) > abs(dy) * dominance else { return nil }
        let predicted = predictedEndX ?? dx
        guard abs(dx) >= commitDistance || (abs(predicted) >= predictedDistance && abs(dx) >= 24) else { return nil }
        return dx < 0 ? 1 : -1
    }

    /// Whether a drag in progress is horizontal enough to move the content with the finger.
    public static func tracks(translationX dx: Double, translationY dy: Double) -> Bool {
        abs(dx) > 12 && abs(dx) > abs(dy) * dominance
    }
}
