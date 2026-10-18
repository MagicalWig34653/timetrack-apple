import SwiftUI
import TimetrackDesign
import UIKit

/// Accent colours of the app icon. Single source for the icon picker; the lead may later also use
/// them to drive the in-app accent colour (hex values are documented in docs/ICONS.md and generated
/// from `scripts/icons/build_icons.py`, keep the three in sync).
struct AppIconChoice: Identifiable, Equatable {
    /// Name of the alternate icon bundle; nil is the primary icon (Blau).
    let iconName: String?
    /// Name of the preview image set in `IconPreviews.xcassets`.
    let previewAsset: String
    /// German label (accent colour name or "Motiv Hintergrund").
    let title: String
    /// Picker group: "Klassik" (accent colours) or the motif name (IC1, grouped by motif).
    let group: String
    /// German background name shown under the tile ("Hell", "Mesh", ...), nil for the classic accents.
    let background: String?
    /// Stronger tone (bottom of the ring gradient), sRGB hex.
    let strongHex: UInt32
    /// Lighter tone (top of the ring gradient), sRGB hex.
    let lightHex: UInt32

    var id: String { iconName ?? "primary" }
    var strong: Color { Color(iconHex: strongHex) }
    var light: Color { Color(iconHex: lightHex) }

    static let classic = "Klassik"

    static let accents: [AppIconChoice] = [
        AppIconChoice(iconName: nil, previewAsset: "IconPreview-blue", title: "Blau", group: Self.classic, background: nil, strongHex: 0x2563EB, lightHex: 0x5E93FC),
        AppIconChoice(iconName: "TimetrackTeal", previewAsset: "IconPreview-teal", title: "Türkis", group: Self.classic, background: nil, strongHex: 0x0EA5A4, lightHex: 0x61CDCB),
        AppIconChoice(iconName: "TimetrackViolet", previewAsset: "IconPreview-violet", title: "Violett", group: Self.classic, background: nil, strongHex: 0x7C3AED, lightHex: 0x9D79FE),
        AppIconChoice(iconName: "TimetrackGreen", previewAsset: "IconPreview-green", title: "Grün", group: Self.classic, background: nil, strongHex: 0x16A34A, lightHex: 0x60CA79),
        AppIconChoice(iconName: "TimetrackOrange", previewAsset: "IconPreview-orange", title: "Orange", group: Self.classic, background: nil, strongHex: 0xF97316, lightHex: 0xFEB692),
        AppIconChoice(iconName: "TimetrackPink", previewAsset: "IconPreview-pink", title: "Rosa", group: Self.classic, background: nil, strongHex: 0xEC4899, lightHex: 0xFE91BF),
    ]

    /// Everything the picker offers, in display order (IC1: motif variants come from the generated catalog).
    static let all: [AppIconChoice] = accents + motifs

    /// Group titles in display order with their choices.
    static var groups: [(title: String, choices: [AppIconChoice])] {
        var order: [String] = []
        for c in all where !order.contains(c.group) { order.append(c.group) }
        return order.map { g in (g, all.filter { $0.group == g }) }
    }
}

extension Color {
    fileprivate init(iconHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Left-to-right layout that wraps to the next line when the next child does not fit.
private struct IconFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, CGSize(width: maxX, height: y + rowHeight))
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
        VStack(alignment: .leading, spacing: TT.Space.m) {
            // Motif groups flow left to right and wrap, so small groups share a row.
            IconFlowLayout(spacing: 20) {
                ForEach(AppIconChoice.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: TT.Space.s) {
                        Text(group.title).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                            .accessibilityAddTraits(.isHeader)
                        // Wide groups (Klassik) wrap into rows of up to 3 tiles.
                        let rows = stride(from: 0, to: group.choices.count, by: 3).map {
                            Array(group.choices[$0..<min($0 + 3, group.choices.count)])
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(rows.indices, id: \.self) { r in
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(rows[r]) { choice in
                                        Button { select(choice) } label: { tile(choice).frame(width: 72) }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(choice.title)
                                            .accessibilityIdentifier("appearance.icon.\(choice.iconName ?? "primary")")
                                            .accessibilityAddTraits(choice.iconName == current ? [.isSelected] : [])
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).font(TTFont.meta).foregroundStyle(TT.danger)
            }
        }
        .padding(TT.Space.l)
    }

    private func tile(_ choice: AppIconChoice) -> some View {
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
            Text(choice.background ?? choice.title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(selected ? TT.textPrimary : TT.textSecondary)
        }
    }

    private func select(_ choice: AppIconChoice) {
        guard UIApplication.shared.supportsAlternateIcons, choice.iconName != current else { return }
        UIApplication.shared.setAlternateIconName(choice.iconName) { error in
            DispatchQueue.main.async {
                if let error {
                    errorMessage = String(localized: "Symbol konnte nicht gewechselt werden: \(error.localizedDescription)")
                    TTHaptics.play(.error)
                } else {
                    errorMessage = nil
                    current = choice.iconName
                    TTHaptics.play(.success)
                }
            }
        }
    }
}
