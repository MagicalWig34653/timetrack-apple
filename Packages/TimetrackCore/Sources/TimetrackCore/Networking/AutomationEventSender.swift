import Foundation

/// Posts automation events. The production implementation authenticates with the device token, tests inject a fake.
public protocol AutomationEventSending: Sendable {
    func send(_ event: AutomationEventPayload) async throws -> AutomationEventResult
}

/// `POST /api/v1/automation/events` with `Authorization: Bearer <device token>` (no cookie, no CSRF).
/// Uses its own transport so the session cookie of `APIClient` is never attached.
public struct DeviceTokenEventSender: AutomationEventSending {
    private let baseURL: URL
    private let token: String
    private let transport: HTTPTransport

    public init(baseURL: URL, token: String, transport: HTTPTransport) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    public func send(_ event: AutomationEventPayload) async throws -> AutomationEventResult {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw TimetrackError.invalidServerURL }
        let prefix = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = prefix + APIClient.basePath + "/automation/events"
        guard let url = components.url else { throw TimetrackError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONCoding.makeEncoder().encode(event)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw TimetrackError.cancelled
        } catch let error as URLError {
            if error.code == .cancelled { throw TimetrackError.cancelled }
            throw TimetrackError.network(error.code)
        }
        guard (200..<300).contains(response.statusCode) else {
            var code = "http_\(response.statusCode)"
            var message = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            struct Envelope: Decodable { struct Body: Decodable { let code: String?; let message: String? }; let error: Body? }
            if let body = try? JSONCoding.makeDecoder().decode(Envelope.self, from: data).error {
                if let value = body.code, !value.isEmpty { code = value }
                if let value = body.message, !value.isEmpty { message = value }
            }
            throw TimetrackError.api(status: response.statusCode, code: code, message: message)
        }
        do { return try JSONCoding.makeDecoder().decode(AutomationEventResult.self, from: data) } catch { throw TimetrackError.decoding("AutomationEventResult") }
    }
}
