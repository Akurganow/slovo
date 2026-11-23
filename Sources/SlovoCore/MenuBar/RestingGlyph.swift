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
    /// A failure flash, or a notice that ended the dictation, owns the glyph, so
    /// nothing is painted.
    case leave
    /// A dictation is live and nothing owns the glyph: paint what it is doing.
    case hold
    /// The pulsing preparing-speech-model glyph.
    case loading
    /// The idle glyph (or the update-ready one, which rides the idle slot).
    case idle

    /// The one decision behind every repaint of the resting glyph. A flash wins
    /// over everything; a live dictation wins over the gate, so a repaint never
    /// lands idle or loading on a live glyph.
    public static func derive(
        isPipelineActive: Bool,
        isShowingBriefStatus: Bool,
        isGlyphHeldByNotice: Bool,
        gate: ModelGate
    ) -> RestingGlyph {
        if isShowingBriefStatus { return .leave }
        if isPipelineActive { return isGlyphHeldByNotice ? .leave : .hold }
        return gate == .loading ? .loading : .idle
    }
}
