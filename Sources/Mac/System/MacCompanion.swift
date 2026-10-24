import AppKit
import ApplicationServices
import Foundation
import Observation
import SwiftUI
import TimetrackCore
import TimetrackStores

/// M2: everything that makes the Mac app a menu bar companion and gives it a sense of the Mac around it.
///
/// - app activity capture (foreground app, optional window title) into the local `ActivityStore`,
/// - presence signals (screen lock, sleep, long inactivity) -> questions, never silent changes,
/// - the global hotkey, the Dock/menu-bar-only mode and the window bookkeeping that goes with it.
///
/// One instance for the process. All sources are public AppKit/IOKit-free APIs: `NSWorkspace` notifications, `CGEventSource`
/// idle time (no permission needed, it reports a number and no input), the screen-lock distributed notifications and Carbon hotkeys.
@MainActor
@Observable
final class MacCompanion {
    static let shared = MacCompanion()

    let activity: ActivityStore
    let loginItem = LoginItem()
    let hotkey = GlobalHotkey()

    private(set) var presence: PresenceSettings
    private(set) var accessibilityTrusted = AXIsProcessTrusted()
    /// The app in front right now (for the settings preview "Zuletzt erfasst").
    private(set) var currentApp: String?
    private(set) var hotkeyFailed = false

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var recorder = ActivityRecorder()
    @ObservationIgnored private var advisor: PresenceAdvisor
    @ObservationIgnored private var locked = false
    @ObservationIgnored private var asleep = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastCheckpoint = Date.now
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored var openMainWindow: (() -> Void)?

