import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Which files may be attached to an absence (ADR-0006 whitelist, same as the PWA: PDF, PNG, JPG, HEIC, TXT). The server checks
/// type and size again (413 `file_too_large`, 415 `unsupported_type`); this only catches the obvious early.
public enum AttachmentRules {
    public static let allowedExtensions = ["pdf", "png", "jpg", "jpeg", "heic", "txt"]

    /// Sanity cap against filling memory; the real limit is set by the server operator (default 10 MiB) and answers 413.
    public static let hardMaxBytes = 64 * 1024 * 1024

    public enum Problem: Sendable, Equatable { case unsupportedType, empty, tooLarge }

    public static func fileExtension(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    public static func isAllowed(name: String) -> Bool { allowedExtensions.contains(fileExtension(of: name)) }

    public static func validate(name: String, size: Int) -> Problem? {
        if !isAllowed(name: name) { return .unsupportedType }
        if size <= 0 { return .empty }
        if size > hardMaxBytes { return .tooLarge }
        return nil
    }

    /// MIME type sent in the multipart part for a file name.
    public static func contentType(forName name: String) -> String {
        switch fileExtension(of: name) {
        case "pdf": "application/pdf"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "heic": "image/heic"
        case "txt": "text/plain"
        default: "application/octet-stream"
        }
    }

    /// A safe upload name: no path parts, no control characters, limited length, extension kept.
    public static func sanitizedName(_ name: String, fallback: String = "Anhang") -> String {
        let cleaned = name.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar) || "/\\:\"".unicodeScalars.contains(scalar) { return "_" }
            return Character(scalar)
        }
        let text = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "." else { return fallback }
        guard text.count > 120 else { return text }
        let ext = fileExtension(of: text)
        let stem = String(text.dropLast(ext.isEmpty ? 0 : ext.count + 1).prefix(110))
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }
}

/// Shrinks photos before the upload (phone photos are often 5 to 10 MB as HEIC/JPEG, which is not needed for a medical certificate).
public enum ImageCompressor {
    /// Re-encodes any image ImageIO can read as JPEG with the long edge at most `maxPixelSize`; EXIF orientation is applied.
    /// Returns nil when the data is not an image.
    public static func jpegData(from data: Data, maxPixelSize: Int = 3000, quality: Double = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 16),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.1), 1)] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// `Foto.heic` -> `Foto.jpg`.
    public static func jpegName(for name: String, fallback: String = "Foto") -> String {
        let stem = name.lastIndex(of: ".").map { String(name[..<$0]) } ?? name
        return (stem.isEmpty ? fallback : stem) + ".jpg"
    }
}
