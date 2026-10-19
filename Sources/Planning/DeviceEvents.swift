import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

extension EnvironmentValues {
    /// E1: device calendars (EventKit). Nil where the platform has no integration (macOS, previews); the day view then shows nothing.
    @Entry var deviceCalendar: DeviceCalendarStore?
}

/// Day view section "Termine": events of the selected device calendars as read-only context. They are never turned into time
/// entries automatically; the only action is a proposal the user must complete and confirm.
struct DeviceEventsSection: View {
    let day: LocalDay
    let calendar: DayCalendar
    /// Whether time entries can be created (the module is available and the account is signed in).
    let canSuggest: Bool
    @Binding var sheet: PlanSheet?
    @Environment(\.deviceCalendar) private var store
    @State private var events: [DeviceEvent] = []
    @State private var colors: [String: Color] = [:]

    var body: some View {
        Group {
            if let store, store.showsEvents {
                VStack(alignment: .leading, spacing: TT.Space.s) {
                    Eyebrow("Termine aus dem Kalender").padding(.horizontal, TT.Space.s).accessibilityAddTraits(.isHeader)
                    if events.isEmpty {
                        Card(padding: TT.Space.m) { Text("Keine Termine an diesem Tag.").font(TTFont.body).foregroundStyle(TT.textSecondary) }
                            .accessibilityIdentifier("events.empty")
                    } else {
                        ListCard {
                            ForEach(events) { event in row(event) }
                        }
                    }
                    Text("Nur zur Ansicht. Die Termine bleiben auf diesem Gerät und werden nicht automatisch zu Zeiteinträgen.")
                        .font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.s)
                }
                .task(id: reloadKey(store)) { reload(store) }
            }
        }
        .environment(\.timeZone, calendar.timeZone)
    }

    private func reloadKey(_ store: DeviceCalendarStore) -> String { "\(day)-\(store.changeCount)-\(store.access.rawValue)" }

    private func reload(_ store: DeviceCalendarStore) {
        events = store.events(on: day, calendar: calendar)
        let infos = Dictionary(store.calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        colors = infos.compactMapValues { info in info.colorHex.flatMap { UInt32($0, radix: 16) }.map { Color(hex: $0) } }
    }

    private func row(_ event: DeviceEvent) -> some View {
        HStack(alignment: .top, spacing: TT.Space.m) {
            RoundedRectangle(cornerRadius: 2).fill(colors[event.calendarID] ?? TT.textTertiary).frame(width: 4).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.title.isEmpty ? "(ohne Titel)" : event.title).font(TTFont.body).foregroundStyle(TT.textPrimary)
                timeLine(event).font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                if let location = event.location, !location.isEmpty { Text(verbatim: location).font(TTFont.meta).foregroundStyle(TT.textTertiary) }
            }
            Spacer(minLength: TT.Space.s)
            if !event.isAllDay, canSuggest {
                Button { sheet = .eventDraft(day, event) } label: { Image(systemName: "clock.badge.questionmark") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Termin als Zeitabschnitt vorschlagen"))
                    .accessibilityIdentifier("event.suggest")
            }
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event.row")
        .contextMenu {
            if !event.isAllDay, canSuggest {
                Button { sheet = .eventDraft(day, event) } label: { Label("Termin als Zeitabschnitt vorschlagen", systemImage: "clock.badge.questionmark") }
            }
        }
    }

    @ViewBuilder private func timeLine(_ event: DeviceEvent) -> some View {
        if event.isAllDay {
            Text("Ganztägig")
        } else {
            Text("\(event.start, format: .dateTime.hour().minute()) – \(event.end, format: .dateTime.hour().minute())")
        }
    }
}

/// Editable proposal for a time segment derived from a calendar event. The kind is NOT preselected: the user states what the
/// appointment was, nothing is guessed. The event title is shown here only as local context and is not part of the entry.
struct EventDraftSheet: View {
    let store: CalendarStore
    let list: TimeListStore
    let day: LocalDay
    let event: DeviceEvent
    @Environment(\.dismiss) private var dismiss
    @State private var kind: SegmentKind?
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var note = ""
    @State private var problem: String?
    @State private var saving = false

    private var canSave: Bool { problem == nil && kind != nil && end > start }

    var body: some View {
        SheetFrame(title: "Vorschlag", canSave: canSave, saving: saving, identifier: "eventdraft", save: save) {
            Card(padding: TT.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Termin (nur auf diesem Gerät)").font(TTFont.label).foregroundStyle(TT.textSecondary)
                    Text(verbatim: event.title.isEmpty ? "(ohne Titel)" : event.title).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
            if let problem {
                Text(verbatim: problem).font(TTFont.body).foregroundStyle(TT.danger).accessibilityIdentifier("eventdraft.problem")
            }
            FormSection("Art des Zeitabschnitts", footer: "Nichts ist vorausgewählt: Du entscheidest, was dieser Termin war. Der Titel wird nicht gespeichert und nicht an den Server gesendet.") {
                KindChoice(selection: $kind).padding(TT.Space.m)
            }
            FormSection("editor.time") {
                EditorRow { DatePicker("editor.start", selection: $start, displayedComponents: .hourAndMinute).accessibilityIdentifier("eventdraft.start") }
                EditorRow { DatePicker("editor.end", selection: $end, displayedComponents: .hourAndMinute).accessibilityIdentifier("eventdraft.end") }
            }
            FormSection("editor.note") { TextField("editor.note", text: $note, axis: .vertical).lineLimit(1...3).padding(TT.Space.l).accessibilityIdentifier("eventdraft.note") }
            if let error = list.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.dismiss") { list.error = nil } }
        }
        .environment(\.timeZone, store.calendar.timeZone)
        .onAppear {
            list.error = nil
            do {
                let draft = try EventDraftMapper.draft(from: event, on: day, calendar: store.calendar)
                start = draft.startedAt
                end = draft.endedAt
            } catch EventDraftError.allDayEvent {
                problem = "Ganztägige Termine haben keine Uhrzeit. Lege den Zeitabschnitt manuell an."
            } catch {
                problem = "Dieser Termin liegt nicht an diesem Tag."
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let input = try EventDraftMapper.input(from: SegmentDraft(startedAt: start, endedAt: end, kind: kind, note: note))
            if await list.create(input) {
                await store.loadDetail()
                dismiss()
            }
        } catch {
            problem = "Wähle die Art des Zeitabschnitts und prüfe die Zeiten."
        }
    }
}

/// Kind choice without a default (the shared `KindSelector` always has a selection).
private struct KindChoice: View {
    @Binding var selection: SegmentKind?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TT.Space.s) { options }
            VStack(spacing: TT.Space.s) { options }
        }
        .accessibilityElement(children: .contain)
    }

    private var options: some View {
        ForEach(SegmentKind.selectable, id: \.self) { kind in
            let selected = selection == kind
            Button { if selection != kind { TTHaptics.play(.selection) }; selection = kind } label: {
                HStack(spacing: 8) {
                    Image(systemName: kind.ttSymbol)
                    Text(kind.ttTitle)
                }
                .font(TTFont.label).lineLimit(1)
                .padding(.horizontal, TT.Space.m)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? kind.ttTint : TT.textSecondary)
                .background(selected ? kind.ttTint.opacity(scheme == .dark ? 0.22 : 0.13) : Color.clear, in: .capsule)
                .overlay { Capsule().strokeBorder(selected ? kind.ttTint.opacity(0.5) : TT.separator, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("eventdraft.kind.\(kind.rawValue)")
        }
    }
}
