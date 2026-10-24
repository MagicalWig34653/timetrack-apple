import Foundation

/// Why a template or a generated PDF cannot be used (mirrors the PWA's `PdfProblem`).
public enum FormPDFProblem: String, Error, Sendable, Equatable {
    case notPDF = "not_pdf"
    case tooLarge = "too_large"
    case empty
    case encrypted
    case unreadable
}

public enum FormPDFLimits {
    /// The server stores templates up to 5 MB (contract v0.25.0).
    public static let maxBytes = 5 * 1024 * 1024

    /// `%PDF-` within the first 1024 bytes (viewers accept leading junk up to that offset).
    public static func hasPDFMagic(_ data: Data) -> Bool {
        let head = data.prefix(1024)
        return head.range(of: Data("%PDF-".utf8)) != nil
    }

    /// Size and magic number check for a template; throws a `FormPDFProblem`.
    public static func validate(_ data: Data) throws {
        if data.isEmpty { throw FormPDFProblem.empty }
        if data.count > maxBytes { throw FormPDFProblem.tooLarge }
        if !hasPDFMagic(data) { throw FormPDFProblem.notPDF }
    }
}

#if canImport(PDFKit)
import PDFKit
import CoreGraphics
import CoreText
#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
#endif

/// Kind of a fillable field, as far as the mapping can address it.
public enum FormFieldKind: String, Sendable, Equatable { case text, checkbox, dropdown, other }

public struct FormFieldInfo: Sendable, Equatable {
    public let name: String
    public let kind: FormFieldKind
    /// 1-based page of the widget.
    public let page: Int
    public let readOnly: Bool
    public let options: [String]
}

public struct FormFillResult: Sendable {
    public let data: Data
    /// Names of fields whose value could not be written (dropdown value not offered, ...) and `overlay:<id>` for overlays.
    public let skipped: [String]
    /// Mapped fields (and overlays) that exist in the PDF and were written.
    public let filledCount: Int
}

/// Fills the account's vacation request template with PDFKit (iOS, iPadOS, macOS). Same semantics as the PWA's `fillPdf`.
public enum FormPDF {
    private static func load(_ data: Data) throws -> PDFDocument {
        try FormPDFLimits.validate(data)
        guard let document = PDFDocument(data: data) else { throw FormPDFProblem.unreadable }
        if document.isLocked || (document.isEncrypted && !document.allowsDocumentChanges) { throw FormPDFProblem.encrypted }
        guard document.pageCount > 0 else { throw FormPDFProblem.unreadable }
        return document
    }

    private static func kind(of annotation: PDFAnnotation) -> FormFieldKind? {
        switch annotation.widgetFieldType {
        case .text: return .text
        case .button: return annotation.widgetControlType == .checkBoxControl ? .checkbox : .other
        case .choice: return annotation.isListChoice ? .other : .dropdown
        default: return .other
        }
    }

    private static func widgets(of document: PDFDocument) -> [(page: Int, annotation: PDFAnnotation)] {
        var result: [(Int, PDFAnnotation)] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.type == "Widget" && annotation.fieldName != nil { result.append((index + 1, annotation)) }
        }
        return result
    }

    /// Lists the page count and all form fields of a template.
    public static func inspect(_ data: Data) throws -> (pageCount: Int, fields: [FormFieldInfo]) {
        let document = try load(data)
        let fields = widgets(of: document).compactMap { entry -> FormFieldInfo? in
            guard let name = entry.annotation.fieldName, let kind = kind(of: entry.annotation) else { return nil }
            return FormFieldInfo(name: name, kind: kind, page: entry.page, readOnly: entry.annotation.isReadOnly, options: entry.annotation.choices ?? [])
        }
        return (document.pageCount, fields)
    }

    /// Fills a copy of the template with the mapped values; the template bytes are never modified.
    /// `flatten` overrides `mapping.flatten`: the form fields are then drawn into the page content and the PDF is no longer fillable.
    public static func fill(template: Data, mapping: FormMapping, request: FormRequestData, flatten: Bool? = nil) throws -> FormFillResult {
        let document = try load(template)
        var skipped: [String] = []
        var filled = 0

        for entry in widgets(of: document) {
            let annotation = entry.annotation
            guard let name = annotation.fieldName, let binding = mapping.fields[name], !annotation.isReadOnly, let kind = kind(of: annotation) else { continue }
            let value = mapping.resolve(binding, request)
            switch kind {
            case .text:
                if case .text(let text) = value { annotation.widgetStringValue = text } else { annotation.widgetStringValue = "" }
                filled += 1
            case .checkbox:
                annotation.buttonWidgetState = value == .flag(true) ? .onState : .offState
                filled += 1
            case .dropdown:
                if case .text(let text) = value {
                    if (annotation.choices ?? []).contains(text) {
                        annotation.widgetStringValue = text
                        filled += 1
                    } else {
                        skipped.append(name)
                    }
                }
            case .other:
                break
            }
        }

        for overlay in mapping.overlays {
            guard overlay.page < document.pageCount, let page = document.page(at: overlay.page), case .text(let text) = mapping.resolve(overlay.binding, request) else { continue }
            let font = PlatformFont(name: "Helvetica", size: overlay.fontSize) ?? PlatformFont.systemFont(ofSize: overlay.fontSize)
            let size = textSize(text, fontSize: overlay.fontSize)
            // The mapping's x/y is the text baseline start (pdf-lib `drawText`); the annotation box sits a little below it for descenders.
            let descent = overlay.fontSize * 0.25
            let box = CGRect(x: overlay.x, y: overlay.y - descent, width: ceil(size.width) + 8, height: ceil(size.height) + 2)
            let annotation = PDFAnnotation(bounds: box, forType: .freeText, withProperties: nil)
            annotation.contents = text
            annotation.font = font
            annotation.fontColor = PlatformColor.black
            annotation.color = PlatformColor.clear
            let border = PDFBorder()
            border.lineWidth = 0
            annotation.border = border
            page.addAnnotation(annotation)
            filled += 1
        }

        var output: Data
        if flatten ?? mapping.flatten {
            output = try flattened(document)
        } else {
            guard let data = document.dataRepresentation() else { throw FormPDFProblem.unreadable }
            output = data
        }
        return FormFillResult(data: output, skipped: skipped, filledCount: filled)
    }

    private static func textSize(_ text: String, fontSize: Double) -> CGSize {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        return CGSize(width: CTLineGetTypographicBounds(line, nil, nil, nil), height: fontSize * 1.2)
    }

    /// Redraws every page (content and annotations) into a new PDF, so form fields become page content.
    private static func flattened(_ document: PDFDocument) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw FormPDFProblem.unreadable }
        var firstBox = document.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else { throw FormPDFProblem.unreadable }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            var box = page.bounds(for: .mediaBox)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(info)
            page.draw(with: .mediaBox, to: context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Reads back the current values of text, checkbox and dropdown fields (tests and the preview check).
    public static func fieldValues(_ data: Data) throws -> [String: String] {
        let document = try load(data)
        var values: [String: String] = [:]
        for entry in widgets(of: document) {
            guard let name = entry.annotation.fieldName, let kind = kind(of: entry.annotation) else { continue }
            switch kind {
            case .text, .dropdown: values[name] = entry.annotation.widgetStringValue ?? ""
            case .checkbox: values[name] = entry.annotation.buttonWidgetState == .onState ? "on" : "off"
            case .other: break
            }
        }
        return values
    }

    /// All text on the pages (flattened fields and overlays included).
    public static func text(_ data: Data) -> String? { PDFDocument(data: data)?.string }
}
#endif
