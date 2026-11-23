import Synchronization
import Testing

@testable import SlovoCore
import SlovoTestSupport

// A failed mute or restore, through the real running composition over seam fakes.
// Neither stops the dictation: a failed mute is reported at once and the hold
// records on; a failed restore is reported after its transition's other effects.
@Suite("Orchestrator output mute failures")
struct OrchestratorOutputMuteFailureTests {
    private static let prior = PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)

    private static func orchestrator(
        audio: FakeSystemAudioController,
        cues: FakeDictationCueController,
        injector: FakeInjector = FakeInjector(outcome: .success),
        statusReporter: @escaping @Sendable (StatusMessage) -> Void
    ) -> Orchestrator {
        let state = AppState(config: Config(mutesSystemAudioWhileDictating: true), isOpenRouterKeyPresent: true)
        return PipelineFactory.makeOrchestrator(
            dependencies: Dependencies(
                transcriber: FakeTranscriber(outcome: .success("hi")),
                cleaner: FakeCleaner(outcome: .success("HI")),
                injector: injector,
                personalization: FakePersonalizationSource(terms: []),
                audio: audio,
                recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
                cueController: cues,
                log: RedactionSafeLog(subsystem: "slovo", category: "orch-mute-failure-test"),
                settings: FakeSettingsSource(state.dictationSettings).provider,
                statusReporter: statusReporter
            )
        )
    }

    /// A mute that fails at the HAL is reported once while the key is still held,
    /// with its Error behind Start, and the dictation still inserts its text.
    /// Stated sensitivity: drop the report (today's `try?`) → no status before
    /// key-up → RED; report it from the restore effect instead → no status before
    /// key-up → RED.
    @Test
    func failedMuteReportsAtOnceAndTheHoldRecordsOn() async {
        let reported = Mutex<[StatusMessage]>([])
        let cues = FakeDictationCueController()
        let injector = FakeInjector(outcome: .success)
        let orchestrator = Self.orchestrator(
            audio: FakeSystemAudioController(mute: .fails), cues: cues, injector: injector
        ) { status in reported.withLock { $0.append(status) } }

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()

        #expect(reported.withLock { $0 } == [.outputMuteFailed], "a failed mute must be reported before key-up")
        #expect(cues.playedCues == [.start, .error], "its Error must be queued while the key is held; got \(cues.playedCues)")
        #expect(await orchestrator.currentState() == .recording, "a failed mute must not stop the recording")

        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(injector.calls == ["HI"], "the dictation must still insert its text; got \(injector.calls)")
        #expect(reported.withLock { $0 } == [.outputMuteFailed], "the failed mute must be reported exactly once")
    }

    /// A device with no mute or volume lever is not a failure: nothing is reported,
    /// no Error plays and, with nothing muted, nothing is restored.
    /// Stated sensitivity: treat a nil mute as a failure → a status and an Error
    /// → RED.
    @Test
    func deviceWithNoLeverReportsNothing() async {
        let reported = Mutex<[StatusMessage]>([])
        let cues = FakeDictationCueController()
        let audio = FakeSystemAudioController(mute: .noLever)
        let orchestrator = Self.orchestrator(audio: audio, cues: cues) { status in
            reported.withLock { $0.append(status) }
        }

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(audio.muteCount == 1, "the mute must have been attempted")
        #expect(reported.withLock { $0 }.isEmpty, "no lever is not a failure; got \(reported.withLock { $0 })")
        #expect(cues.playedCues == [.start, .end], "no Error may play; got \(cues.playedCues)")
        #expect(audio.restoredDeviceIDs.isEmpty, "nothing muted → nothing restored; got \(audio.restoredDeviceIDs)")
    }

    /// A restore that fails at key-up is reported, and its Error lands behind End.
    /// Stated sensitivity: report inside the restore effect instead of deferring it
    /// → Error before End → RED.
    @Test
    func failedRestoreAtKeyUpQueuesErrorBehindEnd() async {
        let reported = Mutex<[StatusMessage]>([])
        let cues = FakeDictationCueController()
        let injector = FakeInjector(outcome: .success)
        let orchestrator = Self.orchestrator(
            audio: FakeSystemAudioController(mute: .returns(Self.prior), restoreFails: true), cues: cues, injector: injector
        ) { status in reported.withLock { $0.append(status) } }

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(reported.withLock { $0 } == [.outputRestoreFailed], "a failed restore must be reported")
        #expect(cues.playedCues == [.start, .end, .error], "Error must follow End; got \(cues.playedCues)")
        #expect(injector.calls == ["HI"], "a failed restore must not stop the insertion; got \(injector.calls)")
    }

    /// A cancelled hold whose restore fails reports the notice, and its Error is
    /// dropped: the cue session ended with the cancel.
    /// Stated sensitivity: report before `.returnToIdle` → Error enqueued into the
    /// live session → RED.
    @Test
    func failedRestoreOnCancelReportsWithoutError() async {
        let reported = Mutex<[StatusMessage]>([])
        let cues = FakeDictationCueController()
        let orchestrator = Self.orchestrator(
            audio: FakeSystemAudioController(mute: .returns(Self.prior), restoreFails: true), cues: cues
        ) { status in reported.withLock { $0.append(status) } }

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.cancelRequested)

        #expect(reported.withLock { $0 } == [.outputRestoreFailed], "a failed restore must be reported on a cancel too")
        #expect(cues.playedCues == [.start], "a cancel plays no Error; got \(cues.playedCues)")
    }
}
