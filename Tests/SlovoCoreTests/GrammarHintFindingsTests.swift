import AppKit
import Foundation
import Testing

import SlovoCore

@Suite("Grammar hint findings")
struct GrammarHintFindingsTests {
    /// A grammar result spans its whole sentence, and `NSGrammarRange` is relative to
    /// that sentence. A leading clean sentence pushes the result off offset 0, so an
    /// absolute reading slices different text.
    ///
    /// Stated sensitivity: reading the detail range as an absolute transcript offset
    /// (dropping `result.range.location +`) slices " i" instead of "is" → RED.
    @Test
    func grammarFragmentIsResolvedRelativeToTheSentence() {
        let transcript = "Everything is fine here. The datas is wrong."
        let result = NSTextCheckingResult.grammarCheckingResult(
            range: NSRange(location: 25, length: 19),
            details: [
                [
                    NSGrammarRange: NSValue(range: NSRange(location: 10, length: 2)),
                    NSGrammarUserDescription: "The word 'is' may not agree with the rest of the sentence.",
                    NSGrammarCorrections: ["are"],
                ],
            ]
        )

        let findings = SystemSpellCheckHintProvider.grammarFindings(from: result, in: transcript)

        #expect(findings.map(\.fragment) == ["is"])
    }

    /// The message is the whole value of a grammar hint: "is" alone advises nothing.
    ///
    /// Stated sensitivity: dropping the `NSGrammarUserDescription` guard, or only its
    /// empty-string check, admits a detail with no message → RED.
    @Test
    func grammarDetailWithoutAMessageIsDropped() {
        let transcript = "The datas is wrong."
        let fragment = NSValue(range: NSRange(location: 10, length: 2))
        let message = "The word 'is' may not agree with the rest of the sentence."
        let result = NSTextCheckingResult.grammarCheckingResult(
            range: NSRange(location: 0, length: 19),
            details: [
                [NSGrammarRange: fragment, NSGrammarCorrections: ["are"]],
                [NSGrammarRange: fragment, NSGrammarUserDescription: "", NSGrammarCorrections: ["are"]],
                [NSGrammarRange: fragment, NSGrammarUserDescription: message, NSGrammarCorrections: ["are"]],
            ]
        )

        let findings = SystemSpellCheckHintProvider.grammarFindings(from: result, in: transcript)

        #expect(findings.map(\.message) == [message])
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
}
