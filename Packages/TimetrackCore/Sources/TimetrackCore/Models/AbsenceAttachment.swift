import Foundation

/// `FileMeta` (contract v0.24.0): metadata of a stored file, e.g. an absence attachment.
public struct FileMeta: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let size: Int
    public let sha256: String
    public let contentType: String
    public let createdAt: String

    public init(id: UUID, name: String, size: Int, sha256: String = "", contentType: String, createdAt: String = "") {
        self.id = id
        self.name = name
        self.size = size
        self.sha256 = sha256
        self.contentType = contentType
        self.createdAt = createdAt
    }

    /// Types for which `GET /files/{id}?disposition=inline` answers inline (contract v0.24.0); every other type falls back to attachment.
    public static let inlineContentTypes: Set<String> = ["image/png", "image/jpeg", "image/gif", "image/webp", "application/pdf", "text/plain"]

    public var supportsInline: Bool {
        Self.inlineContentTypes.contains(contentType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "")
    }

    /// A safe file name for the temporary copy that QuickLook opens (no path parts, extension kept).
    public var safeFileName: String {
        let base = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_").replacingOccurrences(of: ":", with: "_")
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "attachment" : String(trimmed.prefix(120))
    }
}
