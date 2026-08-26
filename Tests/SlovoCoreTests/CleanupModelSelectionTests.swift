import Testing
import SlovoCore

@Suite("CleanupModelSelection (spec rev 3 §4 K2)")
struct CleanupModelSelectionTests {
    private let catalog = CleanupModelCatalog.options
    private let defaultId = Config.defaultOpenRouterModel  // openai/gpt-5.6-luna
    private let haiku = "anthropic/claude-haiku-4.5"
    private let gemini = "google/gemini-3.1-flash-lite"

    private func derive(_ preference: String, _ scope: CleanupModelScope) -> CleanupModelSelection.Result {
        CleanupModelSelection.derive(preference: preference, catalog: catalog, scope: scope)
    }

    // K2 row 1: unknown scope is today's exact behavior (K5).
    @Test func unknownScopeIsFailOpen() {
        let r = derive(defaultId, .unknown)
        #expect(r.options == catalog)
        #expect(r.customRow == nil)
        #expect(r.effective == defaultId)
        #expect(r.note == nil)
    }

    // K2 row 1 with a custom preference: the custom row survives.
    @Test func unknownScopeKeepsCustomRow() {
        let r = derive("custom/x", .unknown)
        #expect(r.options == catalog)
        #expect(r.customRow == CleanupModelOption(id: "custom/x", displayName: "custom/x"))
        #expect(r.effective == "custom/x")
        #expect(r.note == nil)
    }

    // K2 row 2: empty and catalog-disjoint scopes are degenerate → treated as .unknown.
    // Sensitivity: fail closed (empty options) instead → RED.
    @Test func degenerateScopeFailsOpen() {
        for scope in [CleanupModelScope.known([]), .known(["no/overlap"])] {
            let r = derive("custom/x", scope)
            #expect(r.options == catalog)
            #expect(r.customRow?.id == "custom/x")
            #expect(r.effective == "custom/x")
            #expect(r.note == nil)
        }
    }

    // K2 row 3: catalog preference in scope — untouched, options filtered in catalog order.
    @Test func catalogPreferenceInScope() {
        let r = derive(gemini, .known([defaultId, gemini]))
        #expect(r.options.map(\.id) == [defaultId, gemini])
        #expect(r.customRow == nil)
        #expect(r.effective == gemini)
        #expect(r.note == nil)
    }

    // K2 row 4: catalog preference out of scope → default first. The note MUST carry
    // the original preference (K1's behavioral half: derivation, not rewriting).
    @Test func catalogPreferenceOutOfScopeSubstitutesDefault() {
        let r = derive(haiku, .known([defaultId, gemini]))
        #expect(r.effective == defaultId)
        #expect(r.note == .substitution(preferred: haiku, effective: defaultId))
        #expect(r.options.map(\.id) == [defaultId, gemini])
    }

    // K2 row 4, default also out of scope → FIRST catalog-declaration-order id in
    // scope. Sensitivity: the options-order assertion pins catalog iteration; a
    // set-iteration mutant reddens it on most runs (Set order is per-process
    // randomized — probabilistic, stated honestly), and any such mutant also
    // changes `options`, which IS pinned deterministically.
    @Test func fallbackOrderIsCatalogDeclarationOrder() {
        let r = derive(defaultId, .known([gemini, "minimax/minimax-m3"]))
        #expect(r.effective == gemini)
        #expect(r.note == .substitution(preferred: defaultId, effective: gemini))
        #expect(r.options.map(\.id) == [gemini, "minimax/minimax-m3"])
    }

    // K2 row 5: custom id in scope.
    @Test func customPreferenceInScope() {
        let r = derive("custom/x", .known([defaultId, "custom/x"]))
        #expect(r.effective == "custom/x")
        #expect(r.customRow?.id == "custom/x")
        #expect(r.note == nil)
    }

    // K2 row 6: custom id out of scope stays EFFECTIVE (D3, intent primacy) with the warning.
    // Sensitivity: swap the custom/catalog asymmetry (substitute custom ids too) → RED.
    @Test func customPreferenceOutOfScopeStaysEffectiveWithWarning() {
        let r = derive("custom/x", .known([defaultId]))
        #expect(r.effective == "custom/x")
        #expect(r.note == .customOutsideScope)
        #expect(r.options.map(\.id) == [defaultId])
        #expect(r.customRow?.id == "custom/x")
    }
}
