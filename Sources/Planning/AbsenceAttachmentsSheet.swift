import PhotosUI
import QuickLook
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
import UniformTypeIdentifiers
#if os(iOS)
import VisionKit
#endif

// AB1: attachments of an absence (V3 showed them; AB1 adds, scans, drops and deletes them).
// Paths in: Files picker, document scanner (iOS, VisionKit), photo library, drag and drop (iPad, Mac).
// Strings live in `Vacation.xcstrings` (table "Vacation").

/// Lists the attachments of one absence, previews them with QuickLook, adds new ones and deletes them.
struct AbsenceAttachmentsSheet: View {
    let planning: PlanningStore
    let absence: Absence
    @State private var store: AbsenceAttachmentsStore
    @Environment(\.dismiss) private var dismiss
    @State private var openingId: UUID?
    @State private var openError = false
    @State private var readError: String?
    @State private var previewURL: URL?
    @State private var tempDirectory: URL?
    @State private var importing = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var deleting: FileMeta?
    @State private var dropTargeted = false
    #if os(iOS)
    @State private var scanning = false
    #endif

    init(planning: PlanningStore, absence: Absence) {
        self.planning = planning
        self.absence = absence
        _store = State(initialValue: planning.makeAttachmentsStore(for: absence))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    addSection
                    if !store.uploads.isEmpty { uploadsSection }
                    filesSection
                    if openError { HintBanner(LocalizedStringKey(VT.s("attachments.open_failed")), symbol: "exclamationmark.triangle.fill") }
                    if let readError { HintBanner(LocalizedStringKey(readError), symbol: "exclamationmark.triangle.fill") }
                    if let error = store.lastError {
                        ErrorBanner(message: error.germanDescription, retryTitle: "common.dismiss") { store.lastError = nil }.accessibilityIdentifier("attachments.error")
                    }
                }
                .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .overlay { if dropTargeted { dropOverlay } }
            .navigationTitle(VT.s("attachments.title")).inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(VT.s("attachments.done")) { dismiss() }.accessibilityIdentifier("attachments.done") } }
            .quickLookPreview($previewURL)
            .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await importFiles(urls) } }
            }
            .onDrop(of: [.fileURL, .image, .pdf, .plainText], isTargeted: $dropTargeted) { providers in
                handleDrop(providers)
                return true
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await importPhotos(items) }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $scanning) {
                DocumentScannerView { images in
                    scanning = false
                    importScan(images)
                } onCancel: { scanning = false }
                .ignoresSafeArea()
            }
            #endif
            .confirmationDialog(VT.s("attachments.delete_title"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { file in
                Button(VT.s("attachments.delete"), role: .destructive) { Task { await store.remove(file) } }
            } message: { file in Text(verbatim: VT.s("attachments.delete_message", file.name)) }
        }
        .task {
            await store.load()
            #if DEBUG
            await debugAttachFromEnvironment()
            #endif
        }
        .onDisappear { if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) } }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }

    static let importTypes: [UTType] = [.pdf, .png, .jpeg, .heic, .plainText]

    // MARK: Add

    private var addSection: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Eyebrow(verbatim: VT.s("attachments.add_title")).padding(.horizontal, TT.Space.s).accessibilityAddTraits(.isHeader)
            ListCard {
                addRow(symbol: "folder", title: VT.s("attachments.add_file"), id: "attachments.add.file") { importing = true }
                #if os(iOS)
                if VNDocumentCameraViewController.isSupported {
                    addRow(symbol: "doc.viewfinder", title: VT.s("attachments.add_scan"), id: "attachments.add.scan") { scanning = true }
                }
                #endif
                PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                    Self.addLabel(symbol: "photo.on.rectangle", title: VT.s("attachments.add_photo"))
                }
                .buttonStyle(.plain).accessibilityIdentifier("attachments.add.photo")
            }
            Text(verbatim: VT.s("attachments.add_hint") + dropHint).font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.s)
        }
    }

    private var dropHint: String {
        #if os(macOS)
        " " + VT.s("attachments.add_hint_drop")
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? " " + VT.s("attachments.add_hint_drop") : ""
        #endif
    }

    private nonisolated static func addLabel(symbol: String, title: String) -> some View {
        HStack(spacing: TT.Space.m) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(TT.kindVacation)
            Text(verbatim: title).font(TTFont.body).foregroundStyle(TT.textPrimary)
            Spacer(minLength: TT.Space.s)
            Image(systemName: "plus.circle").foregroundStyle(TT.textSecondary)
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).frame(minHeight: 44)
        .contentShape(.rect)
    }

    private func addRow(symbol: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Self.addLabel(symbol: symbol, title: title) }
            .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: TT.Radius.card, style: .continuous)
            .strokeBorder(TT.kindVacation, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            .background(TT.kindVacation.opacity(0.08), in: .rect(cornerRadius: TT.Radius.card, style: .continuous))
            .overlay { Label(VT.s("attachments.drop_here"), systemImage: "arrow.down.doc").font(TTFont.cardTitle).foregroundStyle(TT.kindVacation) }
            .padding(TT.Space.m).allowsHitTesting(false)
    }

    // MARK: Uploads in progress

    private var uploadsSection: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            Eyebrow(verbatim: VT.s("attachments.uploads_title")).padding(.horizontal, TT.Space.s).accessibilityAddTraits(.isHeader)
            ListCard { ForEach(store.uploads) { uploadRow($0) } }
        }
    }

    private func uploadRow(_ item: PendingUpload) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            HStack(spacing: TT.Space.m) {
                Image(systemName: Self.symbol(item.contentType)).frame(width: 28).foregroundStyle(TT.kindVacation)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.name).font(TTFont.body).foregroundStyle(TT.textPrimary).lineLimit(2)
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                Spacer(minLength: TT.Space.s)
            }
            switch item.state {
            case .uploading(let progress):
                ProgressBar(progress: progress, tint: TT.kindVacation)
                Text(verbatim: VT.s("attachments.uploading", Int((progress * 100).rounded()))).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            case .failed(let failure):
                Label(Self.message(for: failure), systemImage: "exclamationmark.triangle.fill").font(TTFont.meta).foregroundStyle(TT.danger)
                HStack(spacing: TT.Space.m) {
                    if failure.isRetryable {
                        Button(VT.s("attachments.retry_upload")) { store.retry(item.id) }.buttonStyle(.bordered).buttonBorderShape(.capsule).accessibilityIdentifier("attachments.retry")
                    }
                    Button(VT.s("attachments.dismiss"), role: .cancel) { store.dismiss(item.id) }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                        .accessibilityIdentifier("attachments.dismiss")
                }
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .accessibilityElement(children: .contain).accessibilityIdentifier("attachments.upload")
    }

    static func message(for failure: UploadFailure) -> String {
        switch failure {
        case .tooLarge: VT.s("attachments.failed.too_large")
        case .unsupportedType: VT.s("attachments.failed.unsupported")
        case .empty: VT.s("attachments.failed.empty")
        case .offline: VT.s("attachments.failed.offline")
        case .server(let error): error.germanDescription
        }
    }

    // MARK: Files

    @ViewBuilder private var filesSection: some View {
        switch store.phase {
        case .loading: SkeletonList(rows: 2)
        case .failed:
            ErrorBanner(message: VT.s("attachments.load_failed"), retryTitle: "common.retry") { Task { await store.load() } }
        case .unavailable:
            Card { EmptyState(symbol: "paperclip", title: LocalizedStringKey(VT.s("attachments.unavailable"))) }
        case .loaded:
            if store.files.isEmpty {
                if store.uploads.isEmpty { Card { EmptyState(symbol: "paperclip", title: LocalizedStringKey(VT.s("attachments.empty"))) } }
            } else {
                VStack(alignment: .leading, spacing: TT.Space.s) {
                    Eyebrow(verbatim: VT.s("attachments.files_title")).padding(.horizontal, TT.Space.s).accessibilityAddTraits(.isHeader)
                    ListCard { ForEach(store.files) { row($0) } }
                }
            }
        }
    }

    private func row(_ file: FileMeta) -> some View {
        HStack(spacing: 0) {
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
                .padding(.leading, TT.Space.l).padding(.vertical, TT.Space.m)
                .contentShape(.rect)
            }
            .buttonStyle(.plain).disabled(openingId != nil)
            .accessibilityHint(Text(verbatim: VT.s("attachments.hint")))
            .accessibilityIdentifier("attachment.row")
            Button { deleting = file } label: {
                Image(systemName: store.removing.contains(file.id) ? "hourglass" : "trash").foregroundStyle(TT.danger).frame(width: 44, height: 44).contentShape(.rect)
            }
            .buttonStyle(.plain).disabled(store.removing.contains(file.id))
            .accessibilityLabel(Text(verbatim: VT.s("attachments.delete_label", file.name)))
            .accessibilityIdentifier("attachment.delete")
            .padding(.trailing, TT.Space.xs)
        }
    }

    static func symbol(_ contentType: String) -> String {
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType == "application/pdf" { return "doc.richtext" }
        return "doc"
    }

    // MARK: Preview

    private func open(_ file: FileMeta) async {
        openError = false
        openingId = file.id
        defer { openingId = nil }
        do {
            let data = try await store.data(of: file)
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

    // MARK: Import paths

    private func importFiles(_ urls: [URL]) async {
        readError = nil
        for url in urls {
            let loaded = await Task.detached { () -> Data? in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try? Data(contentsOf: url)
            }.value
            guard let data = loaded else { readError = VT.s("attachments.read_failed"); continue }
            store.add(name: url.lastPathComponent, data: data)
        }
    }

    /// Photos: any format the library holds (HEIC, JPEG, PNG, ...) becomes a JPEG of at most 3000 px, so it is small and previews anywhere.
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        readError = nil
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self) else { readError = VT.s("attachments.read_failed"); continue }
            let jpeg = await Task.detached { ImageCompressor.jpegData(from: raw) }.value
            guard let jpeg else { readError = VT.s("attachments.read_failed"); continue }
            store.add(name: Self.stampedName(prefix: "Foto", ext: "jpg"), data: jpeg, contentType: "image/jpeg")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        readError = nil
        for provider in providers {
            let identifier = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .data) == true } ?? UTType.item.identifier
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                // The file only exists during this callback, so it is read right here.
                guard let url, let data = try? Data(contentsOf: url) else {
                    Task { @MainActor in readError = VT.s("attachments.read_failed") }
                    return
                }
                let name = url.lastPathComponent
                Task { @MainActor in store.add(name: name, data: data) }
            }
        }
    }

    static func stampedName(prefix: String, ext: String, date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return "\(prefix)_\(formatter.string(from: date)).\(ext)"
    }

    #if os(iOS)
    private func importScan(_ images: [UIImage]) {
        readError = nil
        Task {
            let pdf = await Task.detached { ScanPDF.make(images: images) }.value
            guard let pdf else { readError = VT.s("attachments.scan_failed"); return }
            store.add(name: Self.stampedName(prefix: "Scan", ext: "pdf"), data: pdf, contentType: "application/pdf")
        }
    }
    #endif

    #if DEBUG
    /// UI tests cannot drive the system pickers, so `TT_DEV_ATTACH_FILE=<path>` adds that file once, like a pick would.
    private func debugAttachFromEnvironment() async {
        guard let path = ProcessInfo.processInfo.environment["TT_DEV_ATTACH_FILE"], !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        store.add(name: URL(fileURLWithPath: path).lastPathComponent, data: data)
    }
    #endif
}

