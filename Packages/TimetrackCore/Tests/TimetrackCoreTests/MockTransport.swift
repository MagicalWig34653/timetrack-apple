import Foundation
@testable import TimetrackCore

/// Scripted transport: answers are matched by "METHOD /path" prefix in FIFO order per key; every request is recorded.
final class MockTransport: HTTPTransport, SessionCookieJar, @unchecked Sendable {
    struct Reply {
        var status: Int = 200
        var body: String = ""
        var error: URLError.Code?
    }

    private let lock = NSLock()
    private var replies: [String: [Reply]] = [:]
    private(set) var requests: [URLRequest] = []
    private var cookie: String?
    var delay: Duration?

    func enqueue(_ key: String, status: Int = 200, body: String = "", error: URLError.Code? = nil) {
        lock.withLock { replies[key, default: []].append(Reply(status: status, body: body, error: error)) }
    }

    /// Replaces any queued or repeating answers of `key` (used when a test changes the server's answer midway).
    func set(_ key: String, status: Int = 200, body: String = "") {
        lock.withLock { replies[key] = [Reply(status: status, body: body)] }
    }

    func requests(matching key: String) -> [URLRequest] {
        lock.withLock { requests.filter { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" == key } }
    }

    /// H4: one-shot barrier for the NEXT request of `key`: the answer is decided when the request arrives but delivered only after
    /// `release()`, i.e. a slow response that overtakes later requests (stale read).
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { continuation in
                let resumeNow = lock.withLock { () -> Bool in
                    if open { return true }
                    waiters.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }

        func release() {
            let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                open = true
                defer { waiters = [] }
                return waiters
            }
            pending.forEach { $0.resume() }
        }
    }

    private var holds: [String: [Gate]] = [:]

    func hold(_ key: String) -> Gate {
        let gate = Gate()
        lock.withLock { holds[key, default: []].append(gate) }
        return gate
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let delay { try await Task.sleep(for: delay) }
        let key = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
        let gate: Gate? = lock.withLock { holds[key]?.isEmpty == false ? holds[key]!.removeFirst() : nil }
        let reply: Reply? = lock.withLock {
            requests.append(request)
            guard var queue = replies[key], !queue.isEmpty else { return nil }
            let first = queue.removeFirst()
            replies[key] = queue.isEmpty ? [first] : queue // the last reply repeats
            return first
        }
        await gate?.wait()
        guard let reply else { return (Data(#"{"error":{"code":"not_found","message":"unmocked"}}"#.utf8), response(request, 404)) }
        if let error = reply.error { throw URLError(error) }
        return (Data(reply.body.utf8), response(request, reply.status))
    }

    private func response(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    // SessionCookieJar
    func sessionCookieValue(for baseURL: URL) -> String? { lock.withLock { cookie } }
    func setSessionCookie(_ value: String, for baseURL: URL) { lock.withLock { cookie = value } }
    func clearSessionCookie(for baseURL: URL) { lock.withLock { cookie = nil } }
}

enum Fixtures {
    static let baseURL = URL(string: "http://localhost:18090")!

    static let accountJSON = #"{"id":"11111111-1111-4111-8111-111111111111","handle":"anna","displayName":"Anna Beispiel","role":"member"}"#

    static func sessionJSON(csrf: String = "csrf-1", recovery: Bool = false) -> String {
        #"{"account":\#(accountJSON),"csrfToken":"\#(csrf)","recovery":\#(recovery),"expiresAt":"2026-11-01T08:00:00Z"}"#
    }

    static let segmentJSON = #"""
    {"id":"22222222-2222-4222-8222-222222222222","kind":"work","placeId":null,"startedAt":"2026-10-16T06:07:00.123Z",
     "endedAt":null,"rawStartedAt":"2026-10-16T06:07:00Z","rawEndedAt":null,"source":"timer","note":null,"version":1,
     "voided":false,"needsReview":false,"revisions":0}
    """#

    static let closedSegmentJSON = #"""
    {"id":"33333333-3333-4333-8333-333333333333","kind":"school","startedAt":"2026-10-16T06:00:00Z","endedAt":"2026-10-16T09:30:00Z",
     "rawStartedAt":"2026-10-16T06:00:00Z","rawEndedAt":"2026-10-16T09:30:00Z","source":"manual","note":"Mathe","version":3,
     "voided":false,"needsReview":true,"revisions":2}
    """#

    static let dayJSON = #"""
    {"date":"2026-10-16","modelId":"44444444-4444-4444-8444-444444444444","mark":"none","skipFixedBreaks":false,
     "targetSeconds":27720,"rawWorkSeconds":24900,"breakDeductionSeconds":0,"startAdjustSeconds":420,"endAdjustSeconds":780,
     "evaluatedWorkSeconds":26100,"creditSeconds":0,"deltaSeconds":-1620,"evaluatedStart":"2026-10-16T06:00:00Z",
     "evaluatedEnd":null,"provisional":true,"segmentIds":["22222222-2222-4222-8222-222222222222"],
     "segments":[\#(segmentJSON)],"markCreditSeconds":null,"markSource":"none","targetOverrideSeconds":null,"note":null,
     "breakHints":[{"code":"break_missing_30"}],"someFutureField":42}
    """#

    static let accountBalanceJSON = #"{"asOf":"2026-10-16","accountStart":"2026-09-01","balanceSeconds":-1080,"openingSeconds":0,"adjustmentSeconds":0,"provisional":true}"#

    static let modulesJSON = #"""
    [{"key":"reports","serverEnabled":true,"accountEnabled":true,"effective":true,"lockedByOperator":false},
     {"key":"planning","serverEnabled":true,"accountEnabled":false,"effective":false,"lockedByOperator":false},
     {"key":"mcp","serverEnabled":false,"accountEnabled":true,"effective":false,"lockedByOperator":true},
     {"key":"fancy_future","serverEnabled":true,"accountEnabled":true,"effective":true,"lockedByOperator":false}]
    """#

    static let workModelJSON = #"""
    [{"id":"44444444-4444-4444-8444-444444444444","createdAt":"2026-09-01T00:00:00Z","validFrom":"2026-09-01","validTo":null,"timezone":"Europe/Berlin",
      "weeklyTargetSeconds":138600,"workdays":[1,2,3,4,5],"travelCountsAsWork":true,"roundingEnabled":true,"roundingMinutes":15,
      "schoolFullDayThresholdSeconds":10800,"schoolCreditSeconds":null,"dayBoundaryMinutes":0,"fixedBreaks":[{"start":"12:00","end":"12:30"}]}]
    """#

    static func client(_ transport: MockTransport) -> APIClient { APIClient(baseURL: baseURL, transport: transport) }
}
