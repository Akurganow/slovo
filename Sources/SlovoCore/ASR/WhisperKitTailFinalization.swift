import Foundation

struct WhisperKitStreamState: Equatable, Sendable {
    var confirmedText = ""
    var unconfirmedText = ""
    var processedSampleCount = 0
    var confirmedEndSeconds: Float = 0
}

enum WhisperKitTranscriptText {
    static func compose(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct WhisperKitDecodedWord: Equatable, Sendable {
    let text: String
    let probability: Float
    let startSeconds: Float
    let endSeconds: Float

    var durationSeconds: Float {
        endSeconds - startSeconds
    }
}

enum WhisperKitTerminalHallucinationGuard {
    private struct TokenizedWord {
        let word: WhisperKitDecodedWord
        let tokens: [String]
    }

    // Mirrors OpenAI Whisper's score while Slovo requires stricter boundary evidence.
    private static let maximumScoredWordCount = 8
    private static let anomalousSuffixScore: Float = 3
    private static let scoreComparisonTolerance: Float = 0.01
    private static let lowProbabilityThreshold: Float = 0.15
    private static let shortWordDuration: Float = 0.133
    private static let shortWordPenalty: Float = 15
    private static let longWordDuration: Float = 2

    static func shouldInspect(
        sampleCount: Int,
        modelWindowSampleCount: Int,
        confirmedEndSeconds: Float,
        liveText: String
    ) -> Bool {
        sampleCount < modelWindowSampleCount
            && confirmedEndSeconds == 0
            && !liveText.isEmpty
    }

    static func resolve(
        liveText: String,
        decodedText: String,
        words: [WhisperKitDecodedWord]?,
        audioDurationSeconds: Float
    ) -> String {
        guard audioDurationSeconds.isFinite,
              audioDurationSeconds >= 0,
              let words,
              !words.isEmpty
        else { return decodedText }

        let liveTokens = lexicalTokens(in: liveText)
        let decodedTokens = lexicalTokens(in: decodedText)
        let timedWords = words.compactMap { word -> TokenizedWord? in
            let tokens = lexicalTokens(in: word.text)
            return tokens.isEmpty ? nil : TokenizedWord(word: word, tokens: tokens)
        }
        let timedTokens = timedWords.flatMap(\.tokens)

        guard !liveTokens.isEmpty,
              timedTokens == decodedTokens,
              timedTokens.count > liveTokens.count,
              Array(timedTokens.prefix(liveTokens.count)) == liveTokens,
              let suffixStart = suffixWordIndex(
                  afterTokenCount: liveTokens.count,
                  timedWords: timedWords
              )
        else { return decodedText }

        let suffix = timedWords[suffixStart...].map(\.word)
        guard suffix.allSatisfy({ word in
            word.probability.isFinite
                && (0...1).contains(word.probability)
                && word.startSeconds.isFinite
                && word.endSeconds.isFinite
                && word.endSeconds >= word.startSeconds
                && word.startSeconds > audioDurationSeconds
        }), isAnomalous(suffix)
        else { return decodedText }

        return liveText
    }

    private static func suffixWordIndex(
        afterTokenCount tokenCount: Int,
        timedWords: [TokenizedWord]
    ) -> Int? {
        var consumedTokenCount = 0
        for (index, timedWord) in timedWords.enumerated() {
            consumedTokenCount += timedWord.tokens.count
            if consumedTokenCount == tokenCount {
                return timedWords.index(after: index)
            }
            if consumedTokenCount > tokenCount { return nil }
        }
        return nil
    }

    private static func isAnomalous(_ words: [WhisperKitDecodedWord]) -> Bool {
        let scoredWords = words.prefix(maximumScoredWordCount)
        guard !scoredWords.isEmpty else { return false }
        let score = scoredWords.reduce(Float.zero) { $0 + anomalyScore(for: $1) }
        return score >= anomalousSuffixScore
            || score + scoreComparisonTolerance >= Float(scoredWords.count)
    }

    private static func anomalyScore(for word: WhisperKitDecodedWord) -> Float {
        var score: Float = word.probability < lowProbabilityThreshold ? 1 : 0
        if word.durationSeconds < shortWordDuration {
            score += (shortWordDuration - word.durationSeconds) * shortWordPenalty
        }
        if word.durationSeconds > longWordDuration {
            score += word.durationSeconds - longWordDuration
        }
        return score
    }

    private static func lexicalTokens(in text: String) -> [String] {
        text.precomposedStringWithCanonicalMapping
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

enum WhisperKitTailFinalization {
    enum Plan: Equatable, Sendable {
        case noAudio
        case reuse(String)
        case decode(confirmedPrefix: String, fromSeconds: Float)
    }

    static func plan(
        totalSampleCount: Int,
        state: WhisperKitStreamState
    ) -> Plan {
        guard totalSampleCount > 0 else { return .noAudio }
        guard state.processedSampleCount < totalSampleCount else {
            return .reuse(WhisperKitTranscriptText.compose([
                state.confirmedText,
                state.unconfirmedText,
            ]))
        }
        return .decode(
            confirmedPrefix: state.confirmedText,
            fromSeconds: state.confirmedEndSeconds
        )
    }

    nonisolated(nonsending) static func resolve(
        plan: Plan,
        decode: (Float) async throws -> String
    ) async rethrows -> String {
        switch plan {
        case .noAudio:
            return ""
        case .reuse(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .decode(let confirmedPrefix, let fromSeconds):
            let tail = try await decode(fromSeconds)
            return WhisperKitTranscriptText.compose([confirmedPrefix, tail])
        }
    }
}