#if os(iOS)
import PDFKit

/// Pages of a document scan as one PDF (JPEG-compressed images, so a three-page scan stays well below the server limit).
enum ScanPDF {
    static func make(images: [UIImage]) -> Data? {
        let document = PDFDocument()
        for image in images {
            guard let page = PDFPage(image: image, options: [.compressionQuality: 0.7]) else { continue }
            document.insert(page, at: document.pageCount)
        }
        return document.pageCount == 0 ? nil : document.dataRepresentation()
    }
}

/// VisionKit document scanner (camera with edge detection and perspective correction). Needs a real camera, so the row is hidden in the simulator.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onFinish: @MainActor ([UIImage]) -> Void
    let onCancel: @MainActor () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish, onCancel: onCancel) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: @MainActor ([UIImage]) -> Void
        private let onCancel: @MainActor () -> Void
        init(onFinish: @escaping @MainActor ([UIImage]) -> Void, onCancel: @escaping @MainActor () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        // VisionKit calls its delegate on the main thread.
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            let finish = onFinish
            MainActor.assumeIsolated { finish(images) }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { let cancel = onCancel; MainActor.assumeIsolated { cancel() } }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { let cancel = onCancel; MainActor.assumeIsolated { cancel() } }
    }
}
#endif

// MARK: - Row button

/// Paperclip with count next to a list row; opens the attachment sheet. Without attachments it invites to add one.
struct AttachmentButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) { AttachmentGlyph(count: count) }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityHint(Text(verbatim: VT.s("attachments.hint")))
            .accessibilityIdentifier("absence.attachments")
    }

    private var label: String {
        count == 0 ? VT.s("attachments.add_a11y") : VT.s(count == 1 ? "attachments.count_one" : "attachments.count_other", count)
    }
}

struct AttachmentGlyph: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: count == 0 ? "paperclip.badge.plus" : "paperclip")
            if count > 1 { Text(verbatim: "\(count)").font(TTFont.meta).monospacedDigit() }
        }
        .foregroundStyle(count == 0 ? TT.textTertiary : TT.textSecondary)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
    }
}
