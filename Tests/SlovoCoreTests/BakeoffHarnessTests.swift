import AVFoundation
import Foundation
import Testing

import AsrBakeoff
import SlovoCore
import SlovoTestSupport

// Epic 05 — AC-1 (CI-half, harness side): the bake-off harness scores each
// candidate's per-clip output through the I3 gate and ranks the code-switched
// candidate as winner, holding the collapsed candidate BELOW the bar.
//
// Contract under test (implementer builds the NON-PRODUCT `BakeoffHarness` in a
// NEW `Tools/asr-bakeoff/` target per plan §2; CURRENTLY supplied by the
// WRONG-ON-PURPOSE `_RedScaffold_AsrBakeoff.swift` stub that ignores the gate
// and picks the first candidate — so the ranking is wrong → RED).
@Suite("Epic 05 AC-1 bakeoff harness ranking")
struct BakeoffHarnessTests {
    /// A synthetic clip: a 1-frame 16 kHz mono buffer whose first sample encodes
    /// the clip index, so `ScriptedTranscriber` maps clip→transcript without a
    /// real model. (Not real audio — exercises harness/gate STRUCTURE only.)
    private static func clip(index: Int) -> SlovoCore.AudioBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        return SlovoCore.AudioBuffer(samples: [Float(index)], format: format)
    }

    /// Three code-switched transcripts (Cyrillic + PR + GitHub), one per clip.
    private static func codeSwitchedScript(_ audio: SlovoCore.AudioBuffer) -> Result<String, TranscriptionError> {
        .success("запушь PR в GitHub репозиторий")
    }

    /// Three collapsed transcripts (Latin anchors transliterated away).
    private static func collapsedScript(_ audio: SlovoCore.AudioBuffer) -> Result<String, TranscriptionError> {
        .success("запушь пиар в гитхаб репозиторий")
    }

    /// The harness must rank the code-switched candidate as winner and hold the
    /// collapsed candidate below the ≥2-of-3 bar.
    /// Stated sensitivity: a harness that ignores the gate (counts every clip as
    /// passing) or always picks the first candidate → wrong winner / collapsed not
    /// held below bar → RED. (The scaffold ignores the gate and picks the first
    /// candidate — listed first below is the COLLAPSED one — so both assertions RED.)
    @Test
    func ranksCodeSwitchedCandidateAboveCollapsed() async {
        let clips = [Self.clip(index: 0), Self.clip(index: 1), Self.clip(index: 2)]
        let expectations = clips.enumerated().map { index, _ in
            ClipExpectation(clipId: "clip-\(index)", requiredLatinTerms: ["PR", "GitHub"])
        }
        let bar = PassBar(minClipsPassing: 2)

        // Order the COLLAPSED candidate first, so a "pick the first candidate"
        // scaffold names the wrong winner.
        let candidates: [(name: String, transcriber: any Transcriber)] = [
            ("collapsed", ScriptedTranscriber(Self.collapsedScript)),
            ("codeSwitched", ScriptedTranscriber(Self.codeSwitchedScript)),
        ]

        let verdict = await BakeoffHarness.run(
            candidates: candidates, clips: clips, expectations: expectations,
            bar: bar, biasTerms: []
        )

        #expect(verdict.winner == "codeSwitched",
                "the code-switched candidate must win, got \(String(describing: verdict.winner))")

        let collapsed = verdict.results.first { $0.candidateName == "collapsed" }
        #expect(collapsed?.passedClips ?? 99 < bar.minClipsPassing,
                "the collapsed candidate must be held below the ≥\(bar.minClipsPassing) bar, got \(collapsed?.passedClips ?? -1) passing")
    }
}
