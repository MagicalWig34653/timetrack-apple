import SwiftUI

/// Filled primary action (accent, or danger for destructive actions like "Stoppen").
public struct TTPrimaryButtonStyle: ButtonStyle {
    let danger: Bool
    @Environment(\.ttTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(danger: Bool = false) { self.danger = danger }

    public func makeBody(configuration: Configuration) -> some View {
        let fill = danger ? TT.dangerFill : theme.accent
        configuration.label
            .font(.system(.body, weight: .semibold))
            .ttButtonLabelFit(typeSize)
            .foregroundStyle(danger ? Color.white : theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: controlSize == .large ? 54 : 44)
            .padding(.horizontal, TT.Space.m)
            .padding(.vertical, TT.Space.s)
            .background(fill.gradient, in: .rect(cornerRadius: TT.Radius.control + 2, style: .continuous))
            .shadow(color: fill.opacity(isEnabled ? 0.28 : 0), radius: 10, y: 4)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(.rect)
    }
}

/// Quiet outlined action on a tinted surface.
public struct TTSecondaryButtonStyle: ButtonStyle {
    @Environment(\.ttTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.dynamicTypeSize) private var typeSize

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .ttButtonLabelFit(typeSize)
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, minHeight: controlSize == .large ? 54 : 44)
            .padding(.horizontal, TT.Space.m)
            .padding(.vertical, TT.Space.s)
            .background(theme.accent.opacity(configuration.isPressed ? 0.16 : 0.09), in: .rect(cornerRadius: TT.Radius.control + 2, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(.rect)
    }
}

extension View {
    /// Button labels stay on one line (scaling down a little before they would break); at accessibility sizes they wrap instead of truncating.
    func ttButtonLabelFit(_ typeSize: DynamicTypeSize) -> some View {
        self.lineLimit(typeSize.isAccessibilitySize ? 4 : 1)
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.75)
            .multilineTextAlignment(.center)
    }
}

extension ButtonStyle where Self == TTPrimaryButtonStyle {
    public static var ttPrimary: TTPrimaryButtonStyle { TTPrimaryButtonStyle() }
    public static var ttDanger: TTPrimaryButtonStyle { TTPrimaryButtonStyle(danger: true) }
}

extension ButtonStyle where Self == TTSecondaryButtonStyle {
    public static var ttSecondary: TTSecondaryButtonStyle { TTSecondaryButtonStyle() }
}

/// Text field with the design's field surface (label above is the caller's job).
public struct TTFieldStyle: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, TT.Space.m)
            .frame(minHeight: 48)
            .background(TT.surfaceRaised, in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: TT.Radius.control, style: .continuous).strokeBorder(TT.cardBorder, lineWidth: 1) }
    }
}

extension View {
    public func ttField() -> some View { modifier(TTFieldStyle()) }
}

// MARK: - Form sections

/// Grouped form section: title above, rows in a card with hairline dividers, footer below.
public struct FormSection<Content: View>: View {
    private let title: LocalizedStringKey?
    private let footer: LocalizedStringKey?
    private let content: Content

    public init(_ title: LocalizedStringKey? = nil, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            if let title { Eyebrow(title).padding(.horizontal, TT.Space.s).accessibilityAddTraits(.isHeader) }
            ListCard { content }
            if let footer {
                Text(footer).font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.s)
            }
        }
    }
}

/// Label on the left, value on the right; stacks at accessibility sizes.
public struct FormRow<Value: View>: View {
    private let label: Text
    private let value: Value
    private let stacked: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `stacked` puts a long value (URL) below its label.
    public init(_ key: LocalizedStringKey, stacked: Bool = false, @ViewBuilder value: () -> Value) {
        self.stacked = stacked
        label = Text(key)
        self.value = value()
    }

    public var body: some View {
        let vertical = typeSize.isAccessibilitySize || stacked
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: TT.Space.m))
        layout {
            label.font(vertical && stacked ? TTFont.meta : TTFont.body).foregroundStyle(vertical && stacked ? TT.textSecondary : TT.textPrimary)
            if !vertical { Spacer(minLength: TT.Space.s) }
            value.font(TTFont.body).foregroundStyle(stacked ? TT.textPrimary : TT.textSecondary).multilineTextAlignment(vertical ? .leading : .trailing)
        }
        .padding(.horizontal, TT.Space.l)
        .padding(.vertical, TT.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
