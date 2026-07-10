import Testing

import SlovoCore

// The silent interrupt-cancel row: a right-modifier combo cancels the in-flight
// dictation with the recording discarded, audio restored exactly once (leaving
// recording), and NOTHING transcribed/cleaned/inserted and NO notify — the cancel
// is silent by contract.
@Suite("FSM cancel")
struct DictationFsmCancelTests {

    /// Cancel while recording discards capture, restores audio, and returns to
    /// idle — silently.
    /// Stated sensitivity: route cancel through the transcribe path
    /// (`.endCaptureAndTranscribe`) → the effect list differs → RED; add a notify
    /// → RED.
    @Test
    func cancelRequestedDiscardsSilentlyAndRestores() {
        let (state, effects) = DictationFsm.transition(.recording, on: .cancelRequested)
        #expect(state == .idle, "cancel returns to idle, got \(state)")
        #expect(effects == [.discardCapture, .restoreSystemOutput, .returnToIdle],
                "cancel must discard capture, restore audio, and return to idle, got \(effects)")
        let hasNotify = effects.contains { effect in
            if case .notify = effect { return true }
            return false
        }
        #expect(!hasNotify, "a silent cancel must emit NO notify effect")
    }

    /// Cancel is only meaningful while recording (the trigger is physically held).
    /// Outside recording it is a lossless logged no-op, never a stray effect.
    /// Stated sensitivity: add a broad cancel handler that fires in idle → RED.
    @Test
    func cancelRequestedWhileIdleIsLoggedNoOp() {
        let (state, effects) = DictationFsm.transition(.idle, on: .cancelRequested)
        #expect(state == .idle)
        #expect(effects == [.log(.unexpectedEvent)])
    }
}
