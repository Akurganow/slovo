import Foundation
import Testing

// AppComposition is in the executable "slovo" target, which no test target imports
// (Package.swift, SlovoCoreTests dependencies), and Dependencies defaults both hint
// seams to nil, so a composition that omits one still compiles; the source is the only
// place the choice shows.
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
