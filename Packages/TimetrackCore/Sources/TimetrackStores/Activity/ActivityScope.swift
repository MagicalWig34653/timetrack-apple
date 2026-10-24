import Foundation
import Observation

/// Owns the `ActivityStore` of the account that is signed in right now. Activity data and its consent (recording on/off,
/// window titles, exclusions, rules) are per account: another account never sees them and never inherits "enabled".
/// Without a signed-in account the store is an empty in-memory one with recording off.
@MainActor
@Observable
public final class ActivityScope {
    public private(set) var store: ActivityStore
    public private(set) var accountId: UUID?

    @ObservationIgnored private let makeStorage: (UUID) -> ActivityStorage

    /// - Parameter makeStorage: storage for one account id (the Mac app uses a folder per account).
    public init(makeStorage: @escaping (UUID) -> ActivityStorage) {
        self.makeStorage = makeStorage
        store = ActivityStore(storage: .inMemory())
    }

    /// Switches to the store of `accountId` (nil = signed out). Returns true when the store changed. The caller closes its
    /// open interval into the OLD store before calling this (see `MacCompanion`).
    @discardableResult
    public func switchAccount(to accountId: UUID?) -> Bool {
        guard accountId != self.accountId else { return false }
        self.accountId = accountId
        store = accountId.map { ActivityStore(storage: makeStorage($0)) } ?? ActivityStore(storage: .inMemory())
        return true
    }

    /// Folder layout: `<base>/<account id>/...`.
    public static func folderStorage(base: URL) -> (UUID) -> ActivityStorage {
        { ActivityStorage.files(in: base.appendingPathComponent($0.uuidString, isDirectory: true)) }
    }

    /// Removes the files of the old, account-less layout (`<base>/settings.json` etc.): their owner is unknown and they must
    /// not appear for whoever signs in next.
    public static func removeLegacyFiles(in base: URL, fileManager: FileManager = .default) {
        for name in ["settings.json", "rules.json", "log.json", "dismissed.json"] {
            try? fileManager.removeItem(at: base.appendingPathComponent(name))
        }
    }
}
