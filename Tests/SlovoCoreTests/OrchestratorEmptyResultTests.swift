import Testing
import Synchronization

import SlovoCore
import SlovoTestSupport

// Silence is intercepted before cleanup and injection in EITHER mode — no OpenRouter
// round trip, no ⌘V cycle. Driven through the real PipelineFactory + Orchestrator over
// the seam fakes, so the interception is proven end-to-end, not just in the transition.
@Suite("Empty-result interception")
struct OrchestratorEmptyResultTests {
    /// Clean mode: the cleaner can invent text for empty input, so a call here is the
    /// hallucinated-insertion exposure — that is what this test exists to prove; the cue
    /// sequence is secondary.
    /// Sensitivity: route `""` to `.clean` → the cleaner is called and the invented text
    /// inserted → RED. Separately, make End conditional on a non-empty transcript → RED
    /// on the cues, since End marks the end of the RECORDING.
    @Test
    func silenceInCleanModeNeverCleansOrInjects() async {
        let reported = Mutex<[StatusMessage]>([])
        let cleaner = FakeCleaner(outcome: .success("HALLUCINATED"))
        let injector = FakeInjector(outcome: .success)
        let cues = FakeDictationCueController()
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: FakeTranscriber(outcome: .success("")),
                cleaner: cleaner,
                injector: injector,
                cues: cues,
                statusReporter: { status in reported.withLock { $0.append(status) } }
            )
        )

        await Self.runSession(orchestrator)

        #expect(cleaner.calls.isEmpty, "silence must never reach the cleaner; got \(cleaner.calls.map(\.raw))")
        #expect(injector.calls.isEmpty, "silence must never reach the injector; got \(injector.calls)")
        #expect(reported.withLock { $0 }.contains(.noSpeechDetected),
                "silence must surface the .noSpeechDetected glyph; got \(reported.withLock { $0 })")
        #expect(cues.playedCues == [.start, .end, .error],
                "the recording still started and ended, so Start and End sound; only the silence adds Error; got \(cues.playedCues)")
        #expect(await orchestrator.currentState() == .idle, "silence must return the session to idle")
    }

    /// Bare whitespace is silence too, and takes the same path.
    /// Sensitivity: an `isEmpty`-only guard lets "  \n" through → RED, while the
    /// empty-string test stays green.
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

    /// Raw mode skips the cleaner anyway, but ⌘V on an empty pasteboard can delete an
    /// active selection — that is the destructive exposure guarded here.
    /// Sensitivity: forward `.cleaned("")` to `.inject("")` → RED.
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

    /// Dependencies with the seam fakes, mirroring the sibling orchestrator suites.
    private static func deps(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        injector: FakeInjector,
        cues: FakeDictationCueController = FakeDictationCueController(),
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in }
    ) -> Dependencies {
        Dependencies(
            transcriber: transcriber, cleaner: cleaner, injector: injector,
            personalization: FakePersonalizationSource(terms: []),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            cueController: cues,
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
