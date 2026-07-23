import Testing
import Synchronization

import SlovoCore
import SlovoTestSupport

// Genuine silence (the key held over silence) must be intercepted at the FSM
// boundary BEFORE cleanup and injection: no OpenRouter round trip on empty input,
// no clipboard ⌘V cycle on empty text, in EITHER mode. Only the brief no-speech
// glyph surfaces. Driven through the REAL PipelineFactory.makeOrchestrator +
// Orchestrator over the seam FAKES, so the interception is proven end-to-end, not
// just in the pure transition.
@Suite("Empty-result interception")
struct OrchestratorEmptyResultTests {
    /// Clean mode (cleanup on, the default): silence must not call the cleaner. The
    /// cleaner is the network round trip and the model can invent text for empty
    /// input, so a call here is the hallucinated-insertion exposure.
    /// Stated sensitivity: the pre-fix pipeline routes `.transcriptReady("")` to
    /// `.clean("")` → the cleaner records one call and the injector inserts the
    /// (possibly invented) result → RED on both call-count assertions.
    @Test
    func silenceInCleanModeNeverCleansOrInjects() async {
        let reported = Mutex<[StatusMessage]>([])
        let cleaner = FakeCleaner(outcome: .success("HALLUCINATED"))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: FakeTranscriber(outcome: .success("")),
                cleaner: cleaner,
                injector: injector,
                statusReporter: { status in reported.withLock { $0.append(status) } }
            )
        )

        await Self.runSession(orchestrator)

        #expect(cleaner.calls.isEmpty, "silence must never reach the cleaner; got \(cleaner.calls.map(\.raw))")
        #expect(injector.calls.isEmpty, "silence must never reach the injector; got \(injector.calls)")
        #expect(reported.withLock { $0 }.contains(.noSpeechDetected),
                "silence must surface the .noSpeechDetected glyph; got \(reported.withLock { $0 })")
        #expect(await orchestrator.currentState() == .idle, "silence must return the session to idle")
    }

    /// Whitespace-only finish in clean mode takes the same no-speech path — bare
    /// whitespace is silence, not speech, so it must not be cleaned or injected.
    /// Stated sensitivity: an `isEmpty`-only guard (instead of whitespace-trimmed)
    /// lets "  \n" through to clean/inject → RED (the empty-string test would stay
    /// green, so this is the whitespace mutant-catcher at the orchestrator level).
    @Test
    func whitespaceOnlyInCleanModeNeverCleansOrInjects() async {
        let cleaner = FakeCleaner(outcome: .success("HALLUCINATED"))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: FakeTranscriber(outcome: .success("  \n")),
                cleaner: cleaner,
                injector: injector
            )
        )

        await Self.runSession(orchestrator)

        #expect(cleaner.calls.isEmpty, "whitespace-only silence must never reach the cleaner; got \(cleaner.calls.map(\.raw))")
        #expect(injector.calls.isEmpty, "whitespace-only silence must never reach the injector; got \(injector.calls)")
    }

    /// Raw mode (cleanup off): silence must not reach the injector. Raw mode skips
    /// the cleaner already, but the pre-fix pipeline still runs `.inject("")`, and
    /// ⌘V on an empty pasteboard can delete an active selection — the destructive
    /// exposure this guard removes.
    /// Stated sensitivity: the pre-fix pipeline forwards `.cleaned("")` → `.inject("")`
    /// → the injector records one empty insert → RED on the injector assertion.
    @Test
    func silenceInRawModeNeverInjects() async {
        let reported = Mutex<[StatusMessage]>([])
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: FakeTranscriber(outcome: .success("")),
                cleaner: FakeCleaner(outcome: .success("UNUSED")),
                injector: injector,
                statusReporter: { status in reported.withLock { $0.append(status) } }
            ),
            cleanupConfig: Self.cleanupConfig(runsCleaner: false)
        )

        await Self.runSession(orchestrator)

        #expect(injector.calls.isEmpty, "raw-mode silence must never reach the injector; got \(injector.calls)")
        #expect(reported.withLock { $0 }.contains(.noSpeechDetected),
                "raw-mode silence must surface the .noSpeechDetected glyph; got \(reported.withLock { $0 })")
        #expect(await orchestrator.currentState() == .idle, "raw-mode silence must return the session to idle")
    }

    private static func cleanupConfig(runsCleaner: Bool) -> CleanupConfig {
        var cleanupConfig = Config().cleanupConfig
        cleanupConfig.runsCleaner = runsCleaner
        return cleanupConfig
    }

    /// Builds Dependencies with the given seam fakes (mic authorized; a pinned
    /// PriorAudioState for mute/restore) — mirrors the sibling orchestrator suites.
    private static func deps(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        injector: FakeInjector,
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in }
    ) -> Dependencies {
        Dependencies(
            transcriber: transcriber, cleaner: cleaner, injector: injector,
            personalization: FakePersonalizationSource(terms: []),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            log: RedactionSafeLog(subsystem: "slovo", category: "empty-result-test"),
            statusReporter: statusReporter
        )
    }

    /// Runs a full Start→Stop session through the orchestrator.
    private static func runSession(_ orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
    }
}
