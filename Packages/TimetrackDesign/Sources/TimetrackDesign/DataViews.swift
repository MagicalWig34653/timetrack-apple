import SwiftUI
import TimetrackCore

// MARK: - StatTile

/// Key figure: small label, big numeral, optional caption and "vorläufig"-style chip.
public struct StatTile: View {
    private let title: LocalizedStringKey
    private let value: String
    private let caption: LocalizedStringKey?
    private let chip: LocalizedStringKey?
    private let tone: TTTone?
    private let symbol: String?

    public init(_ title: LocalizedStringKey, value: String, caption: LocalizedStringKey? = nil, chip: LocalizedStringKey? = nil,
                tone: TTTone? = nil, symbol: String? = nil) {
        self.title = title
        self.value = value
        self.caption = caption
        self.chip = chip
        self.tone = tone
        self.symbol = symbol
    }

    @Environment(\.ttTheme) private var theme

    public var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.xs) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).imageScale(.small).foregroundStyle(TT.textTertiary).accessibilityHidden(true) }
                Text(title).font(TTFont.label).foregroundStyle(TT.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(verbatim: value)
                .font(TTFont.stat)
                .foregroundStyle(tone.map { $0.color(accent: theme.ink) } ?? TT.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption { Text(caption).font(TTFont.meta).foregroundStyle(TT.textSecondary) }
            if let chip { StatusChip(chip, tone: .neutral) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(TT.Space.l)
        .ttSurface(radius: TT.Radius.card - 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Progress

/// Ring that shows captured vs. target. Over 100 % keeps the ring full and switches to the success tint.
public struct ProgressRing<Center: View>: View {
    private let progress: Double
    private let lineWidth: CGFloat
    private let tint: Color?
    private let center: Center
    @Environment(\.ttTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: Double, lineWidth: CGFloat = 12, tint: Color? = nil, @ViewBuilder center: () -> Center = { EmptyView() }) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.tint = tint
        self.center = center()
    }

    public var body: some View {
        let clamped = min(max(progress, 0), 1)
        let color = tint ?? (progress >= 1 ? TT.success : theme.accent)
        ZStack {
            Circle().stroke(color.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, progress > 0 ? 0.012 : 0))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: clamped)
            center
        }
        .ttRingHalo(color)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(verbatim: "\(Int((progress * 100).rounded())) %"))
    }
}

/// Slim horizontal variant for tight spaces (watch, day headers).
public struct ProgressBar: View {
    private let progress: Double
    private let tint: Color?
    private let height: CGFloat
    @Environment(\.ttTheme) private var theme

    public init(progress: Double, tint: Color? = nil, height: CGFloat = 6) {
        self.progress = progress
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        let color = tint ?? (progress >= 1 ? TT.success : theme.accent)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color.gradient).frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(verbatim: "\(Int((progress * 100).rounded())) %"))
    }
}

// MARK: - Segment row

/// One time segment: kind glyph, time range, kind name + note, duration; running and review states.
public struct SegmentRowCell: View {
    private let kind: SegmentKind
    private let timeRange: String
    private let duration: String?
    private let note: String?
    private let isRunning: Bool
    private let needsReview: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(kind: SegmentKind, timeRange: String, duration: String?, note: String? = nil, isRunning: Bool = false, needsReview: Bool = false) {
        self.kind = kind
        self.timeRange = timeRange
        self.duration = duration
        self.note = note
        self.isRunning = isRunning
        self.needsReview = needsReview
    }

