import SwiftUI
import UIKit

/// Self-contained settings section to choose the app icon (primary or alternate).
/// Alternate icon names match the `.icon` bundles in Icons/ (see docs/ICONS.md).
/// Previews are small SwiftUI approximations of the icons (arc + pointer on a surface).
struct AppIconPickerSection: View {
    private struct Choice: Identifiable {
        let id: String?          // nil = primary icon
        let title: String
        let surface: Color
        let arc: Color
        let hand: Color
    }

    private static let choices: [Choice] = [
        Choice(id: nil, title: String(localized: "Standard", defaultValue: "Standard"),
               surface: Color(red: 0.957, green: 0.957, blue: 0.961), arc: Color(red: 0.631, green: 0.631, blue: 0.667),
               hand: Color(red: 0.145, green: 0.388, blue: 0.922)),
        Choice(id: "TimetrackLight", title: String(localized: "Hell", defaultValue: "Hell"),
               surface: Color(red: 0.98, green: 0.98, blue: 0.98), arc: Color(red: 0.831, green: 0.831, blue: 0.847),
               hand: Color(red: 0.145, green: 0.388, blue: 0.922)),
        Choice(id: "TimetrackDark", title: String(localized: "Dunkel", defaultValue: "Dunkel"),
               surface: Color(red: 0.094, green: 0.094, blue: 0.106), arc: Color(red: 0.322, green: 0.322, blue: 0.357),
               hand: Color(red: 0.231, green: 0.510, blue: 0.965)),
        Choice(id: "TimetrackMono", title: String(localized: "Kontrast", defaultValue: "Kontrast"),
               surface: .black, arc: .white, hand: .white),
        Choice(id: "TimetrackTeal", title: String(localized: "Petrol", defaultValue: "Petrol"),
               surface: Color(red: 0.957, green: 0.957, blue: 0.961), arc: Color(red: 0.631, green: 0.631, blue: 0.667),
               hand: Color(red: 0.051, green: 0.580, blue: 0.533)),
    ]

    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Self.choices) { choice in
                        Button { select(choice) } label: { tile(choice) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                            .accessibilityAddTraits(choice.id == current ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 4)
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text(String(localized: "App-Symbol", defaultValue: "App-Symbol"))
        }
    }

    private func tile(_ choice: Choice) -> some View {
        let selected = choice.id == current
        return VStack(spacing: 6) {
            IconThumbnail(surface: choice.surface, arc: choice.arc, hand: choice.hand)
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1)
                )
            Text(choice.title).font(.caption)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
    }

    private func select(_ choice: Choice) {
        guard UIApplication.shared.supportsAlternateIcons, choice.id != current else { return }
        UIApplication.shared.setAlternateIconName(choice.id) { error in
            DispatchQueue.main.async {
                if let error {
                    errorMessage = String(localized: "Symbol konnte nicht gewechselt werden: \(error.localizedDescription)")
                } else {
                    errorMessage = nil
                    current = choice.id
                }
            }
        }
    }
}

/// Approximation of the icon artwork (see Icons/source/*.svg), drawn on a 1024 grid.
private struct IconThumbnail: View {
    let surface: Color, arc: Color, hand: Color

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 1024
            ZStack {
                surface
                Path { p in
                    p.addArc(center: CGPoint(x: 512 * k, y: 540 * k), radius: 280 * k,
                             startAngle: .degrees(120), endAngle: .degrees(60), clockwise: false)
                }
                .stroke(arc, style: StrokeStyle(lineWidth: 52 * k, lineCap: .round))
                Path { p in
                    p.move(to: CGPoint(x: 512 * k, y: 540 * k))
                    p.addLine(to: CGPoint(x: 652 * k, y: 338 * k))
                }
                .stroke(hand, style: StrokeStyle(lineWidth: 60 * k, lineCap: .round))
                Circle().fill(hand).frame(width: 128 * k, height: 128 * k)
                    .position(x: 512 * k, y: 540 * k)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
