import Foundation
import Testing
@testable import SlovoCore
import SlovoTestSupport

@Suite("FallbackCleaner failure observer (spec rev 3 §4 K8)")
struct FallbackCleanerObserverTests {
    private static var config: CleanupConfig { CleanupConfig(writingStyle: .formal) }
    private static var context: PersonalizationContext { PersonalizationContext(vocabulary: []) }

    /// Lock-guarded recorder, same idiom as StubScenario: the observer closure is
    /// invoked synchronously inside `clean(...)`, the test reads after awaiting it.
    private final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [CleanupError] = []
        func append(_ error: CleanupError) {
            lock.lock(); defer { lock.unlock() }
            _values.append(error)
        }
        var values: [CleanupError] {
            lock.lock(); defer { lock.unlock() }
            return _values
        }
    }

    private struct Failing: Cleaner {
        let error: CleanupError
        func clean(_ raw: String, config: CleanupConfig, context: PersonalizationContext) async throws -> String { throw error }
    }
    private struct Succeeding: Cleaner {
        func clean(_ raw: String, config: CleanupConfig, context: PersonalizationContext) async throws -> String { raw }
    }

    @Test
    func observerReceivesTheCleanupErrorOnFailure() async throws {
        let box = ErrorBox()
        let cleaner = FallbackCleaner(
            cleaner: Failing(error: .modelUnavailable),
            statusReporter: { _ in },
            onCleanupFailure: { box.append($0) }
        )
        _ = try await cleaner.clean("raw", config: Self.config, context: Self.context)
        let seen = box.values
        #expect(seen.count == 1)
        guard case .modelUnavailable = seen.first else {
            Issue.record("observer received the wrong error case")
            return
        }
    }

    @Test
    func observerSilentOnSuccess() async throws {
        let box = ErrorBox()
        let cleaner = FallbackCleaner(
            cleaner: Succeeding(),
            statusReporter: { _ in },
            onCleanupFailure: { box.append($0) }
        )
        _ = try await cleaner.clean("raw", config: Self.config, context: Self.context)
        #expect(box.values.isEmpty)
    }

    /// K8 chain, link (a): the composition root threads the observer into the
    /// `FallbackCleaner` it builds around the configured cleaner. A dictation whose
    /// cleaner fails must reach the observer, and still insert the raw transcript.
    /// Stated sensitivity: drop `onCleanupFailure:` from the `FallbackCleaner` that
    /// `PipelineFactory.makeOrchestrator` builds → the observer sees nothing → RED.
    @Test
    func factoryThreadsTheObserverIntoTheFallback() async {
        let box = ErrorBox()
        let injector = FakeInjector(outcome: .success)
        var dependencies = Dependencies(
            transcriber: FakeTranscriber(outcome: .success("raw words")),
            cleaner: FakeCleaner(outcome: .failure(.modelUnavailable)),
            injector: injector,
            personalization: FakePersonalizationSource(terms: []),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            cueController: FakeDictationCueController(),
            log: RedactionSafeLog(subsystem: "slovo", category: "observer-test"),
            settings: FakeSettingsSource().provider
        )
        dependencies.onCleanupFailure = { box.append($0) }
        let orchestrator = PipelineFactory.makeOrchestrator(dependencies: dependencies)

        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(injector.calls.last == "raw words", "the failed cleanup must degrade to the raw transcript")
        guard case .modelUnavailable = box.values.first else {
            Issue.record("the observer must receive the cleaner's failure; saw \(box.values)")
            return
        }
        #expect(box.values.count == 1)
    }
}
