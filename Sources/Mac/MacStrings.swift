import Foundation

/// AD1: strings of the adaptive Mac shell live in their own table (`AD1.xcstrings`) so parallel packages that edit
/// `Localizable.xcstrings` do not conflict with it.
enum AD {
    static func s(_ key: String.LocalizationValue) -> String { String(localized: key, table: "AD1") }
}
