import Foundation

/// What a bake-off clip is expected to contain: its id plus the Latin technical
/// anchors that must survive transcription (e.g. `PR`, `GitHub`).
public struct ClipExpectation: Sendable, Equatable {
    public let clipId: String
    public let requiredLatinTerms: [String]

    public init(clipId: String, requiredLatinTerms: [String]) {
        self.clipId = clipId
        self.requiredLatinTerms = requiredLatinTerms
    }
}

/// The aggregate acceptance bar: at least `minClipsPassing` clips must pass the
/// per-clip gate (the total is implicit — `scores.count`).
public struct PassBar: Sendable, Equatable {
    public let minClipsPassing: Int

    public init(minClipsPassing: Int) {
        self.minClipsPassing = minClipsPassing
    }
}

/// The pass/fail outcome for one clip.
public struct ClipScore: Sendable, Equatable {
    public let clipId: String
    public let passed: Bool

    public init(clipId: String, passed: Bool) {
        self.clipId = clipId
        self.passed = passed
    }
}

/// The code-switching acceptance gate.
///
/// The load-bearing rule: a transcript passes ONLY when it contains BOTH a
/// Cyrillic run AND every required Latin anchor. This is deliberately two-sided —
/// a one-script-only check is the false-green this gate exists to catch (it would
/// pass a transcript that collapsed the Latin anchors into Cyrillic, the
/// FluidAudio `TokenLanguageFilter` failure mode, or a Latin-only transcript that
/// dropped the Russian).
public enum CodeSwitchingGate {
    /// `true` iff the transcript has a Cyrillic run AND contains every required
    /// Latin term (case-insensitive).
    public static func clipPasses(transcript: String, expectation: ClipExpectation) -> Bool {
        let hasCyrillicRun = transcript.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
        guard hasCyrillicRun else { return false }

        return expectation.requiredLatinTerms.allSatisfy { term in
            transcript.range(of: term, options: .caseInsensitive) != nil
        }
    }

    /// `true` iff at least `bar.minClipsPassing` of the scored clips passed.
    public static func meetsBar(_ scores: [ClipScore], bar: PassBar) -> Bool {
        scores.filter(\.passed).count >= bar.minClipsPassing
    }
}
