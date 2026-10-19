import SwiftUI
import QuickLook
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// V3: vacation ring with planned share, absence filter/sort and attachment preview.
// Strings live in their own catalog (`Vacation.xcstrings`, table "Vacation") so the shared catalogs stay untouched.

enum VT {
    static func s(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, tableName: "Vacation", bundle: .main, value: key, comment: "")
        return args.isEmpty ? format : String(format: format, arguments: args)
    }
    static func t(_ key: String, _ args: CVarArg...) -> Text { Text(verbatim: args.isEmpty ? s(key) : String(format: s(key), arguments: args)) }
    static func days(_ halfDays: Int) -> String { String(localized: "vacation.days \(HalfDayFormat.days(halfDays))") }
}

/// Section with title above, rows in a card and footer below (like `FormSection`, but with strings from the Vacation table).
private struct VSection<Content: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            if let title { Eyebrow(verbatim: title).padding(.horizontal, TT.Space.s).accessibilityAddTraits(.isHeader) }
            ListCard { content }
            if let footer { Text(verbatim: footer).font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.s) }
        }
    }
}

// MARK: - Ring

/// Vacation consumption: booked (solid, blue), planned (hatched, amber), free (track). Pattern and legend carry the meaning, not colour alone.
struct VacationRing: View {
    let segments: VacationRingSegments

    static let bookedTint = TT.kindVacation
    static let plannedTint = TT.warning

    var body: some View {
        SegmentedRing(
            segments: [
                RingSegment(id: "booked", fraction: segments.bookedFraction, tint: Self.bookedTint),
                RingSegment(id: "planned", fraction: segments.plannedFraction, tint: Self.plannedTint, hatched: true),
            ],
            lineWidth: 12, trackTint: Self.bookedTint, accessibilityText: Text(verbatim: accessibilityText)
        ) {
            Image(systemName: "beach.umbrella.fill").font(.title2).foregroundStyle(TT.kindVacation)
        }
    }

    var accessibilityText: String {
        let booked = VT.days(segments.bookedHalfDays), planned = VT.days(segments.plannedHalfDays)
        if segments.isOverPlanned {
            return VT.s("ring.a11y_over", booked, planned, VT.days(-segments.freeAfterPlannedHalfDays))
        }
        return VT.s("ring.a11y", booked, planned, VT.days(segments.freeAfterPlannedHalfDays))
    }
}

/// Short legend below the ring; hidden from VoiceOver because the ring's label already reads all values.
struct VacationRingLegend: View {
    let segments: VacationRingSegments

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            item(tint: VacationRing.bookedTint, hatched: false, track: false, "ring.booked", segments.bookedHalfDays)
            item(tint: VacationRing.plannedTint, hatched: true, track: false, "ring.planned", segments.plannedHalfDays)
            item(tint: VacationRing.bookedTint, hatched: false, track: true, "ring.free", max(segments.freeAfterPlannedHalfDays, 0))
            if segments.isOverPlanned {
                Label { VT.t("ring.over", HalfDayFormat.days(-segments.freeAfterPlannedHalfDays)) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(TTFont.meta).foregroundStyle(TT.danger)
            }
        }
        .accessibilityHidden(true)
    }

    private func item(tint: Color, hatched: Bool, track: Bool, _ key: String, _ halfDays: Int) -> some View {
        HStack(spacing: TT.Space.s) {
            RingLegendSwatch(tint: tint, hatched: hatched, isTrack: track)
            VT.t(key).foregroundStyle(TT.textPrimary)
            Spacer(minLength: TT.Space.s)
            Text(verbatim: VT.days(halfDays)).monospacedDigit().foregroundStyle(TT.textSecondary)
        }
        .font(TTFont.meta)
    }
}

// MARK: - Labels

extension AbsenceListOptions.Sort {
    var title: String { VT.s("sort.\(rawValue)") }
}

extension AbsenceListOptions.Attachment {
    var title: String { VT.s("attachment.\(rawValue)") }
}

extension AbsenceKind {
    var filterTitle: String { plainName }
}

extension AbsenceListOptions {
    enum PeriodChoice: String, CaseIterable { case all, upcoming, past, custom }

    var periodChoice: PeriodChoice {
        switch period {
        case .all: .all
        case .upcoming: .upcoming
        case .past: .past
        case .custom: .custom
        }
    }

