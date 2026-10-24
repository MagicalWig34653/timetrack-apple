import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// BH1: Berichtsheft (training report book), shared by iOS/iPadOS and macOS. Strings: table "Reports".

enum BH {
    static func s(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, tableName: "Reports", bundle: .main, value: key, comment: "")
        return args.isEmpty ? format : String(format: format, arguments: args)
    }
    static func t(_ key: String, _ args: CVarArg...) -> Text {
        let format = NSLocalizedString(key, tableName: "Reports", bundle: .main, value: key, comment: "")
        return Text(verbatim: args.isEmpty ? format : String(format: format, arguments: args))
    }
    static func plural(_ key: String, _ count: Int) -> String { s(count == 1 ? key + ".one" : key + ".other", count) }

    /// "1:30 h" for lists; zero stays visible as "0:00 h" because the time is optional but never hidden.
    static func hours(_ seconds: Int) -> String { s("duration.h", DurationFormat.hoursMinutes(seconds)) }
    static func spokenHours(_ seconds: Int) -> String { DurationFormat.spoken(seconds, locale: Locale(identifier: "de_DE")) }
}

/// One store per signed-in client, kept while the screen is left (the week stays selected).
@MainActor
final class ReportsStoreCache {
    static let shared = ReportsStoreCache()
    private var owner: ObjectIdentifier?
    private var store: ReportsStore?

    func store(_ client: APIClient, calendar: DayCalendar) -> ReportsStore {
        let id = ObjectIdentifier(client)
        if owner != id { owner = id; store = nil }
        if let store { return store }
        let created = ReportsStore(client: client, calendar: calendar)
        created.onOutcome = { TTHaptics.handle($0) }
        store = created
        return created
    }
}

/// Copies plain and rich text together, so the IHK portal gets the plain lines and rich editors keep the table.
@MainActor
enum ReportPasteboard {
    static func copy(plain: String, html: String) {
        #if os(iOS)
        UIPasteboard.general.setItems([["public.utf8-plain-text": plain, "public.html": html]], options: [.expirationDate: Date().addingTimeInterval(3600)])
        #else
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(plain, forType: .string)
        board.setString(html, forType: .html)
        #endif
    }
}

/// Week bar: previous/next, KW and range, jump back to this week.
struct ReportWeekBar: View {
    let week: ReportWeekRef
    let calendar: DayCalendar
    let isCurrent: Bool
    let previous: () -> Void
    let next: () -> Void
    let current: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: TT.Space.s) {
                Button { TTHaptics.play(.softTap); previous() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(.rect) }
                    .accessibilityLabel(BH.t("nav.previous")).accessibilityIdentifier("reports.previous")
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text(verbatim: week.title).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary).accessibilityIdentifier("reports.title")
                    Text(verbatim: weekRangeText(start: week.monday, end: week.sunday, calendar: calendar)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1).minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { TTHaptics.play(.softTap); next() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(.rect) }
                    .accessibilityLabel(BH.t("nav.next")).accessibilityIdentifier("reports.next")
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }
            .buttonStyle(.borderless)
            if !isCurrent {
                Button(action: current) { BH.t("nav.this_week").frame(minHeight: 44) }
                    .buttonStyle(.borderless).font(TTFont.meta).accessibilityIdentifier("reports.current")
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}

/// "Entwurf" / "Erledigt" marker of a week (only a marker; done weeks stay editable).
struct ReportStatusPicker: View {
    let status: ReportStatus
    let busy: Bool
    let change: (ReportStatus) -> Void

    var body: some View {
        Picker(selection: Binding(get: { status }, set: { change($0) })) {
            BH.t("status.draft").tag(ReportStatus.draft)
            BH.t("status.done").tag(ReportStatus.done)
        } label: { BH.t("status.label") }
        .pickerStyle(.segmented)
        .disabled(busy)
        .accessibilityIdentifier("reports.status")
    }
}

extension ReportStatus {
    var title: String { BH.s(self == .done ? "status.done" : "status.draft") }
}
