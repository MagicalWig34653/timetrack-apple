import SwiftUI
import TimetrackDesign

/// One row of a settings group: symbol, title, optional trailing value and a chevron. Used inside `FormSection`.
struct SettingsLinkRow<Destination: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    var value: String?
    let id: String
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRowLabel(title: title, symbol: symbol, value: value, chevron: "chevron.right")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Same look as `SettingsLinkRow`, but runs an action (opens a sheet, sends something) instead of pushing a page.
struct SettingsActionRow: View {
    let title: LocalizedStringKey
    let symbol: String
    var trailingSymbol = "chevron.right"
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(title: title, symbol: symbol, value: nil, chevron: trailingSymbol)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: String?
    let chevron: String

    var body: some View {
        HStack(spacing: TT.Space.m) {
            Label(title, systemImage: symbol).foregroundStyle(TT.textPrimary)
            Spacer(minLength: TT.Space.s)
            if let value { Text(verbatim: value).font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(1) }
            Image(systemName: chevron).font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}
