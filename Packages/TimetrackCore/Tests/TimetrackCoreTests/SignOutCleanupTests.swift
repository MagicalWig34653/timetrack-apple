import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// X4 on the Mac: the sign-out cleanup (`MacAutomationRuntime.signedOut()`) hangs on `AppModel.onPhaseChange`, because a Mac app in
/// "nur Menüleiste" mode may have no window whose `onChange` could see the sign-out.
@MainActor
@Suite struct SignOutCleanupTests {
    final class Counter { var runs = 0 }

    func signedInModel() async -> AppModel {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        let model = AppModel(auth: AuthService(secrets: InMemorySecretStore(), transport: transport))
        await model.signInWithSessionCookie(serverInput: "localhost:18090", cookie: "a")
        return model
    }

    @Test func signingOutRunsTheCleanupOnce() async {
        let model = await signedInModel()
        #expect(model.phase == .signedIn)
        let counter = Counter()
        let cleanup = SignOutCleanup { counter.runs += 1 }
        var changes: [AppModel.Phase] = []
        model.onPhaseChange = { old, new in changes.append(new); cleanup.phaseChanged(from: old, to: new) }

        await model.signOut()
        await cleanup.wait()

        #expect(changes == [.signedOut])
        #expect(counter.runs == 1)
    }

    @Test func otherTransitionsDoNotRunTheCleanup() async {
        let counter = Counter()
        let cleanup = SignOutCleanup { counter.runs += 1 }
        cleanup.phaseChanged(from: .restoring, to: .signedOut) // launch without credentials
        cleanup.phaseChanged(from: .offline, to: .signedIn)
        cleanup.phaseChanged(from: .signedOut, to: .signedIn)
        await cleanup.wait()
        #expect(counter.runs == 0)
    }

    @Test func theNextAccountWaitsForAPendingCleanup() async {
        var log: [String] = []
        let cleanup = SignOutCleanup {
            try? await Task.sleep(for: .milliseconds(50))
            log.append("cleanup")
        }
        cleanup.phaseChanged(from: .signedIn, to: .signedOut)
        await cleanup.wait()
        log.append("next account")
        #expect(log == ["cleanup", "next account"])
    }
}
