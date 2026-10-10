# Specification: decode a hold of one second or less

## Work item

#144, from `pipeline/1-decode-sub-second-hold`. It answers #83.

## Problem

Two thresholds coincide at exactly 1.000 s of 16 kHz audio, and a hold that fits under both is decoded by nobody:

- the SDK's streaming loop runs its first pass only after the buffer grows by **more than** one second, so for a whole hold of ≤ 16 000 samples no live pass ever runs and the mirrored stream state stays at its defaults — `""`, `0`, `0`;
- the key-up decode's window loop is `while seek < seekClipEnd - windowPadding` with `windowPadding` = `windowClipTime` × 16 000 = 16 000 (Slovo never sets `windowClipTime`, so the SDK default `1.0` applies), and `0 < N − 16 000` is false. Zero windows are opened and the decode returns empty text rather than throwing; the bias-free retry re-runs the same zero-window decode.

`plan` does schedule the decode from the beginning, and its live-text fallback is gated to exactly the zero-window case — but that fallback was built for a **short tail after a confirmed boundary**, where live text exists. For a whole hold of one second or less there has been no live pass, so the fallback is empty by construction. `resolve` then composes two empty strings and the FSM takes its no-speech arm. Whisper's own silence suppressor cannot save it either: `noSpeechProb` is hard-coded to `0` on that path in the SDK.

**What the review established.** The chain above is confirmed by reading the sources at `01ae6a2c` and the pinned SDK revision (argmax-oss-swift `1e2a1637`, v1.1.0): the failure is window arithmetic alone, with no model behaviour involved. The sample buffer only appends and `purgeAudioSamples` has no caller, so no intermediate count can exceed the hold's total. The silence gate at `plan` passes for real speech (two frames above 0.25; the quietest measured speech is 0.43), so a spoken short hold really does reach the dead decode. `docs/references/asr-whisperkit.md:278-279` states the opposite of the code and is wrong today.

**What the review struck, and the fix must watch out for.**

1. **The obvious gate is too wide.** Gating on `tailSampleCount <= minimumDecodableTailSampleCount && liveText.isEmpty` also selects a *long* recording whose post-boundary tail is short with no live text. There, dropping the end-of-window clip decodes the **whole recording** with the terminal-hallucination guard switched off — that guard needs non-empty live text to run at all — and appends a silence-padded window's output to a prefix that is safe today. Narrow the gate to the **no-confirmed-prefix** case (`confirmedText` empty / `confirmedEndSeconds == 0` / `processedSampleCount == 0`), which is the only situation where nobody has decoded anything.
2. **"The risk is confined to a spoken sub-second hold" is wrong** as the report stated it, for exactly the reason in (1). It becomes true only once the gate is narrowed.
3. **The proposed second regression test cannot fail.** It compares `DecodingOptions()` against itself. Drive the regression tests through `plan`/`resolve` — the composed outcome — rather than asserting on an options field.

**What nobody has measured.** Two facts the fix rests on were not established, because nothing was built or run where the report and the review were written:

- whether real capture on this hardware ever delivers ≤ 16 000 samples for a hold a person would actually make. The report's "roughly 1.3–1.4 s" figure has nothing behind it; capture callback size is a device fact.
- whether a decode returns the word **once a window does open**. `firstTokenLogProbThreshold` (-1.5, active) can empty a window and keep it empty across retries, in which case removing the end clip changes nothing user-visible.

If the first is false the bug is unreachable in practice, and if the second is false the proposed fix does not fix it. No pipeline stage can measure either: both need a person at a Mac with a microphone and a loaded model. The owner checks every deliverable on its dev build before the merge (`AGENTS.md`, "Standing owner directives", 3), and microphone capture is proven only there (`.agents/rules/verification.md`, "What a green run does not prove"). Acceptance criteria 1 and 2 are therefore checks of that dev-build run, not a precondition of the implementation.

The report's effort rating of `S` looks optimistic once the measurements and the narrowed gate are done. The rest of its ratings were not assessed.

## The rule it serves

> **Empty result** (key held but only silence): the menu bar briefly shows the
> red failure glyph "Ⱁ" (U+2C11), nothing is inserted, and cleanup is never
> called

`AGENTS.md`, "Product intent — how the app must work". A spoken hold is not silence, so it must end with its word inserted.

## Proposed change

**Chosen: the plan names a single-window decode, and the options derivation opens exactly that one window.**

