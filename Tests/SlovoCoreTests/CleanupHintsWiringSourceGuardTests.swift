import Foundation
import Testing

// No test target depends on the `slovo` executable, and `Dependencies` defaults
// both hint seams to nil, so a composition that omits one still compiles; the source is
// the only place the choice shows.
@Suite("Cleanup hints wiring source guard")
struct CleanupHintsWiringSourceGuardTests {
    /// Stated sensitivity: dropping either real hint provider from the Dependencies
    /// construction (so production dictation gathers no hints) turns this red.
    @Test
    func compositionWiresBothHintProviders() throws {
        let composition = try SourceText.code("Sources/slovo/AppComposition.swift")

        #expect(composition.contains("inputSourceLanguage: SystemInputSourceLanguageReader()"))
        #expect(composition.contains("spellCheckHints: SystemSpellCheckHintProvider()"))
    }
}