    private var kindLine: some View {
        HStack(spacing: 6) {
            Text(kind.ttTitle).foregroundStyle(kind.ttTint)
            if let note, !note.isEmpty {
                Text(verbatim: "·").foregroundStyle(TT.textTertiary)
                Text(verbatim: note).foregroundStyle(TT.textSecondary).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
        }
        .font(TTFont.meta)
    }

    private var trailing: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
            if isRunning {
                StatusChip("segment.running", tone: .success, symbol: "circle.fill")
            } else if let duration {
                Text(verbatim: duration).font(TTFont.numeral).foregroundStyle(TT.textPrimary)
            }
            if needsReview {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(TT.warning).imageScale(.small)
                    .accessibilityLabel(Text("segment.needs_review"))
            }
        }
    }

    public var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Everything stacked: nothing competes for width at accessibility sizes.
                VStack(alignment: .leading, spacing: TT.Space.s) {
                    HStack(spacing: TT.Space.m) {
                        KindGlyph(symbol: kind.ttSymbol, tint: kind.ttTint)
                        Text(verbatim: timeRange).font(TTFont.numeral).foregroundStyle(TT.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }
                    kindLine
                    trailing
                }
            } else {
                HStack(alignment: .center, spacing: TT.Space.m) {
                    KindGlyph(symbol: kind.ttSymbol, tint: kind.ttTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: timeRange).font(TTFont.numeral).foregroundStyle(TT.textPrimary)
                        kindLine
                    }
                    Spacer(minLength: TT.Space.s)
                    trailing
                }
            }
        }
        .padding(.horizontal, TT.Space.l)
        .padding(.vertical, TT.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty / error / loading

public struct EmptyState: View {
    private let symbol: String
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey?

    public init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
    }

    @Environment(\.ttTheme) private var theme

    public var body: some View {
        VStack(spacing: TT.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(theme.ink)
                .frame(width: 56, height: 56)
                .background(theme.accent.opacity(0.10), in: .circle)
                .padding(.bottom, TT.Space.xs)
                .accessibilityHidden(true)
            Text(title).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary).multilineTextAlignment(.center)
            if let message {
                Text(message).font(TTFont.meta).foregroundStyle(TT.textSecondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TT.Space.xl)
        .padding(.horizontal, TT.Space.l)
        .accessibilityElement(children: .combine)
    }
}

/// Inline error with retry; text is the already localized, user-facing message.
public struct ErrorBanner: View {
    private let message: String
    private let retryTitle: LocalizedStringKey
    private let retry: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(message: String, retryTitle: LocalizedStringKey, retry: @escaping () -> Void) {
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: TT.Space.s)) : AnyLayout(HStackLayout(spacing: TT.Space.m))
        layout {
            HStack(alignment: .top, spacing: TT.Space.s) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(TT.danger).accessibilityHidden(true)
                Text(verbatim: message).font(TTFont.meta).foregroundStyle(TT.textPrimary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Button(retryTitle, action: retry).font(TTFont.label).lineLimit(1).buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                .frame(minHeight: 44).contentShape(.rect)
        }
        .padding(TT.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TT.danger.opacity(0.10), in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: TT.Radius.control, style: .continuous).strokeBorder(TT.danger.opacity(0.25), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Neutral hint callout (break hints and similar), not an error.
public struct HintBanner: View {
    private let text: LocalizedStringKey
    private let symbol: String

    public init(_ text: LocalizedStringKey, symbol: String = "info.circle.fill") {
        self.text = text
        self.symbol = symbol
    }

    public var body: some View {
        HStack(alignment: .top, spacing: TT.Space.s) {
            Image(systemName: symbol).foregroundStyle(TT.warning).accessibilityHidden(true)
            Text(text).font(TTFont.meta).foregroundStyle(TT.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(TT.Space.m)
        .background(TT.warning.opacity(0.10), in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Shimmering placeholder block.
public struct SkeletonBlock: View {
    private let height: CGFloat
    private let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    public init(height: CGFloat = 16, radius: CGFloat = 8) {
        self.height = height
        self.radius = radius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(TT.textTertiary.opacity(phase ? 0.12 : 0.22))
            .frame(height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { phase = true }
            }
            .accessibilityHidden(true)
    }
}

/// Loading layout for Today / lists.
public struct SkeletonList: View {
    private let rows: Int
    public init(rows: Int = 3) { self.rows = rows }

    public var body: some View {
        ListCard {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: TT.Space.m) {
                    SkeletonBlock(height: 36, radius: 11).frame(width: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(height: 14).frame(maxWidth: 150)
                        SkeletonBlock(height: 11).frame(maxWidth: 90)
                    }
                    Spacer()
                    SkeletonBlock(height: 14).frame(width: 44)
                }
                .padding(TT.Space.l)
            }
        }
        .accessibilityLabel(Text("root.loading"))
    }
}
