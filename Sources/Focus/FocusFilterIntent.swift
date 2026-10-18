import AppIntents
import Foundation
import TimetrackCore
import TimetrackStores

// The system "Focus filter" shown in Settings > Focus > [Focus] > Focus filters > Timetrack.
// All titles/descriptions below are what the user reads in the system UI: German, short, no jargon.

enum FocusModeOption: String, AppEnum {
    case off, suggest, direct

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Was soll Timetrack tun?")
    static let caseDisplayRepresentations: [FocusModeOption: DisplayRepresentation] = [
        .off: DisplayRepresentation(title: "Nichts tun", subtitle: "Der Timer bleibt, wie er ist."),
        .suggest: DisplayRepresentation(title: "Nachfragen", subtitle: "Du bekommst eine Mitteilung und entscheidest."),
        .direct: DisplayRepresentation(title: "Automatisch starten und stoppen", subtitle: "Ohne Rückfrage."),
    ]

    var mode: FocusMode {
        switch self {
        case .off: .off
        case .suggest: .suggest
        case .direct: .direct
        }
    }
}

enum FocusKindOption: String, AppEnum {
    case work, travel, school

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Art des Zeitabschnitts")
    static let caseDisplayRepresentations: [FocusKindOption: DisplayRepresentation] = [
        .work: DisplayRepresentation(title: "Arbeit"),
        .travel: DisplayRepresentation(title: "Fahrt"),
        .school: DisplayRepresentation(title: "Schule"),
    ]

    var kind: SegmentKind {
        switch self {
        case .work: .work
        case .travel: .travel
        case .school: .school
        }
    }
}

/// A place from the account (e.g. "Betrieb"); optional on the filter. Offered from the cached list, refreshed from the server.
struct FocusPlaceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ort")
    static let defaultQuery = FocusPlaceQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct FocusPlaceQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [FocusPlaceEntity] {
        let places = FocusStateStore().load().places
        return identifiers.compactMap { id in places.first { $0.id == id }.map { FocusPlaceEntity(id: $0.id, name: $0.name) } }
    }

    func suggestedEntities() async throws -> [FocusPlaceEntity] {
        if let client = try? await IntentSession.client(), let fetched = try? await client.listPlaces() {
            let places = fetched.filter { !$0.archived }.map { FocusPlace(id: $0.id, name: $0.name) }
            FocusStateStore().update { $0.places = places }
        }
        return FocusStateStore().load().places.map { FocusPlaceEntity(id: $0.id, name: $0.name) }
    }
}

struct TimetrackFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Timer mit dem Fokus verbinden"
    static let isDiscoverable = false // configured in the system Focus settings, not a Shortcuts action
    static let description = IntentDescription(
        "Startet den Timer in Timetrack, wenn dieser Fokus eingeschaltet wird, und stoppt ihn, wenn der Fokus endet. Auf Wunsch fragt Timetrack vorher nach.",
        categoryName: "Zeiterfassung")

    @Parameter(title: "Was soll Timetrack tun?",
               description: "„Nachfragen“ sendet eine Mitteilung. „Automatisch“ startet und stoppt ohne Rückfrage.")
    var mode: FocusModeOption?

    @Parameter(title: "Art des Zeitabschnitts", description: "Als welche Art wird die Zeit gebucht?", default: .work)
    var kind: FocusKindOption

    @Parameter(title: "Ort (optional)", description: "Wird dem Zeitabschnitt zugeordnet, wenn du einen Ort wählst.")
    var place: FocusPlaceEntity?

    @Parameter(title: "Name dieses Fokus (optional)", description: "Erscheint in den Mitteilungen, z. B. „Arbeit“.")
    var focusName: String?

    var displayRepresentation: DisplayRepresentation {
        let kindName = FocusText.kindName(kind.kind)
        switch mode {
        case nil:
            return DisplayRepresentation(title: "Timetrack: Bitte „Was soll Timetrack tun?“ wählen", subtitle: "Bis dahin passiert nichts.")
        case .off?:
            return DisplayRepresentation(title: "Timetrack: Nichts tun", subtitle: "Der Timer bleibt, wie er ist.")
        case .suggest?:
            return DisplayRepresentation(title: "Timetrack: Nach Timer fragen (\(kindName))", subtitle: "Mitteilung beim Ein- und Ausschalten.")
        case .direct?:
            return DisplayRepresentation(title: "Timetrack: Timer automatisch starten (\(kindName))", subtitle: "Stoppt automatisch, wenn der Fokus endet.")
        }
    }

    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [TimetrackFocusFilter] {
        var filter = TimetrackFocusFilter()
        filter.mode = .suggest
        return [filter]
    }

    /// The system calls this when a Focus with the filter turns on and again when it turns off (then without a usable mode).
    /// No mode = "the Focus ended"; the stored state decides what that means. Kept small: no store loads.
    func perform() async throws -> some IntentResult {
        let configuration = mode.map {
            FocusConfiguration(mode: $0.mode, kind: kind.kind, placeId: place?.id, placeName: place?.name, focusName: focusName)
        }
        let runner = FocusEnvironment.makeRunner()
        let reports = await runner.handle(incoming: configuration, trigger: configuration == nil ? .focusOff : .focusOn)
        await FocusEnvironment.publishIfChanged(reports)
        return .result()
    }
}
