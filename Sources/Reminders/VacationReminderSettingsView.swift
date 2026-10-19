import SwiftUI
import TimetrackCore
import TimetrackDesign
import UIKit
import UserNotifications

/// Settings > "Urlaubserinnerungen": local reminders to submit planned vacation, on this device only.
struct VacationReminderSettingsView: View {
    @State private var center = VacationReminderCenter.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                intro
                FormSection(footer: "Beim Einschalten fragt iOS einmal nach der Erlaubnis für Mitteilungen.") {
                    Toggle(isOn: Binding(get: { center.settings.enabled }, set: { value in Task { await center.setEnabled(value) } })) {
                        Label("Erinnerungen", systemImage: "bell.badge").foregroundStyle(TT.textPrimary)
                    }
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                    .accessibilityIdentifier("reminders.toggle")
                }
                if center.authorization == .denied { deniedCard }
                if center.settings.enabled {
                    leadSection
                    timeSection
                    FormSection { statusRow }
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("Urlaubserinnerungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await center.refreshAuthorization() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await center.refreshAuthorization() } } } // permission may have changed in iOS Settings
    }

    private var intro: some View {
        Card {
            HStack(alignment: .top, spacing: TT.Space.m) {
                KindGlyph(symbol: "beach.umbrella", tint: TT.kindVacation)
                VStack(alignment: .leading, spacing: TT.Space.xs) {
                    Text("Urlaub rechtzeitig einreichen").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                    Text("Für geplanten Urlaub, der noch nicht beantragt ist, erinnert Timetrack vor dem Beginn. Sobald der Urlaub beantragt, genehmigt oder gelöscht ist, entfällt die Erinnerung.")
                        .font(TTFont.body).foregroundStyle(TT.textSecondary)
                }
            }
        }
    }

    private var deniedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                Label("Mitteilungen sind ausgeschaltet", systemImage: "bell.slash").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                Text("Du hast Mitteilungen für Timetrack abgelehnt. Erlaube sie in den iOS-Einstellungen, damit Erinnerungen ankommen können.")
                    .font(TTFont.body).foregroundStyle(TT.textSecondary).accessibilityIdentifier("reminders.denied")
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Label("iOS-Einstellungen öffnen", systemImage: "gearshape") }
                    .buttonStyle(.ttSecondary).accessibilityIdentifier("reminders.open_settings")
            }
        }
    }

    private var leadSection: some View {
        FormSection("Erinnern vor Urlaubsbeginn", footer: "Mehrere Zeitpunkte sind möglich. Zeitpunkte, die schon vorbei sind, entfallen.") {
            ForEach(VacationReminderSettings.leadDayChoices, id: \.self) { days in
                Toggle(isOn: Binding(get: { center.settings.leadDays.contains(days) }, set: { value in Task { await center.setLeadDay(days, selected: value) } })) {
                    Text(verbatim: VacationReminderText.lead(days)).foregroundStyle(TT.textPrimary)
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.xs)
                .accessibilityIdentifier("reminders.lead.\(days)")
            }
        }
    }

    private var timeSection: some View {
        FormSection("Uhrzeit", footer: "Die Uhrzeit gilt in der Zeitzone deines Arbeitsmodells.") {
            DatePicker("Uhrzeit", selection: Binding(get: { timeValue }, set: { setTime($0) }), displayedComponents: .hourAndMinute)
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                .accessibilityIdentifier("reminders.time")
        }
    }

    private var statusRow: some View {
        HStack {
            Text("Geplante Erinnerungen").font(TTFont.body).foregroundStyle(TT.textPrimary)
            Spacer()
            StatusChip(verbatim: "\(center.scheduledCount)", tone: .neutral).accessibilityIdentifier("reminders.count")
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
    }

    private var timeValue: Date {
        Calendar.current.date(bySettingHour: center.settings.hour, minute: center.settings.minute, second: 0, of: .now) ?? .now
    }

    private func setTime(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        Task { await center.setTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0) }
    }
}

/// Compact row on the Urlaub tab leading to the reminder settings.
struct VacationReminderLink: View {
    @State private var center = VacationReminderCenter.shared

    var body: some View {
        NavigationLink {
            VacationReminderSettingsView()
        } label: {
            HStack(spacing: TT.Space.m) {
                KindGlyph(symbol: center.settings.enabled ? "bell.badge" : "bell", tint: TT.kindVacation)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Erinnerungen zum Einreichen").font(TTFont.body).foregroundStyle(TT.textPrimary)
                    Text(verbatim: summary).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vacation.reminders")
        .task { await center.refreshAuthorization() }
    }

    private var summary: String {
        guard center.settings.enabled else { return "Aus" }
        let leads = center.settings.normalizedLeadDays.map { VacationReminderText.lead($0) }.joined(separator: ", ")
        return "\(leads) vorher, \(String(format: "%02d:%02d", center.settings.hour, center.settings.minute)) Uhr"
    }
}
