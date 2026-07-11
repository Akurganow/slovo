import AppKit

/// Real `SpellCheckHintProviding` backed by the OS's on-device `NSSpellChecker`.
/// It flags possibly-misspelled tokens with top-3 guesses over the raw transcript,
/// ignoring the user's vocabulary (via `setIgnoredWords`, never `learnWord`, which is
/// device-global and persistent). Findings whose language is not enabled in System
/// Settings are dropped (graceful degradation). Any failure yields [] — the pass is
/// non-fatal by contract.
public struct SystemSpellCheckHintProvider: SpellCheckHintProviding {
    /// Advisory budget: more findings than this add prompt noise, not signal. The
    /// cap is applied inside the pure pipeline below so a unit test can pin it.
    private static let maxFindings = 15

    public init() {}

    public func findings(in transcript: String, ignoring vocabulary: [String]) -> [SpellFinding] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let checker = NSSpellChecker.shared
        checker.automaticallyIdentifiesLanguages = true
        let enabled = Set(checker.userPreferredLanguages)
        guard !enabled.isEmpty else { return [] }

        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }
        checker.setIgnoredWords(vocabulary, inSpellDocumentWithTag: tag)

        var orthography: NSOrthography?
        var wordCount = 0
        let results = checker.check(
            transcript,
            range: NSRange(location: 0, length: transcript.utf16.count),
            types: NSTextCheckingResult.CheckingType.spelling.rawValue,
            options: nil,
            inSpellDocumentWithTag: tag,
            orthography: &orthography,
            wordCount: &wordCount
        )

        var candidates: [(finding: SpellFinding, language: String)] = []
        for result in results where result.resultType == .spelling {
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
            candidates.append((
                finding: SpellFinding(token: token, guesses: Array(guesses.prefix(3))),
                language: language
            ))
        }

        return Self.findingsWithEnabledLanguages(candidates, enabled: enabled)
    }

    /// Keeps only findings whose primary language subtag is enabled, capped at the
    /// advisory budget (earliest findings win). Pure and testable in isolation:
    /// this is the spec's language-mismatch degradation plus the 15-findings cap.
    public static func findingsWithEnabledLanguages(
        _ candidates: [(finding: SpellFinding, language: String)],
        enabled: Set<String>
    ) -> [SpellFinding] {
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
