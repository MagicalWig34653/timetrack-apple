import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// AUD3-A: shown after a 403 `reauth_required`. The server wants a session younger than ten minutes; the app signs in again
/// with a passkey in place (no sign-out needed), then the person repeats the action.
struct FreshLoginNotice: View {
    @Environment(AppModel.self) private var model
    @State private var failure: TimetrackError?
    @State private var done = false

    var body: some View {
        FormSection("Frische Anmeldung nötig", footer: "Für diese Aktion musst du dich zur Sicherheit erneut anmelden. Melde dich mit deinem Passkey an und versuche es dann noch einmal.") {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                if done {
                    Label("Angemeldet. Du kannst es jetzt noch einmal versuchen.", systemImage: "checkmark.circle").font(TTFont.body).foregroundStyle(TT.textPrimary)
                } else {
                    Button {
                        Task {
                            failure = await model.reauthenticate()
                            done = failure == nil
                        }
                    } label: { Label("Mit Passkey erneut anmelden", systemImage: "person.badge.key").frame(maxWidth: .infinity) }
                        .buttonStyle(.ttPrimary)
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("account.reauth")
                }
                if let failure, failure != .cancelled {
                    Text(verbatim: failure.germanDescription).font(TTFont.meta).foregroundStyle(TT.danger)
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        }
        .accessibilityIdentifier("account.reauth_notice")
    }
}

/// One line of feedback inside a form card (error in red, confirmation in the normal text colour).
struct StatusLine: View {
    enum Tone { case error, success }
    let text: String
    let tone: Tone
    var id: String?

    var body: some View {
        Label {
            Text(verbatim: text).font(TTFont.meta)
        } icon: {
            Image(systemName: tone == .error ? "exclamationmark.circle" : "checkmark.circle")
        }
        .foregroundStyle(tone == .error ? TT.danger : TT.textSecondary)
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(id ?? (tone == .error ? "account.error" : "account.notice"))
    }
}

#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
