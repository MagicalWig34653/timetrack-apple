import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// N2/P14c: "Kalenderabos" (ICS): subscriptions that show absences, holidays and optionally plan and tracked days in any calendar app.
/// Mirrors the web app's calendar-feed settings. The secret link is shown once after creating.
struct CalendarFeedsPage: View {
    @Environment(AppModel.self) private var model
    @State private var store: CalendarFeedsStore?
    @State private var showCreate = false
    @State private var revoking: CalendarFeed?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let store {
                    feedsSection(store)
                    Text("Ein Abo ist ein geheimer Link. Jeder, der ihn kennt, sieht diese Einträge, auch ohne Anmeldung. Gib ihn nicht weiter und widerrufe ihn, wenn er in falsche Hände geraten ist. Apple Kalender aktualisiert Abos meist stündlich; andere Dienste (zum Beispiel Google) brauchen oft Stunden bis Tage.")
                        .font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.s)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, TT.Space.xl)
                }
            }
            .p14cPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("Kalenderabos")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if store == nil, let client = model.apiClient { store = CalendarFeedsStore(client: client) }
            await store?.load()
        }
        .sheet(isPresented: $showCreate) {
            if let store { CalendarFeedCreateSheet(store: store) }
        }
        .sheet(item: Binding(get: { store?.created.map(CreatedSheetItem.init) }, set: { if $0 == nil { store?.dismissCreated() } })) { item in
            CalendarFeedLinkSheet(created: item.created) { store?.dismissCreated() }
        }
        .confirmationDialog(revoking.map { "Abo „\($0.label)“ widerrufen?" } ?? "", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible, presenting: revoking) { feed in
            Button("Widerrufen", role: .destructive) { Task { await store?.revoke(feed) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Der Link funktioniert danach nicht mehr. Kalender, die ihn abonniert haben, zeigen keine neuen Einträge mehr.")
        }
    }

    @ViewBuilder private func feedsSection(_ store: CalendarFeedsStore) -> some View {
        FormSection("Deine Abos", footer: store.canCreate ? nil : "Höchstens \(CalendarFeedsStore.maximum) aktive Abos. Widerrufe eines, um ein neues anzulegen.") {
            if store.hasLoaded, store.feeds.isEmpty {
                Text("Noch kein Abo. Lege eines an, um Urlaub und Feiertage in deinem Kalender zu sehen.")
                    .font(TTFont.body).foregroundStyle(TT.textSecondary)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("feeds.empty")
            }
            ForEach(store.feeds) { feed in
                feedRow(feed)
            }
            if let error = store.error {
                Text(verbatim: error.germanDescription).font(TTFont.meta).foregroundStyle(TT.danger)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("feeds.error")
            }
            Button { showCreate = true } label: { Label("Neues Abo", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.ttSecondary)
                .disabled(!store.canCreate)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier("feeds.new")
        }
    }

    private func feedRow(_ feed: CalendarFeed) -> some View {
        HStack(alignment: .top, spacing: TT.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: feed.label).font(TTFont.body).foregroundStyle(TT.textPrimary)
                Text(verbatim: feed.contentSummary).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                Text(verbatim: Self.usage(feed)).font(TTFont.meta).foregroundStyle(TT.textTertiary)
            }
            Spacer(minLength: TT.Space.s)
            Button { revoking = feed } label: { Image(systemName: "xmark.circle").font(.title3).frame(minWidth: 44, minHeight: 44) }
                .buttonStyle(.plain)
                .foregroundStyle(TT.danger)
                .accessibilityLabel(Text("Abo „\(feed.label)“ widerrufen"))
                .accessibilityIdentifier("feeds.revoke.\(feed.label)")
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feeds.row.\(feed.label)")
    }

    static func usage(_ feed: CalendarFeed) -> String {
        var parts: [String] = []
        parts.append(feed.lastUsedAt.map { "Zuletzt abgerufen \($0.formatted(.dateTime.day().month().hour().minute()))" } ?? "Noch nie abgerufen")
        if let expires = feed.expiresAt { parts.append("läuft \(expires.formatted(.dateTime.day().month().year())) ab") }
        return parts.joined(separator: ", ")
    }
}

