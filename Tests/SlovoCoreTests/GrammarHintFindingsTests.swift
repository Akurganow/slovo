import AppKit
import Foundation
import Testing

import SlovoCore

@Suite("Grammar hint findings")
struct GrammarHintFindingsTests {
    /// Builds a real grammar `NSTextCheckingResult` for `text`, or nil when this Mac
    /// produced none (grammar rules are English-only, so a machine without English
    /// spelling enabled legitimately yields nothing).
    private static func grammarResult(for text: String) -> NSTextCheckingResult? {
        let checker = NSSpellChecker.shared
        checker.automaticallyIdentifiesLanguages = true
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }
        var orthography: NSOrthography?
        var wordCount = 0
        let results = checker.check(
            text,
            range: NSRange(location: 0, length: text.utf16.count),
            types: NSTextCheckingResult.CheckingType.spelling.rawValue
                | NSTextCheckingResult.CheckingType.grammar.rawValue,
            options: nil,
            inSpellDocumentWithTag: tag,
            orthography: &orthography,
            wordCount: &wordCount
        )
        return results.first { $0.resultType == .grammar }
    }

    private static var runsLocally: Bool {
        ProcessInfo.processInfo.environment["CI"] == nil
    }

    /// THE regression this whole seam turns on. A grammar result spans the entire
    /// sentence while `NSGrammarRange` is relative to that sentence, so a leading
    /// clean sentence pushes the result's start away from 0 and the two readings
    /// diverge.
    ///
    /// Stated sensitivity: reading the detail range as an absolute transcript offset
    /// (dropping `result.range.location +`) slices " i" instead of "is" — this turns
    /// red. Verified against the real checker on macOS 26.
    @Test(.enabled(if: runsLocally, "real NSSpellChecker; skipped on shared CI"))
    func grammarFragmentIsResolvedRelativeToTheSentence() throws {
        let transcript = "Everything is fine here. The datas is wrong."
        guard let result = Self.grammarResult(for: transcript) else { return }
        try #require(result.range.location > 0, "the padding sentence must push the result off offset 0")

        let findings = SystemSpellCheckHintProvider.grammarFindings(from: result, in: transcript)

        let fragments: [String] = findings.map(\.fragment)
        #expect(!fragments.contains(" i"),
                "a fragment sliced with an absolute offset means the detail range was misread; got \(fragments)")
        for finding in findings where !finding.fragment.isEmpty {
            let fragment: String = finding.fragment
            #expect(transcript.contains(fragment),
                    "every fragment must be real transcript text; got '\(fragment)'")
        }
    }

    /// Stated sensitivity: dropping the `NSGrammarUserDescription` guard admits
    /// message-less details, so a finding with an empty message survives → red. The
    /// message is the entire value of a grammar hint: "is" alone advises nothing.
    @Test(.enabled(if: runsLocally, "real NSSpellChecker; skipped on shared CI"))
    func everyGrammarFindingCarriesAMessage() {
        let transcript = "He go to the store yesterday. The datas is wrong."
        guard let result = Self.grammarResult(for: transcript) else { return }

        let findings = SystemSpellCheckHintProvider.grammarFindings(from: result, in: transcript)

        for finding in findings {
            #expect(!finding.message.isEmpty, "a grammar finding without its explanation is not a hint")
        }
    }

    /// Stated sensitivity: the shared language gate must cap grammar findings exactly
    /// as it caps spelling ones; a grammar path that skips the cap lets all 20 through
    /// → red.
    @Test
    func grammarFindingsAreCappedAtFifteen() {
        let candidates = (0..<20).map { index in
            (
                finding: GrammarFinding(fragment: "frag\(index)", message: "msg\(index)", corrections: []),
                language: "en"
            )
        }

        let gated = SystemSpellCheckHintProvider.findingsWithEnabledLanguages(candidates, enabled: ["en-US"])

        #expect(gated.count == 15, "the advisory grammar pass is capped at 15 findings; got \(gated.count)")
        #expect(gated.first == candidates.first?.finding, "the cap must keep the EARLIEST findings")
    }

    /// Stated sensitivity: removing the enabled-language filter from the grammar path
    /// lets a finding whose language is disabled survive → red.
    @Test
    func grammarFindingsFromDisabledLanguagesAreDropped() {
        let english = GrammarFinding(fragment: "is", message: "may not agree", corrections: ["are"])
        let german = GrammarFinding(fragment: "ist", message: "stimmt nicht", corrections: [])

        let gated = SystemSpellCheckHintProvider.findingsWithEnabledLanguages(
            [(finding: english, language: "en"), (finding: german, language: "de")],
            enabled: ["en-US"]
        )

        #expect(gated == [english], "only findings whose primary language is enabled survive; got \(gated)")
    }

    /// The end-to-end proof on the real API: with English enabled, a sentence with a
    /// subject-verb disagreement produces at least one grammar finding carrying both
    /// a message and a suggested correction.
    ///
    /// Stated sensitivity: a provider that never passes `.grammar` in its checking
    /// types (the pre-change behavior) returns no grammar findings at all → red.
    @Test(.enabled(if: runsLocally, "real NSSpellChecker; skipped on shared CI"))
    func realProviderReturnsGrammarFindingsWhenEnglishEnabled() {
        let englishEnabled = NSSpellChecker.shared.userPreferredLanguages
            .contains { $0.lowercased().hasPrefix("en") }
        let provider = SystemSpellCheckHintProvider()

        let findings = provider.findings(in: "The datas is wrong.", ignoring: [])

        #expect(!findings.grammar.isEmpty || !englishEnabled,
                "with English enabled the on-device checker must flag the disagreement; got \(findings.grammar)")
        for finding in findings.grammar {
            #expect(!finding.message.isEmpty)
        }
    }
}
