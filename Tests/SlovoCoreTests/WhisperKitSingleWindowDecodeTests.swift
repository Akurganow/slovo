import Testing
import WhisperKit

@testable import SlovoCore

// Drives `plan` -> `resolve` through the SDK's window bound, so each test asserts the transcript
// the user would get rather than an options field.
@Suite("WhisperKit single-window decode")
struct WhisperKitSingleWindowDecodeTests {
    /// A hold of one second or less never reaches the live loop, so the key-up decode is its only
    /// decode, and it must open exactly one window.
    /// Stated sensitivity: a gate that always plans `nil`, or a dropped `windowClipTime`
    /// assignment, keeps the SDK's one-second clip, opens zero windows and leaves `""` → RED.
    /// A clip of 0 opens a second window over the trailing near-silence and appends its
    /// hallucination → RED.
    @Test
    func subsecondHoldDecodesItsOneWindowIntoTheTranscript() async {
        let plan = WhisperKitTailFinalization.plan(
            totalSampleCount: 12_000,
            tailSampleCount: 12_000,
            minimumDecodableTailSampleCount: 16_000,
            relativeEnergy: [0.4, 0.4],
            state: WhisperKitStreamState()
        )

        let result = await WhisperKitTailFinalization.resolve(
            plan: plan,
            decode: Self.scriptedWindowDecode(
                sampleCount: 12_000,
                windowTexts: ["да", "Продолжение следует"],
                lastTimestampSeconds: 0.6
            )
        )

        #expect(result == "да")
    }

    /// A long recording whose post-boundary tail is short and has no live text keeps the SDK's
    /// one-second clip: no window opens, and the confirmed prefix stands alone.
    /// Stated sensitivity: a gate that passes the tail's sample count instead of the whole
    /// recording's opens a window at the boundary and appends its hallucination → RED. A clip of 0
    /// on any gate that selects this input does the same → RED.
    @Test
    func shortTailAfterABoundaryWithoutLiveTextKeepsTheEndOfWindowClip() async {
        let state = WhisperKitStreamState(
            confirmedText: "привет мир",
            unconfirmedText: "",
            processedSampleCount: 32_000,
            confirmedEndSeconds: 2.0
        )
        let plan = WhisperKitTailFinalization.plan(
            totalSampleCount: 40_000,
            tailSampleCount: 8_000,
            minimumDecodableTailSampleCount: 16_000,
            relativeEnergy: [0.4, 0.4],
            state: state
        )

        let result = await WhisperKitTailFinalization.resolve(
            plan: plan,
            decode: Self.scriptedWindowDecode(
                sampleCount: 40_000,
                windowTexts: ["Продолжение следует", "Продолжение следует"],
                lastTimestampSeconds: 0.25
            )
        )

        #expect(result == "привет мир")
    }

    /// The SDK's window loop over scripted window texts, with the options derived by the real
    /// `tailDecodingOptions`: seek starts at the clip start, a window opens while
    /// `seek < N - Int(windowClipTime * 16 000)`, and a double-timestamp ending moves seek to the
    /// clip start plus the window's last timestamp.
    private static func scriptedWindowDecode(
        sampleCount: Int,
        windowTexts: [String],
        lastTimestampSeconds: Float
    ) -> (Float, Int?) -> String {
        { fromSeconds, singleWindowSampleCount in
            let options = WhisperKitLiveSession.tailDecodingOptions(
                base: DecodingOptions(),
                fromSeconds: fromSeconds,
                singleWindowSampleCount: singleWindowSampleCount,
                wordTimestamps: false,
                withBias: true
            )
            let sampleRate = Float(WhisperKit.sampleRate)
            let clipStart = Int((fromSeconds * sampleRate).rounded())
            let windowPadding = Int(options.windowClipTime * sampleRate)
            let seeks = [clipStart, clipStart + Int(lastTimestampSeconds * sampleRate)]
            let opened = zip(seeks, windowTexts).prefix { seek, _ in seek < sampleCount - windowPadding }
            return WhisperKitTranscriptText.compose(opened.map(\.1))
        }
    }
}
