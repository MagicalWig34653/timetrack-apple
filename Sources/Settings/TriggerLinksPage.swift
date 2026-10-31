import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// AUD3-A: "Auslöse-Links" (ADR-0027): addresses that start or stop the time tracking when opened, for NFC tags, widgets and shortcuts.
/// Mirrors the web app's trigger-link settings. The secret addresses are shown once after creating.
struct TriggerLinksPage: View {
    @Environment(AppModel.self) private var model
    @State private var store: TriggerLinksStore?
    @State private var showCreate = false
    @State private var revoking: TriggerLink?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let store {
                    securitySection
                    linksSection(store)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, TT.Space.xl)
                }
            }
            .p14cPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("Auslöse-Links")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if store == nil, let client = model.apiClient { store = TriggerLinksStore(client: client) }
            await store?.load()
        }
        .sheet(isPresented: $showCreate) {
            if let store { TriggerLinkCreateSheet(store: store) }
        }
        .sheet(item: Binding(get: { store?.created.map(TriggerCreatedItem.init) }, set: { if $0 == nil { store?.dismissCreated() } })) { item in
            TriggerLinkAddressSheet(created: item.created) { store?.dismissCreated() }
        }
        .confirmationDialog(revoking.map { "Link „\($0.label)“ widerrufen?" } ?? "", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible, presenting: revoking) { link in
            Button("Endgültig widerrufen", role: .destructive) { Task { await store?.revoke(link) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Der Link antwortet danach sofort nicht mehr. Das lässt sich nicht rückgängig machen.")
        }
    }

    private var securitySection: some View {
        FormSection("Wie ein Passwort behandeln", footer: "Wer in einem Programm Kopfzeilen setzen kann, sollte stattdessen ein Gerätetoken verwenden (PWA: Einstellungen, Geräte).") {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Text("Adressen, die beim Öffnen die Zeiterfassung starten oder stoppen, etwa für NFC-Tags, Widgets oder Kurzbefehle ohne Anmeldung.")
                Text("Die Adresse enthält ein geheimes Token. Wer sie kennt, kann damit deine Zeiterfassung steuern, ohne sich anzumelden. Teile sie nicht.")
                Text("Lege für jeden Zweck einen eigenen Link an, damit du ihn bei Verlust einzeln widerrufen kannst.")
                Text("Die Adresse landet im Verlauf und in den Protokollen des Geräts, das sie aufruft. Bei Verdacht widerrufe den Link sofort.")
            }
            .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("trigger.security")
        }
    }

    @ViewBuilder private func linksSection(_ store: TriggerLinksStore) -> some View {
        FormSection("Deine Links", footer: store.canCreate ? "Die Adresse eines Links kann nach dem Anlegen nicht mehr angezeigt werden. Hast du sie nicht gespeichert, widerrufe den Link und lege einen neuen an." : "Höchstens \(TriggerLinksStore.maximum) aktive Links. Widerrufe einen, um einen neuen anzulegen.") {
            if store.hasLoaded, store.links.isEmpty {
                Text("Noch keine Auslöse-Links.")
                    .font(TTFont.body).foregroundStyle(TT.textSecondary)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("trigger.empty")
            }
            ForEach(store.links) { link in
                linkRow(link, store: store)
            }
            if let error = store.error {
                Text(verbatim: error.germanDescription).font(TTFont.meta).foregroundStyle(TT.danger)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("trigger.error")
            }
            Button { showCreate = true } label: { Label("Neuer Link", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.ttSecondary)
                .disabled(!store.canCreate)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityIdentifier("trigger.new")
        }
    }

    private func linkRow(_ link: TriggerLink, store: TriggerLinksStore) -> some View {
        HStack(alignment: .top, spacing: TT.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: link.label).font(TTFont.body).foregroundStyle(TT.textPrimary)
                Text(verbatim: "Aktionen: \(link.actionSummary) · \(Self.kindTitle(link.kind)) · \(store.placeDescription(for: link))")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                Text(verbatim: Self.usage(link)).font(TTFont.meta).foregroundStyle(TT.textTertiary)
            }
            Spacer(minLength: TT.Space.s)
            Button { revoking = link } label: { Image(systemName: "xmark.circle").font(.title3).frame(minWidth: 44, minHeight: 44) }
                .buttonStyle(.plain)
                .foregroundStyle(TT.danger)
                .accessibilityLabel(Text("Link „\(link.label)“ widerrufen"))
                .accessibilityIdentifier("trigger.revoke.\(link.label)")
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trigger.row.\(link.label)")
    }

    static func kindTitle(_ kind: SegmentKind) -> String {
        switch kind {
        case .work, .unknown: "Arbeit"
        case .travel: "Fahrt"
        case .school: "Schule"
        }
    }

    static func usage(_ link: TriggerLink) -> String {
        func stamp(_ date: Date) -> String { date.formatted(.dateTime.day().month().year().hour().minute()) }
        var parts = ["Erstellt \(stamp(link.createdAt))"]
        if let used = link.lastUsedAt {
            parts.append("zuletzt benutzt \(stamp(used)) (\(link.lastActionTitle ?? "–"))")
        } else {
            parts.append("noch nie benutzt")
        }
        parts.append(link.expiresAt.map { "läuft \(stamp($0)) ab" } ?? "läuft nicht ab")
        return parts.joined(separator: ", ")
    }
}

