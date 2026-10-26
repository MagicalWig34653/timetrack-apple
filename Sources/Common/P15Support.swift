import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// P15: legal profile choice for work models, informative day notes (warnings, school lessons) and the review acknowledgement.
// Strings live in their own table (`P15.xcstrings`). Wording: informative hints, never a statement of legal compliance.

func p15(_ key: String.LocalizationValue) -> String { String(localized: key, table: "P15") }
func p15Key(_ key: String.LocalizationValue) -> LocalizedStringKey { LocalizedStringKey(p15(key)) }

// MARK: - Profile choice in the work model editor

/// Two selectable rows (adult / minor) with the rules the server reports, the sources and the standing notice.
struct LegalProfileSection: View {
    @Binding var profileId: String
    let profiles: [LegalProfile]
    let fromServer: Bool

    private var selected: LegalProfile? { profiles.first { $0.id == profileId } }

    var body: some View {
        FormSection(p15Key("legal.title"), footer: p15Key("legal.notice")) {
            ForEach(profiles) { profile in
                let on = profile.id == profileId
                Button { profileId = profile.id } label: {
                    HStack(alignment: .top, spacing: TT.Space.m) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? TT.textPrimary : TT.textTertiary).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: profile.name).font(TTFont.body).foregroundStyle(TT.textPrimary)
                            if !profile.ruleSummary.isEmpty {
                                Text(verbatim: profile.ruleSummary).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44).contentShape(.rect)
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.xs)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("workmodel.profile.\(profile.id)")
            }
            if !profiles.contains(where: { $0.id == profileId }) {
                Text(p15Key("legal.unknown")).font(TTFont.meta).foregroundStyle(TT.warning).padding(.horizontal, TT.Space.l)
            }
            Text(p15Key("legal.explain")).font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            if selected?.recordsSchoolLessons == true {
                Text(p15Key("legal.minor_school")).font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.s)
            }
            if let selected, !selected.sources.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p15Key("legal.sources")).font(TTFont.eyebrow).foregroundStyle(TT.textTertiary)
                    ForEach(selected.sources, id: \.self) { source in
                        if let url = URL(string: source), url.scheme == "https" {
                            Link(destination: url) { Text(verbatim: Self.sourceTitle(url)).font(TTFont.meta) }
                        }
                    }
                }
                .padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.s)
            } else if !fromServer {
                Text(p15Key("legal.no_details")).font(TTFont.meta).foregroundStyle(TT.textTertiary).padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.s)
            }
        }
    }
}

extension LegalProfileSection {
    /// `https://www.gesetze-im-internet.de/jarbschg/__9.html` -> `§ 9 JArBSchG`-style label; other links show host and file name.
    static func sourceTitle(_ url: URL) -> String {
        let file = url.deletingPathExtension().lastPathComponent
        let law = url.pathComponents.dropFirst().first?.uppercased() ?? ""
        if file.hasPrefix("__"), !law.isEmpty { return "§ \(file.dropFirst(2)) \(law)" }
        return "\(url.host() ?? "") · \(url.lastPathComponent)"
    }
}

extension WorkModel {
    /// Display name for the model card (known ids only; unknown ids show the raw id).
    var legalProfileTitle: String {
        LegalProfile.fallback.first { $0.id == effectiveLegalProfileId }?.name ?? effectiveLegalProfileId
    }
}

// MARK: - Day notes (warnings and school lessons)

extension DayEvaluation {
    /// True when the day carries anything to show: warnings, or a minor profile (school lessons can be recorded).
    var hasLegalNotes: Bool {
        guard legalProfileId != nil else { return false }
        return !(legalWarnings ?? []).isEmpty || recordsSchoolLessons
    }

    /// Minor profile and at least one school entry: the number of lessons is requested (it cannot be derived from the duration).
    var recordsSchoolLessons: Bool {
        legalProfileId == LegalProfileID.minor && (segments ?? []).contains { $0.kind == .school && !$0.voided }
    }
}

/// Informative warnings of the server plus the school lesson count of a minor's school day. Never shows a "compliant" state.
struct LegalDayNotes: View {
    let day: DayEvaluation
    /// Saves the lesson count (nil clears it); answers the server error, nil on success.
    let setLessons: (Int?) async -> TimetrackError?
    @State private var message: String?

    var body: some View {
        if day.hasLegalNotes {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                ForEach(day.legalWarnings ?? [], id: \.code) { warning in
                    Label { Text(verbatim: warning.germanText).font(TTFont.meta) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(TT.warning) }
                        .foregroundStyle(TT.textPrimary)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(verbatim: p15("legal.warning.a11y \(warning.germanText)")))
                }
                if day.recordsSchoolLessons {
                    HStack {
                        Text(p15Key("legal.lessons")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        Spacer(minLength: 0)
                        Picker(p15Key("legal.lessons"), selection: lessons) {
                            Text(p15Key("legal.lessons.none")).tag(Int?.none)
                            ForEach(0...20, id: \.self) { Text(verbatim: "\($0)").tag(Int?.some($0)) }
                        }
                        .labelsHidden().pickerStyle(.menu)
                        .accessibilityLabel(Text(p15Key("legal.lessons")))
                        .accessibilityIdentifier("day.school_lessons")
                    }
                    .frame(minHeight: 44)
                }
                if let message { Text(verbatim: message).font(TTFont.meta).foregroundStyle(TT.danger) }
                Text(p15Key("legal.day_notice")).font(TTFont.meta).foregroundStyle(TT.textTertiary)
            }
            .padding(TT.Space.m).frame(maxWidth: .infinity, alignment: .leading)
            .background(TT.surface, in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("day.legal_notes")
        }
    }

    private var lessons: Binding<Int?> {
        Binding(get: { day.schoolLessonCount }, set: { newValue in
            Task { message = await setLessons(newValue)?.germanMessage(in: .schoolLessons) }
        })
    }
}

// MARK: - Review acknowledgement

/// "Als geprüft markieren" for a flagged entry: clears the server marker (X3). Shown only while `needsReview` is set.
struct AcknowledgeReviewButton: View {
    let segment: Segment
    let acknowledge: () async -> Void
    @State private var busy = false

    var body: some View {
        if segment.needsReview {
            Button {
                guard !busy else { return }
                busy = true
                Task { await acknowledge(); busy = false }
            } label: { Label(p15Key("review.acknowledge"), systemImage: "checkmark.seal") }
            .buttonStyle(.ttSecondary)
            .disabled(busy || segment.isRunning)
            .accessibilityHint(Text(p15Key("review.acknowledge.hint")))
            .accessibilityIdentifier("segment.acknowledge")
        }
    }
}
