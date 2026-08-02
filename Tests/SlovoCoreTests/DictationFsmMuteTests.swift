import Foundation
import Testing

import SlovoCore

// Where the cue and system-audio effects land, and in what order. Two rulings under
// test: a cue finishing after the hold ended never mutes, and restore runs exactly
// once on leaving `recording`, with End queued behind it. The silent-cancel and
// capture-failure restores are pinned where those rows live, in
// `DictationFsmCancelTests` and `DictationFsmCaptureFailureTests`.
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

    /// Readiness withholds delivery BEFORE starting the cue, so the cue's own opening
    /// frames cannot re-enter through the microphone.
    /// Sensitivity: swap the pair, drop the suspend, or mute here → RED.
    @Test
    func captureReadySuspendsDeliveryBeforeStartingTheCue() {
        let (state, effects) = DictationFsm.transition(.recording, on: .captureReady)
        #expect(state == .recording, "capture readiness keeps the session recording, got \(state)")
        #expect(effects == [.suspendDelivery, .playStartCue],
                "must withhold delivery before the cue starts, and never wait on it; got \(effects)")
        #expect(!effects.contains(.muteSystemOutput),
                "muting here would silence the cue itself; got \(effects)")
    }

    /// The cue's completion mutes first, then reopens delivery — reopening first would
    /// admit the very playback this mute silences.
    /// Sensitivity: swap or drop either effect → RED.
    @Test
    func startCueFinishedMutesBeforeResumingDelivery() {
        let (state, effects) = DictationFsm.transition(.recording, on: .startCueFinished)
        #expect(state == .recording, "the cue completion keeps the session recording, got \(state)")
        #expect(effects == [.muteSystemOutput, .resumeDelivery],
                "must mute before reopening delivery, exactly once each; got \(effects)")
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

    /// The same property along the real path: key-up first, then the cue completion,
    /// driven through the actual transition rather than an assumed state.
    /// Sensitivity: a state-agnostic `startCueFinished` row → RED.
    @Test
    func startCueFinishingAfterKeyUpNeverReMutes() {
        let (afterKeyUp, keyUpEffects) = DictationFsm.transition(.recording, on: .stopRequested(.plain))
        #expect(keyUpEffects.contains(.restoreSystemOutput),
                "key-up must restore system output, got \(keyUpEffects)")

        let (state, lateCueEffects) = DictationFsm.transition(afterKeyUp, on: .startCueFinished)
        #expect(state == afterKeyUp,
                "a late cue completion must not disturb the post-key-up state, got \(state)")
        #expect(!lateCueEffects.contains(.muteSystemOutput),
                "a cue completing after key-up must never re-mute system output, got \(lateCueEffects)")
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

    /// End is queued after the restore: sent into still-muted output it would not be heard.
    /// Sensitivity: emit End ahead of restore → RED (a missing End is caught by the
    /// sequence above, not here).
    @Test
    func keyUpQueuesEndOnlyAfterOutputIsRestored() {
        let (_, effects) = DictationFsm.transition(.recording, on: .stopRequested(.plain))
        #expect(Self.position(of: .restoreSystemOutput, in: effects)
                < Self.position(of: .enqueueCue(.end), in: effects),
                "End queued into muted output would not be heard — restore must come first; got \(effects)")
    }

    /// A failure before key-up restores audio first: an error must never leave output muted.
    /// Sensitivity: drop `.restoreSystemOutput` from this row → RED.
    @Test
    func failureDuringRecordingRestoresAudio() {
        let (state, effects) = DictationFsm.transition(
            .recording, on: .failed(.transcription(.backendUnavailable))
        )
        #expect(state == .idle, "a failure during recording must return to idle, got \(state)")
        #expect(
            effects == [.restoreSystemOutput, .notify(.transcriptionFailed), .log(.stageFailed), .returnToIdle],
            "must emit exactly [restoreSystemOutput, notify, log, returnToIdle], got \(effects)"
        )
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

    /// A failure after key-up does not restore again either.
    /// Sensitivity: add `.restoreSystemOutput` to the processing-failure row → RED.
    @Test
    func processingFailureDoesNotRestoreAgain() {
        let (state, effects) = DictationFsm.transition(
            .processing, on: .failed(.injection(.pasteFailed))
        )
        #expect(state == .idle, "a processing failure returns to idle, got \(state)")
        #expect(!effects.contains(.restoreSystemOutput),
                "a processing-phase failure must NOT restore again (already restored at key-up), got \(effects)")
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

    /// Position of an effect, or past the end when absent, so an ordering assertion on a
    /// missing effect fails instead of trapping.
    private static func position(of effect: DictationEffect, in effects: [DictationEffect]) -> Int {
        effects.firstIndex(of: effect) ?? Int.max
    }
}
