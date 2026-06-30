import Foundation

public enum CleanupQualityGate {
    public static func evaluate(output: String, sample: CleanupBenchmarkSample) -> CleanupQualityResult {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        var failures: [String] = []

        if trimmed.isEmpty {
            failures.append("empty-output")
        }

        for required in sample.expectation.requiredSubstrings where !trimmed.contains(required) {
            failures.append("required-substring:\(required)")
        }

        let folded = trimmed.lowercased()
        for forbidden in sample.expectation.forbiddenSubstrings where folded.contains(forbidden.lowercased()) {
            failures.append("forbidden-substring:\(forbidden)")
        }

        if sample.expectation.requireTerminalPunctuation,
           trimmed.last.map({ !Self.terminalPunctuation.contains($0) }) ?? true {
            failures.append("terminal-punctuation")
        }

        if let minimum = sample.expectation.minimumSentenceTerminators,
           Self.sentenceTerminatorCount(in: trimmed) < minimum {
            failures.append("sentence-structure")
        }

        if sample.expectation.forbidChatResponse,
           Self.chatResponsePrefixes.contains(where: { folded.hasPrefix($0) }) {
            failures.append("chat-response")
        }

        let rawCount = max(sample.raw.count, 1)
        if Double(trimmed.count) > Double(rawCount) * sample.expectation.maxLengthRatio {
            failures.append("length-ratio")
        }

        return CleanupQualityResult(passed: failures.isEmpty, failures: failures)
    }

    private static let terminalPunctuation = Set<Character>(".!?…")

    private static func sentenceTerminatorCount(in text: String) -> Int {
        text.reduce(0) { count, character in
            terminalPunctuation.contains(character) ? count + 1 : count
        }
    }

    private static let chatResponsePrefixes = [
        "i'm not sure",
        "i am not sure",
        "sure,",
        "sure:",
        "certainly,",
        "certainly:",
        "of course,",
        "of course:",
        "here is",
        "here's",
        "could you provide",
        "could you clarify",
        "please provide",
        "feel free to",
        "as an ai",
        "я не уверен",
        "можете уточнить",
        "пожалуйста, уточните",
    ]
}
