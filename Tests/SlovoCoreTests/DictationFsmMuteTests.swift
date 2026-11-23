import Foundation
import Testing

import SlovoCore

// Where the cue and system-audio effects land, and in what order. Two rulings under
// test: a cue finishing after the hold ended never mutes, and restore runs exactly
// once on leaving `recording`, with End queued behind it. The silent-cancel and
// capture-failure restores are pinned where those rows live, in
// `DictationFsmCancelTests` and `DictationFsmCaptureFailureTests`, and the failure rows
// in `FsmTests`.
@Suite("FSM cue/mute/restore")
struct DictationFsmMuteTests {

    // MARK: - Key-down, cue start, cue completion

    /// Key-down only begins capture — no cue and no mute before readiness.
    /// Sensitivity: an eager `.playStartCue` or `.muteSystemOutput` here → RED.
    @Test
    func startRequestedBeginsCaptureWithoutCueOrMute() {
        let (state, effects) = DictationFsm.transition(.idle, on: .startRequested)
        #expect(state == .recording, "idle + startRequested must move to recording, got \(state)")
        #expect(effects == [.beginCapture], "must emit only beginCapture before readiness, got \(effects)")
    }

    /// Readiness only starts the cue, and never waits on it. Muting here would silence
    /// the cue itself.
    /// Sensitivity: add `.muteSystemOutput` or any other effect, or drop `.playStartCue` → RED.
    @Test
    func captureReadyOnlyStartsTheCue() {
        let (state, effects) = DictationFsm.transition(.recording, on: .captureReady)
        #expect(state == .recording, "capture readiness keeps the session recording, got \(state)")
        #expect(effects == [.playStartCue],
                "must start the cue and nothing else (muting would silence the cue itself); got \(effects)")
    }

    /// The cue's completion mutes output, once and with nothing else.
    /// Sensitivity: drop the mute or add any other effect → RED.
    @Test
    func startCueFinishedOnlyMutesOutput() {
        let (state, effects) = DictationFsm.transition(.recording, on: .startCueFinished)
        #expect(state == .recording, "the cue completion keeps the session recording, got \(state)")
        #expect(effects == [.muteSystemOutput], "must mute exactly once and do nothing else; got \(effects)")
    }

    // MARK: - A late cue completion can never mute (the safety property)

    /// A cue finishing after the hold ended must do nothing: no mute after the key-up
    /// restore, and no log — a hold shorter than the cue is the ordinary case.
    /// Sensitivity: a state-agnostic `startCueFinished` row → a mute outside recording;
    /// falling through to `default` → an `unexpectedEvent` log. Both RED.
    @Test
    func startCueFinishedOutsideRecordingIsInertAndNeverMutes() {
        for origin in Self.statesOutsideRecording {
            let (state, effects) = DictationFsm.transition(origin, on: .startCueFinished)
            #expect(state == origin,
                    "a late cue completion must not move the session out of \(origin), got \(state)")
            #expect(effects.isEmpty,
                    "a late cue completion in \(origin) must do nothing at all, got \(effects)")
            #expect(!effects.contains(.muteSystemOutput),
                    "a cue completing outside recording must never mute system output, got \(effects)")
        }
    }

    // MARK: - Restore at key-up, then End

    /// Key-up stops capture, restores output, then queues End — End marks the end of the
    /// RECORDING, not a successful transcription.
    /// Sensitivity: drop End or restore, or reorder the stop/restore pair → RED.
    @Test
    func stopRequestedRestoresThenQueuesEndAtKeyUp() {
        let (state, effects) = DictationFsm.transition(.recording, on: .stopRequested(.plain))
        #expect(state == .processing, "recording + stopRequested must move to processing, got \(state)")
        #expect(effects == [.endCaptureAndFinalizeTranscript, .restoreSystemOutput, .enqueueCue(.end)],
                "must stop, restore, then announce the end of recording; got \(effects)")
    }

    // MARK: - No second restore in processing

    /// Success completes without a second restore — audio came back at key-up.
    /// Sensitivity: add `.restoreSystemOutput` to this row → RED.
    @Test
    func injectedDoesNotRestoreAgain() {
        let (state, effects) = DictationFsm.transition(.processing, on: .injected)
        #expect(state == .idle, "injected returns to idle, got \(state)")
        #expect(effects == [.returnToIdle],
                "injected must emit exactly [returnToIdle] (no second restore), got \(effects)")
        #expect(!effects.contains(.restoreSystemOutput),
                "injected must NOT restore again — already restored at key-up")
    }

    /// A second Start while processing is ignored and issues no second mute — a re-mute
    /// would corrupt the stashed PriorAudioState.
    /// Sensitivity: allow re-entry into `.recording` → RED.
    @Test
    func singleFlightStartIssuesNoSecondMute() {
        let (state, effects) = DictationFsm.transition(.processing, on: .startRequested)
        #expect(state == .processing, "single-flight: state must stay processing, got \(state)")
        #expect(effects == [.log(.singleFlightIgnored)],
                "must emit exactly [log(.singleFlightIgnored)], got \(effects)")
        #expect(!effects.contains(.muteSystemOutput),
                "single-flight must NOT issue a second mute")
    }

    /// Every state but `.recording`. The exhaustive `switch` is the guard: a new
    /// `DictationState` fails to compile until it is classified here.
    private static var statesOutsideRecording: [DictationState] {
        [DictationState.idle, .recording, .processing].filter(isOutsideRecording)
    }

    private static func isOutsideRecording(_ state: DictationState) -> Bool {
        switch state {
        case .recording:
            return false
        case .idle, .processing:
            return true
        }
    }
}