    private init() {
        let folder = ((try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Activity", isDirectory: true)
        activity = ActivityStore(storage: .files(in: folder))
        let stored = UserDefaults.standard.data(forKey: MacPrefs.presenceSettings).flatMap { try? JSONDecoder().decode(PresenceSettings.self, from: $0) } ?? PresenceSettings()
        presence = stored
        advisor = PresenceAdvisor(settings: stored)
    }

    // MARK: Lifecycle

    func attach(_ model: AppModel) {
        self.model = model
        guard !started else { return }
        started = true
        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        applyHotkey()
        applyActivationPolicy()
        observeSystem()
        activity.prune(now: .now)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func quit() {
        apply(recorder.finish(at: .now))
    }

    // MARK: Presence settings

    func updatePresence(_ change: (inout PresenceSettings) -> Void) {
        var copy = presence
        change(&copy)
        presence = copy
        advisor.settings = copy
        if let data = try? JSONEncoder().encode(copy) { UserDefaults.standard.set(data, forKey: MacPrefs.presenceSettings) }
        if copy.enabled { Task { await MacNotifications.requestIfNeeded() } }
    }

    // MARK: Hotkey and Dock

    func applyHotkey() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: MacPrefs.hotkeyEnabled) else { hotkey.register(nil); hotkeyFailed = false; return }
        hotkey.register(HotkeyPreset(rawValue: defaults.integer(forKey: MacPrefs.hotkeyPreset)) ?? .controlOptionT)
        hotkeyFailed = hotkey.lastRegistrationFailed
    }

    private func hotkeyPressed() {
        guard let model else { return }
        Task { @MainActor in
            await toggleTimer(model)
            // A tiny confirmation so a start/stop from another app is never a silent surprise.
            NSSound.beep()
        }
    }

    /// Dock icon visible (regular) or hidden (accessory = menu bar only). Windows opened in the accessory mode raise the app to regular
    /// until the last one closes, because an accessory app cannot reliably bring its windows and the Settings scene to the front.
    func applyActivationPolicy() {
        let wantsAccessory = UserDefaults.standard.bool(forKey: MacPrefs.menuBarOnly)
        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        NSApp.setActivationPolicy(wantsAccessory && !hasVisibleWindow ? .accessory : .regular)
    }

    func showMainWindow() {
        if UserDefaults.standard.bool(forKey: MacPrefs.menuBarOnly) { NSApp.setActivationPolicy(.regular) }
        openMainWindow?()
        NSApp.activate()
    }

    // MARK: System signals

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemAway(.asleep) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemReturned(sleepEnded: true) }
        })
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemAway(.locked) }
        })
        distributedObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemReturned(sleepEnded: false) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            // After the window is gone (next run loop pass) the app may hide its Dock icon again.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyActivationPolicy() } }
        })
    }

    private func systemAway(_ reason: PresenceReason) {
        if reason == .locked { locked = true } else { asleep = true }
        tick()
        advisor.away(reason, at: .now)
    }

    private func systemReturned(sleepEnded: Bool) {
        if sleepEnded { asleep = false } else { locked = false }
        guard !locked, !asleep else { return }
        accessibilityTrusted = AXIsProcessTrusted()
        let timer = timerState
        let now = Date.now
        Task { @MainActor in
            let atPlace = await MacAutomationRuntime.shared.isAtWorkPlace()
            let advice = advisor.returned(at: now, timer: timer, atWorkPlace: atPlace)
            await deliver(advice)
            tick()
        }
    }

    private func deliver(_ advice: PresenceAdvice) async {
        switch advice {
        case .none: break
        case .suggestStop(let endAt, let away, let reason):
            let clock = LeaveStopFilter.clockText(endAt)
            let why = switch reason {
            case .locked: "Der Bildschirm war \(Int(away / 60)) Minuten gesperrt."
            case .asleep: "Der Mac war \(Int(away / 60)) Minuten im Ruhezustand."
            case .idle: "Seit \(Int(away / 60)) Minuten gab es keine Eingabe."
            }
            _ = await MacNotifications.postStopQuestion(title: "Timer beenden um \(clock)?", body: "\(why) Der Timer läuft noch. Beenden setzt das Ende auf \(clock).",
                                                        endAt: endAt, eventId: UUID(), source: "presence")
        case .suggestStart(let away):
            _ = await MacNotifications.postStartQuestion(awayMinutes: max(1, Int(away / 60)))
        }
    }

    private var timerState: PresenceTimer {
        model?.today?.running.map { .running(startedAt: $0.startedAt) } ?? .idle
    }

    // MARK: Poll

    /// Idle time in seconds since the last keyboard/mouse/trackpad event. The system reports only this number.
    private var idleSeconds: TimeInterval {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private func tick() {
        guard model?.phase == .signedIn else { _ = recorder.finish(at: .now); return }
        let now = Date.now
        let idle = idleSeconds
        // Presence: long inactivity while unlocked.
        if presence.enabled, !locked, !asleep {
            let advice = advisor.idle(seconds: idle, at: now, timer: timerState)
            if advice != .none { Task { await deliver(advice) } }
        }
        recordActivity(now: now, idle: idle)
    }

    private func recordActivity(now: Date, idle: TimeInterval) {
        let settings = activity.settings
        let front = NSWorkspace.shared.frontmostApplication
        currentApp = front?.localizedName
        let context = ActivityContext(timerRunning: model?.today?.running != nil, screenLocked: locked, asleep: asleep,
                                      idle: idle >= Self.activityIdleSeconds)
        var foreground: ForegroundApp?
        if let front, settings.isRecording, let bundle = front.bundleIdentifier, !settings.isExcluded(bundle) {
            let title = settings.recordWindowTitles && accessibilityTrusted ? Self.focusedWindowTitle(of: front) : nil
            foreground = ForegroundApp(bundleID: bundle, appName: front.localizedName ?? bundle, windowTitle: title)
        }
        apply(recorder.update(foreground: foreground, at: now, context: context, settings: settings))
        if now.timeIntervalSince(lastCheckpoint) >= 60 {
            lastCheckpoint = now
            apply(recorder.checkpoint(at: now))
        }
    }

    /// No input for this long counts as away from the Mac for the activity log (the time is not attributed to the app in front).
    static let activityIdleSeconds: TimeInterval = 5 * 60

    private func apply(_ closed: [ActivityInterval]) { activity.record(closed) }

    /// Title of the focused window through the Accessibility API. Needs the user's permission under Privacy & Security > Accessibility.
    private static func focusedWindowTitle(of app: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success, let window else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }

    /// Opens the system prompt (once) and the Accessibility pane. Titles stay off until the user has granted it and switched them on.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func refreshAccessibility() { accessibilityTrusted = AXIsProcessTrusted() }
}
