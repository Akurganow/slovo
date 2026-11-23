import Testing

@testable import SlovoCore
import SlovoTestSupport

// `Orchestrator.deliver(_:)` maps each hotkey edge to the one FSM event it stands
// for, over the seam fakes. `HotkeyEdge`'s initializer is internal to SlovoCore,
// which is why these tests import it testable.
@Suite("Orchestrator deliver")
struct OrchestratorDeliverTests {
    private struct Rig {
        let transcriber = FakeTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let injector = FakeInjector(outcome: .success)
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        let orchestrator: Orchestrator

        init() {
            orchestrator = PipelineFactory.makeOrchestrator(
                dependencies: Dependencies(
                    transcriber: transcriber,
                    cleaner: cleaner,
                    injector: injector,
                    personalization: FakePersonalizationSource(terms: []),
                    audio: FakeSystemAudioController(
                        muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
                    ),
                    recorder: recorder,
                    cueController: FakeDictationCueController(),
                    log: RedactionSafeLog(subsystem: "slovo", category: "orch-deliver-test"),
                    settings: FakeSettingsSource().provider
                )
            )
        }

        func deliver(_ phase: HotkeyPhase) async {
            await orchestrator.deliver(HotkeyEdge(phase: phase, arrivedWhileBusy: false))
        }
    }

    /// Stated sensitivity: map `.down` to nothing, or to a stop → the state stays
    /// `.idle` and the engine never starts → RED.
    @Test
    func downEdgeStartsTheRecording() async {
        let rig = Rig()

        await rig.deliver(.down(.plain))

        #expect(await rig.orchestrator.currentState() == .recording, "a down edge must open a session")
        #expect(rig.recorder.engineStartCount == 1, "a down edge must start the capture engine once")

        await rig.deliver(.cancel)
        await rig.orchestrator.awaitPipelineDrain()
    }

    /// Stated sensitivity: map `.up(let mode)` to `.stopRequested(.plain)` instead of
    /// `.stopRequested(mode)` → the cleaner's `translate` stays `false` → RED.
    @Test
    func upEdgeCarriesItsModeToTheCleaner() async {
        let rig = Rig()

        await rig.deliver(.down(.plain))
        await rig.deliver(.up(.translate))
        await rig.orchestrator.awaitPipelineDrain()

        #expect(rig.cleaner.calls.last?.config.translate == true,
                "an up edge in translate mode must clean with translate on; got \(String(describing: rig.cleaner.calls.last?.config.translate))")
    }

    /// Stated sensitivity: map `.cancel` to `.stopRequested(.plain)` → the session
    /// finishes, so `cancelCount` stays 0 and the injector receives text → RED.
    @Test
    func cancelEdgeDiscardsTheSession() async {
        let rig = Rig()

        await rig.deliver(.down(.plain))
        await rig.deliver(.cancel)
        await rig.orchestrator.awaitPipelineDrain()

        #expect(await rig.orchestrator.currentState() == .idle, "a cancel edge returns the session to idle")
        #expect(rig.transcriber.cancelCount == 1, "a cancel edge must tear the ASR session down via cancel()")
        #expect(rig.injector.calls.isEmpty, "a cancel edge must insert nothing, got \(rig.injector.calls)")
    }

    /// Stated sensitivity: map `.translateLatched` to `.startRequested` → the idle
    /// orchestrator starts recording → RED.
    @Test
    func translateLatchedEdgeChangesNothing() async {
        let rig = Rig()

        await rig.deliver(.translateLatched)

        #expect(await rig.orchestrator.currentState() == .idle, "a translate latch is the sink's repaint, not an orchestrator event")
        #expect(rig.recorder.engineStartCount == 0, "a translate latch must not start the capture engine")
    }
}
