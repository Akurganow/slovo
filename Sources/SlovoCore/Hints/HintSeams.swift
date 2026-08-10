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

/// One fragment the on-device grammar checker flagged, with its own explanation and
/// suggested rewrites. Advisory only — never applied automatically.
///
/// Unlike a `SpellFinding`, the useful signal here is the checker's `message`: the
/// flagged `fragment` alone ("is") says nothing without "may not agree with the rest
/// of the sentence".
public struct GrammarFinding: Equatable, Sendable {
    /// The flagged text itself, resolved from the detail's range within the sentence
    /// the checker reported (see `SystemSpellCheckHintProvider` — the detail range is
    /// relative to that sentence, not to the transcript).
    public var fragment: String
    /// The checker's human-readable explanation, e.g. "The word 'is' may not agree
    /// with the rest of the sentence."
    public var message: String
    /// The checker's suggested replacements for `fragment`, possibly empty.
    public var corrections: [String]

    public init(fragment: String, message: String, corrections: [String]) {
        self.fragment = fragment
        self.message = message
        self.corrections = corrections
    }
}

/// Everything one on-device checking pass produced. A single value because a single
/// `NSSpellChecker` call yields both kinds at once: splitting them across two protocol
/// methods would mean checking the transcript twice.
public struct SpellCheckFindings: Equatable, Sendable {
    public var spelling: [SpellFinding]
    public var grammar: [GrammarFinding]

    /// The neutral value: nothing found, nothing to advise.
    public static let empty = SpellCheckFindings()

    public var isEmpty: Bool { spelling.isEmpty && grammar.isEmpty }

    public init(spelling: [SpellFinding] = [], grammar: [GrammarFinding] = []) {
        self.spelling = spelling
        self.grammar = grammar
    }
}

/// On-device language hints gathered at key-up for a single cleanup pass: the active
/// keyboard input language, a capped list of spell-check findings, and a capped list
/// of grammar findings. All are advisory context for the cleanup model, never a
/// forced rewrite. Empty is the neutral value, in which case no advisory block is
/// emitted.
public struct CleanupHints: Equatable, Sendable {
    /// First BCP-47 code of the active keyboard input source (e.g. "ru", "en"), or
    /// nil when it cannot be determined. This hint has no toggle.
    public var inputLocale: String?
    /// Possibly-misspelled tokens with suggestions, capped at 15 by the provider.
    public var spellFindings: [SpellFinding]
    /// Fragments the grammar checker flagged, capped at 15 by the provider. Apple
    /// ships grammar rules for English only, so this is empty for most dictations
    /// by design — a silent, non-fatal degradation like every other hint.
    public var grammarFindings: [GrammarFinding]

    public init(
        inputLocale: String? = nil,
        spellFindings: [SpellFinding] = [],
        grammarFindings: [GrammarFinding] = []
    ) {
        self.inputLocale = inputLocale
        self.spellFindings = spellFindings
        self.grammarFindings = grammarFindings
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

/// Finds possibly-misspelled tokens and flagged grammar fragments in a transcript,
/// honoring an ignore list. `Sendable` so the `actor Orchestrator` can hold it in its
/// `Dependencies`.
public protocol SpellCheckHintProviding: Sendable {
    /// The spelling and grammar findings in `transcript`, never flagging a term in
    /// `vocabulary`. Returns `.empty` on any failure — the pass is non-fatal by
    /// contract, so a failure omits the hints and lets cleanup proceed.
    func findings(in transcript: String, ignoring vocabulary: [String]) -> SpellCheckFindings
}
