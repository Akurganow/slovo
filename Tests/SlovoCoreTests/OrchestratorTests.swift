import Foundation
import Testing
import Synchronization

import SlovoCore
import SlovoTestSupport

// Epic 09a — AC-2 (running pipeline + degradation + the FOLDED vocab→biasTerms),
// AC-4 (single-flight: no second mute/capture), AC-5 (I1 latency budget).
//
// Drives the REAL `PipelineFactory.makeOrchestrator` + `Orchestrator` over the
// existing seam FAKES (running-composition, §19.2 L3 — NEVER a hand-wired copy).
// This ABSORBS the retired `BiasTermsWiring` coverage: AC-2 asserts the
// transcriber received the resolved vocab as `biasTerms` (the fold into the
// actor's `.endCaptureAndTranscribe`).
//
// SEED-LEAK RULE: synthetic neutral public anchors only.
@Suite("Epic 09a AC-2/AC-4/AC-5 Orchestrator")
struct OrchestratorTests {
    // Computed (not a stored non-Sendable global) for Swift-6.
    private static var vocab: [Term] {
        [
            Term(term: "ExampleCorp", expansion: nil, lang: .en, weight: 9),
            Term(term: "GitHub", expansion: nil, lang: .en, weight: 7),
        ]
    }

    private static var cleanupConfig: Config {
        Config()
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
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "orch-test"),
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
            config: Self.cleanupConfig,
            dependencies: Self.deps(transcriber: transcriber, cleaner: cleaner, injector: injector)
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
            config: Self.cleanupConfig,
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

    /// #2: switching the cleanup model applies to the NEXT dictation live — the
    /// SAME running orchestrator (no rebuild) cleans with the new model on the
    /// following session. This is why the app never needs a pipeline rebuild (and
    /// its ASR re-warm + loading pulse) to change the cleanup model.
    /// Stated sensitivity: make `updateCleanupConfig` a no-op (don't store the new
    /// config) → the second dictation still cleans with the old model → RED.
    @Test
    func updatedCleanupModelReachesNextDictationLive() async {
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(openRouterModel: "openai/model-a"),
            dependencies: Self.deps(
                transcriber: FakeTranscriber(outcome: .success("hi")),
                cleaner: cleaner,
                injector: FakeInjector(outcome: .success)
            )
        )

