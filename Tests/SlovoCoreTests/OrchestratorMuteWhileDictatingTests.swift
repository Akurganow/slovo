import Foundation
import Testing

@testable import SlovoCore
import SlovoTestSupport

// The mute-while-dictating switch, exercised through the REAL running composition
// (`PipelineFactory.makeOrchestrator` over the seam fakes — never a hand-wired
// copy). The switch is a CAPTURE-stage flag: MUTE is gated on the flag the dictation
// read when its recording began, while RESTORE stays gated ONLY on the stashed prior
// audio, so the mute/restore invariant never depends on the switch.
@Suite("Orchestrator mute-while-dictating")
struct OrchestratorMuteWhileDictatingTests {
    private static var vocab: [Term] {
        [Term(term: "ExampleCorp", expansion: nil, lang: .en, weight: 9)]
    }

    /// A fresh mute/restore observer with the pinned prior-audio state (not already
    /// muted, so a restore issues a real device write).
    private static func mutingAudio() -> FakeSystemAudioController {
        FakeSystemAudioController(
            muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
        )
    }

    /// Builds a running orchestrator via the REAL factory over seam fakes, with the
    /// mute switch starting at `mutingEnabled` and the given audio observer wired in.
    private static func orchestrator(
        mutingEnabled: Bool,
        audio: FakeSystemAudioController
    ) -> Orchestrator {
        let state = AppState(config: Config(mutesSystemAudioWhileDictating: mutingEnabled), isOpenRouterKeyPresent: true)
        return PipelineFactory.makeOrchestrator(
            dependencies: Dependencies(
                transcriber: FakeTranscriber(outcome: .success("hi")),
                cleaner: FakeCleaner(outcome: .success("HI")),
                injector: FakeInjector(outcome: .success),
                personalization: FakePersonalizationSource(terms: vocab),
                audio: audio,
                recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
                cueController: FakeDictationCueController(),
                log: RedactionSafeLog(subsystem: "slovo", category: "orch-mute-test"),
                settings: FakeSettingsSource(state.dictationSettings).provider
            )
        )
    }

    /// A hold long enough to outlast the readiness cue, which is when muting happens.
    /// Awaiting the cue is what a real hold does by lasting longer than it; a release
    /// that beats the cue deliberately leaves audio untouched.
    private static func runSession(_ orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
    }

    /// AC3: with muting OFF, a full session skips BOTH the mute and the restore —
    /// nothing is silenced, so nothing is restored.
    /// Stated sensitivity: drop the flag guard in `execute(.muteSystemOutput)` (mute
    /// unconditionally) → muteCount == 1 → RED.
    @Test
    func mutingDisabledSkipsMuteAndRestore() async {
        let audio = Self.mutingAudio()
        let orchestrator = Self.orchestrator(mutingEnabled: false, audio: audio)

        await Self.runSession(orchestrator)

        #expect(audio.muteCount == 0, "muting disabled must skip the mute; got \(audio.muteCount)")
        #expect(audio.restoredDeviceIDs.isEmpty, "nothing muted → nothing restored; got \(audio.restoredDeviceIDs)")
    }
}
