import Foundation

// Vacation request form (AB1): a port of the PWA's `vacation-form` library (P6/P8), so a mapping saved in the web app fills the
// same PDF the same way on Apple devices. The server stores the mapping as opaque JSON (<= 64 KB, contract v0.25.0).

/// Date styles a form can use (`dd.MM.yyyy`, `d.M.yy`, `iso`).
public enum FormDateFormat: String, Codable, Sendable, CaseIterable {
    case dotted = "dd.MM.yyyy"
    case shortDotted = "d.M.yy"
    case iso

    /// Formats an ISO date (`2026-07-06`); unparsable input is returned unchanged (like the PWA).
    public func format(_ day: LocalDay) -> String {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              day.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || $0 == 45 }),
              let month = Int(parts[1]), let dayNumber = Int(parts[2]) else { return day }
        switch self {
        case .iso: return day
        case .shortDotted: return "\(dayNumber).\(month).\(parts[0].suffix(2))"
        case .dotted: return "\(parts[2]).\(parts[1]).\(parts[0])"
        }
    }
}

public enum FormDays {
    /// Day amounts as German decimals in half-day steps: 30 -> "30", 4.5 -> "4,5".
    public static func format(_ days: Double) -> String {
        let rounded = (days * 2).rounded() / 2
        if rounded == rounded.rounded(), abs(rounded) < 1e9 { return String(Int(rounded)) }
        return String(rounded).replacingOccurrences(of: ".", with: ",")
    }
}

/// The data sources a PDF field can be bound to. Raw values equal the PWA's source ids (they are stored in the mapping).
public enum FormSource: String, Sendable, CaseIterable {
    case lastName, firstName, fullName, personnelNo, department, place
    case entitlementTotal, entitlementYear, carryOver, additional, paidOut, restBefore, restAfter
    case dateFrom, dateTo, dateRange, workingDays
    case freeRangeFrom, freeRangeTo, freeRange, freeDaysCount, hasFreeDays
    case substitute, today
    case fixedText, fixedCheckbox

    /// Extra option a binding of this source carries.
    public enum Option: Sendable { case text, checked, index }

    public var option: Option? {
        switch self {
        case .fixedText: .text
        case .fixedCheckbox: .checked
        case .freeRangeFrom, .freeRangeTo, .freeRange: .index
        default: nil
        }
    }

    /// The value is asked at request time (not stored in the profile).
    public var askedAtRequest: Bool { self == .substitute }

    /// Sources that fill checkboxes; every other source fills text, dropdown and overlay targets.
    public var isCheckbox: Bool { self == .hasFreeDays || self == .fixedCheckbox }
}

/// Largest number of free-day range positions a binding may address.
public let maxFreeRanges = 8

/// One data source chosen for one PDF field or overlay position.
public struct FormBinding: Sendable, Hashable {
    public var source: FormSource
    public var text: String?
    public var checked: Bool?
    /// 1-based position in the list of free-day ranges.
    public var index: Int?
    public var dateFormat: FormDateFormat?

    public init(source: FormSource, text: String? = nil, checked: Bool? = nil, index: Int? = nil, dateFormat: FormDateFormat? = nil) {
        self.source = source
        self.text = text
        self.checked = checked
        self.index = index
        self.dateFormat = dateFormat
    }
}

public struct FormPerson: Sendable, Hashable {
    public var lastName = ""
    public var firstName = ""
    public var personnelNo = ""
    public var department = ""
    public var place = ""

    public init(lastName: String = "", firstName: String = "", personnelNo: String = "", department: String = "", place: String = "") {
        self.lastName = lastName
        self.firstName = firstName
        self.personnelNo = personnelNo
        self.department = department
        self.place = place
    }
}

/// Free text position on a flat PDF; x/y in PDF points from the bottom-left corner of the page (0-based page index).
public struct FormOverlay: Sendable, Hashable {
    public var id: String
    public var page: Int
    public var x: Double
    public var y: Double
    public var fontSize: Double
    public var binding: FormBinding

