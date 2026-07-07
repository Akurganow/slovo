import Foundation
import Testing

import SlovoCore

// FSM half: a capture failure flows through the EXISTING
// `(.recording, .failed)` recording-failure row, restoring system audio first
// (it was muted at key-down), then surfacing the honest microphone status.
//
// Contract under test (implementer extends `Sources/SlovoCore/FSM/DictationFsm.swift`):
// add `StageFailure.capture(AudioCaptureError)`, a new
// `StatusMessage.microphoneUnavailable`, and ONE `statusMessage(for:)` branch
// mapping all capture cases → `.microphoneUnavailable`. NO transition-row changes.
//
// RED today: `StageFailure.capture` and `StatusMessage.microphoneUnavailable`
// do not exist yet, so the references below DO NOT COMPILE — that is the
// documented initial RED for the FSM half. Once the cases exist and the branch
// maps capture → `.microphoneUnavailable`, this goes GREEN; mapping `.capture`
// to a WRONG status then fails the sequence assertion (value RED).
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
