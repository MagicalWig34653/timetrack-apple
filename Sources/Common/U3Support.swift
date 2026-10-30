import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// U3: pieces shared by iOS/iPadOS and macOS. Strings live in `U3.xcstrings` (table "U3").

func u3(_ key: String.LocalizationValue) -> Text { Text(LocalizedStringResource(key, table: "U3")) }
func u3String(_ key: String.LocalizationValue) -> String { String(localized: key, table: "U3") }

extension Notification.Name {
    /// A timer was started or stopped outside the stores (notification action, leave-stop, location automation event, push);
    /// the model checks the server for the running timer.
    static let ttTimerChangedExternally = Notification.Name("de.linolaske.timetrack.timerChangedExternally")
}

/// Keeps the running timer fresh on every screen: a timer started by the location automation (server side, another device, link, watch)
/// shows promptly, so a manual start never runs into "already running".
/// - on becoming active (every tab, not only "Heute"),
/// - while active, a cheap check every `interval` seconds (`TodayStore.refreshRunning`: one request, a full reload only on a change),
/// - on notifications about timer changes (`.ttTimerChangedExternally`, posted for automation events, notification actions and pushes).
struct TimerFreshness: ViewModifier {
    let model: AppModel
    var interval: Duration = .seconds(30)
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await model.today?.refreshRunning()
                    try? await Task.sleep(for: interval)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttTimerChangedExternally)) { _ in
                Task { await model.today?.refreshRunning() }
            }
            .modifier(TimerConflictToast())
    }
}

extension View {
    func timerFreshness(model: AppModel) -> some View { modifier(TimerFreshness(model: model)) }
}

/// A start was refused because a timer already runs. The running timer is shown; when another kind was wanted, "Wechseln" ends the
/// running one and starts the requested kind. No error banner.
struct TimerConflictToast: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let conflict = model.today?.conflict, let store = model.today {
                    let since = conflict.running.startedAt.formatted(Date.FormatStyle(timeZone: store.timeZone).hour().minute())
                    VStack(alignment: .leading, spacing: TT.Space.xs) {
                        u3("u3.conflict.title \(conflict.running.kind.plainName) \(since)")
                            .font(TTFont.label).foregroundStyle(TT.textPrimary)
                        HStack {
                            Button { hideTask?.cancel(); Task { await store.switchRunning(to: conflict.requested) } } label: {
                                u3("u3.conflict.switch \(conflict.requested.plainName)").font(TTFont.label.weight(.semibold)).frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("toast.conflict.switch")
                            Spacer(minLength: TT.Space.s)
                            Button { hideTask?.cancel(); store.clearConflict() } label: {
                                u3("u3.conflict.keep").font(TTFont.label).frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("toast.conflict.keep")
                        }
                    }
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                    .background(.regularMaterial, in: .rect(cornerRadius: TT.Radius.card))
                    .overlay { RoundedRectangle(cornerRadius: TT.Radius.card).strokeBorder(TT.cardBorder, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.horizontal, TT.Space.l).padding(.top, TT.Space.xs)
                    .frame(maxWidth: 520)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("toast.conflict")
                }
            }
            .animation(.smooth(duration: 0.3), value: model.today?.conflict)
            .onChange(of: model.today?.conflict) { _, new in
                hideTask?.cancel()
                guard new != nil else { return }
                hideTask = Task {
                    try? await Task.sleep(for: .seconds(12))
                    if !Task.isCancelled { model.today?.clearConflict() }
                }
            }
    }
}