- `WhisperKitTailFinalization.Plan.decode` gains `singleWindowSampleCount: Int?`. `plan` sets it to `totalSampleCount` when `totalSampleCount <= minimumDecodableTailSampleCount`, and to `nil` otherwise. `resolve` passes it to its decode closure beside `fromSeconds`. Nothing else in `plan` or `resolve` changes: the live-text fallback, the reuse guard and the silence gate all stay as they are.
- `WhisperKitLiveSession.tailDecodingOptions` gains `singleWindowSampleCount: Int?`, with no default so every call site has to choose. When the value is non-nil it sets `options.windowClipTime = Float(n - 1) / Float(WhisperKit.sampleRate)`. `finish()` passes the plan's value through `decodeTail`.
- The gate reads the **whole recording's** sample count, not the tail's. That is the narrowing the review required, stated as one comparison. A live pass needs more than 16 000 new samples (SDK `AudioStreamTranscriber.swift:131-140`), so a recording of 16 000 samples or fewer has had no live pass, no confirmed prefix and no live text, and has boundary 0. A long recording with a short post-boundary tail has `totalSampleCount > 16 000`, so it keeps `nil`, keeps the SDK's 1 s end-of-window clip, and behaves exactly as today. Gating on mirrored stream fields (`confirmedEndSeconds == 0` and similar) would also select that case only with an extra tail check, and would put the decision on a snapshot instead of on the audio itself. The N−1 padding also confines any opened window by itself: it admits only seek < 2, so no recording whose boundary is above 0 can open a window through this field, whatever the gate reads.

