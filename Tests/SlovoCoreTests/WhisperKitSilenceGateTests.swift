import Testing

@testable import SlovoCore

@Suite("Silence gate")
struct WhisperKitSilenceGateTests {
    /// Sensitivity: switching the predicate's strict `>` to `>=` makes the
    /// boundary-equal frame count as voice and this all-quiet hold stop gating.
    @Test
    func allFramesAtOrBelowThresholdAreSilent() {
        #expect(WhisperKitTailFinalization.isSilentHold(
            relativeEnergy: [0.0, 0.1, WhisperKitTailFinalization.silentHoldEnergyThreshold],
            threshold: WhisperKitTailFinalization.silentHoldEnergyThreshold
        ))
    }

    /// Sensitivity: keying the predicate on the mean instead of any-frame —
    /// this array's mean is 0.08 (below the 0.15 threshold) while one frame
    /// is voiced, so a mean-keyed predicate calls it silent.
    @Test
    func oneVoicedFrameAnywhereDefeatsSilence() {
        #expect(!WhisperKitTailFinalization.isSilentHold(
            relativeEnergy: [0.0, 0.0, 0.0, 0.0, 0.4],
            threshold: WhisperKitTailFinalization.silentHoldEnergyThreshold
        ))
    }

    /// Totality guarantee only — production reaches `.noAudio` before the
    /// predicate ever sees an empty array. Sensitivity: inverting the
    /// `contains` (dropping the leading `!`).
    @Test
    func emptyEnergiesAreSilent() {
        #expect(WhisperKitTailFinalization.isSilentHold(
            relativeEnergy: [], threshold: 0.15
        ))
    }

    /// Sensitivity: swapping the no-audio and silence guards in `plan` reports
    /// a dead microphone as an intentional silent hold.
    @Test
    func zeroSamplesStayNoAudioNotSilent() {
        #expect(
            WhisperKitTailFinalization.plan(
                totalSampleCount: 0,
                tailSampleCount: 0,
                minimumDecodableTailSampleCount: 16_000,
                relativeEnergy: [],
                state: WhisperKitStreamState()
            ) == .noAudio
        )
    }

    /// Sensitivity: hardcoding the guard's threshold to 0 — the all-quiet
    /// hold (frames above zero, below 0.15) stops gating.
    @Test
    func quietHoldWithAudioIsSilentAndVoicedHoldIsNot() {
        let quiet = WhisperKitTailFinalization.plan(
            totalSampleCount: 32_000,
            tailSampleCount: 32_000,
            minimumDecodableTailSampleCount: 16_000,
            relativeEnergy: [0.05, 0.1, 0.12],
            state: WhisperKitStreamState()
        )
        #expect(quiet == .silent)

        let voiced = WhisperKitTailFinalization.plan(
            totalSampleCount: 32_000,
            tailSampleCount: 32_000,
            minimumDecodableTailSampleCount: 16_000,
            relativeEnergy: [0.05, 0.4, 0.12],
            state: WhisperKitStreamState()
        )
        #expect(voiced != .silent)
    }

    /// Pins the consistency argument: at or below AudioStreamTranscriber's
    /// default `silenceThreshold` (0.3), the gate only fires on holds the
    /// streaming VAD already treated as speechless. Sensitivity: tuning the
    /// constant above 0.3.
    @Test
    func gateThresholdStaysAtOrBelowTheStreamingVad() {
        #expect(WhisperKitTailFinalization.silentHoldEnergyThreshold <= 0.3)
    }

    /// Sensitivity: routing `.silent` through the decode arm — the counter
    /// shows a decode that must not happen.
    @Test
    func silentPlanResolvesEmptyWithoutDecoding() async {
        var decodeCount = 0
        let result = await WhisperKitTailFinalization.resolve(plan: .silent) { _ in
            decodeCount += 1
            return "unexpected"
        }
        #expect(result.isEmpty)
        #expect(decodeCount == 0)
    }
}
