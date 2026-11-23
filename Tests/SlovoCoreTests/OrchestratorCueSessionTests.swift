import Testing

@testable import SlovoCore
import SlovoTestSupport

// The orchestrator must close the cue session when a dictation ends, whatever ended
// it. Leaving it open strands the enabled-preference snapshot from the finished
// dictation and keeps the FIFO tail attached, so the next dictation's cue queues
// behind this one's audio — the microphone delay the design exists to avoid.
// Driven through the real PipelineFactory + Orchestrator over the seam fakes.
@Suite("Orchestrator cue session")
struct OrchestratorCueSessionTests {

    /// A dictation that runs to insertion closes its cue session, with nothing queued after it.
    /// Sensitivity: drop `endSession()` from `returnToIdle` → RED.
    @Test
    func completedDictationClosesTheCueSession() async {
        let cues = FakeDictationCueController()
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(transcript: "hi", cues: cues)
        )

        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(await orchestrator.currentState() == .idle, "the dictation must finish")
        #expect(cues.events.contains(.endSession),
                "a finished dictation must close its cue session; got \(cues.events)")
        #expect(cues.events.last == .endSession,
                "nothing may be queued after the session closed; got \(cues.events)")
    }

    /// A silently cancelled dictation closes its session too — cancellation sounds
    /// nothing, so this is the only observable left on that path.
    /// Sensitivity: move `endSession()` out of `returnToIdle` into the success path →
    /// RED here while the completed-dictation test above stays green.
    @Test
    func cancelledDictationClosesTheCueSession() async {
        let cues = FakeDictationCueController()
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(transcript: "hi", cues: cues)
        )

        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.cancelRequested)
        await orchestrator.awaitPipelineDrain()

        #expect(await orchestrator.currentState() == .idle, "cancellation must return to idle")
        #expect(cues.events.contains(.endSession),
                "a cancelled dictation must close its cue session; got \(cues.events)")
    }

    /// Dependencies with the seam fakes, mirroring the sibling orchestrator suites.
    private static func deps(transcript: String, cues: FakeDictationCueController) -> Dependencies {
        Dependencies(
            transcriber: FakeTranscriber(outcome: .success(transcript)),
            cleaner: FakeCleaner(outcome: .success("cleaned")),
            injector: FakeInjector(outcome: .success),
            personalization: FakePersonalizationSource(terms: []),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            cueController: cues,
            log: RedactionSafeLog(subsystem: "slovo", category: "cue-session-test"),
            statusReporter: { _ in }
        )
    }
}
