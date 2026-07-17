import Testing

import SlovoCore

// Translate mode SWAPS the plain "never translate" contract for a translation
// directive in the SAME single request. These substrings are the contract (authored
// independently in the lead's prompt spec, section 2). RED now: the pre-scaffolding
// builder ignores `translate`, so it still emits the PLAIN block — which contains
// "Never translate" and the plain examples and none of the translate directives.
@Suite("Cleanup prompt translate mode")
struct PromptBuilderTranslateTests {
    private static func translateBlock(style: WritingStyle, target: Language = .ru) -> String {
        PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "прибери мусор and clean up the code",
            config: CleanupConfig(
                writingStyle: style,
                language: .auto,
                translationTargetLanguage: target,
                translate: true
            ),
            context: PersonalizationContext(vocabulary: [])
        ).systemBlocks.joined(separator: "\n")
    }

    /// The translate block carries the translation directive, the fidelity thesis
    /// list, and the RU+EN intra-utterance fold — and drops the plain "never
    /// translate" contract and the plain examples.
    /// Stated sensitivity: each `#expect` reddens on the mutation named in the spec
    /// (drop the directive, hardcode/omit the target, drop a thesis line, leak the
    /// plain contract or a plain example).
    @Test
    func translateModeSwapsInATranslationDirective() {
        let block = Self.translateBlock(style: .casual)

        // The plain contract and plain examples must NOT leak into translate mode.
        #expect(!block.contains("Never translate"),
                "translate mode must not carry the plain 'Never translate' contract")
        #expect(!block.contains("<output>Прибери мусор.</output>"),
                "translate mode must not include the plain cleanup examples (they keep the input language)")

        // The target language is rendered as its English display name.
        #expect(block.contains("Russian"), "the resolved target display name must appear")
        #expect(block.contains("Translate it into Russian"), "translate mode must issue the translate directive")

        // The fidelity thesis list.
        #expect(block.contains("Preserve meaning over literalness"))
        #expect(block.contains("Add nothing and drop nothing"))
        #expect(block.contains("names, vocabulary terms, numbers"))
        // The RU+EN intra-utterance fold guardrail.
        #expect(block.contains("Fold code-switched Russian and English input into Russian"))
        #expect(block.contains("read naturally to a native Russian speaker"))

        // The shared, language-neutral artifact rules survive in translate mode.
        #expect(block.contains("Return only the"))

        // Register present.
        #expect(block.contains("casual"))
    }

    /// The WritingStyle governs the translation register too: the style word must
    /// appear and must differ across styles.
    /// Stated sensitivity: if translate ignores WritingStyle (hardcodes one register
    /// word), the formal block would still contain "casual" (or omit "formal") → RED.
    /// The `Translate it into Russian` anchor makes this RED now (the plain baseline
    /// block never contains it).
    @Test
    func translateRegisterFollowsWritingStyle() {
        let formal = Self.translateBlock(style: .formal)
        let casual = Self.translateBlock(style: .casual)

        // RED-now anchor: both are genuine translate blocks, absent in the baseline.
        #expect(formal.contains("Translate it into Russian"))
        #expect(casual.contains("Translate it into Russian"))

        // The register word tracks the configured style and differs across styles.
        #expect(formal.contains("formal"), "a formal translate block must carry the formal register")
        #expect(!formal.contains("casual"), "a formal translate block must not carry the casual register")
        #expect(casual.contains("casual"), "a casual translate block must carry the casual register")
    }

    /// F4 — the target language is rendered FROM config, not hardcoded: a second
    /// target (.en) proves the directive tracks the configured language. A hardcode of
    /// the target to a literal (e.g. "Russian") survives the `.ru`-only case but
    /// reddens here.
    /// Precise-directive form (not a bare `!contains("Russian")`): the shared fold
    /// clause legitimately reads "Russian and English input into <target>", so the
    /// word "Russian" appears for ANY target — the hardcode is caught by the
    /// target-specific DIRECTIVE strings instead.
    /// Stated sensitivity: hardcode the target to "Russian" (ignore config) →
    /// `Translate it into English` disappears / `Translate it into Russian` appears →
    /// RED.
    @Test
    func translateTargetIsRenderedFromConfigNotHardcoded() {
        let english = Self.translateBlock(style: .casual, target: .en)
        #expect(english.contains("English"), "the English target display name must appear")
        #expect(english.contains("Translate it into English"), "the directive must translate into the configured target")
        #expect(!english.contains("Translate it into Russian"), "an English target must not emit a Russian directive")
        #expect(english.contains("read naturally to a native English speaker"),
                "the naturalness thesis must name the configured target")

        // Cross-check the existing .ru target still issues the Russian directive, so
        // the two cases together pin that the directive follows config both ways.
        let russian = Self.translateBlock(style: .casual, target: .ru)
        #expect(russian.contains("Translate it into Russian"))
        #expect(!russian.contains("Translate it into English"))
    }
}
