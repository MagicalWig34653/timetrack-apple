import Foundation

/// Builds small synthetic PDFs with AcroForm fields for tests (hand-written PDF syntax, no real-world form involved).
enum SyntheticFormPDF {
    struct Field {
        enum Kind { case text, checkbox, dropdown, signature }
        var name: String
        var kind: Kind
        var rect: [Int] = [50, 700, 250, 720]
        var readOnly = false
        var options: [String] = []
        /// Name of a parent field (hierarchical forms: the qualified name is `parent.name`).
        var parent: String?
        /// 0-based page the widget sits on.
        var page = 0
    }

    /// Pages with the given fields; `pageText` is drawn as page content (survives flattening).
    static func make(fields: [Field], pageCount: Int = 1, pageText: String = "Synthetic vacation request") -> Data {
        var objects: [Int: String] = [:]
        var nextId = 10
        func allocate() -> Int { defer { nextId += 1 }; return nextId }

        let pageIds = (0..<pageCount).map { _ in allocate() }
        var topLevel: [String] = []
        var parentIds: [String: Int] = [:]
        var parentKids: [String: [Int]] = [:]
        var pageAnnots: [Int: [Int]] = [:]

        for field in fields {
            let id = allocate()
            let page = pageIds[min(max(field.page, 0), pageCount - 1)]
            var entries = "/Type /Annot /Subtype /Widget /Rect [\(field.rect.map(String.init).joined(separator: " "))] /P \(page) 0 R /F 4"
            var flags = field.readOnly ? 1 : 0
            switch field.kind {
            case .text:
                entries += " /FT /Tx /DA (/Helv 10 Tf 0 g) /V ()"
            case .checkbox:
                let on = allocate(), off = allocate()
                objects[on] = stream("0 0 m 10 10 l S", dict: "/Type /XObject /Subtype /Form /BBox [0 0 10 10]")
                objects[off] = stream("", dict: "/Type /XObject /Subtype /Form /BBox [0 0 10 10]")
                entries += " /FT /Btn /V /Off /AS /Off /AP << /N << /Yes \(on) 0 R /Off \(off) 0 R >> >> /DA (/ZaDb 0 Tf 0 g)"
            case .dropdown:
                flags |= 131_072
                entries += " /FT /Ch /DA (/Helv 10 Tf 0 g) /Opt [\(field.options.map { "(\($0))" }.joined(separator: " "))]"
            case .signature:
                entries += " /FT /Sig"
            }
            if flags != 0 { entries += " /Ff \(flags)" }
            if let parent = field.parent {
                let parentId = parentIds[parent] ?? {
                    let value = allocate()
                    parentIds[parent] = value
                    topLevel.append("\(value) 0 R")
                    return value
                }()
                entries += " /Parent \(parentId) 0 R /T (\(field.name))"
                parentKids[parent, default: []].append(id)
            } else {
                entries += " /T (\(field.name))"
                topLevel.append("\(id) 0 R")
            }
            objects[id] = "<< \(entries) >>"
            pageAnnots[page, default: []].append(id)
        }
        for (name, id) in parentIds {
            let kids = (parentKids[name] ?? []).map { "\($0) 0 R" }.joined(separator: " ")
            objects[id] = "<< /T (\(name)) /Kids [\(kids)] >>"
        }
        for page in pageIds {
            let annots = (pageAnnots[page] ?? []).map { "\($0) 0 R" }.joined(separator: " ")
            objects[page] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /Helv 5 0 R >> >> /Contents 4 0 R /Annots [\(annots)] >>"
        }
        objects[1] = "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [\(topLevel.joined(separator: " "))] /DA (/Helv 0 Tf 0 g) /DR << /Font << /Helv 5 0 R >> >> >> >>"
        objects[2] = "<< /Type /Pages /Kids [\(pageIds.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(pageCount) >>"
        objects[4] = stream("BT /Helv 12 Tf 50 780 Td (\(pageText)) Tj ET", dict: "")
        objects[5] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"

        var data = Data("%PDF-1.7\n".utf8)
        var offsets: [Int: Int] = [:]
        let ids = objects.keys.sorted()
        for id in ids {
            offsets[id] = data.count
            data.append(Data("\(id) 0 obj\n\(objects[id]!)\nendobj\n".utf8))
        }
        let xrefStart = data.count
        let size = (ids.last ?? 0) + 1
        var xref = "xref\n0 \(size)\n0000000000 65535 f \n"
        for id in 1..<size {
            if let offset = offsets[id] { xref += String(format: "%010d 00000 n \n", offset) } else { xref += "0000000000 65535 f \n" }
        }
        xref += "trailer\n<< /Size \(size) /Root 1 0 R >>\nstartxref\n\(xrefStart)\n%%EOF\n"
        data.append(Data(xref.utf8))
        return data
    }

    private static func stream(_ content: String, dict: String) -> String {
        "<< \(dict) /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
    }

    /// A PDF without any form fields (flat template).
    static func flat(pageCount: Int = 1) -> Data { make(fields: [], pageCount: pageCount) }
}
