import SwiftUI
import TimetrackCore
import TimetrackDesign

// Q1 wording for "why does this entry need a look", shared by the iOS sheet and the macOS screen (SG1 moved it here with `Q1.xcstrings`).

enum Q1 {
    static func s(_ key: String.LocalizationValue) -> String { String(localized: key, table: "Q1") }
    static func t(_ key: LocalizedStringKey) -> Text { Text(key, tableName: "Q1") }
}

extension ReviewReason {
    var titleKey: LocalizedStringKey {
        switch self {
        case .endMissingProposed: "q1.reason.proposed.title"
        case .endMissing: "q1.reason.end_missing.title"
        case .markedByAutomation: "q1.reason.marked.title"
        }
    }

    var symbol: String {
        switch self {
        case .endMissingProposed, .endMissing: "clock.badge.exclamationmark"
        case .markedByAutomation: "exclamationmark.circle"
        }
    }

    /// The plain-language explanation; `zone` formats the proposed end in the work model's time zone.
    func detail(zone: TimeZone) -> String {
        switch self {
        case .endMissingProposed(let end): Q1.s("q1.reason.proposed.detail \(end.clockText(in: zone))")
        case .endMissing: Q1.s("q1.reason.end_missing.detail")
        case .markedByAutomation: Q1.s("q1.reason.marked.detail")
        }
    }
}
