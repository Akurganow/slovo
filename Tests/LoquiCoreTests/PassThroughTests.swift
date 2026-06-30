import Foundation
import Testing

import LoquiCore

// Epic 06 — AC-3: `PassThrough` returns its input byte-identical (the terminal
// fallback that never loses the user's words).
//
// Contract under test (implementer builds `Sources/LoquiCore/Cleaner/PassThrough.swift`
// per plan §4; CURRENTLY the WRONG-ON-PURPOSE `_RedScaffold_Cleaner.swift` stub
// UPPERCASES → RED).
@Suite("Epic 06 AC-3 PassThrough")
struct PassThroughTests {
    /// Input chosen to be filler-laden text a real cleaner WOULD change (so the
    /// test is non-tautological: a no-op cleaner and a real cleaner differ here).
    /// Stated sensitivity: make PassThrough uppercase / trim / mutate → output ≠
    /// input → RED. (The scaffold uppercases → RED now.)
    @Test
    func returnsInputUnchanged() async throws {
        let input = "Um, so like, запушь the PR, you know"
        let config = CleanupConfig(writingStyle: .formal, language: .auto)
        let context = PersonalizationContext(vocabulary: [])

        let output = try await PassThrough().clean(input, config: config, context: context)

        #expect(output == input, "PassThrough must return the input byte-identical, got \(output)")
    }
}
