import Foundation
import Testing
import Synchronization

@testable import SlovoCore
import SlovoTestSupport

// Running pipeline + degradation + the FOLDED vocab→biasTerms, single-flight (no
// second mute/capture). Hot-path latency is guarded separately, by source
// invariant, in `DictationHotPathLatencySourceGuardTests`.
//
// Drives the REAL `PipelineFactory.makeOrchestrator` + `Orchestrator` over the
// existing seam FAKES (running-composition — NEVER a hand-wired copy).
// The suite asserts the transcriber received the resolved vocab as `biasTerms`.
// The fold sits in the actor's `.beginCapture` path.
//
// SEED-LEAK RULE: synthetic neutral public anchors only.
@Suite("Orchestrator pipeline")
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
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "orch-test"),
        settings: FakeSettingsSource = FakeSettingsSource(),
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in }
    ) -> Dependencies {
        Dependencies(
            transcriber: transcriber, cleaner: cleaner, injector: injector,
            personalization: FakePersonalizationSource(terms: vocabulary),
            audio: audio, recorder: recorder, cueController: FakeDictationCueController(),
            log: log, settings: settings.provider, statusReporter: statusReporter
        )
    }

    /// Runs a full Start→Stop session through the orchestrator.
    private static func runSession(_ orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)   // beginCapture; the mute follows the Start cue
        await orchestrator.handle(.stopRequested(.plain))    // finalize transcript + restore → clean → inject → injected
        await orchestrator.awaitPipelineDrain()
    }

    /// One uncapped read feeds both consumers: the orchestrator hands the WHOLE
    /// vocabulary to ASR bias and to cleanup context alike, and each budgets it
    /// downstream (bias switch on, so both consumers are observable). The fixture is
    /// 65 terms so it outgrows every plausible cap; the earlier 3-term version let a
    /// reintroduced `prefix(50)` pass unnoticed.
    /// Stated sensitivity: reintroduce `prefix(50)` inside the actor → both arrays hold
    /// 50 terms instead of 65 → RED; `prefix(25)` and `prefix(10)` redden identically.
    /// Cap only one consumer → that array alone shortens and the two diverge → RED.
    @Test
    func fullVocabularyFeedsBothTranscriberBiasAndCleanerContext() async {
        // Weights descend with the index, so the expected order is the seeded order.
        let vocabulary = (1...65).map { index in
            Term(term: String(format: "term-%03d", index), expansion: nil, lang: .en, weight: 100 - index)
        }
        let expected = vocabulary.map(\.term)
        let transcriber = FakeTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let injector = FakeInjector(outcome: .success)
        let biased = AppState(config: Config(usesVocabularyBias: true), isOpenRouterKeyPresent: true).dictationSettings
        let orchestrator = PipelineFactory.makeOrchestrator(
            dependencies: Self.deps(
                transcriber: transcriber,
                cleaner: cleaner,
                injector: injector,
                vocabulary: vocabulary,
                settings: FakeSettingsSource(biased)
            )
        )

        await Self.runSession(orchestrator)

        #expect(transcriber.calls.last?.biasTerms.map(\.term) == expected,
                "ASR biasTerms must carry all 65 terms, uncapped; got \(transcriber.calls.last?.biasTerms.count ?? 0)")
        #expect(cleaner.calls.last?.context.vocabulary.map(\.term) == expected,
                "cleaner context must carry the same 65 terms; got \(cleaner.calls.last?.context.vocabulary.count ?? 0)")
    }

    /// A failing cleaner ⇒ the RAW transcript is injected (never lose the words).
    /// Stated sensitivity: make `FallbackCleaner` return an empty string instead of
    /// the spoken text for a `CleanupError` → the raw transcript is NOT injected → RED.
    /// A rethrow stays green: the orchestrator's own catch inserts the spoken text too.
    @Test
    func failingCleanerDegradesToRawTranscript() async {
        let transcriber = FakeTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .failure(.transport))
        let injector = FakeInjector(outcome: .success)
        let dependencies = Self.deps(transcriber: transcriber, cleaner: cleaner, injector: injector)
        let orchestrator = PipelineFactory.makeOrchestrator(dependencies: dependencies)

        await Self.runSession(orchestrator)

        #expect(injector.calls.last == "hi",
                "a failing cleaner must degrade to the RAW transcript through FallbackCleaner; got \(String(describing: injector.calls.last))")
    }

    /// A persisted `cleanup.enabled=false` is a first-class user-off mode, not a
    /// degradation: loaded end-to-end from the stored blob, the dictation reads
    /// `runsCleaner` false, skips the cleaner and injects the RAW transcript. A
    /// settings value with `runsCleaner` true then cleans again, so the skip is
    /// decided per dictation and the composition still holds the cleaner. This is
    /// the only test covering the full path (stored blob → `ConfigStore.load` →
    /// `AppState.dictationSettings` → the dictation's read); the override-based
    /// `OrchestratorCleanupToggleTests` bypass that mapping.
    /// Stated sensitivity: restore the discard-decode (`cleanup.enabled` read as
    /// its default), or drop both `runsCleaner` derivations (`Config.cleanupConfig`
    /// and the availability override in `AppState.effectiveCleanupConfig`), or
    /// remove the `sessionSettings.cleanup.runsCleaner` guard -> `runsCleaner` reads
    /// `true`, the cleaner is called, and "HI" is injected -> RED. Build the
    /// factory's cleaner without `dependencies.cleaner` -> the second dictation
    /// injects "hi" -> RED.
    @Test
    func persistedDisabledConfigSkipsCleanerEndToEnd() async throws {
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
                "openRouterModel": "openai/gpt-6-luna",
                "writingStyle": "formal"
              }
            }
            """.utf8),
        ]))
        let settings = FakeSettingsSource(AppState(config: config, isOpenRouterKeyPresent: true).dictationSettings)
        let dependencies = Self.deps(transcriber: transcriber, cleaner: cleaner, injector: injector, settings: settings)
        let orchestrator = PipelineFactory.makeOrchestrator(dependencies: dependencies)

        await Self.runSession(orchestrator)

        #expect(cleaner.calls.isEmpty,
                "a persisted enabled=false must skip the cleaner, not attempt it; got \(cleaner.calls.count) calls")
        #expect(injector.calls.last == "hi",
                "cleanup-off injects the raw transcript, not a cleaned result; got \(String(describing: injector.calls.last))")

        var turnedOn = AppState(config: config, isOpenRouterKeyPresent: true).dictationSettings
        turnedOn.cleanup.runsCleaner = true
        settings.replace(with: turnedOn)
        await Self.runSession(orchestrator)

        #expect(injector.calls.last == "HI",
                "turning cleanup back on must reach the cleaner held by the composition; got \(String(describing: injector.calls.last))")
    }

    /// An unexpected cleaner error (not a `CleanupError`) escapes `FallbackCleaner`
    /// and keeps the user's words: the spoken text is inserted, reported once as
    /// `.cleanupUnavailableInsertedAsSpoken` with the Error cue after End, and the
    /// session returns to idle. The owner decided this, so an unexpected error ends
    /// like an expected cleanup failure.
    /// Stated sensitivity: drop `handle(.cleaned(transcript))` in the catch → nothing
    /// injected → RED; report through `deps.statusReporter` instead of
    /// `deps.reportStatus` → no Error cue → RED.
    @Test
    func unexpectedCleanerFailureInsertsTheSpokenText() async {
        let reported = Mutex<[StatusMessage]>([])
        let injector = FakeInjector(outcome: .success)
        let cues = FakeDictationCueController()
        let orchestrator = PipelineFactory.makeOrchestrator(
            dependencies: Dependencies(
                transcriber: FakeTranscriber(outcome: .success("hi")),
                cleaner: ThrowingCleaner(CancellationError()),
                injector: injector,
                personalization: FakePersonalizationSource(terms: Self.vocab),
                audio: FakeSystemAudioController(
                    muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
                ),
                recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
                cueController: cues,
                log: RedactionSafeLog(subsystem: "slovo", category: "orch-test"),
                settings: FakeSettingsSource().provider,
                statusReporter: { status in reported.withLock { $0.append(status) } }
            )
        )

        await Self.runSession(orchestrator)

        #expect(injector.calls == ["hi"],
                "an unexpected cleaner error must insert the spoken text; got \(injector.calls)")
        let statuses = reported.withLock { $0 }
        #expect(statuses.filter { $0 == .cleanupUnavailableInsertedAsSpoken }.count == 1,
                "the spoken-text status must be reported exactly once; got \(statuses)")
        #expect(cues.events.filter { $0 == .enqueue(.end) || $0 == .enqueue(.error) } == [.enqueue(.end), .enqueue(.error)],
                "the Error cue must follow End; got \(cues.events)")
        #expect(await orchestrator.currentState() == .idle,
                "the session must return to idle after the spoken text is inserted")
    }

    /// A transcription failure yields no text, so nothing is injected and the
    /// FSM contains the failure back to idle.
    /// Stated sensitivity: swallowing transcription failure in `finishAndContinue`
    /// without feeding `.failed` leaves the actor stuck in `.processing` → RED.
    @Test
    func transcriptionFailureDoesNotInjectAndReturnsToIdle() async {
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
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

    /// Single-flight: a second Start while processing is IGNORED — no second
    /// capture. The no-second-mute half is pinned in `DictationFsmMuteTests`.
    /// Stated sensitivity: allow re-entry → the recorder starts a second capture,
    /// or the state leaves processing → RED.
    @Test
    func secondStartWhileProcessingDoesNotReCapture() async {
        let transcriber = BlockingTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let injector = FakeInjector(outcome: .success)
        let audio = FakeSystemAudioController(
            muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
        )
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        let orchestrator = PipelineFactory.makeOrchestrator(
            dependencies: Dependencies(
                transcriber: transcriber,
                cleaner: cleaner,
                injector: injector,
                personalization: FakePersonalizationSource(terms: Self.vocab),
                audio: audio,
                recorder: recorder,
                cueController: FakeDictationCueController(),
                log: RedactionSafeLog(subsystem: "slovo", category: "orch-test"),
                settings: FakeSettingsSource().provider
            )
        )

        // Drive into processing: Start (capture) then Stop (→ processing).
        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.plain))
        await transcriber.waitUntilCalled()
        let captureAfterFirst = recorder.engineStartCount

        // A second Start while processing must be single-flight-ignored.
        await orchestrator.handle(.startRequested)

        #expect(await orchestrator.currentState() == .processing,
                "single-flight: state must stay processing while the pipeline is in flight")
        #expect(recorder.engineStartCount == captureAfterFirst,
                "single-flight: a second Start must NOT re-capture; engineStartCount went \(captureAfterFirst)→\(recorder.engineStartCount)")

        await transcriber.release()
        await orchestrator.awaitPipelineDrain()
    }
}
