import SwiftUI
import UniformTypeIdentifiers
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Sources of the week: notes and files the user collects before writing the report. Only the owner sees them; nothing is copied
/// into entries automatically.
struct ReportSourcesCard: View {
    @Bindable var store: ReportsStore
    @State private var noteText = ""
    @State private var noteDay: LocalDay?
    @State private var importing = false
    @State private var removing: ReportSource?
    @State private var previewURL: URL?
    @State private var tempDirectory: URL?
    @State private var openingId: UUID?
    @State private var localError: String?
    @SwiftUI.FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Eyebrow(verbatim: BH.s("sources.title")).accessibilityAddTraits(.isHeader)
            Card {
                VStack(alignment: .leading, spacing: TT.Space.m) {
                    Text(verbatim: BH.s("sources.text")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    if store.sources.isEmpty {
                        Text(verbatim: BH.s("sources.empty")).font(TTFont.body).foregroundStyle(TT.textSecondary).accessibilityIdentifier("reports.sources.empty")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(store.sources) { source in
                                row(source)
                                if source.id != store.sources.last?.id { Divider().overlay(TT.separator) }
                            }
                        }
                    }
                    Divider().overlay(TT.separator)
                    addNote
                    Button { importing = true } label: { Label(BH.s("sources.add_file"), systemImage: "paperclip").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.ttSecondary).disabled(store.isBusy).accessibilityIdentifier("reports.sources.file")
                    if let localError { Label(localError, systemImage: "exclamationmark.triangle.fill").font(TTFont.meta).foregroundStyle(TT.danger) }
                    Text(verbatim: BH.s("sources.never_shared")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .png, .jpeg, .gif, .webP, .plainText, .item], allowsMultipleSelection: false) { result in
            Task { await importFile(result) }
        }
        .quickLookPreview($previewURL)
        .onDisappear { if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) } }
        .confirmationDialog(BH.s("sources.remove_confirm"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { source in
            Button(BH.s("sources.remove"), role: .destructive) { Task { await store.removeSource(source) } }
        }
    }

    private var addNote: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Text(verbatim: BH.s("sources.note")).font(TTFont.label).foregroundStyle(TT.textSecondary)
            TextField(BH.s("sources.note_placeholder"), text: $noteText, axis: .vertical)
                .lineLimit(2...6).focused($noteFocused).textFieldStyle(.plain).ttField()
                .accessibilityIdentifier("reports.sources.note")
            HStack {
                Picker(BH.s("sources.day"), selection: $noteDay) {
                    Text(verbatim: BH.s("sources.whole_week")).tag(LocalDay?.none)
                    ForEach(store.week.days, id: \.self) { day in Text(verbatim: dayTitle(day, calendar: store.calendar)).tag(LocalDay?.some(day)) }
                }
                .labelsHidden().frame(minHeight: 44)
                .accessibilityLabel(Text(verbatim: BH.s("sources.day")))
                Spacer(minLength: TT.Space.s)
                Button(BH.s("sources.note_add")) {
                    Task { if await store.addNoteSource(noteText, day: noteDay) { noteText = ""; noteFocused = false } }
                }
                .buttonStyle(.ttPrimary).disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy || noteText.count > 4000)
                .accessibilityIdentifier("reports.sources.note_add")
            }
            if noteText.count > 4000 { Label(BH.s("sources.note_too_long"), systemImage: "exclamationmark.circle.fill").font(TTFont.meta).foregroundStyle(TT.danger) }
        }
    }

    @ViewBuilder private func row(_ source: ReportSource) -> some View {
        let dayText = source.date.map { dayTitle($0, calendar: store.calendar) } ?? BH.s("sources.whole_week")
        HStack(spacing: TT.Space.m) {
            Button { Task { await open(source) } } label: {
                HStack(spacing: TT.Space.m) {
                    Image(systemName: source.isFile ? "doc" : "note.text").foregroundStyle(TT.textSecondary).frame(width: 24).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: source.isFile ? (source.file?.name ?? BH.s("sources.file_missing")) : (source.note ?? "")).font(TTFont.body)
                            .foregroundStyle(TT.textPrimary).lineLimit(4).multilineTextAlignment(.leading)
                        Text(verbatim: dayText).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if openingId == source.id { ProgressView() }
                }
                .frame(minHeight: 44).contentShape(.rect)
            }
            .buttonStyle(.plain).disabled(!source.isFile || source.file == nil)
            Button { removing = source } label: { Image(systemName: "trash").frame(width: 44, height: 44).contentShape(.rect) }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(verbatim: BH.s("sources.remove_label", source.isFile ? (source.file?.name ?? BH.s("sources.file_kind")) : BH.s("sources.note_kind"))))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.source")
    }

    private func importFile(_ result: Result<[URL], Error>) async {
        localError = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { localError = BH.s("sources.read_failed"); return }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        await store.addFileSource(name: url.lastPathComponent, contentType: type, data: data, day: noteDay)
    }

    private func open(_ source: ReportSource) async {
        guard let file = source.file, openingId == nil else { return }
        openingId = source.id
        defer { openingId = nil }
        localError = nil
        do {
            let data = try await store.fileData(file)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            tempDirectory = directory
            let target = directory.appendingPathComponent(file.safeFileName)
            try data.write(to: target)
            previewURL = target
        } catch {
            localError = BH.s("sources.open_failed")
        }
    }
}
