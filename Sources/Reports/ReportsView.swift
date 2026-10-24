import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Entry point of the Berichtsheft: resolves the store of the signed-in client. `week` opens a specific week (link from the Zeit view).
struct ReportsScreen: View {
    @Environment(AppModel.self) private var model
    var week: ReportWeekRef?

    var body: some View {
        Group {
            if let client = model.apiClient {
                ReportsView(store: ReportsStoreCache.shared.store(client, calendar: model.dayCalendar), requestedWeek: week)
            }
        }
        .navigationTitle(BH.s("title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct ReportsView: View {
    @Bindable var store: ReportsStore
    var requestedWeek: ReportWeekRef?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editor: EditorRequest?
    @State private var deleting: ReportEntry?
    @State private var showCopy = false
    @State private var showFields = false
    @State private var hasLoaded = false

    struct EditorRequest: Identifiable {
        let id = UUID()
        let entry: ReportEntry?
        let day: LocalDay
    }

    var body: some View {
        GeometryReader { proxy in
            let twoColumns = proxy.size.width >= 820 && !typeSize.isAccessibilitySize
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    ReportWeekBar(week: store.week, calendar: store.calendar, isCurrent: store.isCurrentWeek,
                                  previous: { Task { await store.shiftWeeks(-1) } }, next: { Task { await store.shiftWeeks(1) } },
                                  current: { Task { await store.goToCurrentWeek() } })
                    if let error = store.error {
                        ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await store.load() } }
                            .accessibilityIdentifier("reports.error")
                    }
                    if store.isUnavailable {
                        Card { EmptyState(symbol: "book.closed", title: LocalizedStringKey(BH.s("unavailable.title")), message: LocalizedStringKey(BH.s("unavailable.text"))) }
                    } else if store.data == nil && store.error == nil {
                        SkeletonList(rows: 4)
                    } else if store.data != nil {
                        if twoColumns {
                            HStack(alignment: .top, spacing: TT.Space.xl) {
                                VStack(alignment: .leading, spacing: TT.Space.l) { days }.frame(maxWidth: .infinity, alignment: .top)
                                VStack(alignment: .leading, spacing: TT.Space.l) { summary; sourcesCard }.frame(width: 340, alignment: .top)
                            }
                        } else {
                            summary
                            days
                            sourcesCard
                        }
                    }
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                .frame(maxWidth: twoColumns ? 1100 : 720).frame(maxWidth: .infinity)
            }
        }
        .ttScreenBackground()
        .task(id: requestedWeek) {
            if let requestedWeek { store.select(week: requestedWeek) }
            await store.load()
            hasLoaded = true
        }
        .refreshable { await store.load() }
        .toolbar { toolbar }
        .sheet(item: $editor, onDismiss: { Task { await store.load() } }) { request in
            ReportEntrySheet(store: store, entry: request.entry, day: request.day)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
        }
        .sheet(isPresented: $showCopy) { ReportCopySheet(store: store) }
        .navigationDestination(isPresented: $showFields) { LearningFieldsView(store: store) }
        .confirmationDialog(deleting.map { BH.s("entry.delete_confirm", $0.learningField) } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { entry in
            Button(BH.s("entry.delete"), role: .destructive) { Task { await store.delete(entry) } }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { showCopy = true } label: { Label(BH.s("copy.button"), systemImage: "doc.on.clipboard") }
                .help(Text(verbatim: BH.s("copy.button")))
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.data == nil)
                .accessibilityIdentifier("reports.copy")
            Button { showFields = true } label: { Label(BH.s("fields.title"), systemImage: "list.number") }
                .help(Text(verbatim: BH.s("fields.title")))
                .accessibilityIdentifier("reports.fields")
            Button { editor = EditorRequest(entry: nil, day: defaultDay) } label: { Label(BH.s("entry.add"), systemImage: "plus") }
                .help(Text(verbatim: BH.s("entry.add")))
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store.data == nil)
                .accessibilityIdentifier("reports.new")
        }
    }

    /// Today when it lies in the selected week, otherwise the Monday of that week.
    private var defaultDay: LocalDay { store.week.days.contains(store.today) ? store.today : store.week.monday }

    // MARK: Summary

    private var summary: some View {
        let data = store.data
        return Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                ReportStatusPicker(status: store.status, busy: store.isBusy) { value in Task { await store.setStatus(value) } }
                Text(verbatim: BH.s("status.hint")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                Divider().overlay(TT.separator)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: BH.s("summary.total")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    Text(verbatim: BH.hours(data?.totalSeconds ?? 0)).font(TTFont.stat).foregroundStyle(TT.textPrimary).accessibilityIdentifier("reports.total")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: BH.s("summary.total_spoken", BH.spokenHours(data?.totalSeconds ?? 0))))
                if let fields = data?.byLearningField, !fields.isEmpty {
                    VStack(alignment: .leading, spacing: TT.Space.xs) {
                        Eyebrow(verbatim: BH.s("summary.by_field"))
                        ForEach(fields) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: item.learningField).font(TTFont.body).foregroundStyle(TT.textPrimary)
                                Spacer(minLength: TT.Space.s)
                                Text(verbatim: BH.hours(item.seconds)).font(TTFont.numeral).foregroundStyle(TT.textSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if let tracked = data?.trackedWorkSeconds {
                    Text(verbatim: BH.s("summary.tracked", DurationFormat.hoursMinutes(tracked))).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    Text(verbatim: BH.s("summary.tracked_note")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
            }
        }
    }

    // MARK: Days

    @ViewBuilder private var days: some View {
        ForEach(Array(store.week.days.enumerated()), id: \.element) { index, day in
            dayCard(day, index: index)
        }
    }

    private func dayCard(_ day: LocalDay, index: Int) -> some View {
        let entries = store.data?.entries(on: day) ?? []
        let sum = entries.reduce(0) { $0 + $1.durationSeconds }
        return VStack(alignment: .leading, spacing: TT.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: dayTitle(day, calendar: store.calendar)).font(TTFont.label).foregroundStyle(day == store.today ? TT.textPrimary : TT.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                if day == store.today { StatusChip(LocalizedStringKey(BH.s("day.today")), tone: .accent) }
                Spacer(minLength: TT.Space.s)
                if !entries.isEmpty {
                    Text(verbatim: BH.hours(sum)).font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                }
                Button { editor = EditorRequest(entry: nil, day: day) } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44).contentShape(.rect) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(verbatim: BH.s("day.add_label", dayTitle(day, calendar: store.calendar))))
                    .accessibilityIdentifier("reports.add.\(day)")
            }
            if entries.isEmpty {
                Text(verbatim: BH.s("day.empty")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    .padding(.bottom, TT.Space.xs)
            } else {
                ListCard { ForEach(entries) { entryRow($0) } }
            }
        }
    }

    private func entryRow(_ entry: ReportEntry) -> some View {
        Button { editor = EditorRequest(entry: entry, day: entry.date) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: TT.Space.s) {
                    Text(verbatim: entry.learningField).font(TTFont.body.weight(.semibold)).foregroundStyle(TT.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if entry.draft { StatusChip(LocalizedStringKey(BH.s("entry.draft_badge")), tone: .warning) }
                    Spacer(minLength: TT.Space.s)
                    Text(verbatim: BH.hours(entry.durationSeconds)).font(TTFont.numeral).foregroundStyle(TT.textSecondary)
                }
                Text(verbatim: entry.notes.isEmpty ? BH.s("entry.no_notes") : entry.notes).font(TTFont.meta)
                    .foregroundStyle(TT.textSecondary).lineLimit(3).multilineTextAlignment(.leading)
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: BH.s("entry.spoken", entry.learningField, BH.spokenHours(entry.durationSeconds),
                                                entry.notes.isEmpty ? BH.s("entry.no_notes") : entry.notes)))
        .accessibilityHint(Text(verbatim: BH.s("entry.hint")))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("reports.entry")
        .contextMenu {
            Button { editor = EditorRequest(entry: entry, day: entry.date) } label: { Label(BH.s("entry.edit"), systemImage: "pencil") }
            Button(role: .destructive) { deleting = entry } label: { Label(BH.s("entry.delete"), systemImage: "trash") }
        }
        .accessibilityAction(named: Text(verbatim: BH.s("entry.delete"))) { deleting = entry }
    }

    private var sourcesCard: some View { ReportSourcesCard(store: store) }
}
