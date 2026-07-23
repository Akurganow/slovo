import Testing
import WhisperKit

@testable import SlovoCore

// Real WhisperKit token structure (live capture 2026-07-23); after this contract
// the cleaner and the paste path must never see `<|...|>` again. The two
// sensitivities are INDEPENDENT so neither defense masks the other: the compose
// sanitizer reddens on its own (decoder-agnostic — it feeds a raw fixture STRING
// straight to compose), and the decoder flag is pinned on its own (sanitizer-
// agnostic — it inspects only the decoder options).
@Suite("Token-clean transcript domain")
struct TokenCleanTranscriptTests {
    /// Clause 1, authoritative sanitizer. Sensitivity: bypass or remove the
    /// sanitizer at the compose chokepoint → RED, regardless of the decoder flag
    /// (this test never touches the decoder).
    @Test
    func composeStripsRealTokenStructures() {
        for fixture in RealWhisperTokenFixtures.all {
            let composed = WhisperKitTranscriptText.compose([fixture.raw])
            #expect(!composed.contains("<|"), "token leaked: \(composed)")
            #expect(composed.contains(fixture.expectedText), "content lost: \(composed)")
        }
    }

    /// Clause 1, spanning safety. Pins sanitize-AFTER-join: a `<|...|>` token
    /// straddling two parts (the join separator lands inside it) strips whole, so
    /// moving the sanitizer per-part before the join — which every other test
    /// survives — reddens here alone.
    @Test
    func composeStripsTokenStraddlingThePartBoundary() {
        #expect(WhisperKitTranscriptText.compose(["a <|0.", "00|> b"]) == "a b")
    }

    /// Clause 1, nested universality. Sensitivity: reverting the fixpoint to a
    /// single strip pass leaves the once-unwrapped outer form `<|a |>` behind → RED.
    @Test
    func strippingUnwindsNestedTokensToFixpoint() {
        #expect(WhisperKitTranscriptText.strippingSpecialTokens("x <|a<|b|>|> y") == "x y")
    }

    /// Clause 1, truncation universality. Sensitivity: removing the end-anchored
    /// strip lets a trailing unclosed fragment `<|start` survive to the output → RED.
    @Test
    func strippingRemovesTrailingUnclosedFragment() {
        #expect(WhisperKitTranscriptText.strippingSpecialTokens("hello <|start") == "hello")
    }

    /// Clause 1, pure-function unit. Sensitivity: drop the whitespace-collapse or
    /// the trim step and the debris left where inter-segment tokens were removed
    /// (leading spaces, a six-space gap between the two windows) → RED.
    @Test
    func strippingNormalizesWhitespace() {
        let out = WhisperKitTranscriptText.strippingSpecialTokens(
            RealWhisperTokenFixtures.twoSegments.raw)
        #expect(out == RealWhisperTokenFixtures.twoSegments.expectedText)
    }

    /// Clause 2, first-line decoder optimization. Sensitivity: drop
    /// `skipSpecialTokens: true` from `WhisperKitEngine.decodingOptions()` → RED,
    /// regardless of the sanitizer (this test inspects only the decoder options).
    @Test
    func decodingOptionsRequestSkippedSpecialTokens() {
        #expect(WhisperKitEngine.decodingOptions(language: .auto).skipSpecialTokens)
    }
}
