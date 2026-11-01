import AppKit
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// SET-B: the settings pages the Mac was missing after SET-A (same names and texts as iOS and the web app). Strings live in `AD1.xcstrings`.

/// Settings > "Urlaubsanspruch": figures at a glance, the full editor is the shared `VacationSettingsSheet` (also reachable from the Urlaub screen).
struct VacationEntitlementPage: View {
    @Environment(AppModel.self) private var model
    @State private var showingEditor = false
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                Text(verbatim: AD.s("set_b.vacation.intro")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                if let store = model.planning {
                    FormSection(LocalizedStringKey(AD.s("set_b.vacation.current"))) {
                        VStack(spacing: 0) {
                            row(AD.s("set_b.vacation.region"), VacationRegions.all.first { $0.code == store.settings?.region }?.name ?? "–")
                            row(AD.s("set_b.vacation.entitlement"), store.settings.map { Self.days($0.annualEntitlementHalfDays) } ?? "–")
                        }
                    }
                    Button { showingEditor = true } label: { Label(AD.s("set_b.vacation.edit"), systemImage: "slider.horizontal.3") }
                        .buttonStyle(.ttPrimary).disabled(!loaded)
                        .accessibilityIdentifier("settings.vacation.edit")
                }
            }
            .padding(TT.Space.xl).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("Urlaubsanspruch")
        .task {
            // Load before presenting: saving the sheet writes all fields, so it must start from the server values.
            guard let store = model.planning else { return }
            await store.load(); await store.loadSettings(); loaded = true
        }
        .sheet(isPresented: $showingEditor) {
            if let store = model.planning { VacationSettingsSheet(store: store) }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title).font(TTFont.body).foregroundStyle(TT.textPrimary)
            Spacer()
            Text(verbatim: value).font(TTFont.body).foregroundStyle(TT.textSecondary)
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .accessibilityElement(children: .combine)
    }

    /// Half days as shown to the user ("30 Tage", "12,5 Tage").
    static func days(_ halfDays: Int) -> String {
        let value = Double(halfDays) / 2
        let text = value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value).replacingOccurrences(of: ".", with: ",")
        return "\(text) Tage"
    }
}

/// Settings > "Fokus-Filter": the filter is an iOS feature (Focus filters configure an app per device). The page says so honestly and points to the
/// Mac counterpart instead of showing controls that would do nothing.
struct FocusFilterMacPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                Card {
                    HStack(alignment: .top, spacing: TT.Space.m) {
                        KindGlyph(symbol: "moon.circle", tint: TT.kindWork)
                        VStack(alignment: .leading, spacing: TT.Space.xs) {
                            Text(verbatim: AD.s("set_b.focus.title")).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                            Text(verbatim: AD.s("set_b.focus.body")).font(TTFont.body).foregroundStyle(TT.textSecondary)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: TT.Space.xs) {
                        Label(AD.s("set_b.focus.mac_title"), systemImage: "desktopcomputer").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                        Text(verbatim: AD.s("set_b.focus.mac_body")).font(TTFont.body).foregroundStyle(TT.textSecondary)
                    }
                }
            }
            .padding(TT.Space.xl).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("Fokus-Filter")
        .accessibilityIdentifier("settings.focus.mac")
    }
}

/// Settings > "Export": the export itself is a web page; this opens it in the browser (like the iOS row).
struct ExportPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                Text(verbatim: AD.s("set_b.export.body")).font(TTFont.body).foregroundStyle(TT.textSecondary)
                if let url = model.serverURL?.appending(path: "export") { // the PWA route of the page
                    Button { NSWorkspace.shared.open(url) } label: { Label(AD.s("set_b.export.open"), systemImage: "arrow.up.right") }
                        .buttonStyle(.ttPrimary).accessibilityIdentifier("settings.export.open")
                        .accessibilityHint(Text(verbatim: AD.s("set_b.export.hint")))
                }
            }
            .padding(TT.Space.xl).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("Export")
    }
}
