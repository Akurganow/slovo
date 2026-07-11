/// One possibly-misspelled token flagged by the on-device spell checker, with its
/// top guesses. Advisory only — never applied automatically.
public struct SpellFinding: Equatable, Sendable {
    public var token: String
    public var guesses: [String]

    public init(token: String, guesses: [String]) {
        self.token = token
        self.guesses = guesses
    }
}

/// On-device language hints gathered at key-up for a single cleanup pass: the active
/// keyboard input language and a capped list of spell-check findings. Both are
/// advisory context for the cleanup model, never a forced rewrite. Empty is the
/// neutral value, in which case no advisory block is emitted.
public struct CleanupHints: Equatable, Sendable {
    /// First BCP-47 code of the active keyboard input source (e.g. "ru", "en"), or
    /// nil when it cannot be determined. This hint has no toggle.
    public var inputLocale: String?
    /// Possibly-misspelled tokens with suggestions, capped at 15 by the provider.
    public var spellFindings: [SpellFinding]

    public init(inputLocale: String? = nil, spellFindings: [SpellFinding] = []) {
        self.inputLocale = inputLocale
        self.spellFindings = spellFindings
    }
}

/// Reads the active keyboard input source's primary language on demand.
/// `Sendable` so the `actor Orchestrator` can hold it and read it via a main-actor
/// hop at key-up.
public protocol InputSourceLanguageReading: Sendable {
    /// The first BCP-47 language of the active keyboard input source, or nil when it
    /// cannot be determined. Read fresh per dictation — no cached state to go stale.
    func currentPrimaryLanguage() -> String?
}

/// Finds possibly-misspelled tokens in a transcript, honoring an ignore list.
/// `Sendable` so the `actor Orchestrator` can hold it in its `Dependencies`.
public protocol SpellCheckHintProviding: Sendable {
    /// Possibly-misspelled tokens in `transcript` with top guesses, never flagging a
    /// term in `vocabulary`. Returns `[]` on any failure — the pass is non-fatal by
    /// contract, so a failure omits the hints and lets cleanup proceed.
    func findings(in transcript: String, ignoring vocabulary: [String]) -> [SpellFinding]
}
