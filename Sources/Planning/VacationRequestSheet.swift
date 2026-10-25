import PDFKit
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
import UniformTypeIdentifiers

// AB1: fills the account's vacation request template (stored on the server, set up in the web app) for one vacation absence.
// The PDF is filled on this device with PDFKit; nothing but the optional attachment upload leaves it.

struct VacationRequestSheet: View {
    let absence: Absence
    private let calendar: DayCalendar
    @State private var store: VacationRequestStore
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?
    @State private var tempDirectory: URL?
    @State private var exporting = false

    init(planning: PlanningStore, absence: Absence) {
        self.absence = absence
        self.calendar = planning.calendar
        _store = State(initialValue: planning.makeRequestStore(for: absence))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    Text(verbatim: VT.s("request.period", PlanFormat.range(absence.startDate, absence.endDate, calendar: calendar)))
                        .font(TTFont.label).foregroundStyle(TT.textSecondary)
                    switch store.phase {
                    case .loading: SkeletonList(rows: 3)
                    case .noTemplate: noTemplate
                    case .failed(let error):
                        ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await store.load() } }.accessibilityIdentifier("request.error")
                    case .ready: form
                    }
                }
                .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(VT.s("request.title")).inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(VT.s("attachments.done")) { dismiss() }.accessibilityIdentifier("request.done") } }
        }
        .task { await store.load() }
        .onDisappear { if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) } }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    // MARK: No template

    private var noTemplate: some View {
        VStack(alignment: .leading, spacing: TT.Space.m) {
            Card {
                VStack(alignment: .leading, spacing: TT.Space.m) {
                    EmptyState(symbol: "doc.badge.plus", title: LocalizedStringKey(VT.s("request.no_template_title")))
                    Text(verbatim: VT.s("request.no_template")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
            }
            if let url = model.serverURL?.appendingPathComponent("settings/vacation-form") {
                Link(destination: url) {
                    Label(VT.s("request.setup_web"), systemImage: "arrow.up.right").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.ttSecondary).accessibilityIdentifier("request.setup_web")
            }
        }
        .accessibilityIdentifier("request.no_template")
    }

    // MARK: Form

    @ViewBuilder private var form: some View {
        if let data = store.request {
            if store.mappedFieldCount == 0 { HintBanner(LocalizedStringKey(VT.s("request.unmapped")), symbol: "exclamationmark.triangle.fill") }
            summary(data)
            inputs(data).disabled(store.isGenerating) // X4: no edits while the PDF is being filled
            Button { Task { await store.generate() } } label: {
                Text(verbatim: store.isGenerating ? VT.s("request.generating") : (store.generated == nil ? VT.s("request.generate") : VT.s("request.regenerate")))
            }
            .buttonStyle(.ttPrimary).disabled(store.isGenerating).accessibilityIdentifier("request.generate")
            if let problem = store.generationProblem {
                ErrorBanner(message: Self.message(for: problem), retryTitle: "common.retry") { Task { await store.generate() } }.accessibilityIdentifier("request.problem")
            }
            if let generated = store.generated { result(generated) }
            Text(verbatim: VT.s("request.privacy")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
        }
    }

    private func summary(_ data: FormRequestData) -> some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                HStack(alignment: .top, spacing: TT.Space.xl) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: VT.s("request.working_days")).font(TTFont.label).foregroundStyle(TT.textSecondary)
                        Text(verbatim: FormDays.format(data.workingDays)).font(TTFont.stat).foregroundStyle(TT.textPrimary).accessibilityIdentifier("request.working_days")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: VT.s("request.rest")).font(TTFont.label).foregroundStyle(TT.textSecondary)
                        Text(verbatim: "\(FormDays.format(Double(data.restBeforeHalfDays) / 2)) / \(FormDays.format(Double(data.restAfterHalfDays) / 2))")
                            .font(TTFont.stat).foregroundStyle(TT.textPrimary).accessibilityIdentifier("request.rest")
                    }
                }
                Text(verbatim: VT.s("request.stale", String(data.from.prefix(4)))).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func inputs(_ data: FormRequestData) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.l) {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Eyebrow(verbatim: VT.s("request.substitute")).padding(.horizontal, TT.Space.s)
                TextField(VT.s("request.substitute"), text: $store.substitute).textFieldStyle(.plain).ttField()
                    .accessibilityIdentifier("request.substitute")
                Text(verbatim: VT.s("request.substitute_hint")).font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.s)
            }
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Eyebrow(verbatim: VT.s("request.free_title")).padding(.horizontal, TT.Space.s).accessibilityAddTraits(.isHeader)
                ListCard {
                    if data.freeRanges.isEmpty {
                        Text(verbatim: VT.s("request.free_none")).font(TTFont.body).foregroundStyle(TT.textSecondary)
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(data.freeRanges.enumerated()), id: \.offset) { _, range in
                            Text(verbatim: Self.rangeText(range)).font(TTFont.body).foregroundStyle(TT.textPrimary)
                                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Toggle(VT.s("request.free_confirm"), isOn: $store.freeConfirmed).padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                            .accessibilityIdentifier("request.free_confirm")
                    }
                }
                if store.freeConfirmed, store.freeRangeSlots > 0, !store.freeRangeFit.overflow.isEmpty {
                    HintBanner(LocalizedStringKey(VT.s("request.free_overflow", store.freeRangeSlots, store.freeRangeFit.overflow.map(Self.rangeText).joined(separator: ", "))),
                               symbol: "exclamationmark.triangle.fill")
                }
            }
            ListCard {
                Toggle(VT.s("request.flatten"), isOn: $store.flatten).padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                    .accessibilityIdentifier("request.flatten")
            }
        }
    }

    static func rangeText(_ range: FormDayRange) -> String {
        let format = FormDateFormat.dotted
        return range.from == range.to ? format.format(range.from) : "\(format.format(range.from)) - \(format.format(range.to))"
    }

    // MARK: Result

    private func result(_ generated: VacationRequestStore.Generated) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.m) {
            Label(VT.s("request.ready"), systemImage: "checkmark.seal.fill").font(TTFont.cardTitle).foregroundStyle(TT.success).accessibilityIdentifier("request.ready")
            if !generated.skippedFields.isEmpty {
                HintBanner(LocalizedStringKey(VT.s("request.skipped", generated.skippedFields.joined(separator: ", "))), symbol: "exclamationmark.triangle.fill")
            }
            PDFPreview(data: generated.data)
                .frame(height: 380).clipShape(.rect(cornerRadius: TT.Radius.control, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: TT.Radius.control, style: .continuous).strokeBorder(TT.cardBorder) }
                .accessibilityLabel(Text(verbatim: VT.s("request.preview"))).accessibilityIdentifier("request.preview")
            actions(generated)
        }
        .task(id: generated.id) { prepareShare(generated) }
    }

    private func actions(_ generated: VacationRequestStore.Generated) -> some View {
        VStack(spacing: TT.Space.s) {
            attachButton
            HStack(spacing: TT.Space.s) {
                if let shareURL {
                    ShareLink(item: shareURL) { actionLabel(VT.s("request.share"), "square.and.arrow.up") }.buttonStyle(.ttSecondary).accessibilityIdentifier("request.share")
                }
                Button { exporting = true } label: { actionLabel(VT.s("request.save_files"), "folder") }
                    .buttonStyle(.ttSecondary).accessibilityIdentifier("request.save_files")
                Button { PDFPrinting.printPDF(generated.data, jobName: generated.fileName) } label: { actionLabel(VT.s("request.print"), "printer") }
                    .buttonStyle(.ttSecondary).accessibilityIdentifier("request.print")
            }
        }
        .fileExporter(isPresented: $exporting, document: PDFFile(data: generated.data), contentType: .pdf, defaultFilename: generated.fileName) { _ in }
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).labelStyle(.titleAndIcon).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, minHeight: 44)
    }

    @ViewBuilder private var attachButton: some View {
        switch store.attachState {
        case .saved:
            Label(VT.s("request.attached"), systemImage: "paperclip.circle.fill").font(TTFont.label).foregroundStyle(TT.success)
                .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("request.attached")
        case .failed(let failure):
            ErrorBanner(message: AbsenceAttachmentsSheet.message(for: failure), retryTitle: "common.retry") { Task { await store.saveAsAttachment() } }
                .accessibilityIdentifier("request.attach_error")
        case .idle, .saving:
            Button { Task { await store.saveAsAttachment() } } label: {
                Label(store.attachState == .saving ? VT.s("request.attaching") : VT.s("request.attach"), systemImage: "paperclip").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.ttSecondary).disabled(store.attachState == .saving).accessibilityIdentifier("request.attach")
        }
    }

    private func prepareShare(_ generated: VacationRequestStore.Generated) {
        do {
            let root = tempDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("vacation-request-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            tempDirectory = root
            // X4: one folder per generation, so the link never points at the file of an earlier PDF.
            let folder = root.appendingPathComponent(generated.id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(generated.fileName)
            try generated.data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            shareURL = nil
        }
    }

    static func message(for problem: FormPDFProblem) -> String {
        switch problem {
        case .notPDF: VT.s("request.problem.not_pdf")
        case .tooLarge: VT.s("request.problem.too_large")
        case .empty: VT.s("request.problem.empty")
        case .encrypted: VT.s("request.problem.encrypted")
        case .unreadable: VT.s("request.problem.unreadable")
        }
    }
}

// MARK: - PDF helpers

/// The generated PDF as a document for `fileExporter` ("In Dateien sichern" / "Sichern ...").
struct PDFFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

#if os(iOS)
struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) { view.document = PDFDocument(data: data) }
}
#else
struct PDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) { view.document = PDFDocument(data: data) }
}
#endif

enum PDFPrinting {
    @MainActor static func printPDF(_ data: Data, jobName: String) {
        #if os(iOS)
        guard UIPrintInteractionController.isPrintingAvailable else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
        #else
        guard let document = PDFDocument(data: data) else { return }
        let info = NSPrintInfo.shared
        document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true)?.run()
        #endif
    }
}
