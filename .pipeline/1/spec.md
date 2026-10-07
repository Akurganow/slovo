# Specification: decode a hold of one second or less

## Work item

This item's pull request, from `pipeline/1-decode-sub-second-hold`. It answers #83.

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

Measure both before writing the fix: if the first is false the bug is unreachable in practice, and if the second is false the proposed fix does not fix it.

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

**Layer.** Every change sits in `SlovoCore`'s WhisperKit tail finalization, the `WhisperKitTranscriber` bullet of `docs/architecture.md` ("finalizes only its unfinished tail at key-up"). The FSM, cue queue, cleaner and injector are untouched. The pure decision lives in `plan`; `tailDecodingOptions` is a projection of it.

## Acceptance criteria

1. Measured first, on a Mac, and the numbers recorded on this issue: the delivered sample count for a deliberately short spoken hold (one word, key released immediately), with Sound Cues on and off. If no realistic hold lands at or below 16 000 samples, say so here and stop — the rest of this issue is then unreachable in practice.
2. Measured first, and recorded here: a decode of that same short recording with the end-of-window clip removed returns the spoken word. If it comes back empty anyway — `firstTokenLogProbThreshold` is the suspect — the proposed fix does not work and the issue needs a different one.
3. A spoken hold of one second or less inserts the word into the focused app. No red glyph, no Error cue.
4. The gate that enables the new decode selects **only** the no-confirmed-prefix case. A long recording whose post-boundary tail is short and has no live text keeps today's behaviour exactly, including keeping its end-of-window clip.
5. A silent hold of one second or less still flashes the red glyph with nothing inserted, and nothing reaches OpenRouter or the pasteboard.
6. A hold of about 1.5 s of speech still inserts, unchanged.
7. The tail-after-boundary case with live text is unchanged: it keeps the end clip and the live-text fallback, and `emptyTailDecodeFallsBackToTheLiveUnconfirmedText` stays green.
8. Regression tests drive `plan`/`resolve` and assert the **composed transcript**, not an options field, each with the "Stated sensitivity: … → RED" note `AGENTS.md` requires, and each proven able to go red on the unfixed code. A test that asserts `DecodingOptions()` equals itself does not count.
9. `docs/references/asr-whisperkit.md:277-279` says what the code actually does with a sub-second hold — corrected whether or not the fix lands, since the line is wrong today either way.

## Out of scope

Everything above the tail-finalization seam: the state machine, the cue queue, the cleaner and the injector (#83, Requirement).

## Risks

- Nothing here was built, compiled or run, so every "turns RED" above is plausible, not confirmed.
- Whether real capture on a Mac ever delivers ≤ 16 000 samples for a one-word hold (the issue's criterion 1).
- Whether the opened window returns the word, or whether `firstTokenLogProbThreshold` empties it anyway (the issue's criterion 2). The first window under N−1 is identical to the one under a clip of 0, so that measurement applies unchanged.
- That Swift's float32 `Int(Float(n-1)/16000*16000)` matches the Python emulation for every n.
- Whether the <|0.00|> seek stall is reachable in practice.

[seg140]: https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Text/SegmentSeeker.swift#L140-L148
[seg142]: https://github.com/argmaxinc/argmax-oss-swift/blob/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d/Sources/WhisperKit/Core/Text/SegmentSeeker.swift#L142-L145
[lt119]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L119-L132
[lt492]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitLiveTranscriptionTests.swift#L492-L505
[bp210]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitBiasPromptBuilderTests.swift#L210-L215
[bp238]: https://github.com/Akurganow/slovo/blob/1b6e90666293d2ce1222f73deeb70c26af1fa7aa/Tests/SlovoCoreTests/WhisperKitBiasPromptBuilderTests.swift#L238-L240
