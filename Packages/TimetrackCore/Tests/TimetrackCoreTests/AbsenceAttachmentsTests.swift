import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TimetrackCore
@testable import TimetrackStores

// AB1: attach, list and remove files on absences. Synthetic data only; contract 0.24.0 (`/files`, `/absences/{id}/attachments`).

struct AttachmentRulesTests {
    @Test func whitelistMatchesThePWA() {
        for name in ["krank.pdf", "Foto.JPG", "scan.jpeg", "a.png", "b.heic", "notiz.txt"] { #expect(AttachmentRules.isAllowed(name: name), "\(name)") }
        for name in ["archiv.zip", "dokument.docx", "ohne-endung", ".pdf", "bild.gif", "x.exe"] { #expect(!AttachmentRules.isAllowed(name: name), "\(name)") }
    }

    @Test func validationOrderTypeEmptyHuge() {
        #expect(AttachmentRules.validate(name: "a.pdf", size: 10) == nil)
        #expect(AttachmentRules.validate(name: "a.zip", size: 10) == .unsupportedType)
        #expect(AttachmentRules.validate(name: "a.pdf", size: 0) == .empty)
        #expect(AttachmentRules.validate(name: "a.pdf", size: AttachmentRules.hardMaxBytes + 1) == .tooLarge)
    }

    @Test func contentTypesAndNames() {
        #expect(AttachmentRules.contentType(forName: "a.JPG") == "image/jpeg" && AttachmentRules.contentType(forName: "a.pdf") == "application/pdf")
        #expect(AttachmentRules.contentType(forName: "a.heic") == "image/heic" && AttachmentRules.contentType(forName: "a.txt") == "text/plain")
        #expect(AttachmentRules.sanitizedName("../../etc/passwd.pdf") == ".._.._etc_passwd.pdf")
        #expect(AttachmentRules.sanitizedName("  a\u{0007}b\".pdf ") == "a_b_.pdf")
        #expect(AttachmentRules.sanitizedName("   ") == "Anhang")
        let long = String(repeating: "x", count: 300) + ".pdf"
        let cleaned = AttachmentRules.sanitizedName(long)
        #expect(cleaned.count <= 120 && cleaned.hasSuffix(".pdf"))
    }
}

struct ImageCompressorTests {
    private func png(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func size(of data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    @Test func shrinksLargeImagesToJPEG() throws {
        let jpeg = try #require(ImageCompressor.jpegData(from: png(width: 1200, height: 600), maxPixelSize: 400))
        #expect(Array(jpeg.prefix(3)) == [0xFF, 0xD8, 0xFF])
        let (width, height) = try #require(size(of: jpeg))
        #expect(width == 400 && height == 200)
    }

    @Test func doesNotEnlargeSmallImages() throws {
        let jpeg = try #require(ImageCompressor.jpegData(from: png(width: 100, height: 50), maxPixelSize: 3000))
        let (width, height) = try #require(size(of: jpeg))
        #expect(width <= 100 && height <= 50)
    }

    @Test func nonImagesGiveNil() {
        #expect(ImageCompressor.jpegData(from: Data("hello".utf8)) == nil)
        #expect(ImageCompressor.jpegName(for: "IMG_0001.HEIC") == "IMG_0001.jpg" && ImageCompressor.jpegName(for: "") == "Foto.jpg")
    }
}

@MainActor
struct AbsenceAttachmentsStoreTests {
    private let absenceId = UUID(uuidString: "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa")!
    private let fileA = "cccccccc-0000-4000-8000-00000000000a"
    private let fileB = "cccccccc-0000-4000-8000-00000000000b"
    private var listKey: String { "GET /api/v1/absences/\(absenceId.uuidString.lowercased())/attachments" }
    private var attachKey: String { "POST /api/v1/absences/\(absenceId.uuidString.lowercased())/attachments" }

    private func meta(_ id: String, name: String = "krankschein.pdf") -> String {
        #"{"id":"\#(id)","name":"\#(name)","size":4,"sha256":"x","contentType":"application/pdf","createdAt":"2026-10-20T08:00:00Z"}"#
    }

    private func store(_ transport: MockTransport, changed: (@MainActor () -> Void)? = nil) -> AbsenceAttachmentsStore {
        AbsenceAttachmentsStore(client: Fixtures.client(transport), absenceId: absenceId, onChanged: changed)
    }

    /// Waits until the predicate holds (uploads run in a task started by `add`).
    private func settle(_ store: AbsenceAttachmentsStore, _ predicate: @MainActor () -> Bool) async {
        for _ in 0..<400 where !predicate() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func listsAttachments() async {
        let transport = MockTransport()
        transport.set(listKey, body: "[\(meta(fileA))]")
        let store = store(transport)
        await store.load()
        #expect(store.phase == .loaded && store.files.map(\.name) == ["krankschein.pdf"])
    }

    @Test func serverWithoutAttachmentsIsUnavailableNotBroken() async {
        let transport = MockTransport()
        transport.set(listKey, status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let store = store(transport)
        await store.load()
        #expect(store.phase == .unavailable)
    }

    @Test func uploadsAndLinksThenReloadsAndNotifies() async {
        let transport = MockTransport()
        transport.set(listKey, body: "[]")
        transport.set("POST /api/v1/files", status: 201, body: meta(fileA))
        transport.set(attachKey, status: 201, body: meta(fileA))
        var changed = 0
        let store = store(transport) { changed += 1 }
        await store.load()
        transport.set(listKey, body: "[\(meta(fileA))]")
        store.add(name: "krankschein.pdf", data: Data("%PDF-1.4 x".utf8))
        await settle(store) { store.uploads.isEmpty && changed > 0 }
        #expect(store.uploads.isEmpty && store.files.count == 1 && changed == 1)
        let multipart = String(decoding: transport.requests(matching: "POST /api/v1/files").first?.httpBody ?? Data(), as: UTF8.self)
        #expect(multipart.contains("name=\"file\"; filename=\"krankschein.pdf\"") && multipart.contains("Content-Type: application/pdf"))
        let link = transport.requests(matching: attachKey).first
        let linkBody = String(decoding: link?.httpBody ?? Data(), as: UTF8.self)
        #expect(linkBody.contains(fileA))
    }

    @Test func rejectedFilesNeverReachTheNetwork() async {
        let transport = MockTransport()
        let store = store(transport)
        store.add(name: "virus.exe", data: Data([1]))
        store.add(name: "leer.pdf", data: Data())
        #expect(store.uploads.map(\.state) == [.failed(.unsupportedType), .failed(.empty)])
        #expect(transport.requests(matching: "POST /api/v1/files").isEmpty)
        store.retry(store.uploads[0].id) // not retryable
        #expect(store.uploads[0].state == .failed(.unsupportedType))
        store.dismiss(store.uploads[0].id)
        #expect(store.uploads.count == 1)
    }

    @Test func tooLargeFromTheServerIsNotRetryable() async {
        let transport = MockTransport()
        transport.set("POST /api/v1/files", status: 413, body: #"{"error":{"code":"file_too_large","message":"x"}}"#)
        let store = store(transport)
        store.add(name: "gross.pdf", data: Data([1, 2, 3]))
        await settle(store) { !store.isUploading }
        #expect(store.uploads.first?.state == .failed(.tooLarge))
        #expect(UploadFailure.tooLarge.isRetryable == false)
        // Also by status alone (a proxy in front of the server may answer without our error body).
        transport.set("POST /api/v1/files", status: 413, body: "<html>too big</html>")
        store.add(name: "gross2.pdf", data: Data([1]))
        await settle(store) { !store.isUploading }
        #expect(store.uploads.last?.state == .failed(.tooLarge))
    }

    @Test func unsupportedTypeFromTheServer() async {
        let transport = MockTransport()
        transport.set("POST /api/v1/files", status: 415, body: #"{"error":{"code":"unsupported_type","message":"x"}}"#)
        let store = store(transport)
        store.add(name: "komisch.pdf", data: Data([1, 2, 3]))
        await settle(store) { !store.isUploading }
        #expect(store.uploads.first?.state == .failed(.unsupportedType))
    }

    @Test func offlineKeepsTheDataAndRetryWorks() async {
        let transport = MockTransport()
        transport.set(listKey, body: "[\(meta(fileA))]")
        transport.set("POST /api/v1/files", error: .notConnectedToInternet)
        let store = store(transport)
        store.add(name: "krankschein.pdf", data: Data("%PDF-1.4 x".utf8))
        await settle(store) { !store.isUploading }
        let failed = store.uploads.first
        #expect(failed?.state == .failed(.offline) && failed?.byteCount == 10)
        transport.set("POST /api/v1/files", status: 201, body: meta(fileA))
        transport.set(attachKey, status: 201, body: meta(fileA))
        store.retry(failed!.id)
        #expect(store.isUploading)
        await settle(store) { store.uploads.isEmpty && store.files.count == 1 }
        #expect(store.uploads.isEmpty && store.files.count == 1)
        #expect(transport.requests(matching: "POST /api/v1/files").count == 2)
    }

    @Test func linkFailureRemovesTheOrphanAndKeepsTheItemForRetry() async {
        let transport = MockTransport()
        transport.set("POST /api/v1/files", status: 201, body: meta(fileA))
        transport.set(attachKey, status: 500, body: #"{"error":{"code":"internal","message":"x"}}"#)
        transport.set(listKey, body: "[]") // the link state was checked and the file is certainly not linked
        transport.set("DELETE /api/v1/files/\(fileA)", status: 204)
        let store = store(transport)
        store.add(name: "krankschein.pdf", data: Data([1, 2]))
        await settle(store) { !store.isUploading }
        guard case .failed(.server) = store.uploads.first?.state else { Issue.record("expected a server failure"); return }
        #expect(transport.requests(matching: "DELETE /api/v1/files/\(fileA)").count == 1)
        #expect(store.uploads.first?.state != nil && UploadFailure.server(.network(.timedOut)).isRetryable)
    }

    @Test func definiteRejectionDeletesTheOrphanWithoutAskingTheList() async {
        let transport = MockTransport()
        transport.set("POST /api/v1/files", status: 201, body: meta(fileA))
        transport.set(attachKey, status: 422, body: #"{"error":{"code":"validation_failed","message":"x"}}"#)
        transport.set("DELETE /api/v1/files/\(fileA)", status: 204)
        let store = store(transport)
        store.add(name: "krankschein.pdf", data: Data([1, 2]))
        await settle(store) { !store.isUploading }
        #expect(transport.requests(matching: "DELETE /api/v1/files/\(fileA)").count == 1)
        #expect(transport.requests(matching: listKey).isEmpty)
    }

    @Test func lostSuccessResponseKeepsTheExistingLinkAndCountsAsSuccess() async {
        let transport = MockTransport()
        transport.set("POST /api/v1/files", status: 201, body: meta(fileA))
        transport.set(attachKey, error: .timedOut) // the server linked the file, only the answer got lost
        transport.set(listKey, body: "[\(meta(fileA))]")
        transport.set("DELETE /api/v1/files/\(fileA)", status: 204)
        let store = store(transport)
        store.add(name: "krankschein.pdf", data: Data([1, 2]))
        await settle(store) { store.uploads.isEmpty && store.files.count == 1 }
        #expect(store.uploads.isEmpty && store.files.count == 1)
        #expect(transport.requests(matching: "DELETE /api/v1/files/\(fileA)").isEmpty) // deleting would have removed the link
    }

    @Test func unknownLinkStateNeverDeletesTheUpload() async {
        let transport = MockTransport()
        transport.set("POST /api/v1/files", status: 201, body: meta(fileA))
        transport.set(attachKey, error: .timedOut)
        transport.set(listKey, error: .timedOut) // cannot tell whether the link exists
        transport.set("DELETE /api/v1/files/\(fileA)", status: 204)
        let store = store(transport)
        store.add(name: "krankschein.pdf", data: Data([1, 2]))
        await settle(store) { !store.isUploading }
        #expect(store.uploads.first?.state == .failed(.offline))
        #expect(transport.requests(matching: "DELETE /api/v1/files/\(fileA)").isEmpty)
    }

    @Test func removingDetachesThenDeletesTheFile() async {
        let transport = MockTransport()
        transport.set(listKey, body: "[\(meta(fileA)),\(meta(fileB, name: "zweite.pdf"))]")
        transport.set("DELETE /api/v1/absences/\(absenceId.uuidString.lowercased())/attachments/\(fileA)", status: 204)
        transport.set("DELETE /api/v1/files/\(fileA)", status: 204)
        var changed = 0
        let observed = AbsenceAttachmentsStore(client: Fixtures.client(transport), absenceId: absenceId) { changed += 1 }
        await observed.load()
        transport.set(listKey, body: "[\(meta(fileB, name: "zweite.pdf"))]")
        await observed.remove(observed.files[0])
        #expect(observed.files.map(\.name) == ["zweite.pdf"] && changed == 1 && observed.lastError == nil)
        #expect(transport.requests(matching: "DELETE /api/v1/files/\(fileA)").count == 1)
    }

    @Test func removeFailureKeepsTheListAndReportsTheError() async {
        let transport = MockTransport()
        transport.set(listKey, body: "[\(meta(fileA))]")
        let store = store(transport)
        await store.load()
        transport.set("DELETE /api/v1/absences/\(absenceId.uuidString.lowercased())/attachments/\(fileA)", error: .timedOut)
        await store.remove(store.files[0])
        #expect(store.files.count == 1 && store.lastError == .network(.timedOut))
        #expect(transport.requests(matching: "DELETE /api/v1/files/\(fileA)").isEmpty) // the file stays when detaching failed
    }
}

struct UploadProgressTests {
    /// The progress handler is passed through to the transport (URLSession reports it; mocks may ignore it).
    final class ProgressTransport: HTTPTransport, @unchecked Sendable {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { try await send(request, progress: nil) }
        func send(_ request: URLRequest, progress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
            progress?(0.25)
            progress?(1)
            let body = #"{"id":"cccccccc-0000-4000-8000-00000000000a","name":"a.pdf","size":1,"sha256":"x","contentType":"application/pdf","createdAt":"2026-10-20T08:00:00Z"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }
    }

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        func add(_ value: Double) { lock.withLock { values.append(value) } }
        var all: [Double] { lock.withLock { values } }
    }

    @Test func uploadReportsProgress() async throws {
        let client = APIClient(baseURL: Fixtures.baseURL, transport: ProgressTransport())
        let recorder = Recorder()
        _ = try await client.uploadFile(name: "a.pdf", contentType: "application/pdf", data: Data([1])) { recorder.add($0) }
        #expect(recorder.all == [0.25, 1])
    }
}
