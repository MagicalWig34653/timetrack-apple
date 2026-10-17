import AppIntents
import Foundation
import TimetrackCore
import TimetrackStores

// MARK: - Place entity

/// A Timetrack place as a Shortcuts parameter. The list comes from the on-device cache of the last loaded places
/// and is refreshed from the server whenever the session allows it.
struct PlaceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ort"
    static let defaultQuery = PlaceEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PlaceEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [PlaceEntity] {
        let wanted = Set(identifiers)
        return await PlaceCatalog.places().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PlaceEntity] { await PlaceCatalog.places() }
}

enum PlaceCatalog {
    /// Cached places first (works offline and without a session); refreshed from the server when possible.
    static func places() async -> [PlaceEntity] {
        let engine = await MainActor.run { AutomationRuntime.shared.engine }
        if let client = try? await IntentSession.client(), let places = try? await client.listPlaces() {
            await engine.setPlaces(places)
        }
        return await engine.snapshot.places.sorted { $0.name < $1.name }.map { PlaceEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Dialogs

enum AutomationDialog {
    static func arrival(_ outcome: AutomationOutcome) -> String {
        let name = outcome.placeName ?? "diesem Ort"
        switch outcome.decision {
        case .pendingStarted:
            let minutes = outcome.dwellMinutes ?? 5
            return outcome.mode == .direct
                ? "Ankunft in \(name) erfasst. Gebucht wird nach \(minutes) Minuten Aufenthalt."
                : "Ankunft in \(name) erfasst. Nach \(minutes) Minuten Aufenthalt folgt ein Vorschlag."
        case .modeOff: return "Automatik für \(name) ist aus."
        case .globalOff: return "Die Standortautomatik ist ausgeschaltet."
        case .alreadyInside: return "Die Ankunft in \(name) war schon erfasst."
        case .cooldown: return "Zu kurz nach der letzten Abfahrt von \(name): nichts erfasst."
        case .unknownPlace: return "Dieser Ort ist in Timetrack nicht bekannt. Bitte die App öffnen."
        default: return "Fertig."
        }
    }

    static func departure(_ outcome: AutomationOutcome) -> String {
        let name = outcome.placeName ?? "diesem Ort"
        switch outcome.decision {
        case .departureQueued: return "Abfahrt von \(name) erfasst."
        case .confirmedOnExit:
            return outcome.mode == .direct ? "Abfahrt von \(name) erfasst. Der Aufenthalt wird gebucht." : "Abfahrt von \(name) erfasst. Der Aufenthalt wird als Vorschlag angelegt."
        case .passBy: return "Abfahrt von \(name) vor Ablauf der Wartezeit: nichts gebucht."
        case .noArrival: return "Für \(name) war keine Ankunft erfasst."
        case .unknownPlace: return "Dieser Ort ist in Timetrack nicht bekannt. Bitte die App öffnen."
        default: return "Fertig."
        }
    }
}

// MARK: - Intents

struct ArriveAtPlaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Ankunft an einem Ort erfassen"
    static let description = IntentDescription("Meldet Timetrack die Ankunft an einem Ort, zum Beispiel aus einer persönlichen Automation „Wenn ich ankomme“. Gebucht oder vorgeschlagen wird erst nach der Wartezeit, je nach Automatik des Ortes.")
    static let openAppWhenRun = false

    @Parameter(title: "Ort") var place: PlaceEntity

    static var parameterSummary: some ParameterSummary { Summary("Ankunft in \(\.$place) erfassen") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = await MainActor.run { AutomationRuntime.shared.engine }
        let outcome = await engine.shortcutArrived(place.id)
        await MainActor.run { Task { await AutomationRuntime.shared.scheduleChecks() } }
        return .result(dialog: IntentDialog(stringLiteral: AutomationDialog.arrival(outcome)))
    }
}

struct LeaveAtPlaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Abfahrt von einem Ort erfassen"
    static let description = IntentDescription("Meldet Timetrack, dass du einen Ort verlassen hast, zum Beispiel aus einer persönlichen Automation „Wenn ich gehe“.")
    static let openAppWhenRun = false

    @Parameter(title: "Ort") var place: PlaceEntity

    static var parameterSummary: some ParameterSummary { Summary("Abfahrt von \(\.$place) erfassen") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = await MainActor.run { AutomationRuntime.shared.engine }
        let outcome = await engine.shortcutLeft(place.id)
        await MainActor.run { Task { await AutomationRuntime.shared.scheduleChecks() } }
        return .result(dialog: IntentDialog(stringLiteral: AutomationDialog.departure(outcome)))
    }
}

/// Timer kind choice for `StartTimerIntent` (optional parameter).
enum TimerKindOption: String, AppEnum {
    case work, travel, school

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Art"
    static let caseDisplayRepresentations: [TimerKindOption: DisplayRepresentation] = [
        .work: "Arbeit", .travel: "Fahrt", .school: "Schule",
    ]

    var segmentKind: SegmentKind {
        switch self {
        case .work: .work
        case .travel: .travel
        case .school: .school
        }
    }
}
