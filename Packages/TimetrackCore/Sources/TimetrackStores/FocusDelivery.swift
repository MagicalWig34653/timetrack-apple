import Foundation
import TimetrackCore

// F3: building blocks of the reliable Focus pipeline (parameters as received, classification, serialisation, time budget).

/// What the system handed to the filter intent, before any interpretation. `mode == nil` is what iOS delivers when a Focus
/// ends (default-initialised intent) and also what a filter that was never configured delivers.
public struct FocusParameters: Codable, Sendable, Hashable {
    public var mode: FocusMode?
    public var kind: SegmentKind
    public var placeId: UUID?
    public var placeName: String?
    public var focusName: String?

    public init(mode: FocusMode?, kind: SegmentKind = .work, placeId: UUID? = nil, placeName: String? = nil, focusName: String? = nil) {
        self.mode = mode
        self.kind = kind
        self.placeId = placeId
        self.placeName = placeName
        self.focusName = focusName
    }

    public init(_ configuration: FocusConfiguration?) {
        self.init(mode: configuration?.mode, kind: configuration?.kind ?? .work, placeId: configuration?.placeId,
                  placeName: configuration?.placeName, focusName: configuration?.focusName)
    }

    /// The usable configuration, or nil for "Focus ended / not configured".
    public var configuration: FocusConfiguration? {
        mode.map { FocusConfiguration(mode: $0, kind: kind, placeId: placeId, placeName: placeName, focusName: focusName) }
    }

    /// Short German description for the log ("Modus Nachfragen, Art Arbeit, Ort Betrieb" or the "ended" form).
    public var summary: String {
        guard let mode else { return "keine Angaben (Fokus beendet oder Filter nicht eingerichtet)" }
        var text = "Modus \(FocusText.modeName(mode)), Art \(FocusText.kindName(kind))"
        if let placeName { text += ", Ort \(placeName)" }
        if let focusName, !focusName.isEmpty { text += ", Name „\(focusName)“" }
        return text
    }
}

/// How a delivery was interpreted.
public enum FocusClassification: String, Codable, Sendable, Hashable {
    case activated, deactivated
    /// A new configuration arrived while another one was active (Focus switch): nothing is stopped.
    case handover
    case duplicate
    /// "Ended" arrived without an active Focus.
    case notActive
    case answer
}

/// Last delivery as shown in the diagnostics (one small record in the state).
public struct FocusDeliverySummary: Codable, Sendable, Hashable {
    public var receivedAt: Date
    public var sequence: Int64
    public var trigger: FocusTrigger
    public var parameters: String
    public var classification: FocusClassification
    /// Short German result; filled in after the actions ran.
    public var result: String?
    public var failed: Bool

    public init(receivedAt: Date, sequence: Int64, trigger: FocusTrigger, parameters: String, classification: FocusClassification, result: String? = nil, failed: Bool = false) {
        self.receivedAt = receivedAt
        self.sequence = sequence
        self.trigger = trigger
        self.parameters = parameters
        self.classification = classification
        self.result = result
        self.failed = failed
    }
}

/// Async mutex: callbacks of the system, notification answers and retries read-modify-write the same state; this makes
/// each of them atomic with respect to the others inside the process (the intent runs in the app process).
actor FocusGate {
    static let shared = FocusGate()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
        await acquire()
        let value = await body()
        release()
        return value
    }

    private func acquire() async {
        if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

public struct FocusDeadlineExceeded: Error, Sendable {}

/// Runs `operation` but gives up after `seconds`: the system gives a Focus callback only a short time budget, so network work
/// must never be allowed to run until URLSession's own (30 s) timeout. On timeout the operation is cancelled AND abandoned:
/// this is a race of two unstructured tasks, not a task group, because a group would wait for an operation that ignores
/// cancellation (for example a system call that never answers), which would freeze the whole delivery.
public func withFocusDeadline<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    let once = FocusOnce()
    return try await withCheckedThrowingContinuation { continuation in
        let work = Task {
            do {
                let value = try await operation()
                if once.take() { continuation.resume(returning: value) }
            } catch {
                if once.take() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if once.take() {
                work.cancel()
                continuation.resume(throwing: FocusDeadlineExceeded())
            }
        }
    }
}

/// First caller wins.
final class FocusOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func take() -> Bool { lock.withLock { if taken { return false }; taken = true; return true } }
}

/// Plain-text diagnostics the user can copy (no secrets: state, last deliveries, queue size).
public enum FocusDiagnostics {
    public static func text(state: FocusState, entries: [FocusLogEntry], pending: Int, notifications: String, now: Date = .now) -> String {
        var lines = ["Timetrack Fokus-Filter – Diagnose", "Stand: \(Self.format(now))"]
        lines.append("Aktiv: \(state.active.map { FocusText.activeSummary($0) } ?? "nein")")
        if let at = state.activatedAt { lines.append("Seit: \(format(at))") }
        if let last = state.lastDelivery {
            lines.append("Letzte Meldung: \(format(last.receivedAt)) · \(last.classification.rawValue) · \(last.parameters)")
            if let result = last.result { lines.append("Ergebnis: \(result)") }
        } else {
            lines.append("Letzte Meldung: noch keine")
        }
        lines.append("Wartende Aktionen: \(pending)")
        lines.append("Mitteilungen: \(notifications)")
        lines.append("Automatik-Modul: \(state.automationEnabled.map { $0 ? "an" : "aus" } ?? "unbekannt")")
        for entry in entries.prefix(15) {
            var line = "\(format(entry.date)) [\(entry.trigger.rawValue)] \(entry.summary)"
            if let received = entry.received { line += " | erhalten: \(received)" }
            if let detail = entry.detail { line += " | \(detail)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func format(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "Europe/Berlin") ?? .current).day().month().hour().minute().second().locale(Locale(identifier: "de_DE")))
    }
}