    var summary: String {
        let filters = activeFilterCount == 0 ? nil : VT.s(activeFilterCount == 1 ? "filter.active_one" : "filter.active_other", activeFilterCount)
        let sorted = isDefaultSort ? nil : VT.s("filter.sorted", sort.title, VT.s(ascending ? "filter.ascending" : "filter.descending"))
        return [filters, sorted].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Filter bar and sheet

/// Slim entry above the list: opens the filter sheet, shows what is active and offers a reset.
struct AbsenceFilterBar: View {
    @Bindable var store: PlanningStore
    let shown: Int
    @State private var showSheet = false

    var body: some View {
        let options = store.listOptions
        HStack(spacing: TT.Space.m) {
            Button { showSheet = true } label: {
                HStack(spacing: TT.Space.s) {
                    Image(systemName: options.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        VT.t("filter.button").font(TTFont.body)
                        if !options.summary.isEmpty { Text(verbatim: options.summary).font(TTFont.meta).foregroundStyle(TT.textSecondary) }
                    }
                }
                .foregroundStyle(TT.textPrimary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("absence.filter")
            .accessibilityValue(Text(verbatim: options.summary))
            Spacer(minLength: TT.Space.s)
            if options.hasFilters {
                Text(verbatim: VT.s("filter.count", shown, store.absences.count)).font(TTFont.meta).monospacedDigit().foregroundStyle(TT.textSecondary)
                Button { store.listOptions = options.resettingFilters() } label: { Image(systemName: "xmark.circle.fill").frame(width: 32, height: 32) }
                    .buttonStyle(.borderless).foregroundStyle(TT.textSecondary)
                    .accessibilityLabel(Text(verbatim: VT.s("filter.reset"))).accessibilityIdentifier("absence.filter.reset")
            }
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
        .ttSurface()
        .sheet(isPresented: $showSheet) { AbsenceFilterSheet(store: store) }
    }
}

struct AbsenceFilterSheet: View {
    @Bindable var store: PlanningStore
    @Environment(\.dismiss) private var dismiss

    private var options: AbsenceListOptions { store.listOptions }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    sortSection
                    kindSection
                    statusSection
                    periodSection
                    attachmentSection
                    Button(VT.s("filter.reset")) { store.listOptions = options.resettingFilters() }
                        .buttonStyle(.ttSecondary).disabled(!options.hasFilters).accessibilityIdentifier("absence.filter.clear")
                    Text(verbatim: VT.s("filter.remembered")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(VT.s("filter.title")).inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(VT.s("filter.done")) { dismiss() }.accessibilityIdentifier("absence.filter.done") } }
        }
        .environment(\.timeZone, store.calendar.timeZone)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private var sortSection: some View {
        VSection(title: VT.s("filter.sort")) {
            EditorRow {
                Picker(VT.s("filter.sort"), selection: $store.listOptions.sort) {
                    ForEach(AbsenceListOptions.Sort.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("absence.sort")
            }
            EditorRow {
                Toggle(VT.s("filter.reverse"), isOn: Binding(get: { !options.ascending }, set: { store.listOptions.ascending = !$0 }))
                    .accessibilityIdentifier("absence.sort.reverse")
            }
        }
    }

    private var kindSection: some View {
        VSection(title: VT.s("filter.kind")) {
            ForEach(AbsenceListOptions.kindChoices, id: \.self) { kind in
                choiceRow(kind.filterTitle, selected: options.kinds.contains(kind), id: "absence.filter.kind.\(kind.rawValue)") {
                    if options.kinds.contains(kind) { store.listOptions.kinds.remove(kind) } else { store.listOptions.kinds.insert(kind) }
                }
            }
        }
    }

    private var statusSection: some View {
        VSection(title: VT.s("filter.status")) {
            ForEach(AbsenceListOptions.statusChoices, id: \.self) { status in
                choiceRow(status.plainName, selected: options.statuses.contains(status), id: "absence.filter.status.\(status.rawValue)") {
                    if options.statuses.contains(status) { store.listOptions.statuses.remove(status) } else { store.listOptions.statuses.insert(status) }
                }
            }
        }
    }

    private var periodSection: some View {
        VSection(title: VT.s("filter.period"), footer: VT.s("filter.year_hint")) {
            EditorRow {
                Picker(VT.s("filter.period"), selection: Binding(get: { options.periodChoice }, set: setPeriod)) {
                    ForEach(AbsenceListOptions.PeriodChoice.allCases, id: \.self) { Text(verbatim: VT.s("period.\($0.rawValue)")).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("absence.period")
            }
            if case .custom(let from, let to) = options.period {
                boundRow(VT.s("filter.from"), value: from) { store.listOptions.period = .custom(from: $0, to: to) }
                boundRow(VT.s("filter.to"), value: to) { store.listOptions.period = .custom(from: from, to: $0) }
            }
        }
    }

    private var attachmentSection: some View {
        VSection(title: VT.s("filter.attachment")) {
            EditorRow {
                Picker(VT.s("filter.attachment"), selection: $store.listOptions.attachment) {
                    ForEach(AbsenceListOptions.Attachment.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("absence.attachment")
            }
        }
    }

    private func setPeriod(_ choice: AbsenceListOptions.PeriodChoice) {
        switch choice {
        case .all: store.listOptions.period = .all
        case .upcoming: store.listOptions.period = .upcoming
        case .past: store.listOptions.period = .past
        case .custom:
            if case .custom = options.period { return }
            store.listOptions.period = .custom(from: store.today, to: nil)
        }
    }

    /// A date bound that can be switched off (open end).
    private func boundRow(_ title: String, value: LocalDay?, set: @escaping (LocalDay?) -> Void) -> some View {
        EditorRow {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Toggle(title, isOn: Binding(get: { value != nil }, set: { set($0 ? store.today : nil) }))
                if let value {
                    DatePicker(title, selection: dayBinding(Binding(get: { value }, set: { set($0) }), calendar: store.calendar), displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
    }

    private func choiceRow(_ title: String, selected: Bool, id: String, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(verbatim: title).font(TTFont.body).foregroundStyle(TT.textPrimary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? TT.kindVacation : TT.textSecondary)
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

// MARK: - Attachments

/// Paperclip with count next to a list row; opens the attachment sheet.
struct AttachmentButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "paperclip")
                if count > 1 { Text(verbatim: "\(count)").font(TTFont.meta).monospacedDigit() }
            }
            .foregroundStyle(TT.textSecondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: VT.s(count == 1 ? "attachments.count_one" : "attachments.count_other", count)))
        .accessibilityHint(Text(verbatim: VT.s("attachments.hint")))
        .accessibilityIdentifier("absence.attachments")
    }
}

/// Lists the attachments of one absence and previews them with QuickLook (PDF, images, text and what the system can show).
struct AbsenceAttachmentsSheet: View {
    let store: PlanningStore
    let absence: Absence
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var openingId: UUID?
    @State private var openError = false
    @State private var previewURL: URL?
    @State private var tempDirectory: URL?

    enum Phase { case loading, loaded([FileMeta]), failed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    switch phase {
                    case .loading: SkeletonList(rows: 2)
                    case .failed:
                        ErrorBanner(message: VT.s("attachments.load_failed"), retryTitle: "common.retry") { Task { await load() } }
                    case .loaded(let files):
                        if files.isEmpty {
                            Card { EmptyState(symbol: "paperclip", title: LocalizedStringKey(VT.s("attachments.empty"))) }
                        } else {
                            ListCard { ForEach(files) { row($0) } }
                        }
                    }
                    if openError { HintBanner(LocalizedStringKey(VT.s("attachments.open_failed")), symbol: "exclamationmark.triangle.fill") }
                }
                .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(VT.s("attachments.title")).inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(VT.s("attachments.done")) { dismiss() }.accessibilityIdentifier("attachments.done") } }
            .quickLookPreview($previewURL)
        }
        .task { await load() }
        .onDisappear { if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) } }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private func row(_ file: FileMeta) -> some View {
        Button { Task { await open(file) } } label: {
            HStack(spacing: TT.Space.m) {
                Image(systemName: Self.symbol(file.contentType)).frame(width: 28).foregroundStyle(TT.kindVacation)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: file.name).font(TTFont.body).foregroundStyle(TT.textPrimary).lineLimit(2)
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                Spacer(minLength: TT.Space.s)
                if openingId == file.id { ProgressView() } else { Image(systemName: "eye").foregroundStyle(TT.textSecondary) }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .contentShape(.rect)
        }
        .buttonStyle(.plain).disabled(openingId != nil)
        .accessibilityElement(children: .combine).accessibilityHint(Text(verbatim: VT.s("attachments.hint")))
        .accessibilityIdentifier("attachment.row")
    }

    static func symbol(_ contentType: String) -> String {
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType == "application/pdf" { return "doc.richtext" }
        return "doc"
    }

    private func load() async {
        phase = .loading
        do { phase = .loaded(try await store.attachments(of: absence)) } catch { phase = .failed }
    }

    private func open(_ file: FileMeta) async {
        openError = false
        openingId = file.id
        defer { openingId = nil }
        do {
            let data = try await store.fileData(file)
            let root = tempDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("absence-attachments-\(UUID().uuidString)")
            tempDirectory = root
            let directory = root.appendingPathComponent(file.id.uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file.safeFileName)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            previewURL = url
        } catch {
            openError = true
        }
    }
}
