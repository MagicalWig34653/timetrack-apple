import AppIntents
import SwiftUI
import TimetrackCore
import TimetrackDesign
import UIKit

/// Step-by-step help for the personal automation "When I arrive / leave". iOS has no public API to create a personal
/// automation from an app (checked in the iOS 27 SDK), so the app offers: the intents with the place as parameter (donated
/// as App Shortcuts, one per place), this guide with the exact names to copy, and links into the Shortcuts app.
struct ShortcutGuideView: View {
    let places: [Place]
    @Environment(\.openURL) private var openURL
    @State private var selected: UUID?
    @State private var copied = false
    @State private var leaving = false
    @State private var tipVisible = true

    private var place: Place? { places.first { $0.id == selected } ?? places.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if places.count > 1 {
                    Picker("Ort", selection: Binding(get: { place?.id ?? UUID() }, set: { selected = $0 })) {
                        ForEach(places) { Text(verbatim: $0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("automation.guide.place")
                }
                Picker("Auslöser", selection: $leaving) {
                    Text("Ankunft").tag(false)
                    Text("Abfahrt").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("automation.guide.trigger")

                Card {
                    Text("iOS erlaubt Apps nicht, eine Automation selbst anzulegen. In drei Schritten ist sie trotzdem in einer Minute eingerichtet; der Ortsname steht unten zum Kopieren bereit.")
                        .font(TTFont.body).foregroundStyle(TT.textPrimary)
                }

                if let place {
                    step(1, title: leaving ? "Automation „Verlassen“ anlegen" : "Automation „Ankunft“ anlegen",
                         text: "Öffne Kurzbefehle, wechsle zu „Automation“, tippe auf „+“ und wähle „\(leaving ? "Verlassen" : "Ankunft")“. Wähle als Ort „\(place.name)“ und lasse „Jederzeit“ stehen.") {
                        IllustrationAutomationTab(trigger: leaving ? "Verlassen" : "Ankunft")
                    }
                    step(2, title: "Aktion „Timetrack“ wählen",
                         text: "Tippe auf „Aktion hinzufügen“, suche „Timetrack“ und wähle „\(leaving ? "Abfahrt von einem Ort erfassen" : "Ankunft an einem Ort erfassen")“. Setze als Ort „\(place.name)“.") {
                        IllustrationAction(title: leaving ? "Abfahrt von \(place.name) erfassen" : "Ankunft in \(place.name) erfassen")
                    }
                    step(3, title: "Sofort ausführen",
                         text: "Wähle „Sofort ausführen“, damit nichts nachgefragt wird, und tippe auf „Fertig“. Die Automation meldet jetzt jede \(leaving ? "Abfahrt" : "Ankunft"); gebucht oder vorgeschlagen wird nach dem Modus des Ortes.") {
                        IllustrationRunImmediately()
                    }

                    FormSection("Zum Kopieren") {
                        HStack {
                            Text(verbatim: place.name).font(TTFont.body).textSelection(.enabled)
                            Spacer()
                            Button(copied ? "Kopiert" : "Namen kopieren") {
                                UIPasteboard.general.string = place.name
                                copied = true
                            }
                            .font(TTFont.label)
                            .accessibilityIdentifier("automation.guide.copy")
                        }
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    }

                    VStack(alignment: .leading, spacing: TT.Space.m) {
                        Button { if let url = URL(string: "shortcuts://") { openURL(url) } } label: {
                            Label("Kurzbefehle öffnen", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.ttPrimary)
                        .accessibilityIdentifier("automation.guide.open")
                        ShortcutsLink().shortcutsLinkStyle(.automaticOutline)
                        SiriTipView(intent: tipIntent(place), isVisible: $tipVisible)
                    }

                    Text("Hinweis: Die Bezeichnungen in der Kurzbefehle-App können je nach iOS-Version leicht abweichen. Dieser Ablauf wurde noch nicht auf einem echten Gerät erprobt.")
                        .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                } else {
                    EmptyState(symbol: "mappin.slash", title: "Kein Ort vorhanden", message: "Lege zuerst einen Ort an.")
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("Kurzbefehl erstellen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tipIntent(_ place: Place) -> any AppIntent {
        if leaving {
            var intent = LeaveAtPlaceIntent()
            intent.place = PlaceEntity(id: place.id, name: place.name)
            return intent
        }
        var intent = ArriveAtPlaceIntent()
        intent.place = PlaceEntity(id: place.id, name: place.name)
        return intent
    }

    private func step<Illustration: View>(_ number: Int, title: String, text: String, @ViewBuilder illustration: () -> Illustration) -> some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                HStack(spacing: TT.Space.m) {
                    Text("\(number)").font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(TT.kindWork, in: .circle).accessibilityHidden(true)
                    Text(title).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                }
                Text(text).font(TTFont.body).foregroundStyle(TT.textSecondary)
                illustration().accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("automation.guide.step\(number)")
    }
}

// MARK: - Illustrations (drawn, not screenshots: always current and localised)

private struct MockSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(TT.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TT.surfaceRaised, in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: TT.Radius.control, style: .continuous).strokeBorder(TT.cardBorder, lineWidth: 1) }
    }
}

private struct IllustrationAutomationTab: View {
    let trigger: String
    var body: some View {
        MockSurface {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                HStack(spacing: TT.Space.l) {
                    Text("Kurzbefehle").foregroundStyle(TT.textTertiary)
                    Text("Automation").fontWeight(.semibold).foregroundStyle(TT.kindWork)
                    Spacer()
                    Image(systemName: "plus").foregroundStyle(TT.kindWork)
                }
                .font(TTFont.label)
                Divider()
                Label(trigger, systemImage: trigger == "Ankunft" ? "arrow.down.to.line" : "arrow.up.to.line")
                    .font(TTFont.body).foregroundStyle(TT.textPrimary)
                Label("Ort wählen · Jederzeit", systemImage: "mappin.and.ellipse").font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
        }
    }
}

private struct IllustrationAction: View {
    let title: String
    var body: some View {
        MockSurface {
            HStack(spacing: TT.Space.m) {
                Image(systemName: "clock.badge.checkmark").foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(TT.kindWork, in: .rect(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timetrack").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    Text(verbatim: title).font(TTFont.label).foregroundStyle(TT.textPrimary)
                }
            }
        }
    }
}

private struct IllustrationRunImmediately: View {
    var body: some View {
        MockSurface {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                HStack { Text("Sofort ausführen").font(TTFont.body); Spacer(); Image(systemName: "checkmark").foregroundStyle(TT.kindWork) }
                Divider()
                HStack { Text("Vor Ausführung fragen").font(TTFont.body).foregroundStyle(TT.textSecondary); Spacer() }
            }
            .foregroundStyle(TT.textPrimary)
        }
    }
}
