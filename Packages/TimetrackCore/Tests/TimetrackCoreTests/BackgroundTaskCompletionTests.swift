import Foundation
import Testing
@testable import TimetrackCore

private final class CompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Bool] = []
    var values: [Bool] { lock.withLock { results } }
    func add(_ value: Bool) { lock.withLock { results.append(value) } }
}

@Suite struct BackgroundTaskCompletionTests {
    @Test func completesExactlyOnce() {
        let recorder = CompletionRecorder()
        let completion = BackgroundTaskCompletion(complete: { recorder.add($0) })
        #expect(completion.finish(success: true))
        #expect(!completion.finish(success: false))
        #expect(recorder.values == [true])
    }

    @Test func expirationCancelsAttachedWorkAndRunsExpiryAction() async {
        let recorder = CompletionRecorder()
        let expired = CompletionRecorder()
        let completion = BackgroundTaskCompletion(complete: { recorder.add($0) }, onExpire: { expired.add(true) })
        let work = Task<Void, Never> {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            completion.finish(success: !Task.isCancelled)
        }
        completion.attach(work)
        completion.expire()
        await work.value
        #expect(recorder.values == [false])
        #expect(expired.values == [true])
    }

    @Test func workAttachedAfterExpirationIsCancelledImmediately() {
        let completion = BackgroundTaskCompletion(complete: { _ in })
        completion.expire()
        let probe = Task<Void, Never> { try? await Task.sleep(for: .seconds(5)) }
        completion.attach(probe)
        #expect(probe.isCancelled)
    }

    @Test func expirationCompletesImmediatelyEvenIfTheWorkIgnoresCancellation() async {
        let recorder = CompletionRecorder()
        let completion = BackgroundTaskCompletion(complete: { recorder.add($0) })
        let gate = AsyncStream<Void>.makeStream()
        let work = Task<Void, Never> {
            for await _ in gate.stream {} // ignores cancellation until released
            completion.finish(success: true) // late result must be ignored
        }
        completion.attach(work)
        completion.expire()
        #expect(recorder.values == [false]) // before the work returned
        gate.continuation.finish()
        await work.value
        #expect(recorder.values == [false]) // exactly once
        #expect(completion.finish(success: true) == false)
    }
}
