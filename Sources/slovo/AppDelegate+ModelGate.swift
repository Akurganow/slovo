import AppKit
import SlovoCore

// Dictation is gated until the ASR model is resident: a key-down during the cold
// load would open the mic and then sit inside `begin` for the whole load, with the
// key-up queued behind it. While loading, the status bar pulses the Glagolitic
// Zhivete glyph instead of accepting input. The warm-up task succeeds only once
// the model has loaded (it retries a failed load itself) and fails when cancelled,
// so the gate opens only on a loaded model.
extension AppDelegate {
    func prepareModelGate(for live: AppComposition.Live) {
        isModelReady = false
        showModelLoadingState()
        Task { @MainActor [weak self] in
            guard (try? await live.modelWarmUp.value) != nil, let self else { return }
            // Only the composition now wired may open its gate. Compositions share
            // one speech model, so a superseded composition's warm-up also succeeds
            // when that model loads, and must not repaint the state of the
            // composition that replaced it.
            guard live.modelWarmUp == self.composition?.modelWarmUp else { return }
            // The task succeeded, so the model is loaded.
            self.isModelReady = true
            self.stopModelLoadingPulse(on: self.statusItem?.button)
            guard !self.isPipelineActive, !self.isShowingBriefStatus else { return }
            self.paintIdleGlyph(on: self.statusItem?.button)
            self.store.update { $0.statusLine = .idle }
        }
    }

    /// Leaves the loading state WITHOUT opening the gate, for a composition that
    /// will never be gated: `startPipeline` returns at the onboarding guard before
    /// `prepareModelGate`, so no gate task exists to stop the pulse, and the
    /// superseded composition's task now stops at the currency guard above. Without
    /// this the infinite pulse runs for the rest of the launch.
    func clearModelLoadingState() {
        stopModelLoadingPulse(on: statusItem?.button)
        paintIdleGlyph(on: statusItem?.button)
    }

    func showModelLoadingState() {
        setStatusGlyph(status: .preparingSpeechModel, on: statusItem?.button)
        store.update { $0.statusLine = .message(.preparingSpeechModel) }
        startModelLoadingPulse(on: statusItem?.button)
    }
}