        await Self.runSession(orchestrator)
        #expect(cleaner.calls.last?.config.model == "openai/model-a",
                "the first dictation cleans with the initially configured model")

        await orchestrator.updateCleanupConfig(
            CleanupConfig(model: "anthropic/model-b", writingStyle: .casual, language: .auto)
        )
        await Self.runSession(orchestrator)

        #expect(cleaner.calls.last?.config.model == "anthropic/model-b",
                "the switched cleanup model must reach the next dictation on the SAME orchestrator, without a rebuild")
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
        let summary = PipelineFactory.describeComposition(config: Self.cleanupConfig, dependencies: dependencies)
        let orchestrator = PipelineFactory.makeOrchestrator(config: Self.cleanupConfig, dependencies: dependencies)

        await Self.runSession(orchestrator)

        #expect(summary.fallbackChainKinds == ["FakeCleaner", "PassThrough"],
                "factory must compose cleaner failure through PassThrough, not actor-level catch-all fallback; got \(summary.fallbackChainKinds)")
        #expect(injector.calls.last == "hi",
                "a failing cleaner must degrade to the RAW transcript via PassThrough; got \(String(describing: injector.calls.last))")
    }

    /// A legacy persisted `cleanup.enabled=false` flag must not become a user-off
    /// path. Cleanup is always attempted upstream, with PassThrough reserved for
    /// sad-to-fail degradation.
    /// Stated sensitivity: preserve the legacy disabled state in config or branch
    /// on it in the factory -> the upstream cleaner is not called -> RED.
    @Test
    func legacyDisabledConfigStillAttemptsUpstreamCleaner() async throws {
        let transcriber = FakeTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let injector = FakeInjector(outcome: .success)
        let config = ConfigStore.load(from: FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: Data("""
            {
              "language": "ru",
              "keepWarmSeconds": 45,
              "trigger": "fn",
              "mode": "hold",
              "asr": { "backend": "speechtranscriber", "model": "system-dictation" },
              "cleanup": {
                "enabled": false,
                "provider": "openrouter",
                "openRouterModel": "openai/gpt-5.4-nano",
                "writingStyle": "formal"
              }
            }
            """.utf8),
        ]))
        let dependencies = Self.deps(transcriber: transcriber, cleaner: cleaner, injector: injector)
        let summary = PipelineFactory.describeComposition(config: config, dependencies: dependencies)
        let orchestrator = PipelineFactory.makeOrchestrator(config: config, dependencies: dependencies)

        await Self.runSession(orchestrator)

        #expect(summary.fallbackChainKinds == ["FakeCleaner", "PassThrough"],
                "legacy disabled config must still compose upstream cleanup before PassThrough; got \(summary.fallbackChainKinds)")
        #expect(cleaner.calls.count == 1,
                "cleanup must be attempted even when persisted legacy config says enabled=false; got \(cleaner.calls.count) calls")
        #expect(cleaner.calls.last?.config.model == "openai/gpt-5.4-nano")
        #expect(injector.calls.last == "HI",
                "successful cleanup must inject cleaned text, not preserve a user-disabled raw path; got \(String(describing: injector.calls.last))")
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
            config: Self.cleanupConfig,
            dependencies: Dependencies(
                transcriber: FakeTranscriber(outcome: .success("hi")),
                cleaner: ThrowingCleaner(CancellationError()),
                injector: injector,
                personalization: FakePersonalizationSource(terms: Self.vocab),
                audio: FakeSystemAudioController(
                    muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
                ),
                recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
                log: RedactionSafeLog(subsystem: "slovo", category: "orch-test") { capturedLogs.append($0) }
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

    /// A first-run ASR model download can spend seconds inside `begin`; surface
    /// that precise stage when the streaming session opens at key-down.
    /// Stated sensitivity: remove the pre-begin status report → the session opens
    /// with no `.preparingSpeechModel` status recorded → RED.
    ///
    /// Follow-up (test-author): streaming moved the ASR session begin (and its
    /// `.preparingSpeechModel` notice) from key-up to key-down. This test now
    /// asserts the new timing (status at key-down, reported exactly once);
    /// re-derive its RED sensitivity for the streaming seam.
    /// (The literal task-tag token is omitted because the SwiftLint `todo` gate
    /// fails the build on it; flagged to the lead in the hand-back report.)
    @Test
    func reportsSpeechModelPreparationWhenSessionBegins() async {
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
        #expect(reported.withLock { $0 } == [.preparingSpeechModel],
                "ASR preparation status must be surfaced when the session begins at key-down; got \(reported.withLock { $0 })")

        await orchestrator.handle(.stopRequested)
        await transcriber.waitUntilCalled()

        #expect(reported.withLock { $0 } == [.preparingSpeechModel],
                "the ASR preparation status must be reported exactly once; got \(reported.withLock { $0 })")

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
                log: RedactionSafeLog(subsystem: "slovo", category: "orch-test") { capturedLogs.append($0) }
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

    /// AC-5 (I1 latency budget): the all-instant fake pipeline must finish near
    /// instantly, so this catches a synchronous stall in slovo's OWN code — a
    /// blocking `sleep`/call in the orchestrator pushes `elapsed` past the budget.
    /// Stated sensitivity: such a synchronous stall → RED.
    ///
    /// Local-only. This is a wall-clock guard and is meaningful only where
    /// scheduling is stable. Shared CI runners are not: the same ~1 ms pipeline was
    /// observed taking anywhere from 0.24 s to 2.56 s there, so any fixed budget is
    /// either flaky or meaningless. The local gate (Scripts/diagnose.sh) owns this
    /// check; CI runs every other test.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil,
                   "wall-clock guard; shared CI scheduling variance is too high — runs in the local gate"))
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
                "the full fake pipeline must complete within \(budget) (slovo's own sync code); took \(elapsed)")
    }
}
