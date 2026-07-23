import AppKit
import SlovoCore

// Dictation is gated until the ASR model is resident: a key-down during the cold
// load would open the mic and mute system audio for the whole model load (the
// stranded-mute incident, log 2026-07-02 22:45). While loading, the status bar
// pulses the Glagolitic Zhivete glyph instead of accepting input.
extension AppDelegate {
    func prepareModelGate(for live: AppComposition.Live) {
        isModelReady = false
        showModelLoadingState()
        Task { @MainActor [weak self] in
            await live.modelWarmUp.value
            guard let self else { return }
            // A failed preload opens the gate too: `begin` retries the load and
            // surfaces the honest error through the normal status path.
            self.isModelReady = true
            self.stopModelLoadingPulse(on: self.statusItem?.button)
            guard !self.isPipelineActive, !self.isShowingBriefStatus else { return }
            self.setStatusGlyph(.idle, on: self.statusItem?.button)
            self.statusTextItem?.title = "Idle"
        }
    }

    func showModelLoadingState() {
        setStatusGlyph(status: .preparingSpeechModel, on: statusItem?.button)
        statusTextItem?.title = Self.title(for: .preparingSpeechModel)
        startModelLoadingPulse(on: statusItem?.button)
    }
}