private struct TriggerCreatedItem: Identifiable {
    let created: TriggerLinksStore.Created
    var id: UUID { created.link.id }
}

// MARK: - Create

private struct TriggerLinkCreateSheet: View {
    let store: TriggerLinksStore
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var actions: Set<TriggerAction> = [.start, .stop]
    @State private var placeId: UUID?
    @State private var kind: SegmentKind = .work
    @State private var expiryText = ""

    /// Nil when empty (never expires); `.some(nil)` is not used, an invalid text yields `invalid`.
    private var expiry: (days: Int?, valid: Bool) {
        let text = expiryText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return (nil, true) }
        guard let days = Int(text), TriggerLinkInput.expiryRange.contains(days) else { return (nil, false) }
        return (days, true)
    }

    private var canSubmit: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty && !actions.isEmpty && expiry.valid && !store.isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.xl) {
                    FormSection("Bezeichnung", footer: "Zum Beispiel „NFC-Tag Schreibtisch“. Bis zu 80 Zeichen.") {
                        TextField("Bezeichnung", text: $label)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                            .accessibilityIdentifier("trigger.label")
                    }
                    FormSection("Erlaubte Aktionen", footer: "Nur diese Aktionen funktionieren mit dem Link. Alles andere antwortet mit „nicht gefunden“.") {
                        ForEach(TriggerAction.allCases) { action in
                            Toggle(isOn: Binding(get: { actions.contains(action) }, set: { if $0 { actions.insert(action) } else { actions.remove(action) } })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: action.title).font(TTFont.body).foregroundStyle(TT.textPrimary)
                                    Text(verbatim: action.detail).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                                }
                            }
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                            .accessibilityIdentifier("trigger.action.\(action.rawValue)")
                        }
                    }
                    FormSection("Ort (optional)", footer: "An einen Ort gebunden, legt der Start den Abschnitt dort an und der Automatik-Modus des Orts wird beachtet.") {
                        Picker("Ort", selection: $placeId) {
                            Text("Keiner (Ort beim Aufruf mitgeben)").tag(UUID?.none)
                            ForEach(store.selectablePlaces) { Text(verbatim: $0.name).tag(UUID?.some($0.id)) }
                        }
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                        .accessibilityIdentifier("trigger.place")
                    }
                    FormSection("Art des Abschnitts") {
                        Picker("Art des Abschnitts", selection: $kind) {
                            ForEach(SegmentKind.selectable, id: \.self) { Text(verbatim: TriggerLinksPage.kindTitle($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                        .accessibilityIdentifier("trigger.kind")
                    }
                    FormSection("Gültigkeit in Tagen (optional)", footer: expiry.valid ? "1 bis 730. Leer lassen für einen Link ohne Ablauf." : "Bitte gib eine ganze Zahl von 1 bis 730 an.") {
                        TextField("Gültigkeit in Tagen", text: $expiryText)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                            .accessibilityIdentifier("trigger.expires")
                    }
                    if let error = store.error {
                        Text(verbatim: error.germanDescription).font(TTFont.meta).foregroundStyle(TT.danger)
                    }
                }
                .p14cPageLayout()
            }
            .ttScreenBackground()
            .navigationTitle("Neuer Link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        Task {
                            let ordered = TriggerAction.allCases.filter(actions.contains)
                            if await store.create(label: label, actions: ordered, placeId: placeId, kind: kind, expiresInDays: expiry.days) { dismiss() }
                        }
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("trigger.create")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 640)
        #endif
        .onAppear { store.error = nil }
    }
}

// MARK: - One-time addresses

private struct TriggerLinkAddressSheet: View {
    let created: TriggerLinksStore.Created
    let onDone: () -> Void
    @State private var copiedAction: TriggerAction?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.xl) {
                    FormSection("Adressen von „\(created.link.label)“", footer: "Jetzt kopieren: Die Adresse wird nur dieses eine Mal angezeigt und ist später nicht mehr abrufbar. Sie wirkt wie ein Passwort.") {
                        ForEach(created.addresses.entries) { entry in
                            VStack(alignment: .leading, spacing: TT.Space.s) {
                                Text(verbatim: "Adresse für „\(entry.action.title)“").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                                Text(verbatim: entry.url.absoluteString)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                                    .accessibilityIdentifier("trigger.url.\(entry.action.rawValue)")
                                HStack(spacing: TT.Space.m) {
                                    Button { copy(entry) } label: { Label(copiedAction == entry.action ? "Kopiert" : "Kopieren", systemImage: copiedAction == entry.action ? "checkmark" : "doc.on.doc") }
                                        .buttonStyle(.ttSecondary)
                                        .accessibilityIdentifier("trigger.copy.\(entry.action.rawValue)")
                                    ShareLink(item: entry.url) { Label("Teilen", systemImage: "square.and.arrow.up") }
                                        .buttonStyle(.ttSecondary)
                                }
                            }
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .p14cPageLayout()
            }
            .ttScreenBackground()
            .navigationTitle("Link erzeugt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ich habe sie gespeichert", action: onDone).accessibilityIdentifier("trigger.done") } }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 420)
        #endif
        .interactiveDismissDisabled()
    }

    private func copy(_ entry: TriggerLinkAddresses.Entry) {
        #if os(iOS)
        UIPasteboard.general.string = entry.url.absoluteString
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
        #endif
        copiedAction = entry.action
    }
}
