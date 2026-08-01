import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The running orchestrator's silent-cancel behavior: a cancel tears the ASR
// session down via cancel() (never finish()), inserts nothing, cleans nothing,
// releases the mic, restores audio exactly once, and returns to idle.
@Suite("Orchestrator cancel")
struct OrchestratorCancelTests {

    /// Stated sensitivity, per assertion (the first is demonstrated RED in Step 7
    /// against a deliberately wrong finalize impl):
    ///   - route cancel through `finish()` instead of `cancel()` → finishCount == 1
    ///     and cancelCount == 0 → RED;
    ///   - forget `recorder.stop()` → stopCount == 0 → RED;
    ///   - forget restore → restoredDeviceIDs empty → RED;
    ///   - wire cancel through the FSM stop row so clean/inject run → cleaner.calls
    ///     / injector.calls become non-empty → RED.
    @Test
    func cancelDiscardsWithoutTranscribingCleaningOrInjecting() async {
        let transcriber = FakeTranscriber(outcome: .success("hi"))
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let injector = FakeInjector(outcome: .success)
        let audio = FakeSystemAudioController(
            muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
        )
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        let cues = FakeDictationCueController()
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Dependencies(
                transcriber: transcriber,
                cleaner: cleaner,
                injector: injector,
                personalization: FakePersonalizationSource(terms: []),
                audio: audio,
                recorder: recorder,
                cueController: cues,
                log: RedactionSafeLog(subsystem: "slovo", category: "orch-cancel-test")
            )
        )

        await orchestrator.handle(.startRequested)
        // Cancel a hold that already muted and played Start, so the assertions below
        // prove cancel UNDOES those effects rather than merely outrunning them.
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.cancelRequested)
        await orchestrator.awaitPipelineDrain()

        #expect(injector.calls.isEmpty, "cancel must insert nothing, got \(injector.calls)")
        #expect(cleaner.calls.isEmpty, "cancel must never run cleanup, got \(cleaner.calls.count) calls")
        #expect(transcriber.finishCount == 0, "cancel must NOT transcribe, got finish count \(transcriber.finishCount)")
        #expect(transcriber.cancelCount == 1, "cancel must tear down the ASR session via cancel(), got \(transcriber.cancelCount)")
        #expect(recorder.stopCount == 1, "cancel must release the mic, got stop count \(recorder.stopCount)")
        #expect(audio.muteCount == 1 && audio.restoredDeviceIDs == [42],
                "cancel must restore system audio exactly once, got mute \(audio.muteCount) restore \(audio.restoredDeviceIDs)")
        // Sensitivity: routing cancel through normal stop adds End; treating it as
        // a failure adds Error. The already-played Start is the only cue allowed.
        #expect(cues.playedCues == [.start], "intentional cancel must add neither End nor Error; got \(cues.playedCues)")
        #expect(await orchestrator.currentState() == .idle, "cancel returns the session to idle")
    }
}
