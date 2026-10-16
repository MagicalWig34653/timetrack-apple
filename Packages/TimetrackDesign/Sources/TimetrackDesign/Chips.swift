import SwiftUI
import TimetrackCore

public enum TTTone: Sendable {
    case neutral, accent, success, warning, danger, custom(Color)

    public func color(accent: Color) -> Color {
        switch self {
        case .neutral: TT.textSecondary
        case .accent: accent
        case .success: TT.success
        case .warning: TT.warning
        case .danger: TT.danger
        case .custom(let color): color
        }
    }
}

/// Pill with text (never color only) and an optional symbol or live dot.
public struct StatusChip: View {
    private let label: Text
    private let tone: TTTone
    private let symbol: String?
    @Environment(\.ttTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init(_ key: LocalizedStringKey, tone: TTTone = .neutral, symbol: String? = nil) {
        label = Text(key)
        self.tone = tone
        self.symbol = symbol
    }

    public init(verbatim: String, tone: TTTone = .neutral, symbol: String? = nil) {
        label = Text(verbatim: verbatim)
        self.tone = tone
        self.symbol = symbol
    }

    public var body: some View {
        let color = tone.color(accent: theme.ink)
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small).accessibilityHidden(true) }
            label
        }
        .font(.system(.caption, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(color.opacity(scheme == .dark ? 0.20 : 0.12), in: .capsule)
        .fixedSize()
    }
}

/// Segment kind as tinted badge (symbol + name).
public struct KindBadge: View {
    private let kind: SegmentKind
    private let compact: Bool

    public init(_ kind: SegmentKind, compact: Bool = false) {
        self.kind = kind
        self.compact = compact
    }

    public var body: some View {
        if compact {
            KindGlyph(symbol: kind.ttSymbol, tint: kind.ttTint).accessibilityLabel(Text(kind.ttTitle))
        } else {
            StatusChip(kind.ttTitle, tone: .custom(kind.ttTint), symbol: kind.ttSymbol)
        }
    }
}

/// Rounded-square symbol tile in the kind color.
public struct KindGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 36
    @Environment(\.colorScheme) private var scheme

    public init(symbol: String, tint: Color, size: CGFloat = 36) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(scheme == .dark ? 0.20 : 0.12), in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Pulsing dot that shows a live state; static with Reduce Motion.
public struct LiveDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    public init(color: Color) { self.color = color }

    public var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).scaleEffect(pulsing ? 2.1 : 1).opacity(pulsing ? 0 : 1)
            Circle().fill(color)
        }
        .frame(width: 8, height: 8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulsing = true }
        }
        .accessibilityHidden(true)
    }
}
