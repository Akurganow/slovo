import Foundation
import Testing
import Synchronization

import LoquiCore
import LoquiTestSupport

// Epic 09a — AC-2 (running pipeline + degradation + the FOLDED vocab→biasTerms),
// AC-4 (single-flight: no second mute/capture), AC-5 (I1 latency budget).
//
// Drives the REAL `PipelineFactory.makeOrchestrator` + `Orchestrator` over the
// existing seam FAKES (running-composition, §19.2 L3 — NEVER a hand-wired copy).
// This ABSORBS the retired `BiasTermsWiring` coverage: AC-2 asserts the
// transcriber received the resolved vocab as `biasTerms` (the fold into the
// actor's `.endCaptureAndTranscribe`).
//
// SEED-LEAK RULE (P1): synthetic neutral PUBLIC anchors only (ExampleCorp, GitHub).
@Suite("Epic 09a AC-2/AC-4/AC-5 Orchestrator")
struct OrchestratorTests {
    // Computed (not a stored non-Sendable global) for Swift-6.
    private static var vocab: [Term] {
        [
            Term(term: "ExampleCorp", expansion: nil, lang: .en, weight: 9),
            Term(term: "GitHub", expansion: nil, lang: .en, weight: 7),
        ]
    }

    /// Builds Dependencies with the given seam fakes (mic authorized; a pinned
    /// PriorAudioState for mute/restore).
    private static func deps(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        injector: FakeInjector,
        vocabulary: [Term] = vocab,
        audio: FakeSystemAudioController = FakeSystemAudioController(
            muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
        ),
        recorder: FakeAudioRecorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "loqui", category: "orch-test"),
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in }
    ) -> Dependencies {
        Dependencies(
            transcriber: transcriber, cleaner: cleaner, injector: injector,
            personalization: FakePersonalizationSource(terms: vocabulary),
            audio: audio, recorder: recorder, log: log, statusReporter: statusReporter
        )
    }

    /// Runs a full Start→Stop session through the orchestrator.
    private static func runSession(_ orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)   // mute + beginCapture
        await orchestrator.handle(.stopRequested)    // endCaptureAndTranscribe + restore → transcriptReady → clean → inject → injected
        await orchestrator.awaitPipelineDrain()
    }

    /// AC-2 (happy path + folded biasTerms): the cleaned text is injected AND the
    /// transcriber and cleaner received the resolved vocabulary.
    /// Stated sensitivity: drop the vocab→biasTerms resolve (pass `[]`) → recorded
    /// biasTerms/context empty → RED.
    @Test
    func cleanedTextIsInjectedAndVocabReachesTranscriberAndCleaner() async {
        let transcriber = FakeTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(), dependencies: Self.deps(transcriber: transcriber, cleaner: cleaner, injector: injector)
        )

        await Self.runSession(orchestrator)

        #expect(injector.calls.last == "HI", "the cleaned text must be injected; got \(String(describing: injector.calls.last))")
        let biasTerms = transcriber.calls.last?.biasTerms.map(\.term) ?? []
        #expect(biasTerms.contains("ExampleCorp") && biasTerms.contains("GitHub"),
                "the resolved vocabulary must reach the transcriber's biasTerms (folded wiring); got \(biasTerms)")
        let cleanerTerms = cleaner.calls.last?.context.vocabulary.map(\.term) ?? []
        #expect(cleanerTerms.contains("ExampleCorp") && cleanerTerms.contains("GitHub"),
                "the resolved vocabulary must reach the cleaner context for spelling preservation; got \(cleanerTerms)")
    }

    /// The production composition gives one vocabulary budget to both ASR bias and
    /// cleanup context.
    /// Stated sensitivity: hard-code `50` inside the actor or apply a different
    /// limit to cleaner context -> both recorded vocab arrays contain too many terms
    /// or diverge -> RED.
    @Test
    func vocabularyLimitFeedsBothTranscriberBiasAndCleanerContext() async {
        let vocabulary = [
            Term(term: "one", expansion: nil, lang: .en, weight: 10),
            Term(term: "two", expansion: nil, lang: .en, weight: 9),
            Term(term: "three", expansion: nil, lang: .en, weight: 8),
        ]
        let transcriber = FakeTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: transcriber,
                cleaner: cleaner,
                injector: injector,
                vocabulary: vocabulary
            ),
            vocabularyLimit: 2
        )

        await Self.runSession(orchestrator)

        #expect(transcriber.calls.last?.biasTerms.map(\.term) == ["one", "two"],
                "ASR biasTerms must use the configured vocabulary limit")
        #expect(cleaner.calls.last?.context.vocabulary.map(\.term) == ["one", "two"],
                "cleaner context must use the same configured vocabulary limit")
    }

    /// AC-2 (degradation): a failing cleaner ⇒ the RAW transcript is injected via
    /// PassThrough (never lose the words).
    /// Stated sensitivity: break the degradation (don't advance to PassThrough on
    /// `.offline`) → the raw transcript is NOT injected → RED.
    @Test
    func failingCleanerDegradesToRawTranscript() async {
        let transcriber = FakeTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .failure(.offline))
        let injector = FakeInjector(outcome: .success)
        let dependencies = Self.deps(transcriber: transcriber, cleaner: cleaner, injector: injector)
        let summary = PipelineFactory.describeComposition(config: Config(), dependencies: dependencies)
        let orchestrator = PipelineFactory.makeOrchestrator(config: Config(), dependencies: dependencies)

        await Self.runSession(orchestrator)

        #expect(summary.fallbackChainKinds == ["FakeCleaner", "PassThrough"],
                "factory must compose cleaner failure through PassThrough, not actor-level catch-all fallback; got \(summary.fallbackChainKinds)")
        #expect(injector.calls.last == "hi",
                "a failing cleaner must degrade to the RAW transcript via PassThrough; got \(String(describing: injector.calls.last))")
    }

    /// Config `cleanup.enabled=false` must avoid the upstream cleaner entirely:
    /// no cloud cleanup attempt, raw transcript inserted through PassThrough.
    /// Stated sensitivity: parse `cleanupEnabled` but ignore it in the factory →
    /// the upstream cleaner records a call and/or cleaned text is injected → RED.
    @Test
    func cleanupDisabledBypassesUpstreamCleanerAndInjectsRawTranscript() async {
        let transcriber = FakeTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let injector = FakeInjector(outcome: .success)
        let config = Config(cleanupEnabled: false)
        let dependencies = Self.deps(transcriber: transcriber, cleaner: cleaner, injector: injector)
        let summary = PipelineFactory.describeComposition(config: config, dependencies: dependencies)
        let orchestrator = PipelineFactory.makeOrchestrator(config: config, dependencies: dependencies)

        await Self.runSession(orchestrator)

        #expect(summary.fallbackChainKinds == ["PassThrough"],
                "cleanup disabled must compose a PassThrough-only cleaner chain; got \(summary.fallbackChainKinds)")
        #expect(cleaner.calls.isEmpty,
                "cleanup disabled must not call the upstream cleaner; got \(cleaner.calls.count) calls")
        #expect(injector.calls.last == "hi",
                "cleanup disabled must inject the raw transcript through PassThrough; got \(String(describing: injector.calls.last))")
    }

    /// A non-CleanupError from the cleaner is not a degradation case. It must be
    /// contained as a failure, never silently inserted as raw text.
    /// Stated sensitivity: actor-level bare `catch { transcript }` fallback →
    /// raw transcript is injected despite a non-CleanupError → RED.
    @Test
    func unexpectedCleanerFailureDoesNotInjectRawTranscript() async {
        var capturedLogs: [String] = []
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Dependencies(
                transcriber: FakeTranscriber(outcome: .success("hi")),
                cleaner: ThrowingCleaner(CancellationError()),
                injector: injector,
                personalization: FakePersonalizationSource(terms: Self.vocab),
                audio: FakeSystemAudioController(
                    muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
                ),
                recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
                log: RedactionSafeLog(subsystem: "loqui", category: "orch-test") { capturedLogs.append($0) }
            )
        )

        await Self.runSession(orchestrator)

        #expect(injector.calls.isEmpty,
                "a non-CleanupError must not be degraded to raw transcript insertion; got \(injector.calls)")
        #expect(capturedLogs.contains("status.cleanupFailed"),
                "escaped cleanup failures must route through FSM notify(.cleanupFailed); got \(capturedLogs)")
        #expect(capturedLogs.contains("fsm.stageFailed"),
                "escaped cleanup failures must route through FSM log(.stageFailed); got \(capturedLogs)")
        #expect(await orchestrator.currentState() == .idle,
                "a contained cleaner failure must return the session to idle")
    }

    /// A transcription failure yields no text, so nothing is injected and the
    /// FSM contains the failure back to idle.
    /// Stated sensitivity: swallowing transcription failure in `transcribeAndContinue`
    /// without feeding `.failed` leaves the actor stuck in `.processing` → RED.
    @Test
    func transcriptionFailureDoesNotInjectAndReturnsToIdle() async {
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: FakeTranscriber(outcome: .failure(.backendUnavailable)),
                cleaner: FakeCleaner(outcome: .success("HI")),
                injector: injector
            )
        )

        await Self.runSession(orchestrator)

        #expect(injector.calls.isEmpty,
                "a transcription failure must not inject text; got \(injector.calls)")
        #expect(await orchestrator.currentState() == .idle,
                "a contained transcription failure must return the session to idle")
    }

    /// A first-run ASR model download can spend seconds inside `transcribe`;
    /// surface that precise stage before entering the transcriber.
    /// Stated sensitivity: remove the pre-transcribe status report → the blocked
    /// transcriber is entered with no `.preparingSpeechModel` status recorded.
    @Test
    func reportsSpeechModelPreparationBeforeTranscriberCall() async {
        let reported = Mutex<[StatusMessage]>([])
        let transcriber = BlockingTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: transcriber,
                cleaner: cleaner,
                injector: injector,
                statusReporter: { status in reported.withLock { $0.append(status) } }
            )
        )

        await orchestrator.handle(.startRequested)
        #expect(reported.withLock { $0 }.isEmpty,
                "ASR preparation status must not fire while recording before Stop")
        await orchestrator.handle(.stopRequested)
        await transcriber.waitUntilCalled()

        let statuses = reported.withLock { $0 }
        #expect(statuses == [.preparingSpeechModel],
                "the user-visible status must name ASR preparation before transcribe blocks; got \(statuses)")

        await transcriber.release()
        await orchestrator.awaitPipelineDrain()
    }

    /// AC-4 (single-flight): a second Start while processing is IGNORED — no
    /// second mute, no second capture.
    /// Stated sensitivity: allow re-entry → a second mute/capture appears → RED.
    /// A re-entering actor would make muteCount/engineStartCount ≥ 2.
    @Test
    func secondStartWhileProcessingDoesNotReMuteOrReCapture() async {
        var capturedLogs: [String] = []
        let transcriber = BlockingTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let injector = FakeInjector(outcome: .success)
        let audio = FakeSystemAudioController(
            muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
        )
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Dependencies(
                transcriber: transcriber,
                cleaner: cleaner,
                injector: injector,
                personalization: FakePersonalizationSource(terms: Self.vocab),
                audio: audio,
                recorder: recorder,
                log: RedactionSafeLog(subsystem: "loqui", category: "orch-test") { capturedLogs.append($0) }
            )
        )

        // Drive into processing: Start (mute+capture) then Stop (→ processing).
        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested)
        await transcriber.waitUntilCalled()
        let muteAfterFirst = audio.muteCount
        let captureAfterFirst = recorder.engineStartCount

        // A second Start while processing must be single-flight-ignored.
        await orchestrator.handle(.startRequested)

        #expect(await orchestrator.currentState() == .processing,
                "single-flight: state must stay processing while the pipeline is in flight")
        #expect(audio.muteCount == muteAfterFirst,
                "single-flight: a second Start must NOT re-mute; muteCount went \(muteAfterFirst)→\(audio.muteCount)")
        #expect(recorder.engineStartCount == captureAfterFirst,
                "single-flight: a second Start must NOT re-capture; engineStartCount went \(captureAfterFirst)→\(recorder.engineStartCount)")
        #expect(capturedLogs.contains("fsm.singleFlightIgnored"),
                "single-flight must emit a stable payload-free log event; got \(capturedLogs)")

        await transcriber.release()
        await orchestrator.awaitPipelineDrain()
    }

    /// AC-5 (I1 latency budget): the full fake pipeline completes well within the
    /// budget — the fakes are instant, so this catches a synchronous stall in
    /// loqui's OWN code (not network).
    /// Stated sensitivity: a synchronous `sleep`/blocking call in the orchestrator
    /// → elapsed exceeds the budget → RED.
    @Test
    func fullPipelineHoldsLatencyBudget() async {
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: FakeTranscriber(outcome: .success("hi")),
                cleaner: FakeCleaner(outcome: .success("HI")),
                injector: FakeInjector(outcome: .success)
            )
        )

        let budget: Duration = .milliseconds(200)
        let start = ContinuousClock.now
        await Self.runSession(orchestrator)
        let elapsed = ContinuousClock.now - start

        #expect(elapsed < budget,
                "the full fake pipeline must complete within \(budget) (loqui's own sync code); took \(elapsed)")
    }
}
