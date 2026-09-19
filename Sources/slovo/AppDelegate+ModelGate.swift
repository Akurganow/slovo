import AppKit
import SlovoCore

// Dictation is gated until the ASR model is resident: a key-down during the cold
// load would open the mic and then sit inside `begin` for the whole load, with the
// key-up queued behind it. While loading, the status bar pulses the Glagolitic
// Zhivete glyph instead of accepting input.
extension AppDelegate {
    func prepareModelGate(for live: AppComposition.Live) {
        isModelReady = false
        showModelLoadingState()
        Task { @MainActor [weak self] in
            await live.modelWarmUp.value
            guard let self else { return }
            // Only the composition now wired may open its gate. Compositions share
            // one speech model but preload it separately, so a superseded warm-up
            // can still fail while the current one is retrying the load — and the
            // gate must report the retry's outcome, not the attempt it replaced.
            guard live.modelWarmUp == self.composition?.modelWarmUp else { return }
            // A failed preload opens the gate too: `begin` retries the load and
            // surfaces the honest error through the normal status path.
            self.isModelReady = true
            self.stopModelLoadingPulse(on: self.statusItem?.button)
            guard !self.isPipelineActive, !self.isShowingBriefStatus else { return }
            self.paintIdleGlyph(on: self.statusItem?.button)
            self.statusTextItem?.title = self.idleStatusTitle
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
        statusTextItem?.title = Self.title(for: .preparingSpeechModel)
        startModelLoadingPulse(on: statusItem?.button)
    }
}
