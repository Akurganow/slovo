import Foundation
import Testing

import SlovoCore

// The FSM emits the system-audio mute/restore
// effects in the right place and order.
//
// RULING: RESTORE AT KEY-UP. System audio is
// restored the moment `fn` is released (leaving `recording`), never in the
// processing phase. Invariant locked here: restore runs EXACTLY ONCE per muted
// session, on LEAVING `recording` (via stopRequested OR via failed), and NEVER
// in processing.
//
// New `DictationEffect` cases the implementer must add (no associated values;
// keep `DictationEffect` Equatable): `.muteSystemOutput`, `.restoreSystemOutput`.
//
// RED today: those two cases do not exist on `DictationEffect`, so the
// references below DO NOT COMPILE (the documented RED). Once
// the cases exist and the override table is implemented, these go GREEN.
//
// Override transition table (authoritative for this epic):
//   idle       + startRequested        -> recording  + [muteSystemOutput, beginCapture]
//   recording  + stopRequested         -> processing + [endCaptureAndFinalizeTranscript, restoreSystemOutput]
//   recording  + failed(f)             -> idle       + [restoreSystemOutput, notify(s), log(.stageFailed), returnToIdle]
//   processing + transcriptReady(t)    -> processing + [clean(transcript: t)]
//   processing + cleaned(c)            -> processing + [inject(text: c)]
//   processing + injected              -> idle       + [returnToIdle]                (NO restore)
//   processing + startRequested        -> processing + [log(.singleFlightIgnored)]   (NO second mute)
//   processing + failed(f)             -> idle       + [notify(s), log(.stageFailed), returnToIdle]  (NO restore)
//   default                            -> unchanged  + [log(.unexpectedEvent)]
@Suite("FSM mute/restore")
struct DictationFsmMuteTests {

    // MARK: - Mute BEFORE capture on Start

    /// On Start, the FSM silences playback BEFORE opening the mic.
    /// Stated sensitivity: drop the mute (revert to `[.beginCapture]`) → RED; put
    /// mute AFTER beginCapture → order mismatch → RED (proves "before capture").
    @Test
    func startRequestedMutesBeforeBeginCapture() {
        let (state, effects) = DictationFsm.transition(.idle, on: .startRequested)
        #expect(state == .recording, "idle + startRequested must move to recording, got \(state)")
        #expect(effects == [.muteSystemOutput, .beginCapture],
                "must emit exactly [muteSystemOutput, beginCapture] in that order, got \(effects)")
    }

    // MARK: - Restore at key-up (leaving recording via stopRequested)

    /// On `fn` release (stopRequested while recording), the FSM restores system
    /// audio right after closing the mic — restore happens at key-up.
    /// Stated sensitivity: drop `.restoreSystemOutput` here (revert to
    /// `[.endCaptureAndFinalizeTranscript]`) → RED; reorder before endCapture → RED.
    @Test
    func stopRequestedRestoresAtKeyUp() {
        let (state, effects) = DictationFsm.transition(.recording, on: .stopRequested)
        #expect(state == .processing, "recording + stopRequested must move to processing, got \(state)")
        #expect(effects == [.endCaptureAndFinalizeTranscript, .restoreSystemOutput],
                "must emit exactly [endCaptureAndFinalizeTranscript, restoreSystemOutput], got \(effects)")
    }

    // MARK: - Error DURING recording still restores (never leave audio muted)

    /// A failure while still recording must restore system audio (safety: an
    /// error mid-recording can never leave output stuck muted), then surface the
    /// honest status, log, and return to idle.
    /// Stated sensitivity: drop `.restoreSystemOutput` from this row → RED (audio
    /// would be left muted on an error before key-up).
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

    // MARK: - NO double-restore in the processing phase (already restored at key-up)

    /// On success completion (`injected`), the FSM returns to idle WITHOUT a
    /// second restore — audio was already restored at key-up.
    /// Stated sensitivity: add a `.restoreSystemOutput` to this row → a duplicate
    /// restore appears → RED (proves restore is not re-run post-key-up).
    @Test
    func injectedDoesNotRestoreAgain() {
        let (state, effects) = DictationFsm.transition(.processing, on: .injected)
        #expect(state == .idle, "injected returns to idle, got \(state)")
        #expect(effects == [.returnToIdle],
                "injected must emit exactly [returnToIdle] (no second restore), got \(effects)")
        #expect(!effects.contains(.restoreSystemOutput),
                "injected must NOT restore again — already restored at key-up")
    }

    /// A failure in the PROCESSING phase (after key-up) must NOT restore again —
    /// audio was already restored when recording ended.
    /// Stated sensitivity: add a `.restoreSystemOutput` to the processing-failure
    /// row → RED (double restore after key-up).
    @Test
    func processingFailureDoesNotRestoreAgain() {
        let (state, effects) = DictationFsm.transition(
            .processing, on: .failed(.injection(.pasteFailed))
        )
        #expect(state == .idle, "a processing failure returns to idle, got \(state)")
        #expect(!effects.contains(.restoreSystemOutput),
                "a processing-phase failure must NOT restore again (already restored at key-up), got \(effects)")
    }

    // MARK: - Single-flight in processing issues NO second mute

    /// A second Start while processing is ignored-but-logged and issues NO second
    /// mute (a double-mute would corrupt the stashed PriorAudioState).
    /// Stated sensitivity: allow re-entry (`.recording`/`[muteSystemOutput, …]`)
    /// → state changes / a second mute appears → RED.
    @Test
    func singleFlightStartIssuesNoSecondMute() {
        let (state, effects) = DictationFsm.transition(.processing, on: .startRequested)
        #expect(state == .processing, "single-flight: state must stay processing, got \(state)")
        #expect(effects == [.log(.singleFlightIgnored)],
                "must emit exactly [log(.singleFlightIgnored)], got \(effects)")
        #expect(!effects.contains(.muteSystemOutput),
                "single-flight must NOT issue a second mute")
    }
}
