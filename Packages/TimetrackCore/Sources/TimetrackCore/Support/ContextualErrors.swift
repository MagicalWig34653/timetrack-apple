import Foundation

/// P15: German messages for server validation errors that need the context of the call (the generic `germanDescription` only knows the code).
public enum ErrorContext: Sendable {
    /// Saving, previewing or creating a work model version (incl. the legal profile).
    case workModel
    /// Listing, booking or deleting a time account adjustment.
    case accountAdjustment
    /// Acknowledging the review marker of an entry.
    case reviewAcknowledge
    /// Recording the number of school lessons of a day.
    case schoolLessons
    /// P13: saving a plan day or week with plan blocks.
    case planBlocks
}

extension TimetrackError {
    /// Context specific text, falling back to `germanDescription`.
    public func germanMessage(in context: ErrorContext) -> String {
        switch (context, knownCode) {
        case (.workModel, .invalid?):
            return "Der Server hat das Arbeitsmodell abgelehnt. Prüfe Gültigkeitszeitraum, Wochen-Soll, Pausen und das Rechtsprofil (unbekannte Profile werden abgewiesen)."
        case (.workModel, .modelOverlap?):
            return "Die neue Version überschneidet sich mit einer bestehenden. Wähle ein Datum nach dem Beginn der neuesten Version."
        case (.workModel, .staleVersion?):
            return "Diese Version wurde inzwischen anderswo geändert. Schließe das Fenster und öffne es neu."
        case (.accountAdjustment, .notFound?):
            return "Diese Anpassung gibt es nicht (mehr). Die Liste wird neu geladen."
        case (.accountAdjustment, .conflict?):
            return "Es gibt bereits einen Anfangsstand. Lösche ihn zuerst, wenn du ihn neu setzen möchtest."
        case (.accountAdjustment, .invalid?):
            return "Die Angaben zur Anpassung sind ungültig. Prüfe Datum, Dauer und Begründung (höchstens 200 Zeichen)."
        case (.reviewAcknowledge, .staleVersion?):
            return "Der Eintrag wurde inzwischen geändert. Die Liste wird neu geladen; prüfe ihn bei Bedarf erneut."
        case (.reviewAcknowledge, .invalid?):
            return "Die Prüfmarkierung konnte nicht quittiert werden. Korrigiere den Eintrag stattdessen."
        case (.reviewAcknowledge, .notFound?):
            return "Der Eintrag existiert nicht mehr."
        case (.schoolLessons, .invalid?):
            return "Die Zahl der Unterrichtsstunden muss zwischen 0 und 20 liegen."
        case (.planBlocks, .planTimeInvalid?):
            return "Mindestens ein Planblock hat eine ungültige Uhrzeit. Beginn und Ende brauchen die Form HH:MM, das Ende muss nach dem Beginn liegen und spätestens um 23:59 sein."
        case (.planBlocks, .planBlocksOverlap?):
            return "Planblöcke dürfen sich nicht überschneiden und müssen der Zeit nach geordnet sein. Zwischen zwei Blöcken darf eine Lücke liegen."
        case (.planBlocks, .planBlocksInvalid?):
            return "Ein Tag darf höchstens 32 Planblöcke haben; ein freier Tag hat keine Blöcke."
        case (.planBlocks, .planKindInvalid?):
            return "Die Art eines Planblocks ist unbekannt. Wähle Arbeit, Schule, Fahrt, Büro, Homeoffice oder Kunde."
        case (.planBlocks, .planNoteInvalid?):
            return "Die Notiz eines Planblocks ist zu lang. Erlaubt sind höchstens 200 Zeichen."
        default:
            return germanDescription
        }
    }
}
