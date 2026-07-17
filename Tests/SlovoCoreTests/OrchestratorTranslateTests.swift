import Testing
import Synchronization

import SlovoCore
import SlovoTestSupport

// Translate mode threaded through the REAL running composition
// (`PipelineFactory.makeOrchestrator` + `Orchestrator`) over the seam fakes. The
// hotkey-layer latch decides the mode; here it arrives as `.stopRequested(mode)` and
// must reach the cleanup step's `CleanupConfig`, per session, without a new failure
// path.
@Suite("Orchestrator translate mode")
struct OrchestratorTranslateTests {
    /// Builds Dependencies with the given seam fakes (mic authorized; a pinned
    /// PriorAudioState for mute/restore), mirroring OrchestratorTests' harness.
    private static func deps(
        cleaner: FakeCleaner,
        injector: FakeInjector,
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in }
    ) -> Dependencies {
        Dependencies(
            transcriber: FakeTranscriber(outcome: .success("hi")),
            cleaner: cleaner,
            injector: injector,
            personalization: FakePersonalizationSource(terms: []),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            log: RedactionSafeLog(subsystem: "slovo", category: "orch-translate-test"),
            statusReporter: statusReporter
        )
    }

    private static func runSession(_ orchestrator: Orchestrator, mode: DictationMode) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(mode))
        await orchestrator.awaitPipelineDrain()
    }

    /// M2 — the latched translate mode reaches the cleanup step and is per-session: a
    /// `.stopRequested(.translate)` session cleans with `config.translate == true`,
    /// and the following `.plain` session on the SAME orchestrator resets it to
    /// `false`. Passes on the correct code.
    /// Stated sensitivity: (1) ignore the stashed mode when building the clean config
    /// → the first call's `translate` stays `false` → RED; (2) the second plain
    /// session's `false` is guarded by the UNCONDITIONAL stash `sessionMode = mode` on
    /// every `.stopRequested` — mutate it to stash only on `.translate` and the stale
    /// `.translate` from the prior session leaks into the plain session → the second
    /// call stays `true` → RED. (The `returnToIdle` reset is redundant given the
    /// unconditional stash, so it is NOT what this assert pins.)
    @Test
    func translateModeReachesCleanupAndResetsPerSession() async {
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(cleaner: cleaner, injector: FakeInjector(outcome: .success))
        )

        await Self.runSession(orchestrator, mode: .translate)
        #expect(cleaner.calls.last?.config.translate == true,
                "a translate-latched session must clean with translate on; got \(String(describing: cleaner.calls.last?.config.translate))")

        await Self.runSession(orchestrator, mode: .plain)
        #expect(cleaner.calls.last?.config.translate == false,
                "the next plain session must reset translate off; got \(String(describing: cleaner.calls.last?.config.translate))")
    }

    /// M3 — in translate mode the persisted target language reaches the cleaner
    /// alongside the translate flag. The target flows Config→CleanupConfig in both
    /// modes (green now); the `translate == true` is RED now.
    /// Stated sensitivity: drop the stashed-mode mapping → `translate` stays false →
    /// RED; drop the target from the clean config → `translationTargetLanguage` is
    /// not `.ru` → RED.
    @Test
    func translateModeCarriesTheConfiguredTargetLanguageToTheCleaner() async {
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(translationTargetLanguage: .ru),
            dependencies: Self.deps(cleaner: cleaner, injector: FakeInjector(outcome: .success))
        )

        await Self.runSession(orchestrator, mode: .translate)

        #expect(cleaner.calls.last?.config.translationTargetLanguage == .ru,
                "the persisted translate target must reach the cleaner; got \(String(describing: cleaner.calls.last?.config.translationTargetLanguage))")
        #expect(cleaner.calls.last?.config.translate == true,
                "a translate session must request a translate pass; got \(String(describing: cleaner.calls.last?.config.translate))")
    }

    /// A failing cleaner in TRANSLATE mode must degrade exactly like plain mode: the
    /// RAW transcript is inserted and the existing sad-to-fail status is surfaced —
    /// no new status, no swallowed failure, no empty insertion.
    /// Green now (PassThrough returns the raw transcript regardless of the mode).
    /// Stated sensitivity: if the translate path swallowed the cleanup failure or
    /// inserted nothing → the raw-injection assert reddens; if it emitted a different
    /// status → the status assert reddens.
    @Test
    func failingCleanerInTranslateModeDegradesToRawAndReportsSadStatus() async {
        let reported = Mutex<[StatusMessage]>([])
        let cleaner = FakeCleaner(outcome: .failure(.offline))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                cleaner: cleaner,
                injector: injector,
                statusReporter: { status in reported.withLock { $0.append(status) } }
            )
        )

        await Self.runSession(orchestrator, mode: .translate)

        #expect(injector.calls.last == "hi",
                "a failing cleaner in translate mode must still degrade to the RAW transcript; got \(String(describing: injector.calls.last))")
        #expect(reported.withLock { $0 }.contains(.cleanupUnavailableInsertedAsSpoken),
                "the existing sad-to-fail status must surface in translate mode; got \(reported.withLock { $0 })")
    }
}
