import SlovoCore

// Dictation is gated until the ASR model is resident: a key-down before the model
// loads would open the microphone for a session that cannot start, so it is refused
// without a trace. Each write to `modelGate` repaints the resting glyph, which pulses
// the Glagolitic Zhivete glyph while the gate is loading. The warm-up task succeeds
// only once the model has loaded (it retries a failed load itself) and fails when
// cancelled, so the gate opens only on a loaded model.
extension AppDelegate {
    func prepareModelGate(for live: AppComposition.Live) {
        modelGate = .loading
        store.update { $0.statusLine = .message(.preparingSpeechModel) }
        Task { @MainActor [weak self] in
            guard (try? await live.modelWarmUp.value) != nil, let self else { return }
            // Only the composition now wired may open its gate. Compositions share
            // one speech model, so a superseded composition's warm-up also succeeds
            // when that model loads, and must not repaint the state of the
            // composition that replaced it.
            guard live.modelWarmUp == self.composition?.modelWarmUp else { return }
            // The task succeeded, so the model is loaded.
            self.modelGate = .open
            // The status line is not a glyph decision: a dictation or a failure
            // flash that is showing its own status keeps it.
            guard !self.isPipelineActive, !self.isShowingBriefStatus else { return }
            self.store.update { $0.statusLine = .idle }
        }
    }
}
