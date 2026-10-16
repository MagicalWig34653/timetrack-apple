import SwiftUI

/// The Timetrack mark: a rounded tile with an open time arc and a hand. Same motif as the app icon (scripts/make-app-icon.swift).
public struct BrandMark: View {
    private let size: CGFloat
    @Environment(\.ttTheme) private var theme

    public init(size: CGFloat = 72) { self.size = size }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1E2A4A), Color(hex: 0x0B0F1E)], startPoint: .top, endPoint: .bottom))
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(theme.accent.gradient, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round))
                .rotationEffect(.degrees(90))
                .frame(width: size * 0.56, height: size * 0.56)
            Capsule().fill(.white).frame(width: size * 0.05, height: size * 0.2).offset(y: -size * 0.1)
            Capsule().fill(.white.opacity(0.85)).frame(width: size * 0.15, height: size * 0.05).offset(x: size * 0.05)
        }
        .frame(width: size, height: size)
        .shadow(color: theme.accent.opacity(0.35), radius: size * 0.18, y: size * 0.07)
        .accessibilityHidden(true)
    }
}

#Preview("BrandMark") {
    HStack(spacing: 16) { BrandMark(size: 44); BrandMark(size: 96) }.padding(40).ttScreenBackground().ttTheme()
}
