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

        for token in sample.expectation.preserveTokens where !trimmed.contains(token) {
            failures.append("preserve-token:\(token)")
        }

        let folded = trimmed.lowercased()
        for forbidden in sample.expectation.forbiddenSubstrings where folded.contains(forbidden.lowercased()) {
            failures.append("forbidden-substring:\(forbidden)")
        }
        for forbidden in sample.expectation.forbiddenTerms where Self.containsTerm(forbidden, in: folded) {
            failures.append("forbidden-term:\(forbidden)")
        }

        if sample.expectation.requireTerminalPunctuation,
           trimmed.last.map({ !Self.terminalPunctuation.contains($0) }) ?? true {
            failures.append("terminal-punctuation")
        }

        if let minimum = sample.expectation.minimumSentenceTerminators,
           Self.sentenceTerminatorCount(in: trimmed) < minimum {
            failures.append("sentence-structure")
        }

        if let maximum = sample.expectation.maxRunOnWords,
           Self.maxWordsBetweenTerminators(in: trimmed) > maximum {
            failures.append("run-on-words")
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

    private static func maxWordsBetweenTerminators(in text: String) -> Int {
        text.split(whereSeparator: { terminalPunctuation.contains($0) })
            .map { wordCount(in: String($0)) }
            .max() ?? 0
    }

    private static func wordCount(in text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord {
                    count += 1
                    inWord = true
                }
            } else {
                inWord = false
            }
        }
        return count
    }

    private static func containsTerm(_ term: String, in text: String) -> Bool {
        let needle = term.lowercased()
        guard !needle.isEmpty else { return false }

        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: needle, range: searchRange) {
            if hasBoundaryBefore(range.lowerBound, in: text) && hasBoundaryAfter(range.upperBound, in: text) {
                return true
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    private static func hasBoundaryBefore(_ index: String.Index, in text: String) -> Bool {
        guard index != text.startIndex else {
            return true
        }
        return !isWordCharacter(text[text.index(before: index)])
    }

    private static func hasBoundaryAfter(_ index: String.Index, in text: String) -> Bool {
        guard index != text.endIndex else {
            return true
        }
        return !isWordCharacter(text[index])
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
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
