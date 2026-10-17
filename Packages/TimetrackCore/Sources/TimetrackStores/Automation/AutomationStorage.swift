import Foundation

/// Persists one small JSON document (queue, state). The app uses a file; tests use memory.
public protocol BlobStorage: Sendable {
    func load() -> Data?
    func save(_ data: Data)
}

public final class InMemoryBlobStorage: BlobStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    public init() {}

    public func load() -> Data? { lock.withLock { data } }
    public func save(_ data: Data) { lock.withLock { self.data = data } }
}

/// Atomic file storage. `completeUntilFirstUserAuthentication` keeps the file readable for background launches after the first unlock.
public struct FileBlobStorage: BlobStorage {
    private let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> Data? { try? Data(contentsOf: url) }

    public func save(_ data: Data) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url, options: .atomic)
        #endif
    }
}
