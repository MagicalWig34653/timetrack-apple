import SwiftUI
import TimetrackCore
import TimetrackDesign

// SET-A: look of the settings landing, shared by iOS (pushed pages) and macOS (sidebar selection).
// Group heading: bold text with a rule below (like the web app). Entry: title, one-line description (two lines at most) and a disclosure arrow.
// No side borders or accent bars (docs/DESIGN.md): emphasis only through weight, colour and background.

struct SettingsGroupHeading: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Text(verbatim: title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TT.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Divider().overlay(TT.separator)
        }
    }
}

/// One entry row: title, description and the trailing arrow (`chevron.right`, or `arrow.up.right` for entries that leave the app).
struct SettingsEntryLabel: View {
    let entry: SettingsEntry
    var value: String?
    var chevron = "chevron.right"

    var body: some View {
        HStack(spacing: TT.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.title).font(TTFont.body.weight(.medium)).foregroundStyle(TT.textPrimary)
                Text(verbatim: entry.description).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    .lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: TT.Space.s)
            if let value { Text(verbatim: value).font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(1) }
            Image(systemName: chevron).font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(.rect)
    }
}

/// All groups: heading, rule, then the entries as rows of one list card.
struct SettingsGroupsView<Row: View>: View {
    let groups: [SettingsGroup]
    @ViewBuilder let row: (SettingsEntry) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.xl) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: TT.Space.s) {
                    SettingsGroupHeading(title: group.title)
                    ListCard {
                        ForEach(group.entries) { entry in row(entry) }
                    }
                }
            }
            if groups.isEmpty {
                Text("Keine passende Einstellung gefunden.").font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
        }
    }
}

extension SettingsEntryID {
    /// UI-test identifiers (kept from before SET-A where a row already had one).
    var accessibilityID: String {
        switch self {
        case .workModel: "settings.workmodel"
        case .accountTime: "settings.timeaccount"
        case .vacationEntitlement: "settings.vacation"
        case .modules: "settings.server"
        case .notifications: "settings.push"
        case .calendarFeeds: "settings.feeds"
        case .deviceCalendar: "settings.calendar"
        case .overworkHints: "settings.overwork"
        case .vacationReminders: "settings.reminders"
        case .places: "settings.automation"
        case .focusFilter: "settings.focus"
        case .triggerLinks: "settings.triggerlinks"
        case .appleWatch: "settings.watch.send"
        default: "settings.\(rawValue)"
        }
    }
}
