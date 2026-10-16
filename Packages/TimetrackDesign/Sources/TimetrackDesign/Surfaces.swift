import SwiftUI

extension EnvironmentValues {
    /// Forces solid surfaces (previews of the Reduce Transparency fallback, or contexts without glass).
    @Entry public var ttSolidSurfaces = false
}

// MARK: - Backdrop

/// Calm page background: neutral base with two very soft accent glows at the top so glass surfaces have something to refract.
public struct TTBackdrop: View {
    @Environment(\.ttTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        ZStack {
            TT.background
            GeometryReader { proxy in
                let glow = scheme == .dark ? 0.20 : 0.11
                Circle()
                    .fill(theme.accent.opacity(glow))
                    .frame(width: proxy.size.width * 0.9)
                    .blur(radius: 70)
                    .offset(x: -proxy.size.width * 0.35, y: -proxy.size.width * 0.45)
                Circle()
                    .fill(theme.accent.opacity(glow * 0.6))
                    .frame(width: proxy.size.width * 0.7)
                    .blur(radius: 80)
                    .offset(x: proxy.size.width * 0.55, y: -proxy.size.width * 0.2)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Page background with the soft accent glow.
    public func ttScreenBackground() -> some View {
        background { TTBackdrop() }
    }

    /// Solid card surface: fill, hairline border, barely-there shadow. Data cards are never transparent (DESIGN.md).
    public func ttSurface(radius: CGFloat = TT.Radius.card) -> some View {
        modifier(TTSurfaceModifier(radius: radius))
    }

    /// Liquid Glass where available; solid fallback with Reduce Transparency.
    public func ttGlass(radius: CGFloat = TT.Radius.hero, tint: Color? = nil) -> some View {
        modifier(TTGlassModifier(radius: radius, tint: tint))
    }
}

struct TTSurfaceModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(TT.surface, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(TT.cardBorder, lineWidth: 1) }
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

struct TTGlassModifier: ViewModifier {
    let radius: CGFloat
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.ttSolidSurfaces) private var solid

    func body(content: Content) -> some View {
        if reduceTransparency || solid {
            content
                .background(TT.glassFallback, in: .rect(cornerRadius: radius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(TT.cardBorder, lineWidth: 1) }
        } else {
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: .rect(cornerRadius: radius, style: .continuous))
        }
    }
}

// MARK: - Cards

/// Standard solid card.
public struct Card<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = TT.Space.l, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ttSurface()
    }
}

/// Glass card for hero content (timer) that sits on the backdrop.
public struct GlassCard<Content: View>: View {
    private let padding: CGFloat
    private let tint: Color?
    private let content: Content

    public init(padding: CGFloat = TT.Space.xl, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .ttGlass(radius: TT.Radius.hero, tint: tint)
    }
}

/// Card whose children are separated by hairline dividers (lists of rows).
public struct ListCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index]
                    if index < subviews.count - 1 {
                        Divider().overlay(TT.separator).padding(.leading, TT.Space.l)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ttSurface()
    }
}

// MARK: - Section header

/// Section title with an optional trailing accessory (count, action).
public struct SectionHeader<Trailing: View>: View {
    private let title: LocalizedStringKey
    private let trailing: Trailing

    public init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(TTFont.sectionTitle).foregroundStyle(TT.textPrimary).accessibilityAddTraits(.isHeader)
            Spacer(minLength: TT.Space.s)
            trailing.font(TTFont.meta).foregroundStyle(TT.textSecondary)
        }
        .padding(.horizontal, TT.Space.xs)
    }
}

/// Small uppercase label above a title or value.
public struct Eyebrow: View {
    private let text: Text
    public init(_ key: LocalizedStringKey) { text = Text(key) }
    public init(verbatim: String) { text = Text(verbatim: verbatim) }

    public var body: some View {
        text.font(TTFont.eyebrow).textCase(.uppercase).tracking(0.9).foregroundStyle(TT.textSecondary)
    }
}