private struct CreatedSheetItem: Identifiable {
    let created: CalendarFeedsStore.Created
    var id: UUID { created.feed.id }
}

// MARK: - Create

private struct CalendarFeedCreateSheet: View {
    let store: CalendarFeedsStore
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var contents: Set<CalendarFeedContent> = [.absences, .holidays]
    @State private var expires = Expiry.never

    enum Expiry: String, CaseIterable, Identifiable {
        case never, days90, year
        var id: String { rawValue }
        var title: String { switch self { case .never: "Nie"; case .days90: "90 Tage"; case .year: "1 Jahr" } }
        var days: Int? { switch self { case .never: nil; case .days90: 90; case .year: 365 } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.xl) {
                    FormSection("Name", footer: "Zum Beispiel das Gerät oder der Kalender, der das Abo nutzt.") {
                        TextField("Name", text: $label)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                            .accessibilityIdentifier("feeds.label")
                    }
                    FormSection("Inhalt") {
                        ForEach(CalendarFeedContent.allCases) { content in
                            Toggle(isOn: Binding(get: { contents.contains(content) }, set: { if $0 { contents.insert(content) } else { contents.remove(content) } })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: content.title).font(TTFont.body).foregroundStyle(TT.textPrimary)
                                    Text(verbatim: content.detail).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                                }
                            }
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                            .accessibilityIdentifier("feeds.content.\(content.rawValue)")
                        }
                    }
                    FormSection("Läuft ab") {
                        Picker("Läuft ab", selection: $expires) {
                            ForEach(Expiry.allCases) { Text(verbatim: $0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    }
                    if let error = store.error {
                        Text(verbatim: error.germanDescription).font(TTFont.meta).foregroundStyle(TT.danger)
                    }
                }
                .p14cPageLayout()
            }
            .ttScreenBackground()
            .navigationTitle("Neues Abo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        Task {
                            let ordered = CalendarFeedContent.allCases.filter(contents.contains)
                            if await store.create(label: label, include: ordered, expiresInDays: expires.days) { dismiss() }
                        }
                    }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || contents.isEmpty || store.isWorking)
                    .accessibilityIdentifier("feeds.create")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
        .onAppear { store.error = nil }
    }
}

// MARK: - One-time link

private struct CalendarFeedLinkSheet: View {
    let created: CalendarFeedsStore.Created
    let onDone: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var useWebcal = false
    @State private var copied = false

    private var shown: URL { useWebcal ? created.link.webcal : created.link.https }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.xl) {
                    FormSection("Dein Abo-Link", footer: "Dieser Link wird nur jetzt angezeigt. Kopiere ihn oder abonniere direkt; später ist er nicht mehr einsehbar (du kannst das Abo aber widerrufen und neu anlegen).") {
                        Text(verbatim: shown.absoluteString)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("feeds.link")
                        Toggle("Als webcal:// anzeigen", isOn: $useWebcal)
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                            .accessibilityIdentifier("feeds.webcal_toggle")
                    }
                    VStack(spacing: TT.Space.m) {
                        Button { openURL(created.link.webcal) } label: { Label("In Kalender abonnieren", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity) }
                            .buttonStyle(.ttPrimary)
                            .accessibilityIdentifier("feeds.subscribe")
                        Button { copy(shown.absoluteString) } label: { Label(copied ? "Kopiert" : "Link kopieren", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity) }
                            .buttonStyle(.ttSecondary)
                            .accessibilityIdentifier("feeds.copy")
                        ShareLink(item: shown) { Label("Teilen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                            .buttonStyle(.ttSecondary)
                            .accessibilityIdentifier("feeds.share")
                    }
                }
                .p14cPageLayout()
            }
            .ttScreenBackground()
            .navigationTitle(created.feed.label)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig", action: onDone).accessibilityIdentifier("feeds.done") } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
        .interactiveDismissDisabled()
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = true
    }
}
