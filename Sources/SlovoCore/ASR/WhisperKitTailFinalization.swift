import Foundation

struct WhisperKitStreamState: Equatable, Sendable {
    var confirmedText = ""
    var unconfirmedText = ""
    var processedSampleCount = 0
    var confirmedEndSeconds: Float = 0
}

/// The post-boundary span the key-up decode covers: the samples after the
/// confirmed boundary, paired with the live text for that SAME span so the
/// hallucination guard always compares aligned material.
struct WhisperKitTailSpan: Equatable, Sendable {
    let sampleCount: Int
    let liveText: String
}

extension WhisperKitStreamState {
    /// Derived, not stored: the span is a projection of one atomic state
    /// snapshot, so the sample arithmetic and the text can never disagree.
    func tailSpan(totalSampleCount: Int, sampleRate: Int) -> WhisperKitTailSpan {
        WhisperKitTailSpan(
            sampleCount: totalSampleCount - Int(confirmedEndSeconds * Float(sampleRate)),
            liveText: unconfirmedText
        )
    }
}

enum WhisperKitTranscriptText {
    // The single compose chokepoint every WhisperKit `finish()` outcome routes
    // through, so sanitizing here is the AUTHORITATIVE token-domain guarantee
    // (spec 2026-07-23): no `<|...|>` reaches the cleaner or the paste path.
    static func compose(_ parts: [String]) -> String {
        strippingSpecialTokens(
            parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        )
    }

