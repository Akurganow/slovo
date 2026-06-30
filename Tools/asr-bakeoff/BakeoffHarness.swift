import Foundation
import LoquiCore

/// A candidate backend's full per-clip result. Clip outcomes use the PRODUCT
/// `ClipScore` type — the same one the on-device bake-off gate produces — so the
/// scoring shape lives in one place.
public struct CandidateResult {
    public let candidateName: String
    public let perClip: [ClipScore]

    /// How many clips this candidate passed.
    public var passedClips: Int { perClip.filter(\.passed).count }

    public init(candidateName: String, perClip: [ClipScore]) {
        self.candidateName = candidateName
        self.perClip = perClip
    }
}

/// The bake-off outcome: every candidate's result plus the winner (the candidate
/// with the most passing clips among those that clear the bar), or `nil` if none
/// clears it.
public struct BakeoffVerdict {
    public let results: [CandidateResult]
    public let winner: String?

    public init(results: [CandidateResult], winner: String?) {
        self.results = results
        self.winner = winner
    }
}

/// The non-product ASR bake-off armature: scores each candidate's per-clip
/// transcripts through the I3 `CodeSwitchingGate` and ranks them.
///
/// This is a CI/measurement harness, never linked into the shipped app. It picks
/// no winner of its own opinion — it applies the gate and reports.
public enum BakeoffHarness {
    /// Runs every candidate over every clip, gating each transcript, and returns
    /// the verdict. The winner is the candidate with the most passing clips among
    /// those that clear `bar`; `nil` if none clears it.
    public static func run(
        candidates: [(name: String, transcriber: any Transcriber)],
        clips: [AudioBuffer],
        expectations: [ClipExpectation],
        bar: PassBar,
        biasTerms: [Term]
    ) async -> BakeoffVerdict {
        var results: [CandidateResult] = []

        for candidate in candidates {
            var perClip: [ClipScore] = []
            for (index, clip) in clips.enumerated() {
                guard index < expectations.count else { break }
                let expectation: ClipExpectation = expectations[index]
                let passed: Bool
                if let transcript = try? await candidate.transcriber.transcribe(clip, biasTerms: biasTerms) {
                    passed = CodeSwitchingGate.clipPasses(transcript: transcript, expectation: expectation)
                } else {
                    passed = false
                }
                perClip.append(ClipScore(clipId: expectation.clipId, passed: passed))
            }
            results.append(CandidateResult(candidateName: candidate.name, perClip: perClip))
        }

        // Winner = the most-passing candidate among those clearing the bar. The
        // bar decision goes through the PRODUCT gate (`CodeSwitchingGate.meetsBar`)
        // so the pass-bar rule lives in exactly one place.
        let winner: String? = results
            .filter { CodeSwitchingGate.meetsBar($0.perClip, bar: bar) }
            .max { $0.passedClips < $1.passedClips }?
            .candidateName

        return BakeoffVerdict(results: results, winner: winner)
    }
}
