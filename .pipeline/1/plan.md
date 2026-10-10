# Plan: decode a hold of one second or less

## Steps

1. **The fix and its tests, one slice.** Adding a field to `Plan.decode` breaks every test literal of it, so code and tests move together. Write the two tests under Tests first. Show the first red under its always-`nil` mutation, which is today's behaviour, and the second red under each mutation its note names, applied to the fix.
   - [`Sources/SlovoCore/ASR/WhisperKitTailFinalization.swift#L210-L215`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitTailFinalization.swift#L210-L215): add `singleWindowSampleCount: Int?` to `Plan.decode`.
   - [`#L233-L267`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitTailFinalization.swift#L233-L267) `plan`: set the field by the whole-recording gate, with the gate comment from Proposed change.
   - [`#L269-L288`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitTailFinalization.swift#L269-L288) `resolve`: the decode closure becomes `(Float, Int?) async throws -> String`. Replace the comment at L280-L282 with the text from Proposed change.
   - [`Sources/SlovoCore/ASR/WhisperKitLiveSession.swift#L348-L365`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitLiveSession.swift#L348-L365) (`finish()` resolve closure), [`#L384-L413`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitLiveSession.swift#L384-L413) (`decodeTail`) and [`#L415-L436`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitLiveSession.swift#L415-L436) (`tailDecodingOptions`): thread the value through and set `windowClipTime` as Proposed change says. Write the doc-comment sentence at L415-L420 and the comment at [`#L328-L330`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Sources/SlovoCore/ASR/WhisperKitLiveSession.swift#L328-L330) from Proposed change.
   - [`Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L119-L132`][lt119]: sharpen `subsecondUtteranceIsFinalizedFromTheBeginning` into the first test below. It is the test that should have caught the bug, and its plan-only equality is **deleted** in the same change. Add `import WhisperKit` for `DecodingOptions`, plus the private fake described below.
   - The same file: add `singleWindowSampleCount: nil` to the `.decode` literals at [L71](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L71), [L96](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L96), [L219](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L219) and [L235](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L235), and a second closure parameter at L220 and L236. Add the second test below. Extend the source-guard anchors at [L492-L505][lt492] by the new argument line. Without that, `finish()` could hardcode `nil` and no test would see it, because these anchors are prefix matches.
   - [`Tests/SlovoCoreTests/WhisperKitBiasPromptBuilderTests.swift#L210-L215`][bp210] and [`#L238-L240`][bp238]: pass `singleWindowSampleCount: nil`.
2. **The documentation, the final slice.**
   - [`docs/references/asr-whisperkit.md#L277-L279`](https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/docs/references/asr-whisperkit.md#L277-L279): replace the sentence with the passage from Proposed change.
   - [`docs/architecture.md#L73-L86`](https://github.com/Akurganow/slovo/blob/ee14468301a67bfdcc13b9bc2889d3dcd3b5ff99/docs/architecture.md#L73-L86): add the sentence from Proposed change to the `WhisperKitTranscriber` bullet.
   - The final slice also deletes this item's specification directory, `.pipeline/1/`.

## Tests first

Cynefin: **Complicated**. The failure is invisible except as a no-speech outcome, and it sits where three bounds meet: the SDK window loop, the SDK seek rule and Slovo's gate. Full RED→GREEN applies.

Both tests use one private fake of the SDK seam, not of the product. It takes the resolve closure's `(fromSeconds, singleWindowSampleCount)`, derives options through the real `WhisperKitLiveSession.tailDecodingOptions`, starts seek at the clip start `Int(round(fromSeconds × 16 000))` (SDK `Extensions+Internal.swift:113`, `TranscribeTask.swift:108`) and applies the SDK window bound `seek < N − Int(windowClipTime × 16 000)` to a scripted seek sequence: the clip start, then the seek that a double-timestamp ending leaves (clip start + the scripted last timestamp). For each window the bound admits, it returns scripted text. Both tests assert the **composed transcript** out of `plan` → `resolve`.

1. **`subsecondHoldDecodesItsOneWindowIntoTheTranscript`** (the sharpened L119-L132 test). The inputs are 12 000 samples, tail 12 000, minimum 16 000, voiced energy `[0.4, 0.4]` and the default state. The fake answers "да" at seek 0 and "Продолжение следует" at seek 9 600. The test expects `"да"`. It cannot compile against the unfixed code, which has no `singleWindowSampleCount`, so the first mutation below stands in for today's behaviour and is its red on the unfixed code. Each of these mutations turns it red:
   - Revert the gate to always `nil`, which is today's behaviour: zero windows, `""`.
   - Drop the `windowClipTime` assignment: zero windows, `""`.
   - Use `windowClipTime = 0`: the second window opens, giving `"да Продолжение следует"`.
2. **`shortTailAfterABoundaryWithoutLiveTextKeepsTheEndOfWindowClip`** (new), a guard of acceptance criterion 4, not a regression test. No test feeds this input today; L55-L73 carries live text. It is green on the unfixed code by design: there 32 000 < 40 000 − 16 000 is false, so no window opens and the confirmed text stands. Its proof that it can fail is the two mutations below, each applied to the fix. The inputs are 40 000 samples, tail 8 000, and a state of confirmed `"привет мир"`, boundary 2.0, processed 32 000, unconfirmed `""`. The fake answers "Продолжение следует" for any window it opens. The test expects `"привет мир"`. It turns red when the gate passes the tail's sample count instead of the whole recording's (padding 7 999, so seek 32 000 < 40 000 − 7 999 opens a window and appends the hallucination), or when the clip is set to 0 on any gate that selects this input. A widened gate that keeps the whole-recording value is equivalent and cannot turn it red: its padding of 39 999 admits no seek ≥ 2.

The silent short hold is already held by `quietHoldWithAudioIsSilentAndVoicedHoldIsNot` and `emptyEnergiesAreSilent` (`WhisperKitSilenceGateTests.swift`); `.silent` precedes `.decode` in `plan`, so no new test is needed. `emptyTailDecodeFallsBackToTheLiveUnconfirmedText` stays and is only re-typed. Each new or sharpened test carries its "Stated sensitivity: … → RED" note naming the mutations above.

## Verification

- The gate (`.agents/rules/verification.md`, "The gate"), read from the Swift run that covers this item's head: the diagnose script's four stages (`swift-build`, `swift-test`, `cleanup-benchmark-cli`, `strict-lint`) pass, and the armed gate-integrity run exits non-zero.
- The two tests under Tests first: the first shown red under the always-`nil` mutation, the second shown red under each of its two named mutations applied to the fix, then both green on the fix.
- Acceptance criteria 4, 7 and 8: those tests, and `emptyTailDecodeFallsBackToTheLiveUnconfirmedText`.
- Acceptance criterion 9: the diff of `docs/references/asr-whisperkit.md`.
- Acceptance criterion 10: for each of the four comments and two passages, with `<file>` the file it belongs in and `<pattern>` a file holding its text from Proposed change on one line, this prints `1` at the head:

  ```sh
  sed -E 's#^[[:space:]]*(///?[[:space:]]?)?##' <file> | tr '\n' ' ' | tr -s ' ' | grep -oF -f <pattern> | wc -l
  ```

  It strips each line's indentation and comment marker, then joins the lines, so it holds for any wrapping at spaces.
- Only a live run of a dev build proves criteria 1, 2, 3, 5 and 6: the capture of a short spoken hold, the word inserted into the focused app, and the red glyph on a silent hold (`.agents/rules/verification.md`, "What a green run does not prove"). That run is the owner's check before the merge (`AGENTS.md`, "Standing owner directives", 3). Criteria 1 and 2 read the `asr.tailFinalization` line of the `com.slovo.app` subsystem, `dictation` category, for each hold: its `samples=` and `plan=` fields.

## Rollback

- **Before the merge:** revert the slice commits on this branch with new commits, never a force-push. Step 1 touches `WhisperKitTailFinalization.swift`, `WhisperKitLiveSession.swift`, `WhisperKitLiveTranscriptionTests.swift` and `WhisperKitBiasPromptBuilderTests.swift`. Step 2 touches `docs/references/asr-whisperkit.md` and `docs/architecture.md`.
- **After the merge:** revert the one squash-merge commit on `main` through a pull request. It restores those six files together, so no test literal is left naming the removed field.
- **Check after:** the Swift run on the revert passes the gate, and `subsecondUtteranceIsFinalizedFromTheBeginning` is back in its plan-only form. A spoken hold of one second or less again ends in the red glyph: that is the known defect returning, not a new one.

[seg140]: https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Text/SegmentSeeker.swift#L140-L148
[seg142]: https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Text/SegmentSeeker.swift#L142-L145
[lt119]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L119-L132
[lt492]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L492-L505
[bp210]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitBiasPromptBuilderTests.swift#L210-L215
[bp238]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitBiasPromptBuilderTests.swift#L238-L240