    /// AUTHORITATIVE token-domain guarantor (spec 2026-07-23): Slovo-owned,
    /// surface-form bound, WhisperKit-version-independent. Sanitizing the JOINED
    /// output (not each part) is deliberate: a `<|...|>` token can straddle the
    /// part boundary, so the join separator must be inside the scan window. The
    /// decoder's `skipSpecialTokens` is the first-line optimization, not the
    /// contract — this is the guarantee that survives an SDK change.
    ///
    /// Universality beyond today's observed emission: the well-formed strip runs
    /// to a FIXPOINT so nested forms (`<|a<|b|>|>`) fully unwind — `[^<>|]*`
    /// stops at delimiters so adjacent tokens don't merge into one greedy span,
    /// and the fixpoint terminates because each changing pass replaces a
    /// four-plus-character token with one space, strictly shrinking the string —
    /// then one end-anchored pass removes a trailing unclosed fragment
    /// (`<|start` at the very end — the truncation shape), leaving mid-string
    /// unclosed fragments untouched. Declared scope: single-level complete
    /// tokens, nesting, and trailing truncation; arbitrary multi-`<|`
    /// adversarial strings are out of scope (documented limitation). The final
    /// whitespace collapse is UNCONDITIONAL — it applies to every compose output
    /// whether or not a token was stripped, because speech output carries no
    /// meaningful multi-spaces.
    static func strippingSpecialTokens(_ text: String) -> String {
        var stripped = text
        while true {
            let next = stripped.replacingOccurrences(
                of: #"<\|[^<>|]*\|>"#, with: " ", options: .regularExpression)
            if next == stripped { break }
            stripped = next
        }
        return stripped
            .replacingOccurrences(of: #"<\|[^<>|]*$"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

/// One tail-decode attempt's outcome: the composed transcript plus the word
/// timings the terminal-hallucination guard needs — carried together so the
/// guard can only ever see text and timings from the SAME attempt.
struct WhisperKitTailDecode: Equatable, Sendable {
    let text: String
    let words: [WhisperKitDecodedWord]
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

    /// The key-up decode covers only the post-boundary tail, and Whisper can
    /// hallucinate past the end of audio whenever that tail is shorter than one
    /// model window (the decode pads it with silence) — so eligibility is a
    /// property of the tail, not of the whole recording.
    static func shouldInspect(
        tailSampleCount: Int,
        modelWindowSampleCount: Int,
        liveTailText: String
    ) -> Bool {
        tailSampleCount < modelWindowSampleCount && !liveTailText.isEmpty
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
        case silent
        case reuse(String)
        case decode(confirmedPrefix: String, liveTail: String, fromSeconds: Float)
    }

    /// True when fewer than `minimumVoicedFrameCount` frames exceed `threshold`.
    /// Strict `>` mirrors the SDK's `isVoiceDetected`; an empty array is silent.
    static func isSilentHold(relativeEnergy: [Float], threshold: Float) -> Bool {
        relativeEnergy.lazy.filter { $0 > threshold }
            .prefix(minimumVoicedFrameCount).count < minimumVoicedFrameCount
    }

    /// A single 100 ms frame carries a transient (creak, first-frame reference
    /// artifact), never a word — real speech spans many frames.
    static let minimumVoicedFrameCount = 2

    /// Kept below the streaming VAD's 0.3, so a gated hold carries at most one
    /// frame the live path would call voiced. Measured on device: silence spans
    /// 0.12–0.21, the quietest speech 0.43.
    static let silentHoldEnergyThreshold: Float = 0.25

    static func plan(
        totalSampleCount: Int,
        tailSampleCount: Int,
        minimumDecodableTailSampleCount: Int,
        relativeEnergy: [Float],
        state: WhisperKitStreamState
    ) -> Plan {
        // `.noAudio` first: a dead microphone must not read as an intentional
        // silent hold. `.silent` before `.reuse`: a gated hold's lone streamed
        // pass is hallucination-prone, so its text must never be reused.
        guard totalSampleCount > 0 else { return .noAudio }
        guard !isSilentHold(
            relativeEnergy: relativeEnergy,
            threshold: silentHoldEnergyThreshold
        ) else { return .silent }
        guard state.processedSampleCount < totalSampleCount else {
            return .reuse(WhisperKitTranscriptText.compose([
                state.confirmedText,
                state.unconfirmedText,
            ]))
        }
        return .decode(
            confirmedPrefix: state.confirmedText,
            // An empty decode of a DECODABLE tail is the decoder's verdict —
            // nothing spoken there — and must stay empty, ONCE BIAS HAS BEEN
            // RULED OUT (the bias-free retry in `decodeRetryingWithoutBias`
            // runs first; see the empty-result invariant). Only a tail too
            // short to open one decode window cannot testify, so only then
            // does live unconfirmed text stand in.
            liveTail: tailSampleCount <= minimumDecodableTailSampleCount
                ? state.unconfirmedText
                : "",
            fromSeconds: state.confirmedEndSeconds
        )
    }

    nonisolated(nonsending) static func resolve(
        plan: Plan,
        decode: (Float) async throws -> String
    ) async rethrows -> String {
        switch plan {
        case .noAudio, .silent:
            return ""
        case .reuse(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .decode(let confirmedPrefix, let liveTail, let fromSeconds):
            let tail = try await decode(fromSeconds)
            // WhisperKit decodes zero windows for a sub-second tail and returns
            // nothing; the live unconfirmed text is then the only record of the
            // final words, so an empty decode must not erase them.
            return WhisperKitTranscriptText.compose([
                confirmedPrefix,
                tail.isEmpty ? liveTail : tail,
            ])
        }
    }

    /// Bias-free retry policy for the final tail decode (task #44): a bias prompt
    /// can empty out a short decode (EOT at the first sampled position, or the
    /// first-token-confidence fallback cascade), so an empty BIASED decode is not
    /// yet the decoder's verdict — the verdict is the bias-free attempt's. Exactly
    /// one retry; the flag feeds the permanent `biasRetry` telemetry field.
    ///
    /// A throw from the FIRST attempt propagates — it is the only decode there was.
    /// A throw from the RETRY is absorbed in favour of the first attempt's outcome:
    /// the rescue must never turn a survivable empty tail into an error that costs
    /// the user the whole dictation's confirmed prefix.
    nonisolated(nonsending) static func decodeRetryingWithoutBias(
        isBiased: Bool,
        decode: (_ withBias: Bool) async throws -> WhisperKitTailDecode
    ) async rethrows -> (outcome: WhisperKitTailDecode, retriedWithoutBias: Bool) {
        let first = try await decode(isBiased)
        guard isBiased, first.text.isEmpty else { return (first, false) }
        do {
            return (try await decode(false), true)
        } catch {
            return (first, true)
        }
    }

    /// The whole tail-finalization decision for one decode span: bias-free retry,
    /// then the terminal-hallucination guard on the winning attempt. Closure-injected
    /// like `decodeRetryingWithoutBias` so the guard wiring — which attempt's words
    /// the guard sees, whether its verdict is honoured — is unit-testable without a
    /// loaded model. `guardTrimmed` is returned rather than logged because this
    /// module is Foundation-only; the caller owns the attribution mark.
    nonisolated(nonsending) static func finalizeTail(
        isBiased: Bool,
        shouldGuard: Bool,
        liveTailText: String,
        audioDurationSeconds: Float,
        decode: (_ withBias: Bool) async throws -> WhisperKitTailDecode
    ) async rethrows -> (text: String, retriedWithoutBias: Bool, guardTrimmed: Bool) {
        let resolution = try await decodeRetryingWithoutBias(isBiased: isBiased, decode: decode)
        guard shouldGuard else { return (resolution.outcome.text, resolution.retriedWithoutBias, false) }
        let guarded = WhisperKitTerminalHallucinationGuard.resolve(
            liveText: liveTailText,
            decodedText: resolution.outcome.text,
            words: resolution.outcome.words,
            audioDurationSeconds: audioDurationSeconds
        )
        return (guarded, resolution.retriedWithoutBias, guarded != resolution.outcome.text)
    }
}
