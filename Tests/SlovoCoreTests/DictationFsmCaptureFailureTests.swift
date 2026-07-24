import Foundation
import Testing

import SlovoCore

// FSM half: a capture failure flows through the EXISTING
// `(.recording, .failed)` recording-failure row, restoring system audio first
// (it was muted at key-down), then surfacing the honest microphone status.
//
// The capture path adds `StageFailure.capture(AudioCaptureError)` and
// `StatusMessage.microphoneUnavailable`, with ONE `statusMessage(for:)` branch
// mapping every capture case → `.microphoneUnavailable`; no transition-row changes.
@Suite("FSM capture failure")
struct DictationFsmCaptureFailureTests {

    /// A mic-denied capture failure during recording: restore audio FIRST (muted
    /// at key-down must be undone on leaving recording), then notify the honest
    /// `.microphoneUnavailable`, log, and return to idle — in that exact order.
    /// Stated sensitivity: map `.capture` to a wrong status (e.g. `.injectionFailed`)
    /// → the notify mismatches → sequence RED. Drop `.restoreSystemOutput` from
    /// the recording-failure row → sequence RED (regression guard).
    @Test
    func captureFailureDuringRecordingRestoresThenNotifiesMicUnavailable() {
        let (state, effects) = DictationFsm.transition(
            .recording, on: .failed(.capture(.microphoneDenied))
        )
        #expect(state == .idle, "a capture failure must return to idle, got \(state)")
        #expect(
            effects == [
                .restoreSystemOutput,
                .notify(.microphoneUnavailable),
                .log(.stageFailed),
                .returnToIdle,
            ],
            "must emit [restoreSystemOutput, notify(.microphoneUnavailable), log, returnToIdle], got \(effects)"
        )
    }

    /// The other capture cases also surface the single honest mic status (all
    /// capture cases → `.microphoneUnavailable`).
    /// Stated sensitivity: map any capture case to a different status → RED.
    @Test
    func engineStartFailureAlsoNotifiesMicUnavailable() {
        let (_, effects) = DictationFsm.transition(
            .recording, on: .failed(.capture(.engineStartFailed))
        )
        #expect(effects.contains(.notify(.microphoneUnavailable)),
                "engineStartFailed must notify .microphoneUnavailable, got \(effects)")
    }
}
