#if DEBUG
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Simulator/UI-test page (`TT_DEV_CALENDAR_DAY`): the day-view event section and the "Termin als Zeitabschnitt vorschlagen" sheet against
/// the fake calendar and a stub server that records the request body, so a test can prove the event title is never sent.
struct CalendarDayDemo: View {
    @Environment(\.deviceCalendar) private var deviceCalendar
    @State private var sheet: PlanSheet?
    @State private var demo = DemoStores()
    @State private var sentBody = "–"
    private let zone = TimeZone(identifier: "Europe/Berlin") ?? .current

    var body: some View {
        let calendar = DayCalendar(timeZone: zone)
        let day = calendar.day(for: .now)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    Eyebrow(verbatim: PlanFormat.longDay(day, calendar: calendar))
                    DeviceEventsSection(day: day, calendar: calendar, canSuggest: true, sheet: $sheet)
                    Text(verbatim: "Gesendet: \(sentBody)").font(.caption.monospaced()).accessibilityIdentifier("demo.sent")
                }
                .padding(TT.Space.l)
            }
            .ttScreenBackground()
            .navigationTitle("Tag")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $sheet, onDismiss: { sentBody = demo.transport.lastBody ?? "–" }) { sheet in
            if case .eventDraft(let day, let event) = sheet {
                EventDraftSheet(store: demo.calendarStore, list: demo.listStore, day: day, event: event)
            }
        }
        .task {
            if let deviceCalendar {
                await deviceCalendar.requestAccess()
                for info in deviceCalendar.selectableCalendars { deviceCalendar.setSelected(info.id, true) }
            }
        }
    }
}

@MainActor
private final class DemoStores {
    let transport = RecordingTransport()
    let calendarStore: CalendarStore
    let listStore: TimeListStore

    init() {
        let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin") ?? .current)
        let client = APIClient(baseURL: URL(string: "http://localhost:1")!, transport: transport)
        calendarStore = CalendarStore(client: client, calendar: calendar)
        listStore = TimeListStore(client: client, calendar: calendar)
    }
}

/// Answers every request with an empty list, except segment creation, and keeps the last request body.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var body: String?
    var lastBody: String? { lock.withLock { body } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "http://localhost:1")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        if request.httpMethod == "POST", url.path.hasSuffix("/time/segments") {
            lock.withLock { body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } }
            let segment = #"{"id":"22222222-2222-4222-8222-222222222222","kind":"work","placeId":null,"startedAt":"2026-10-16T06:07:00.123Z","endedAt":"2026-10-16T07:07:00.123Z","rawStartedAt":"2026-10-16T06:07:00Z","rawEndedAt":"2026-10-16T07:07:00Z","source":"manual","note":null,"version":1,"voided":false,"needsReview":false,"revisions":0}"#
            return (Data(segment.utf8), response)
        }
        return (Data("[]".utf8), response)
    }
}
#endif
