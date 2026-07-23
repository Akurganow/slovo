/// Real WhisperKit token structures for the token-clean text domain contract.
///
/// Provenance (realistic-fixture rule, spec 2026-07-23): the token STRUCTURE
/// below reproduces genuine WhisperKit segment output observed in the live
/// capture on 2026-07-23 (the incident dictations that surfaced defects A/C/E —
/// raw `<|...|>` tokens reaching the paste path and the cleaner). WhisperKit
/// emits a per-segment header `<|startoftranscript|><|lang|><|transcribe|>`
/// followed by a `<|start|>`-timestamp, the decoded text, and a `<|end|>`-
/// timestamp; a multi-window utterance concatenates several such segments. The
/// text CONTENT here is neutral placeholder speech ("проверяем раз два три",
/// "первый сегмент", "второй сегмент") — no private transcript ever lands in a
/// fixture. Hand-written clean fixtures are insufficient for ASR-facing
/// behavior; only the real token structure catches the audit-green/live-broken
/// failure this contract exists to prevent.
///
/// Capture procedure (to refresh): run a dictation with the WhisperKit decoder's
/// `skipSpecialTokens` OFF and log the raw `TranscriptionResult.text` per
/// segment; copy the surface form verbatim, then substitute neutral words for
/// the spoken content.
enum RealWhisperTokenFixtures {
    /// One raw WhisperKit segment/utterance string and the token-free text a
    /// correct sanitizer must preserve out of it.
    struct Fixture {
        let raw: String
        let expectedText: String
    }

    /// Single-window segment: header, start timestamp, text, end timestamp.
    static let singleSegment = Fixture(
        raw: "<|startoftranscript|><|ru|><|transcribe|><|0.00|> проверяем раз два три<|1.90|>",
        expectedText: "проверяем раз два три"
    )

    /// Two windows concatenated — each carries its own full header, the shape
    /// that reaches the stitched confirmed-prefix path.
    static let twoSegments = Fixture(
        raw: "<|startoftranscript|><|ru|><|transcribe|><|0.00|> первый сегмент<|6.82|>"
            + "<|startoftranscript|><|ru|><|transcribe|><|0.00|> второй сегмент<|4.00|>",
        expectedText: "первый сегмент второй сегмент"
    )

    static let all = [singleSegment, twoSegments]
}
