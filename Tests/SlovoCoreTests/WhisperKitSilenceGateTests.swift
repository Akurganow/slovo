import Testing

@testable import SlovoCore

@Suite("Silence gate")
struct WhisperKitSilenceGateTests {
    /// Two boundary-equal frames, not one: the two-frame rule would otherwise
    /// absorb the mutation this test exists to catch. Sensitivity: switching the
    /// predicate's strict `>` to `>=` makes both frames count as voice and this
    /// all-quiet hold stop gating.
    @Test
    func allFramesAtOrBelowThresholdAreSilent() {
        #expect(WhisperKitTailFinalization.isSilentHold(
            relativeEnergy: [
                0.0,
                WhisperKitTailFinalization.silentHoldEnergyThreshold,
                WhisperKitTailFinalization.silentHoldEnergyThreshold,
            ],
            threshold: WhisperKitTailFinalization.silentHoldEnergyThreshold
        ))
    }

    /// A lone 100 ms frame above threshold is a transient — a chair creak, a key
    /// clack, the opening frame's ambient artifact — and must not un-gate a hold.
    /// Sensitivity: lowering `minimumVoicedFrameCount` to 1, or reverting the
    /// predicate to a plain `contains`, lets the spike through.
    @Test
    func singleSpikeFrameIsStillSilent() {
        #expect(WhisperKitTailFinalization.isSilentHold(
            relativeEnergy: [0.0, 0.0, 0.9, 0.0],
            threshold: WhisperKitTailFinalization.silentHoldEnergyThreshold
        ))
    }

    /// The other half of the two-frame rule: real speech never arrives as a
    /// single voiced frame, so two of them must stand the gate down.
    /// Sensitivity: raising `minimumVoicedFrameCount` to 3 gates this hold and
    /// eats the dictation.
    @Test
    func twoVoicedFramesDefeatSilence() {
        #expect(!WhisperKitTailFinalization.isSilentHold(
            relativeEnergy: [0.0, 0.4, 0.0, 0.35],
            threshold: WhisperKitTailFinalization.silentHoldEnergyThreshold
        ))
    }

    /// Regression pin for the on-device measurement round: these are relative
    /// energies read off real silent holds that the shipped 0.15 threshold let
    /// through. Sensitivity: returning the threshold to 0.15 un-gates them.
    @Test
    func measuredSilenceBandIsGated() {
        #expect(WhisperKitTailFinalization.isSilentHold(
            relativeEnergy: [0.166, 0.12, 0.205, 0.122],
            threshold: WhisperKitTailFinalization.silentHoldEnergyThreshold
        ))
    }

    /// Totality guarantee only — production reaches `.noAudio` before the
    /// predicate ever sees an empty array. Sensitivity: flipping the count
    /// comparison (`>=` for `<`) reports an empty hold as voiced.
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

    /// A hold whose only voiced frame was a single transient must finish silent
    /// even when the stream processed every sample: a spike at the very end can
    /// trigger one voice-detected pass over near-silence, and that pass's text is
    /// exactly the hallucination-prone material the gate exists to discard.
    /// Sensitivity: moving the silence guard below the `.reuse` guard in `plan`
    /// resurrects that pass's text as `.reuse`.
    @Test
    func spikeOnlyFullyProcessedHoldIsSilentNotReuse() {
        var state = WhisperKitStreamState()
        state.confirmedText = "thank you"
        state.processedSampleCount = 32_000
        #expect(WhisperKitTailFinalization.plan(
            totalSampleCount: 32_000,
            tailSampleCount: 0,
            minimumDecodableTailSampleCount: 16_000,
            relativeEnergy: [0.05, 0.45, 0.1],
            state: state
        ) == .silent)
    }

    /// Wires the predicate into `plan()` on both verdicts. The quiet fixture
    /// sits inside the silence band measured on device (0.12-0.21), the voiced
    /// one carries the two frames real speech always brings. Sensitivity:
    /// hardcoding the guard's threshold to 0 — the quiet hold (frames above
    /// zero, below 0.25) stops gating.
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
            relativeEnergy: [0.05, 0.4, 0.3],
            state: WhisperKitStreamState()
        )
        #expect(voiced != .silent)
    }

    /// Pins the frame-threshold ordering against AudioStreamTranscriber's
    /// default `silenceThreshold` (0.3): a gated hold carries at most one frame
    /// the streaming VAD would call voiced. Sensitivity: tuning the constant
    /// above 0.3.
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
