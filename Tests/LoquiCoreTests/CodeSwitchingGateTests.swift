import Foundation
import Testing

import LoquiCore

// Epic 05 — AC-1 (CI-half, gate logic): the I3 code-switching gate passes a
// transcript ONLY when BOTH a Cyrillic run AND every required Latin anchor
// survive; a collapsed one-alphabet transcript FAILS. ≥M-of-N aggregate bar.
//
// Contract under test (implementer builds the PRODUCT gate in
// `Sources/LoquiCore/ASR/CodeSwitchingGate.swift` per plan §3; CURRENTLY
// supplied by the WRONG-ON-PURPOSE `_RedScaffold_AsrBakeoff.swift` stub that
// requires ONLY Cyrillic — so the collapsed transcript wrongly passes → RED).
//
// FIXTURE ANCHOR RULE (P1): the Latin anchors are NEUTRAL PUBLIC tech terms
// (`PR`, `GitHub`) — NEVER the organization name, a product private term, or a private contact
// name (those live only in the gitignored seed).
@Suite("Epic 05 AC-1 code-switching gate")
struct CodeSwitchingGateTests {
    private static let expectation = ClipExpectation(
        clipId: "clip-1", requiredLatinTerms: ["PR", "GitHub"]
    )

    /// A genuinely code-switched transcript (Cyrillic + every Latin anchor)
    /// passes. Guards against an over-strict gate that rejects valid mixing.
    @Test
    func codeSwitchedTranscriptPasses() {
        let transcript = "запушь PR в GitHub репозиторий"
        #expect(CodeSwitchingGate.clipPasses(transcript: transcript, expectation: Self.expectation),
                "a Cyrillic + PR + GitHub transcript must pass the gate")
    }

    /// THE §19.3 FALSE-GREEN GUARD: a collapsed one-alphabet transcript (the
    /// Latin anchors transliterated into Cyrillic — `пиар`/`гитхаб`) must FAIL.
    /// This reproduces the FluidAudio `TokenLanguageFilter`-collapse failure mode
    /// without FluidAudio.
    /// Stated sensitivity: mutate `clipPasses` to require ONLY Cyrillic (drop the
    /// required-Latin check) → this collapsed transcript wrongly passes → RED.
    /// (Symmetrically, requiring ONLY the Latin terms would wrongly pass a
    /// Latin-only transcript — covered by `latinOnlyTranscriptFails`.) The
    /// scaffold requires only Cyrillic, so this test is RED now.
    @Test
    func collapsedTranscriptFails() {
        let collapsed = "запушь пиар в гитхаб репозиторий"
        #expect(!CodeSwitchingGate.clipPasses(transcript: collapsed, expectation: Self.expectation),
                "a collapsed one-alphabet transcript (no surviving Latin anchors) must FAIL the gate")
    }

    /// The other half of "requires BOTH scripts": a Latin-only transcript (no
    /// Cyrillic run) must also FAIL. Guards the symmetric mutation (drop the
    /// Cyrillic-presence check).
    @Test
    func latinOnlyTranscriptFails() {
        let latinOnly = "push the PR to the GitHub repository"
        #expect(!CodeSwitchingGate.clipPasses(transcript: latinOnly, expectation: Self.expectation),
                "a Latin-only transcript (no Cyrillic run) must FAIL the gate")
    }

    /// Aggregate ≥2-of-3: three clips where only ONE passes does NOT meet the bar.
    @Test
    func belowBarWhenTooFewClipsPass() {
        let scores = [
            ClipScore(clipId: "a", passed: true),
            ClipScore(clipId: "b", passed: false),
            ClipScore(clipId: "c", passed: false),
        ]
        #expect(!CodeSwitchingGate.meetsBar(scores, bar: PassBar(minClipsPassing: 2)),
                "1-of-3 passing must NOT meet a ≥2-of-3 bar")
    }

    /// Aggregate ≥2-of-3: all three passing meets the bar (guards an always-false
    /// aggregate).
    @Test
    func meetsBarWhenEnoughClipsPass() {
        let scores = [
            ClipScore(clipId: "a", passed: true),
            ClipScore(clipId: "b", passed: true),
            ClipScore(clipId: "c", passed: true),
        ]
        #expect(CodeSwitchingGate.meetsBar(scores, bar: PassBar(minClipsPassing: 2)),
                "3-of-3 passing must meet a ≥2-of-3 bar")
    }

    // MARK: - Dalek coverage tests (green on correct code; RED on the named mutation)

    /// `clipPasses` requires EVERY required Latin anchor, not just any one. A
    /// transcript with Cyrillic + `PR` but MISSING `GitHub`, expecting both, must
    /// FAIL — a partial-anchor survival is not script-mixing survival.
    /// Stated sensitivity: mutate production `requiredLatinTerms.allSatisfy { … }`
    /// → `.contains(where:) { … }` (require ANY one) → this partial-anchor
    /// transcript wrongly passes → RED.
    @Test
    func clipFailsWhenOnlySomeRequiredLatinAnchorsSurvive() {
        // Has Cyrillic + "PR", but "GitHub" was lost (transliterated to «гитхаб»).
        let partial = "запушь PR в гитхаб репозиторий"
        #expect(!CodeSwitchingGate.clipPasses(transcript: partial, expectation: Self.expectation),
                "a transcript missing one required Latin anchor (GitHub) must FAIL, even though PR survives")
    }

    /// `meetsBar` is inclusive at the boundary: with `minClipsPassing == 2` and
    /// EXACTLY 2 of 3 clips passing, the bar is met.
    /// Stated sensitivity: mutate production `>=` → `>` → exactly-2-of-bar-2
    /// wrongly fails → RED.
    @Test
    func meetsBarAtExactBoundary() {
        let scores = [
            ClipScore(clipId: "a", passed: true),
            ClipScore(clipId: "b", passed: true),
            ClipScore(clipId: "c", passed: false),
        ]
        #expect(CodeSwitchingGate.meetsBar(scores, bar: PassBar(minClipsPassing: 2)),
                "exactly 2 passing must meet a ≥2 bar (inclusive boundary)")
    }
}
