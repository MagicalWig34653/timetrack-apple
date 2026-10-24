import Foundation

/// `GET /vacation/request-form` (contract v0.25.0, ADR-0026): the one private vacation request template of the account.
/// Without a template `exists` is false and all other values are null. The mapping is opaque JSON for the server.
public struct VacationRequestFormInfo: Codable, Sendable, Equatable {
    public let exists: Bool
    public let fileName: String?
    public let sizeBytes: Int?
    public let mapping: JSONValue?
    public let updatedAt: String?

    public init(exists: Bool, fileName: String? = nil, sizeBytes: Int? = nil, mapping: JSONValue? = nil, updatedAt: String? = nil) {
        self.exists = exists
        self.fileName = fileName
        self.sizeBytes = sizeBytes
        self.mapping = mapping
        self.updatedAt = updatedAt
    }
}
