import SwiftUI
import TimetrackDesign
import UIKit

/// Accent colours of the app icon. Single source for the icon picker; the lead may later also use
/// them to drive the in-app accent colour (hex values are documented in docs/ICONS.md and generated
/// from `scripts/icons/build_icons.py`, keep the three in sync).
struct IconAccent: Identifiable, Equatable {
    /// Name of the alternate icon bundle; nil is the primary icon (Blau).
    let iconName: String?
    /// Name of the preview image set in `IconPreviews.xcassets`.
    let previewAsset: String
    /// German label.
    let title: String
    /// Stronger tone (bottom of the ring gradient), sRGB hex.
    let strongHex: UInt32
    /// Lighter tone (top of the ring gradient), sRGB hex.
    let lightHex: UInt32
    /// False for the light-surface variant, which is not a plain accent colour.
    let isAccent: Bool

    var id: String { iconName ?? "primary" }
    var strong: Color { Color(iconHex: strongHex) }
    var light: Color { Color(iconHex: lightHex) }

    static let accents: [IconAccent] = [
        IconAccent(iconName: nil, previewAsset: "IconPreview-blue", title: "Blau", strongHex: 0x2563EB, lightHex: 0x5E93FC, isAccent: true),
        IconAccent(iconName: "TimetrackTeal", previewAsset: "IconPreview-teal", title: "Türkis", strongHex: 0x0EA5A4, lightHex: 0x61CDCB, isAccent: true),
        IconAccent(iconName: "TimetrackViolet", previewAsset: "IconPreview-violet", title: "Violett", strongHex: 0x7C3AED, lightHex: 0x9D79FE, isAccent: true),
        IconAccent(iconName: "TimetrackGreen", previewAsset: "IconPreview-green", title: "Grün", strongHex: 0x16A34A, lightHex: 0x60CA79, isAccent: true),
        IconAccent(iconName: "TimetrackOrange", previewAsset: "IconPreview-orange", title: "Orange", strongHex: 0xF97316, lightHex: 0xFEB692, isAccent: true),
        IconAccent(iconName: "TimetrackPink", previewAsset: "IconPreview-pink", title: "Rosa", strongHex: 0xEC4899, lightHex: 0xFE91BF, isAccent: true),
    ]

    /// Everything the picker offers, in display order.
    static let all: [IconAccent] = accents
}

extension Color {
    fileprivate init(iconHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Content of the app-icon section (wrapped in a `FormSection` by the Darstellung page) to choose the app icon (primary or alternate).
/// The icon is independent from the in-app accent colour.
/// UIKit cannot load alternate icon images, so the tiles use preview images shipped in
/// `IconPreviews.xcassets` (rendered from the `.icon` files by the generator script).
struct AppIconPickerSection: View {
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(IconAccent.all) { choice in
                        Button { select(choice) } label: { tile(choice) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                            .accessibilityAddTraits(choice.iconName == current ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            }
            if let errorMessage {
                Text(errorMessage).font(TTFont.meta).foregroundStyle(TT.danger).padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.m)
            }
        }
    }

    private func tile(_ choice: IconAccent) -> some View {
        let selected = choice.iconName == current
        return VStack(spacing: 6) {
            Image(choice.previewAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(selected ? choice.strong : Color.secondary.opacity(0.25), lineWidth: selected ? 3 : 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, choice.strong)
                            .font(.system(size: 20))
                            .offset(x: 4, y: 4)
                    }
                }
            Text(choice.title).font(.caption)
                .foregroundStyle(selected ? TT.textPrimary : TT.textSecondary)
        }
    }

    private func select(_ choice: IconAccent) {
        guard UIApplication.shared.supportsAlternateIcons, choice.iconName != current else { return }
        UIApplication.shared.setAlternateIconName(choice.iconName) { error in
            DispatchQueue.main.async {
                if let error {
                    errorMessage = String(localized: "Symbol konnte nicht gewechselt werden: \(error.localizedDescription)")
                } else {
                    errorMessage = nil
                    current = choice.iconName
                }
            }
        }
    }
}
