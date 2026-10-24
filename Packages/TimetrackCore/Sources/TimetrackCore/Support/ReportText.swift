import Foundation

/// BH1: input parsing of the report duration (port of the PWA `parseReportDuration`). The API stores whole seconds; the UI shows h:mm.
public enum ReportDuration {
    public enum Kind: Sendable, Equatable { case empty, clock, decimal, hours }

    public struct Parsed: Sendable, Equatable {
        public let seconds: Int
        public let kind: Kind
    }

    public static let maxSeconds = 86_400

    /// Accepts "1:30" (h:mm), "1,5" / "1.5" (decimal hours, rounded to whole minutes), "2" (whole hours) and "" (= 0).
    /// "7,7" is 7 h 42 min, not 7:07; the form shows the parsed h:mm live for that reason. Nil for anything else and above 24 h.
    public static func parse(_ input: String) -> Parsed? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return Parsed(seconds: 0, kind: .empty) }
        if let match = try? #/^(\d{1,2}):([0-5]\d)$/#.wholeMatch(in: text) {
            return within(Parsed(seconds: (Int(match.output.1) ?? 0) * 3600 + (Int(match.output.2) ?? 0) * 60, kind: .clock))
        }
        if let match = try? #/^(\d{0,2})[,.](\d{1,2})$/#.wholeMatch(in: text), !(match.output.1.isEmpty && match.output.2.isEmpty) {
            let whole = match.output.1.isEmpty ? "0" : String(match.output.1)
            let hours = Double("\(whole).\(match.output.2)") ?? 0
            return within(Parsed(seconds: Int((hours * 60).rounded()) * 60, kind: .decimal))
        }
        if let match = try? #/^\d{1,2}$/#.wholeMatch(in: text) {
            return within(Parsed(seconds: (Int(match.output) ?? 0) * 3600, kind: .hours))
        }
        return nil
    }

    private static func within(_ parsed: Parsed) -> Parsed? { parsed.seconds <= maxSeconds ? parsed : nil }

    /// Initial text of the input when editing: 5400 becomes "1:30", 0 becomes "".
    public static func inputValue(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let minutes = Int((Double(seconds) / 60).rounded())
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }
}

/// BH1: copyable output of one report week for the IHK portal. `plain` mirrors the server rendering of
/// `GET /reports/weeks/{year}/{week}/text` (ADR-0008 standard format) so the app can produce it offline; `html` is the rich variant
/// (a table per day) for pasting into editors that keep structure. Minutes are truncated like everywhere else.
public enum ReportText {
    public static let weekdays = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    /// Splits at line breaks, trims blanks, drops empty lines and joins with " / " (so one entry stays on one line).
    public static func singleLine(_ text: String) -> String {
        text.components(separatedBy: CharacterSet(charactersIn: "\n\r\u{85}\u{2028}\u{2029}"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    /// "2026-10-26" becomes "26.10.2026".
    public static func numericDate(_ day: LocalDay) -> String {
        guard let p = LocalDays.parse(day) else { return day }
        return String(format: "%02d.%02d.%04d", p.day, p.month, p.year)
    }

    public static func plain(week ref: ReportWeekRef, entries: [ReportEntry]) -> String {
        let days = ref.days
        var lines = ["Berichtsheft KW \(ref.week)/\(ref.year) (\(numericDate(ref.monday)) – \(numericDate(ref.sunday)))", ""]
        var total = 0
        for (index, day) in days.enumerated() {
            let ofDay = entries.filter { $0.date == day }
            if ofDay.isEmpty { continue }
            lines.append("\(weekdays[index]), \(numericDate(day))")
            for entry in ofDay {
                total += entry.durationSeconds
                let note = singleLine(entry.notes)
                lines.append("\(singleLine(entry.learningField)) | \(DurationFormat.hoursMinutes(entry.durationSeconds)) h" + (note.isEmpty ? "" : " | \(note)"))
            }
            lines.append("")
        }
        lines.append("Summe: \(DurationFormat.hoursMinutes(total)) h")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func html(week ref: ReportWeekRef, entries: [ReportEntry]) -> String {
        var parts = ["<h3>Berichtsheft KW \(ref.week)/\(ref.year) (\(numericDate(ref.monday)) – \(numericDate(ref.sunday)))</h3>"]
        var total = 0
        for (index, day) in ref.days.enumerated() {
            let ofDay = entries.filter { $0.date == day }
            if ofDay.isEmpty { continue }
            parts.append("<p><b>\(weekdays[index]), \(numericDate(day))</b></p>")
            parts.append("<table border=\"1\" cellpadding=\"4\" cellspacing=\"0\"><tr><th align=\"left\">Lernfeld</th><th align=\"right\">Zeit</th><th align=\"left\">Notizen</th></tr>")
            for entry in ofDay {
                total += entry.durationSeconds
                let note = escape(entry.notes).replacingOccurrences(of: "\n", with: "<br>")
                parts.append("<tr><td>\(escape(entry.learningField))</td><td align=\"right\">\(DurationFormat.hoursMinutes(entry.durationSeconds)) h</td><td>\(note)</td></tr>")
            }
            parts.append("</table>")
        }
        parts.append("<p><b>Summe: \(DurationFormat.hoursMinutes(total)) h</b></p>")
        return parts.joined(separator: "\n")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