**Why N−1 and not `windowClipTime = 0` (the rejected alternative).** The SDK window loop is `while seek < seekClipEnd - windowPadding` ([TranscribeTask.swift L113-L116](https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/TranscribeTask.swift#L113-L116)). After a window, seek moves to the last timestamp whenever the output has consecutive timestamps and does not end without one ([SegmentSeeker.swift L140-L148][seg140]). With a clip of 0, a one-word hold whose output ends on a double timestamp at 0.6 s opens a **second** window over the trailing ~0.4 s of near-silence. No live text exists there, so the terminal-hallucination guard cannot run, and whatever that window hallucinates would be inserted. That is exactly the failure the 1 s clip exists to prevent. With a padding of N−1, the loop admits only seek 0 (or 1): a later seek advances by the last timestamp or by N, unless that last timestamp is <|0.00|>, in which case `seek += 0` ([SegmentSeeker.swift L142-L145][seg142]) and the SDK decodes the same window again. That stall already applies to every opened window and is not introduced here. `Int(Float(n-1)/16000*16000)` was checked in IEEE float32 for every n in 1…16 000, and it lands on n−1 (15 909 cases) or n−2 (91 cases). The bound therefore always admits seek 0 and never seek ≥ 2. This check emulated the arithmetic in Python; Swift's rounding was not run.

Also rejected: padding the samples with trailing silence. It feeds the model the same input, because `padOrTrim` already zero-pads each window ([TranscribeTask.swift L126-L127](https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/TranscribeTask.swift#L126-L127)). It still has the second-window problem, and it misstates the audio duration that the guard and the telemetry read.

**Comments the change writes**, each in full. Each wraps at spaces wherever its line would pass 160 columns (acceptance criterion 10):

- Above the new gate in `plan`: `// The whole recording, not the tail: only a hold the live loop never reached has no confirmed prefix to protect, and its one window is the only decode it gets.`
- The comment in `resolve` at `WhisperKitTailFinalization.swift:280-282` becomes: `// A short tail after a confirmed boundary opens zero windows and returns nothing; the live unconfirmed text is then the only record of the final words, so an empty decode must not erase them. A whole short hold opens its one window instead (singleWindowSampleCount).`
- The comment at `WhisperKitLiveSession.swift:328-330` becomes: `// Mirrors TranscribeTask's window-loop bound: a tail at or below windowClipTime opens zero decode windows unless the plan opens its single window, so its empty decode is structural, not a verdict that nothing was spoken.`
- The doc comment of `tailDecodingOptions` at `WhisperKitLiveSession.swift:415-420` gains, after its first sentence: `/// A non-nil singleWindowSampleCount lowers windowClipTime to one sample short of the recording, so the SDK opens exactly one window over a hold too short for its one-second clip.`

**Documentation the change writes.**

- `docs/references/asr-whisperkit.md:278-279`: the sentence "A sub-second dictation, which the native loop has not processed yet, is finalized from the beginning." is replaced by: "A dictation of one second or less never reaches the native loop, which waits for more than one second of new audio. Slovo decodes it at key-up from the beginning, in exactly one window. Only there does it lift the SDK's one-second end-of-window clip, which would otherwise open no window at all. The clip drops to one sample short of the recording, so no second window opens over the trailing silence."
- `docs/architecture.md:84`, in the `WhisperKitTranscriber` bullet, after "so Whisper never gets the chance to hallucinate into silence.": "A voiced hold of one second or less, which the live transcriber never reaches, is decoded at key-up in exactly one window."

**Layer.** Every change sits in `SlovoCore`'s WhisperKit tail finalization, the `WhisperKitTranscriber` bullet of `docs/architecture.md` ("finalizes only its unfinished tail at key-up"). The FSM, cue queue, cleaner and injector are untouched. The pure decision lives in `plan`; `tailDecodingOptions` is a projection of it.

## Acceptance criteria

1. On the owner's dev-build run: a deliberately short spoken hold (one word, key released immediately) delivers 16 000 samples or fewer, with Sound Cues on and with them off. The count is the `samples=` field of that dictation's `asr.tailFinalization` line in the `com.slovo.app` / `dictation` log. The owner records both counts on #83.
2. On the same run, the hold of criterion 1 ends with its word inserted, not the red glyph. A red glyph there, with `plan=decode` in its log line, means the one opened window decoded to nothing (`firstTokenLogProbThreshold` is the suspect), and the fix does not work.
3. A spoken hold of one second or less inserts the word into the focused app. No red glyph, no Error cue.
4. The gate that enables the new decode selects **only** the no-confirmed-prefix case. A long recording whose post-boundary tail is short and has no live text keeps today's behaviour exactly, including keeping its end-of-window clip.
5. A silent hold of one second or less still flashes the red glyph with nothing inserted, and nothing reaches OpenRouter or the pasteboard.
6. A hold of about 1.5 s of speech still inserts, unchanged.
7. The tail-after-boundary case with live text is unchanged: it keeps the end clip and the live-text fallback, and `emptyTailDecodeFallsBackToTheLiveUnconfirmedText` stays green.
8. Both tests under the plan's Tests first drive `plan`/`resolve` and assert the **composed transcript**, not an options field, each with the "Stated sensitivity: … → RED" note `AGENTS.md` requires. The regression test `subsecondHoldDecodesItsOneWindowIntoTheTranscript` is proven red on today's behaviour. The guard `shortTailAfterABoundaryWithoutLiveTextKeepsTheEndOfWindowClip` is green on the unfixed code by design, since today's clip opens no window there, and is proven red by each mutation its note names, applied to the fix. A test that asserts `DecodingOptions()` equals itself does not count.
9. `docs/references/asr-whisperkit.md:277-279` says what the code actually does with a sub-second hold — corrected whether or not the fix lands, since the line is wrong today either way.
10. The four comments and the two documentation passages under Proposed change stand in the tree with their words in order. Each may wrap at any space, so the comments stay inside the 160-column `line_length` warning that strict lint fails on (`.swiftlint.yml`, `strict: true` and `line_length`).

## Out of scope

Everything above the tail-finalization seam: the state machine, the cue queue, the cleaner and the injector (#83, Requirement).

## Risks

- Nothing here was built, compiled or run, so every "turns RED" above is plausible, not confirmed.
- Whether real capture on a Mac ever delivers ≤ 16 000 samples for a one-word hold. Criterion 1 tells us, on the owner's dev-build run. If no realistic hold does, the defect is unreachable in practice, and whether the change still lands is the owner's decision at the merge.
- Whether the opened window returns the word, or whether `firstTokenLogProbThreshold` empties it anyway. Criterion 2 tells us on the same run. The first window under N−1 is identical to the one under a clip of 0, so the check covers the clip-removal question unchanged. If it fails, the owner sends the item back with the log line as the finding.
- That Swift's float32 `Int(Float(n-1)/16000*16000)` matches the Python emulation for every n.
- Whether the <|0.00|> seek stall is reachable in practice.

[seg140]: https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Text/SegmentSeeker.swift#L140-L148
[seg142]: https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Text/SegmentSeeker.swift#L142-L145
