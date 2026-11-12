import Testing

import SlovoCore

// Translate mode SWAPS the plain "never translate" contract for a translation
// directive in the SAME single request. These substrings are the contract, authored
// independently from the builder so they pin drift, not a tautology.
@Suite("Cleanup prompt translate mode")
struct PromptBuilderTranslateTests {
    private static func translateSystemText(
        style: WritingStyle,
        target: Language = .ru,
        vocabulary: [Term] = []
    ) -> String {
        PromptBuilder().buildPrompt(
            raw: "прибери мусор and clean up the code",
            config: CleanupConfig(
                writingStyle: style,
                language: .auto,
                translationTargetLanguage: target,
                translate: true
            ),
            context: PersonalizationContext(vocabulary: vocabulary)
        ).systemBlocks.joined(separator: "\n")
    }

    /// The Russian-target directive and code-switch fold, and the absence of the
    /// bundled plain examples. The target-independent rules are pinned by the
    /// translate golden, which renders Spanish with an empty catalog.
    /// Stated sensitivity: drop the directive, hardcode/omit the target, drop the
    /// Russian code-switch fold, or leak a bundled plain example → RED.
    @Test
    func translateModeSwapsInATranslationDirective() {
        let block = Self.translateSystemText(style: .casual)

        // The plain examples must NOT leak into translate mode.
        #expect(!block.contains("<output>1, 2, 3, проверяем, 1, 2, 3.</output>"),
                "translate mode must not include the plain cleanup examples (they keep the input language)")

        // The target language is rendered as its English display name.
        #expect(block.contains("Translate the transcript into Russian"),
                "translate mode must issue the translate directive")
        #expect(block.contains("Write the output entirely in Russian"),
                "the whole-output language contract must name the target")

        // The intra-utterance code-switch fold guardrail.
        #expect(block.contains("Fold code-switched input into Russian"))
        #expect(block.contains("read naturally to a native Russian speaker"))
    }

    /// The vocabulary block is mode-independent: a translated dictation must correct a
    /// mis-recognized protected term exactly as a cleaned one does, and must not paste
    /// the recorded meaning into the translation.
    /// Stated sensitivity: gate the vocabulary block on plain mode → the `<vocabulary>`
    /// and entry expectations redden; drop any guard line → its expectation reddens.
    @Test
    func translateModeCarriesTheVocabularyBlockWithItsGuards() {
        let block = Self.translateSystemText(
            style: .casual,
            vocabulary: [Term(term: "RCV", expansion: "RingCentral Video", lang: .en, weight: 9)]
        )

        #expect(block.contains("<vocabulary>"))
        #expect(block.contains("in parentheses where known: RCV (RingCentral Video)"))
        #expect(block.contains(PromptBuilderFixtures.parentheticalGuardLine),
                "a translated output must not absorb the recorded meaning of a protected term")
        #expect(block.contains("replace it with the spelling given here."))
        #expect(block.contains("Never introduce a term from this list that the speaker did not say."))
    }

    /// The WritingStyle governs the translation register too: the style word must
    /// appear and must differ across styles.
    /// Stated sensitivity: if translate ignores WritingStyle (hardcodes one register
    /// word), the formal block would still contain "casual" (or omit "formal") → RED.
    /// The `Translate the transcript into Russian` anchor confirms these are genuine
    /// translate blocks (the plain baseline block never contains it).
    @Test
    func translateRegisterFollowsWritingStyle() {
        let formal = Self.translateSystemText(style: .formal)
        let casual = Self.translateSystemText(style: .casual)

        // Anchor: both are genuine translate blocks, absent in the baseline.
        #expect(formal.contains("Translate the transcript into Russian"))
        #expect(casual.contains("Translate the transcript into Russian"))

        // The register word tracks the configured style and differs across styles.
        #expect(formal.contains("formal"), "a formal translate block must carry the formal register")
        #expect(!formal.contains("casual"), "a formal translate block must not carry the casual register")
        #expect(casual.contains("casual"), "a casual translate block must carry the casual register")
    }

    /// F4 — the target language is rendered FROM config, not hardcoded: a second
    /// target (.en) proves the directive tracks the configured language. A hardcode of
    /// the target to a literal (e.g. "Russian") survives the `.ru`-only case but
    /// reddens here.
    /// Stated sensitivity: hardcode the target to "Russian" (ignore config) →
    /// `Translate the transcript into English` disappears / the Russian directive
    /// appears → RED.
    @Test
    func translateTargetIsRenderedFromConfigNotHardcoded() {
        let english = Self.translateSystemText(style: .casual, target: .en)
        #expect(english.contains("Translate the transcript into English"),
                "the directive must translate into the configured target")
        #expect(!english.contains("Translate the transcript into Russian"),
                "an English target must not emit a Russian directive")
        #expect(english.contains("read naturally to a native English speaker"),
                "the naturalness thesis must name the configured target")

        // Cross-check the existing .ru target still issues the Russian directive, so
        // the two cases together pin that the directive follows config both ways.
        let russian = Self.translateSystemText(style: .casual, target: .ru)
        #expect(russian.contains("Translate the transcript into Russian"))
        #expect(!russian.contains("Translate the transcript into English"))
    }

    /// Per-target example gating: a verified core target (en) carries its own
    /// examples block; a target outside the verified core carries NO examples at
    /// all — its prompt stays example-free exactly like today.
    /// Stated sensitivity: keying the gate on the display name, dropping the gate
    /// (all targets get the en block), or emptying the en block each redden one
    /// of these expectations.
    @Test
    func translateExamplesAreGatedOnTheVerifiedTargetCode() {
        let english = Self.translateSystemText(style: .casual, target: .en)
        #expect(english.contains("<examples>"), "the verified en target must carry its examples block")
        #expect(english.contains("feature/auth"), "the en block must carry the code-switch commit example")

        // A target outside the verified core carries ONLY the language-neutral
        // shared examples (math notation) — never another language's pairs.
        let swahili = Self.translateSystemText(style: .casual, target: Language(rawValue: "sw"))
        #expect(swahili.contains("<output>log₂(3)</output>"),
                "every target must carry the shared formula examples")
        #expect(!swahili.contains("feature/auth"),
                "a target outside the verified core must not inherit another language's pairs")
    }

    /// The input wrapping is built at one shared site for both modes; this pins the
    /// translate mode's user message to the same <transcript> format as plain mode.
    /// Stated sensitivity: gating the wrapping on plain mode reddens here.
    @Test
    func translateInputUsesTheTranscriptTags() {
        let raw = "прибери мусор and clean up the code"
        let prompt = PromptBuilder().buildPrompt(
            raw: raw,
            config: CleanupConfig(
                writingStyle: .casual,
                language: .auto,
                translationTargetLanguage: .ru,
                translate: true
            ),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(prompt.input == "<transcript>\(raw)</transcript>",
                "translate mode shares the single input-wrapping site with plain mode")
    }
}
