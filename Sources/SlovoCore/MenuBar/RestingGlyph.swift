/// Whether dictation is accepted yet, as the app shell sees it.
public enum ModelGate: Equatable, Sendable {
    /// Onboarding, or no composition yet: no gate task exists.
    case notGated
    /// The speech model is not resident, and key presses are refused.
    case loading
    /// The speech model is resident and dictation is accepted.
    case open
}

/// What the menu-bar glyph shows when nothing else is drawing on it.
public enum RestingGlyph: Equatable, Sendable {
    /// A dictation or the dictation-failure flash owns the glyph, so nothing is painted.
    case leave
    /// The pulsing preparing-speech-model glyph.
    case loading
    /// The idle glyph (or the update-ready one, which rides the idle slot).
    case idle

    /// The one decision behind every repaint of the resting glyph. Either latch
    /// wins over the gate, so a repaint never lands on a live glyph.
    public static func derive(isPipelineActive: Bool, isShowingBriefStatus: Bool, gate: ModelGate) -> RestingGlyph {
        if isPipelineActive || isShowingBriefStatus { return .leave }
        return gate == .loading ? .loading : .idle
    }
}
