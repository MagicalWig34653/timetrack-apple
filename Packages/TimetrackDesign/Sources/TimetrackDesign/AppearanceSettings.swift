import SwiftUI
import TimetrackCore

#if !os(watchOS) // the page needs ColorPicker and segmented pickers, neither exists on watchOS

/// The "Darstellung" settings page, shared by iOS/iPadOS and macOS: in-app accent colour, light/dark preference, transparency note.
/// `icon` is the platform-specific app-icon section (a picker on iOS, a note on macOS); it is chosen independently from the accent.
public struct AppearanceSettingsPage<Icon: View>: View {
    private let icon: Icon
    private let sync: AppearanceSync?
    @AppStorage(AppearanceKeys.accent) private var accent = AccentChoice.blue.rawValue
    @AppStorage(AppearanceKeys.customHex) private var customHex = "#2563EB"
    @AppStorage(AppearanceKeys.scheme) private var scheme = SchemeChoice.system.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// `sync` writes accent and scheme through to the account; nil keeps the page purely local (previews).
    public init(sync: AppearanceSync? = nil, @ViewBuilder icon: () -> Icon) {
        self.sync = sync
        self.icon = icon()
    }

    private var selected: AccentChoice { AccentChoice(rawValue: accent) ?? .blue }

    public var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.xl) {
            AccentPreviewCard()
            if let sync { SyncStatusLine(sync: sync) }
            accentSection
            FormSection("appearance.scheme", footer: "appearance.scheme.footer") {
                Picker("appearance.scheme", selection: $scheme) {
                    ForEach(SchemeChoice.allCases) { Text($0.titleKey).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(TT.Space.m)
                .accessibilityIdentifier("appearance.scheme")
            }
            FormSection("appearance.transparency", footer: "appearance.transparency.footer") {
                FormRow("appearance.transparency.state") {
                    StatusChip(reduceTransparency ? "appearance.transparency.on" : "appearance.transparency.off", tone: reduceTransparency ? .accent : .neutral)
                }
            }
            icon
        }
        .onChange(of: accent) { sync?.localChanged() }
        .onChange(of: customHex) { sync?.localChanged() }
        .onChange(of: scheme) { sync?.localChanged() }
        .task { await sync?.refreshFromServer() }
    }

    private var accentSection: some View {
        FormSection("appearance.accent", footer: "appearance.accent.footer") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: TT.Space.s)], alignment: .leading, spacing: TT.Space.m) {
                ForEach(AccentChoice.allCases) { choice in
                    Button { if accent != choice.rawValue { TTHaptics.play(.selection) }; accent = choice.rawValue } label: { swatch(choice) }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(choice.titleKey))
                        .accessibilityAddTraits(selected == choice ? [.isButton, .isSelected] : [.isButton])
                        .accessibilityIdentifier("appearance.accent.\(choice.rawValue)")
                }
            }
            .padding(TT.Space.l)
            FormRow("appearance.custom_color") {
                ColorPicker("appearance.custom_color", selection: customBinding, supportsOpacity: false).labelsHidden()
            }
        }
    }

    private var customBinding: Binding<Color> {
        Binding {
            Color(hex: customHex) ?? Color(hex: TT.defaultAccentHex)
        } set: { color in
            customHex = color.ttHexString()
            accent = AccentChoice.custom.rawValue
        }
    }

    private func swatch(_ choice: AccentChoice) -> some View {
        let isSelected = selected == choice
        let hex = AccentChoice.resolvedHex(choice: choice.rawValue, custom: customHex)
        let theme = TTTheme(accentHex: hex)
        return VStack(spacing: 6) {
            ZStack {
                if choice == .custom {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red], center: .center))
                    if isSelected { Circle().fill(theme.accent).padding(9) }
                } else {
                    Circle().fill(theme.accent)
                }
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(theme.onAccent)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(Circle().strokeBorder(isSelected ? TT.textPrimary : TT.cardBorder, lineWidth: isSelected ? 2.5 : 1).padding(isSelected ? -4 : 0))
            .padding(4)
            Text(choice.titleKey).font(TTFont.meta).foregroundStyle(isSelected ? TT.textPrimary : TT.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }
}

/// One quiet line about where the choice is stored; the error variant carries the German message of the failed request.
struct SyncStatusLine: View {
    let sync: AppearanceSync

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TT.Space.s) {
            Image(systemName: symbol).imageScale(.small).foregroundStyle(color).accessibilityHidden(true)
            text.font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TT.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("appearance.sync")
        .accessibilityValue(Text(verbatim: stateName))
    }

    private var stateName: String {
        switch sync.status {
        case .localOnly: "local"
        case .synced: "synced"
        case .syncing: "syncing"
        case .pending: "pending"
        case .failed: "failed"
        }
    }

    private var symbol: String {
        switch sync.status {
        case .synced: "checkmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .pending, .localOnly: "icloud.slash"
        case .failed: "exclamationmark.icloud"
        }
    }

    private var color: Color {
        if case .failed = sync.status { return TT.warning }
        return TT.textSecondary
    }

    @ViewBuilder private var text: some View {
        switch sync.status {
        case .synced: Text("appearance.sync.synced")
        case .syncing: Text("appearance.sync.syncing")
        case .pending: Text("appearance.sync.pending")
        case .localOnly: Text("appearance.sync.local")
        case .failed(let error): Text("appearance.sync.failed \(error.germanDescription)")
        }
    }
}

/// Live sample of the active accent: ring, primary/secondary action, chip and accent text.
struct AccentPreviewCard: View {
    @Environment(\.ttTheme) private var theme

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                HStack(spacing: TT.Space.l) {
                    ProgressRing(progress: 0.62, lineWidth: 9) {
                        Text(verbatim: "62 %").font(TTFont.statSmall).foregroundStyle(TT.textPrimary)
                    }
                    .frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: TT.Space.xs) {
                        Eyebrow("appearance.preview")
                        StatusChip("appearance.preview.chip", tone: .accent, symbol: "checkmark")
                        Text("appearance.preview.text").font(TTFont.label).foregroundStyle(theme.ink)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: TT.Space.m) {
                    Button {} label: { Text("appearance.preview.primary") }.buttonStyle(.ttPrimary)
                    Button {} label: { Text("appearance.preview.secondary") }.buttonStyle(.ttSecondary)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#endif
