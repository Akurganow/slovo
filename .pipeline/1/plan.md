# Plan: decode a hold of one second or less

## Steps

- [`Sources/SlovoCore/ASR/WhisperKitTailFinalization.swift#L210-L215`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitTailFinalization.swift#L210-L215): add `singleWindowSampleCount: Int?` to `Plan.decode`.
- [`#L233-L267`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitTailFinalization.swift#L233-L267) `plan`: set the field by the whole-recording gate above, with a comment explaining why the gate reads the total and not the tail.
- [`#L269-L288`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitTailFinalization.swift#L269-L288) `resolve`: the decode closure becomes `(Float, Int?) async throws -> String`. Rewrite the comment at L280-L282: the fallback covers a short tail after a boundary, and a whole short hold is decoded in its one window.
- [`Sources/SlovoCore/ASR/WhisperKitLiveSession.swift#L348-L365`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitLiveSession.swift#L348-L365) (`finish()` resolve closure), [`#L384-L413`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitLiveSession.swift#L384-L413) (`decodeTail`) and [`#L415-L436`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitLiveSession.swift#L415-L436) (`tailDecodingOptions`): thread the value through and set `windowClipTime` as above. Update the doc comment at L415-L420. Leave the comment at [`#L328-L330`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitLiveSession.swift#L328-L330) true by adding "unless the plan opens its single window".
- [`Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L119-L132`][lt119]: sharpen `subsecondUtteranceIsFinalizedFromTheBeginning` into the first test below. It is the test that should have caught the bug, and its plan-only equality is **deleted** in the same change. Add `import WhisperKit` for `DecodingOptions`, plus one private fake described below.
- The same file: add `singleWindowSampleCount: nil` to the `.decode` literals at [L71](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L71), [L96](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L96), [L219](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L219) and [L235](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L235), and a second closure parameter at L220 and L236. Extend the source-guard anchors at [L492-L505][lt492] by the new argument line. Without that, `finish()` could hardcode `nil` and no test would see it, because these anchors are prefix matches.
- [`Tests/SlovoCoreTests/WhisperKitBiasPromptBuilderTests.swift#L210-L215`][bp210] and [`#L238-L240`][bp238]: pass `singleWindowSampleCount: nil`.
- [`docs/references/asr-whisperkit.md#L277-L279`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/docs/references/asr-whisperkit.md#L277-L279): say that a hold of one second or less is never seen by the live loop and is decoded at key-up in exactly one window. Say that the SDK's 1 s end-of-window clip is lifted only there, and why.
- [`docs/architecture.md#L64-L78`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/docs/architecture.md#L64-L78): add one sentence to the `WhisperKitTranscriber` bullet saying the same.

## Tests first

Cynefin: **Complicated**. The failure is invisible except as a no-speech outcome, and it sits where three bounds meet: the SDK window loop, the SDK seek rule and Slovo's gate. Full RED→GREEN applies.

Both tests use one private fake of the SDK seam, not of the product. It takes the resolve closure's `(fromSeconds, singleWindowSampleCount)`, derives options through the real `WhisperKitLiveSession.tailDecodingOptions`, starts seek at the clip start `Int(round(fromSeconds × 16 000))` (SDK `Extensions+Internal.swift:113`, `TranscribeTask.swift:108`) and applies the SDK window bound `seek < N − Int(windowClipTime × 16 000)` to a scripted seek sequence: the clip start, then the seek that a double-timestamp ending leaves (clip start + the scripted last timestamp). For each window the bound admits, it returns scripted text. Both tests assert the **composed transcript** out of `plan` → `resolve`.

1. **`subsecondHoldDecodesItsOneWindowIntoTheTranscript`** (the sharpened L119-L132 test). The inputs are 12 000 samples, tail 12 000, minimum 16 000, voiced energy `[0.4, 0.4]` and the default state. The fake answers "да" at seek 0 and "Продолжение следует" at seek 9 600. The test expects `"да"`. Each of these mutations turns it red:
   - Revert the gate to always `nil`, which is today's behaviour: zero windows, `""`.
   - Drop the `windowClipTime` assignment: zero windows, `""`.
   - Use `windowClipTime = 0`: the second window opens, giving `"да Продолжение следует"`.
2. **`shortTailAfterABoundaryWithoutLiveTextKeepsTheEndOfWindowClip`** (new). No test feeds this input today; L55-L73 carries live text. The inputs are 40 000 samples, tail 8 000, and a state of confirmed `"привет мир"`, boundary 2.0, processed 32 000, unconfirmed `""`. The fake answers "Продолжение следует" for any window it opens. The test expects `"привет мир"`. It turns red when the gate passes the tail's sample count instead of the whole recording's (padding 7 999, so seek 32 000 < 40 000 − 7 999 opens a window and appends the hallucination), or when the clip is set to 0 on any gate that selects this input. A widened gate that keeps the whole-recording value is equivalent and cannot turn it red: its padding of 39 999 admits no seek ≥ 2.

The silent short hold is already held by `quietHoldWithAudioIsSilentAndVoicedHoldIsNot` and `emptyEnergiesAreSilent` (`WhisperKitSilenceGateTests.swift`); `.silent` precedes `.decode` in `plan`, so no new test is needed. `emptyTailDecodeFallsBackToTheLiveUnconfirmedText` stays and is only re-typed. Each new or sharpened test carries its "Stated sensitivity: … → RED" note naming the mutations above.

## Verification

- The gate (`.agents/rules/verification.md`, "The gate"): both of its commands hold, read from the Swift run that covers this item's head.
- The two tests under Tests first, each shown red on the unfixed code, then green.
- Acceptance criteria 4, 7 and 8: those tests, and `emptyTailDecodeFallsBackToTheLiveUnconfirmedText`.
- Acceptance criterion 9: the diff of `docs/references/asr-whisperkit.md`.
- Only a live run of a dev build proves criteria 1, 2, 3, 5 and 6: the capture of a short spoken hold, the word inserted into the focused app, and the red glyph on a silent hold (`.agents/rules/verification.md`, "What a green run does not prove").

## Rollback

[NEEDS CLARIFICATION: unfilled skeleton — the spec writer fills this section]

[seg140]: https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Text/SegmentSeeker.swift#L140-L148
[seg142]: https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Text/SegmentSeeker.swift#L142-L145
[lt119]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L119-L132
[lt492]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L492-L505
[bp210]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitBiasPromptBuilderTests.swift#L210-L215
[bp238]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitBiasPromptBuilderTests.swift#L238-L240