    public init(id: String, page: Int, x: Double, y: Double, fontSize: Double = FormMapping.defaultOverlayFontSize, binding: FormBinding) {
        self.id = id
        self.page = page
        self.x = x
        self.y = y
        self.fontSize = fontSize
        self.binding = binding
    }
}

/// The saved profile (what the PWA writes with `PUT /vacation/request-form/mapping`).
public struct FormMapping: Sendable, Hashable {
    public static let maxBytes = 64 * 1024
    public static let maxFieldNameLength = 256
    public static let maxTextLength = 500
    public static let maxOverlays = 200
    public static let defaultOverlayFontSize = 11.0

    public var person = FormPerson()
    public var dateFormat: FormDateFormat = .dotted
    /// Flatten the generated PDF (no longer fillable) unless the request says otherwise.
    public var flatten = false
    /// AcroForm field name (fully qualified, dot separated) -> binding.
    public var fields: [String: FormBinding] = [:]
    public var overlays: [FormOverlay] = []

    public init() {}

    /// Reads a stored mapping defensively (it may come from an older client or a hand-edited backup): unknown sources and
    /// malformed entries are dropped, numbers clamped, everything else falls back to defaults. Same rules as the PWA's `parseMapping`.
    public init(json value: JSONValue?) {
        guard case .object(let root)? = value else { return }
        if case .object(let person)? = root["person"] {
            func text(_ key: String) -> String { Self.string(person[key], max: 200) }
            self.person = FormPerson(lastName: text("lastName"), firstName: text("firstName"), personnelNo: text("personnelNo"),
                                     department: text("department"), place: text("place"))
        }
        if let format = Self.dateFormat(root["dateFormat"]) { dateFormat = format }
        if case .bool(true)? = root["flatten"] { flatten = true }
        if case .object(let raw)? = root["fields"] {
            for (name, entry) in raw where name.count <= Self.maxFieldNameLength {
                if let binding = Self.binding(entry) { fields[name] = binding }
            }
        }
        if case .array(let raw)? = root["overlays"] {
            for entry in raw.prefix(Self.maxOverlays) {
                guard case .object(let object) = entry, let binding = Self.binding(object["binding"]), case .string(let id)? = object["id"] else { continue }
                overlays.append(FormOverlay(
                    id: String(id.prefix(64)),
                    page: Int(min(max(Self.finite(object["page"], 0).rounded(.towardZero), 0), 1_000_000)),
                    x: Self.finite(object["x"], 0), y: Self.finite(object["y"], 0),
                    fontSize: min(max(Self.finite(object["fontSize"], Self.defaultOverlayFontSize), 4), 48),
                    binding: binding))
            }
        }
    }

    private static func string(_ value: JSONValue?, max: Int = maxTextLength) -> String {
        if case .string(let text)? = value { return String(text.prefix(max)) }
        return ""
    }

    private static func finite(_ value: JSONValue?, _ fallback: Double) -> Double {
        if case .number(let number)? = value, number.isFinite { return number }
        return fallback
    }

    private static func dateFormat(_ value: JSONValue?) -> FormDateFormat? {
        if case .string(let raw)? = value { return FormDateFormat(rawValue: raw) }
        return nil
    }

    private static func binding(_ value: JSONValue?) -> FormBinding? {
        guard case .object(let object)? = value, case .string(let raw)? = object["source"], let source = FormSource(rawValue: raw) else { return nil }
        var binding = FormBinding(source: source)
        switch source.option {
        case .text: binding.text = string(object["text"])
        case .checked: if case .bool(true)? = object["checked"] { binding.checked = true } else { binding.checked = false }
        case .index: binding.index = Int(min(max(finite(object["index"], 1).rounded(.towardZero), 1), Double(maxFreeRanges)))
        case nil: break
        }
        binding.dateFormat = dateFormat(object["dateFormat"])
        return binding
    }
}
