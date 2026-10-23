import SwiftUI
import TimetrackCore

extension Date {
    /// Wall-clock time in the work model's zone (`HH:mm`), independent of the watch's own zone.
    func clockText(in zone: TimeZone) -> String {
        formatted(Date.FormatStyle(timeZone: zone).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

extension SegmentKind {
    var titleKey: LocalizedStringKey {
        switch self {
        case .work, .unknown: "kind.work"
        case .travel: "kind.travel"
        case .school: "kind.school"
        }
    }

    /// Plain localized name for interpolation into other strings (same as `plainName` on iOS/macOS, H5).
    var plainName: String {
        switch self {
        case .work, .unknown: String(localized: "kind.work")
        case .travel: String(localized: "kind.travel")
        case .school: String(localized: "kind.school")
        }
    }

    var symbol: String {
        switch self {
        case .work, .unknown: "briefcase"
        case .travel: "car"
        case .school: "graduationcap"
        }
    }
}
