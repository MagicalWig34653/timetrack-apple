import Foundation
import Observation
import TimetrackCore

extension APIClient {
    /// Uploads a file and links it to an absence. When only the linking fails the orphaned upload is removed again (best effort).
    @discardableResult
    public func uploadAttachment(absenceId: UUID, name: String, contentType: String, data: Data,
                                 progress: (@Sendable (Double) -> Void)? = nil) async throws -> FileMeta {
        let meta = try await uploadFile(name: name, contentType: contentType, data: data, progress: progress)
        do {
            return try await attachFile(absenceId: absenceId, fileId: meta.id)
        } catch {
            // `DELETE /files/{id}` also removes an existing attachment link, so the upload may only be removed when it is
            // certainly unlinked. Unclear outcomes (the success response may just have been lost) are checked first.
            if Self.isOutcomeUnclear(error) {
                guard let linked = try? await listAbsenceAttachments(id: absenceId) else { throw error } // state unknown: keep the file
                if let existing = linked.first(where: { $0.id == meta.id }) { return existing } // the link exists: success
            }
            try? await deleteFile(id: meta.id)
            throw error
        }
    }

    /// Network errors, timeouts, cancellation and server errors: the request may have been applied although no success arrived.
    static func isOutcomeUnclear(_ error: Error) -> Bool {
        guard let error = error as? TimetrackError, let status = error.status else { return true }
        return status >= 500 || status == 408
    }
}

/// Why an upload did not work; the UI maps these to German texts.
public enum UploadFailure: Sendable, Equatable {
    case unsupportedType, empty, tooLarge
    /// No connection or a timeout.
    case offline
    case server(TimetrackError)

    /// Worth trying again with the same data (everything except files the server or the rules reject).
    public var isRetryable: Bool {
        switch self {
        case .unsupportedType, .empty, .tooLarge: false
        case .offline, .server: true
        }
    }

    public init(_ error: TimetrackError) {
        if error.status == 413 || error.knownCode == .fileTooLarge { self = .tooLarge }
        else if error.status == 415 || error.knownCode == .unsupportedType { self = .unsupportedType }
        else if error.isNetworkError { self = .offline }
        else { self = .server(error) }
    }
}

/// One file on its way to an absence. The data stays in memory until the upload worked or the user dismisses it, so "Erneut versuchen" needs no new pick.
public struct PendingUpload: Identifiable, Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case uploading(progress: Double)
        case failed(UploadFailure)
    }

    public let id: UUID
    public let name: String
    public let contentType: String
    public let data: Data
    public var state: State
    public var byteCount: Int { data.count }
}

/// Attachments of one absence: list, upload with progress and retry, delete (PWA `AbsenceAttachments`, plus the Apple capture paths).
@MainActor
@Observable
public final class AbsenceAttachmentsStore {
    public enum Phase: Equatable { case loading, loaded, failed(TimetrackError), unavailable }

    public private(set) var phase: Phase = .loading
    public private(set) var files: [FileMeta] = []
    public private(set) var uploads: [PendingUpload] = []
    /// Set after a delete or upload that the user should hear about (cleared by the UI).
    public var lastError: TimetrackError?
    public private(set) var removing: Set<UUID> = []

    public let absenceId: UUID
    private let client: APIClient
    /// Called when the number of attachments changed (the Urlaub list reloads its paperclips).
    private let onChanged: (@MainActor () -> Void)?

    public init(client: APIClient, absenceId: UUID, onChanged: (@MainActor () -> Void)? = nil) {
        self.client = client
        self.absenceId = absenceId
        self.onChanged = onChanged
    }

    public var isUploading: Bool { uploads.contains { if case .uploading = $0.state { true } else { false } } }

    public func load() async {
        if files.isEmpty { phase = .loading }
        do {
            files = try await client.listAbsenceAttachments(id: absenceId)
            phase = .loaded
        } catch let error as TimetrackError {
            if error.status == 404 || error.status == 501 { phase = .unavailable } else if error != .cancelled { phase = .failed(error) }
        } catch {
            phase = .failed(.cancelled)
        }
    }

    /// Validates and uploads one file. A rejected file stays in the list as a failed entry so the reason is visible.
    @discardableResult
    public func add(name: String, data: Data, contentType: String? = nil) -> UUID {
        let safeName = AttachmentRules.sanitizedName(name)
        let type = contentType ?? AttachmentRules.contentType(forName: safeName)
        var item = PendingUpload(id: UUID(), name: safeName, contentType: type, data: data, state: .uploading(progress: 0))
        if let problem = AttachmentRules.validate(name: safeName, size: data.count) {
            item.state = .failed(problem == .unsupportedType ? .unsupportedType : problem == .empty ? .empty : .tooLarge)
            uploads.append(item)
            return item.id
        }
        uploads.append(item)
        let id = item.id
        Task { await upload(id) }
        return id
    }

    public func retry(_ id: UUID) {
        guard let index = uploads.firstIndex(where: { $0.id == id }), case .failed(let failure) = uploads[index].state, failure.isRetryable else { return }
        uploads[index].state = .uploading(progress: 0)
        Task { await upload(id) }
    }

    public func dismiss(_ id: UUID) { uploads.removeAll { $0.id == id } }

    private func setProgress(_ id: UUID, _ value: Double) {
        guard let index = uploads.firstIndex(where: { $0.id == id }), case .uploading = uploads[index].state else { return }
        uploads[index].state = .uploading(progress: value)
    }

    private func upload(_ id: UUID) async {
        guard let item = uploads.first(where: { $0.id == id }) else { return }
        do {
            try await client.uploadAttachment(absenceId: absenceId, name: item.name, contentType: item.contentType, data: item.data) { [weak self] value in
                Task { @MainActor in self?.setProgress(id, value) }
            }
            uploads.removeAll { $0.id == id }
            await load()
            onChanged?()
        } catch let error as TimetrackError {
            guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
            uploads[index].state = .failed(UploadFailure(error))
        } catch {
            guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
            uploads[index].state = .failed(.offline)
        }
    }

    /// Detaches the file and deletes it (the document is not needed any more; the delete is best effort like in the PWA).
    public func remove(_ file: FileMeta) async {
        removing.insert(file.id)
        defer { removing.remove(file.id) }
        do {
            try await client.detachFile(absenceId: absenceId, fileId: file.id)
            try? await client.deleteFile(id: file.id)
            lastError = nil
            await load()
            onChanged?()
        } catch let error as TimetrackError {
            if error != .cancelled { lastError = error }
        } catch {
            lastError = .cancelled
        }
    }

    public func data(of file: FileMeta) async throws -> Data {
        try await client.downloadFile(id: file.id, inline: file.supportsInline)
    }
}
