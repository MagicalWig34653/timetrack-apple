import SwiftUI
import TimetrackCore

/// Kind selector (three capsule options) used before starting a timer. Wraps vertically at accessibility sizes.
public struct KindSelector: View {
    @Binding private var selection: SegmentKind
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 20

    public init(selection: Binding<SegmentKind>) { _selection = selection }

    public var body: some View {
        // One row while every option fits at its natural width, otherwise one option per row (no clipped labels).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TT.Space.s) { options(measured: true) }
            VStack(spacing: TT.Space.s) { options(measured: false) }
        }
        .accessibilityElement(children: .contain)
    }

    private func options(measured: Bool) -> some View {
            ForEach(SegmentKind.selectable, id: \.self) { kind in
                let selected = selection == kind
                Button { if selection != kind { TTHaptics.play(.selection) }; selection = kind } label: {
                    HStack(spacing: 8) {
                        Image(systemName: kind.ttSymbol).frame(minWidth: iconWidth)
                        Text(kind.ttTitle).fixedSize(horizontal: measured, vertical: false)
                    }
                        .font(TTFont.label)
                        .lineLimit(1)
                        .padding(.horizontal, TT.Space.m)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? kind.ttTint : TT.textSecondary)
                        .background(selected ? kind.ttTint.opacity(scheme == .dark ? 0.22 : 0.13) : Color.clear, in: .capsule)
                        .overlay { Capsule().strokeBorder(selected ? kind.ttTint.opacity(0.5) : TT.separator, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
    }
}

/// Big timer card. Idle: calm prompt + actions. Running: tinted by the kind, large numerals, subtle live dot.
public struct TimerHero<Actions: View>: View {
    private let startedAt: Date?
    private let kind: SegmentKind
    private let idleTitle: LocalizedStringKey
    private let idleSubtitle: LocalizedStringKey?
    private let runningCaption: LocalizedStringKey
    private let actions: Actions
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 60
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(startedAt: Date?, kind: SegmentKind, idleTitle: LocalizedStringKey, idleSubtitle: LocalizedStringKey? = nil,
                runningCaption: LocalizedStringKey, @ViewBuilder actions: () -> Actions) {
        self.startedAt = startedAt
        self.kind = kind
        self.idleTitle = idleTitle
        self.idleSubtitle = idleSubtitle
        self.runningCaption = runningCaption
        self.actions = actions()
    }

    public var body: some View {
        GlassCard(padding: TT.Space.xl, tint: startedAt == nil ? nil : kind.ttTint.opacity(0.22)) {
            VStack(spacing: TT.Space.l) {
                if let startedAt {
                    HStack(spacing: TT.Space.s) {
                        LiveDot(color: kind.ttTint)
                        Eyebrow(runningCaption)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let clock = RunningTimerDisplay(startedAt: startedAt).clock(at: context.date)
                        Text(verbatim: clock)
                            .font(.system(size: numeralSize, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(TT.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                            // UX3 (F26): spoken to the minute, so VoiceOver does not re-read the clock every second.
                            .accessibilityLabel(Text(verbatim: DurationFormat.spoken(RunningTimerDisplay(startedAt: startedAt).elapsedSeconds(at: context.date))))
                    }
                    KindBadge(kind)
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(TT.textTertiary)
                        .accessibilityHidden(true)
                    VStack(spacing: 4) {
                        Text(idleTitle).font(TTFont.sectionTitle).foregroundStyle(TT.textPrimary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        if let idleSubtitle {
                            Text(idleSubtitle).font(TTFont.meta).foregroundStyle(TT.textSecondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                actions
            }
        }
    }
}
