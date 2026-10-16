import SwiftUI
import TimetrackCore
import TimetrackStores

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let today = model.today {
            if let running = today.running {
                Text("menubar.running_since \(running.startedAt.clockText(in: model.dayCalendar.timeZone))")
                Button("command.stop") { Task { await today.stop() } }
                    .keyboardShortcut("t", modifiers: [.command, .option])
            } else {
                Text("today.not_running")
                Button("command.start") { Task { await today.start() } }
                    .keyboardShortcut("t", modifiers: [.command, .option])
            }
            if let day = today.day {
                Text("menubar.today_total \(DurationFormat.hoursMinutes(day.evaluatedWorkSeconds + day.creditSeconds)) \(DurationFormat.hoursMinutes(day.targetSeconds))")
            }
            Divider()
        } else {
            Text("menubar.signed_out")
        }
        Button("menubar.open") {
            openWindow(id: "main")
            NSApplication.shared.activate()
        }
        Button("menubar.reload") { Task { await model.today?.load() } }
            .disabled(model.today == nil)
        Divider()
        Button("menubar.quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
