import AppKit

/// Real `SpellCheckHintProviding` backed by the OS's on-device `NSSpellChecker`.
/// One pass over the raw transcript yields both kinds of advisory finding:
/// possibly-misspelled tokens with top-3 guesses, and grammar fragments with the
/// checker's own explanation. The user's vocabulary is ignored (via
/// `setIgnoredWords`, never `learnWord`, which is device-global and persistent).
/// Findings whose language is not enabled in System Settings are dropped (graceful
/// degradation). Any failure yields `.empty` — the pass is non-fatal by contract.
///
/// Note on coverage: Apple ships grammar rules for English only (verified against
/// `checkGrammar` across every installed language), so the grammar half is empty for
/// most dictations. That is the intended silent degradation, not a defect — it costs
/// one bitmask flag in the same call that already runs.
public struct SystemSpellCheckHintProvider: SpellCheckHintProviding {
    /// Advisory budget: more findings than this add prompt noise, not signal. The
    /// cap is applied per kind, inside the pure pipelines below so a unit test can
    /// pin it.
    private static let maxFindings = 15

    public init() {}

    public func findings(in transcript: String, ignoring vocabulary: [String]) -> SpellCheckFindings {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let checker = NSSpellChecker.shared
        checker.automaticallyIdentifiesLanguages = true
        let enabled = Set(checker.userPreferredLanguages)
        guard !enabled.isEmpty else { return .empty }

        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }
        checker.setIgnoredWords(vocabulary, inSpellDocumentWithTag: tag)

        var orthography: NSOrthography?
        var wordCount = 0
        let results = checker.check(
            transcript,
            range: NSRange(location: 0, length: transcript.utf16.count),
            types: NSTextCheckingResult.CheckingType.spelling.rawValue
                | NSTextCheckingResult.CheckingType.grammar.rawValue,
            options: nil,
            inSpellDocumentWithTag: tag,
            orthography: &orthography,
            wordCount: &wordCount
        )

        var spellingCandidates: [(finding: SpellFinding, language: String)] = []
        var grammarCandidates: [(finding: GrammarFinding, language: String)] = []
        for result in results {
            switch result.resultType {
            case .spelling:
                guard let tokenRange = Range(result.range, in: transcript) else { continue }
                let token = String(transcript[tokenRange])
                let language = checker.language(forWordRange: result.range, in: transcript, orthography: orthography)
                    ?? checker.language()
                let guesses = checker.guesses(
                    forWordRange: result.range,
                    in: transcript,
                    language: language,
                    inSpellDocumentWithTag: tag
                ) ?? []
                spellingCandidates.append((
                    finding: SpellFinding(token: token, guesses: Array(guesses.prefix(3))),
                    language: language
                ))
            case .grammar:
                // A grammar result spans the whole SENTENCE; the flagged fragment
                // lives in each detail. `language(forWordRange:)` returns nil for a
                // sentence-wide range, so the checker's current language is the only
                // signal available for the enabled-language gate.
                let language = checker.language(forWordRange: result.range, in: transcript, orthography: orthography)
                    ?? checker.language()
                for finding in Self.grammarFindings(from: result, in: transcript) {
                    grammarCandidates.append((finding: finding, language: language))
                }
            default:
                continue
            }
        }

        return SpellCheckFindings(
            spelling: Self.findingsWithEnabledLanguages(spellingCandidates, enabled: enabled),
            grammar: Self.findingsWithEnabledLanguages(grammarCandidates, enabled: enabled)
        )
    }

    /// The grammar findings carried by one sentence-wide result.
    ///
    /// The load-bearing detail: `NSGrammarRange` is relative to `result.range`, NOT to
    /// the transcript. Reading it as an absolute range silently slices the wrong
    /// substring (verified on macOS 26: an absolute read of the flagged "is" yields
    /// " i"), which would feed the model a corrupt fragment. A detail without a usable
    /// range or description is skipped rather than guessed at.
    public static func grammarFindings(
        from result: NSTextCheckingResult,
        in transcript: String
    ) -> [GrammarFinding] {
        (result.grammarDetails ?? []).compactMap { detail in
            guard let message = detail[NSGrammarUserDescription] as? String, !message.isEmpty else {
                return nil
            }
            let corrections = detail[NSGrammarCorrections] as? [String] ?? []
            let fragment = (detail[NSGrammarRange] as? NSRange).flatMap { relative -> String? in
                let absolute = NSRange(
                    location: result.range.location + relative.location,
                    length: relative.length
                )
                guard absolute.length > 0, let range = Range(absolute, in: transcript) else { return nil }
                return String(transcript[range])
            }
            // A description with no resolvable fragment is still useful advice, so it
            // survives with an empty fragment rather than being dropped.
            return GrammarFinding(fragment: fragment ?? "", message: message, corrections: corrections)
        }
    }

    /// Keeps only findings whose primary language subtag is enabled, capped at the
    /// advisory budget (earliest findings win). Pure and testable in isolation:
    /// this is the spec's language-mismatch degradation plus the 15-findings cap.
    /// Generic over the finding type so spelling and grammar share one gate and
    /// cannot drift apart.
    public static func findingsWithEnabledLanguages<Finding>(
        _ candidates: [(finding: Finding, language: String)],
        enabled: Set<String>
    ) -> [Finding] {
        let enabledPrimary = Set(enabled.map(primarySubtag))
        return candidates
            .filter { enabledPrimary.contains(primarySubtag($0.language)) }
            .prefix(maxFindings)
            .map(\.finding)
    }

    private static func primarySubtag(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code)).lowercased()
    }
}
