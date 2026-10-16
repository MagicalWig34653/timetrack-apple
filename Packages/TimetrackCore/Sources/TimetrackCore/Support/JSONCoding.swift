import Foundation

/// Shared JSON coders. The API sends UTC ISO-8601 instants, with or without fractional seconds.
public enum JSONCoding {
    private static let plain = Date.ISO8601FormatStyle()
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public static func parseInstant(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: fractional) { return date }
        return try? Date(text, strategy: plain)
    }

    public static func formatInstant(_ date: Date) -> String {
        date.formatted(plain)
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = JSONCoding.parseInstant(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 instant")
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(JSONCoding.formatInstant(date))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// A calendar day as `YYYY-MM-DD` in the work model's time zone (the API never sends local days as instants).
public typealias LocalDay = String
