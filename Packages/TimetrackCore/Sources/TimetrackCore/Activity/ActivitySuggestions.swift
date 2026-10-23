import Foundation

// M2: mapping rules (app -> kind / project / learning field) and the editable suggestions made from them.
//
// A suggestion is never a booking. It proposes a note (and, when the block covers a whole entry, a kind) for an entry that
// already exists; the user edits it in the normal editor and saves it with a reason, like any other correction.

/// What a rule writes into the note of an entry.
public enum ActivityLabelType: String, Codable, Sendable, Hashable, CaseIterable {
    case none, project, learningField

    /// "Projekt: Timetrack", "Lernfeld: LF 5", or just the text.
    public func formatted(_ text: String) -> String {
        switch self {
        case .none: text
        case .project: "Projekt: \(text)"
        case .learningField: "Lernfeld: \(text)"
        }
    }
}

/// "When app X is in front, the time is probably this kind / this project / this learning field."
public struct ActivityRule: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var bundleID: String
    public var appName: String
    /// Proposed kind; nil keeps the kind of the entry.
    public var kind: SegmentKind?
    public var labelType: ActivityLabelType
    /// Project name or learning field; empty means no label.
    public var label: String

    public init(id: UUID = UUID(), bundleID: String, appName: String, kind: SegmentKind? = nil, labelType: ActivityLabelType = .none, label: String = "") {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.kind = kind
        self.labelType = labelType
        self.label = label
    }

    public var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A rule without a kind and without a label proposes nothing.
    public var isUseful: Bool { kind != nil || !trimmedLabel.isEmpty }

    /// Rules with the same target are one block when their intervals are adjacent (Xcode and Terminal for the same project).
    var targetKey: String { "\(kind?.rawValue ?? "-")|\(labelType.rawValue)|\(trimmedLabel)" }

    public var formattedLabel: String? { trimmedLabel.isEmpty ? nil : labelType.formatted(trimmedLabel) }
}

/// A proposal for one block of time inside one entry. Editable before it is applied.
public struct ActivitySuggestion: Identifiable, Sendable, Hashable {
    /// Stable for the same block (rule target and start), so a dismissed suggestion stays dismissed.
    public let id: String
    public let segmentID: UUID
    public let start: Date
    public let end: Date
    public let appNames: [String]
    public let proposedKind: SegmentKind?
    /// The note the entry would get (existing note plus the label); the user edits it before saving.
    public let proposedNote: String
    public let seconds: TimeInterval

    public var duration: TimeInterval { seconds }
}

public enum ActivitySuggestionEngine {
    /// A block shorter than this is not worth a suggestion.
    public static let minimumBlockSeconds: TimeInterval = 5 * 60
    /// Adjacent intervals of the same target are one block if the gap between them is at most this long.
    public static let mergeGap: TimeInterval = 2 * 60
    /// The proposed kind is only offered when the block covers at least this share of the entry.
    public static let wholeEntryShare = 0.9

    /// Suggestions for the finished and running entries in `segments`, from `intervals` (already restricted to the days of interest).
    /// Nothing is suggested for unmatched apps, for voided entries, for blocks that would change nothing, or for dismissed ids.
    public static func suggestions(intervals: [ActivityInterval], rules: [ActivityRule], segments: [Segment], dismissed: Set<String> = [], now: Date = .now) -> [ActivitySuggestion] {
        let useful = rules.filter(\.isUseful)
        guard !useful.isEmpty, !intervals.isEmpty else { return [] }
        let entries = segments.filter { !$0.voided }.sorted { $0.startedAt < $1.startedAt }
        var result: [ActivitySuggestion] = []

        for segment in entries {
            let segmentEnd = segment.endedAt ?? now
            guard segmentEnd > segment.startedAt else { continue }
            // Clip the matching intervals to the entry; an app that was in front outside any entry never counts toward it.
            let pieces: [(rule: ActivityRule, start: Date, end: Date, name: String)] = intervals.compactMap { interval in
                guard let rule = useful.first(where: { $0.bundleID == interval.bundleID }) else { return nil }
                let start = max(interval.start, segment.startedAt), end = min(interval.end, segmentEnd)
                return end > start ? (rule, start, end, interval.appName) : nil
            }.sorted { $0.start < $1.start }

            var blocks: [(key: String, rule: ActivityRule, start: Date, end: Date, names: [String], seconds: TimeInterval)] = []
            for piece in pieces {
                if let last = blocks.last, last.key == piece.rule.targetKey, piece.start.timeIntervalSince(last.end) <= mergeGap {
                    blocks[blocks.count - 1].end = max(last.end, piece.end)
                    blocks[blocks.count - 1].seconds += piece.end.timeIntervalSince(piece.start)
                    if !last.names.contains(piece.name) { blocks[blocks.count - 1].names.append(piece.name) }
                } else {
                    blocks.append((piece.rule.targetKey, piece.rule, piece.start, piece.end, [piece.name], piece.end.timeIntervalSince(piece.start)))
                }
            }

            for block in blocks where block.seconds >= minimumBlockSeconds {
                let id = "\(block.key)@\(Int(block.start.timeIntervalSince1970))"
                guard !dismissed.contains(id) else { continue }
                let covers = block.end.timeIntervalSince(block.start) >= segmentEnd.timeIntervalSince(segment.startedAt) * wholeEntryShare
                let kind = covers ? block.rule.kind.flatMap { $0 != segment.kind ? $0 : nil } : nil
                let note = proposedNote(existing: segment.note, label: block.rule.formattedLabel)
                let noteChanges = note != (segment.note ?? "")
                guard kind != nil || noteChanges else { continue }
                result.append(ActivitySuggestion(id: id, segmentID: segment.id, start: block.start, end: block.end, appNames: block.names,
                                                 proposedKind: kind, proposedNote: note, seconds: block.seconds))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// Appends the label to an existing note instead of replacing it; a label that is already in the note changes nothing.
    public static func proposedNote(existing: String?, label: String?) -> String {
        let current = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let label, !label.isEmpty else { return current }
        if current.isEmpty { return label }
        if current.localizedCaseInsensitiveContains(label) { return current }
        return "\(current) · \(label)"
    }
}
