import Foundation
import Testing

@testable import SlovoCore

@Suite("WhisperKit terminal hallucination guard")
struct WhisperKitHallucinationGuardTests {
    /// Sensitivity: replacing all eligibility requirements with alternatives makes
    /// each negative case inspect evidence from an unsupported transcription path.
    @Test
    func inspectionRequiresShortUnconfirmedAudioAndLiveText() {
        #expect(WhisperKitTerminalHallucinationGuard.shouldInspect(
            sampleCount: 479_999,
            modelWindowSampleCount: 480_000,
            confirmedEndSeconds: 0,
            liveText: "hello"
        ))
        #expect(!WhisperKitTerminalHallucinationGuard.shouldInspect(
            sampleCount: 480_000,
            modelWindowSampleCount: 480_000,
            confirmedEndSeconds: 0,
            liveText: "hello"
        ))
        #expect(!WhisperKitTerminalHallucinationGuard.shouldInspect(
            sampleCount: 479_999,
            modelWindowSampleCount: 480_000,
            confirmedEndSeconds: 0.1,
            liveText: "hello"
        ))
        #expect(!WhisperKitTerminalHallucinationGuard.shouldInspect(
            sampleCount: 479_999,
            modelWindowSampleCount: 480_000,
            confirmedEndSeconds: 0,
            liveText: ""
        ))
    }

    /// Sensitivity: removing the mixed-language prefix comparison or treating the
    /// recording boundary as inside keeps the hallucinated terminal word.
    @Test
    func outsideAnomalousSuffixReusesMixedLanguageLiveText() {
        let liveText = "привет hello"
        let decodedText = "привет hello merci thank you"

        #expect(
            WhisperKitTerminalHallucinationGuard.resolve(
                liveText: liveText,
                decodedText: decodedText,
                words: [
                    decodedWord("привет", probability: 0.99, start: 0.1, end: 0.4),
                    decodedWord("hello", probability: 0.99, start: 0.5, end: 0.8),
                    decodedWord("merci", probability: 0.05, start: 1.01, end: 1.21),
                    decodedWord("thank", probability: 0.05, start: 1.21, end: 1.41),
                    decodedWord("you", probability: 0.99, start: 1.41, end: 1.46),
                ],
                audioDurationSeconds: 1.0
            ) == liveText
        )
    }

    /// Sensitivity: anomaly scoring without the outside-audio requirement deletes
    /// a quiet but timestamped final word that belongs to the recording.
    @Test
    func anomalousSuffixInsideAudioKeepsDecodedText() {
        let decodedText = "call Мария"

        #expect(
            WhisperKitTerminalHallucinationGuard.resolve(
                liveText: "call",
                decodedText: decodedText,
                words: [
                    decodedWord("call", probability: 0.99, start: 0.1, end: 0.5),
                    decodedWord("Мария", probability: 0.05, start: 0.94, end: 0.99),
                ],
                audioDurationSeconds: 1.0
            ) == decodedText
        )
    }

    /// Sensitivity: changing the strict boundary check to greater-than-or-equal
    /// discards a legitimate word whose timestamp was rounded to the audio end.
    @Test
    func anomalousSuffixAtRoundedBoundaryKeepsDecodedText() {
        let decodedText = "call Maria"

        #expect(
            WhisperKitTerminalHallucinationGuard.resolve(
                liveText: "call",
                decodedText: decodedText,
                words: [
                    decodedWord("call", probability: 0.99, start: 0.1, end: 0.5),
                    decodedWord("Maria", probability: 0.05, start: 1.0, end: 1.05),
                ],
                audioDurationSeconds: 1.0
            ) == decodedText
        )
    }

    /// Sensitivity: dropping the upstream anomaly-score requirement replaces a
    /// credible final word merely because its timestamp is outside the recording.
    @Test
    func credibleTerminalWordKeepsDecodedText() {
        let decodedText = "call Maria"

        #expect(
            WhisperKitTerminalHallucinationGuard.resolve(
                liveText: "call",
                decodedText: decodedText,
                words: [
                    decodedWord("call", probability: 0.99, start: 0.1, end: 0.5),
                    decodedWord("Maria", probability: 0.95, start: 1.01, end: 1.31),
                ],
                audioDurationSeconds: 1.0
            ) == decodedText
        )
    }

    /// Sensitivity: suffix-only comparison discards a legitimate correction when
    /// the final decode no longer starts with the normalized live transcript.
    @Test
    func correctedNonPrefixTranscriptKeepsDecodedText() {
        let decodedText = "turn off light merci"

        #expect(
            WhisperKitTerminalHallucinationGuard.resolve(
                liveText: "turn on light",
                decodedText: decodedText,
                words: [
                    decodedWord("turn", probability: 0.99, start: 0.1, end: 0.2),
                    decodedWord("off", probability: 0.99, start: 0.3, end: 0.4),
                    decodedWord("light", probability: 0.99, start: 0.5, end: 0.8),
                    decodedWord("merci", probability: 0.05, start: 1.01, end: 1.06),
                ],
                audioDurationSeconds: 1.0
            ) == decodedText
        )
    }

    /// Sensitivity: guessing through absent, mismatched, or reversed timings can
    /// replace decoded text without evidence that its terminal word is impossible.
    @Test
    func incompleteWordEvidenceKeepsDecodedText() {
        let liveText = "hello"
        let decodedText = "hello merci"

        #expect(WhisperKitTerminalHallucinationGuard.resolve(
            liveText: liveText,
            decodedText: decodedText,
            words: nil,
            audioDurationSeconds: 1.0
        ) == decodedText)
        #expect(WhisperKitTerminalHallucinationGuard.resolve(
            liveText: liveText,
            decodedText: decodedText,
            words: [
                decodedWord("hello", probability: 0.99, start: 0.1, end: 0.5),
                decodedWord("thanks", probability: 0.05, start: 1.01, end: 1.06),
            ],
            audioDurationSeconds: 1.0
        ) == decodedText)
        #expect(WhisperKitTerminalHallucinationGuard.resolve(
            liveText: liveText,
            decodedText: decodedText,
            words: [
                decodedWord("hello", probability: 0.99, start: 0.1, end: 0.5),
                decodedWord("merci", probability: 0.05, start: 1.05, end: 1.0),
            ],
            audioDurationSeconds: 1.0
        ) == decodedText)
    }

    /// Sensitivity: omitting the long-duration term or scoring beyond the first
    /// eight suffix words changes one of these two upstream classifications.
    @Test
    func anomalyScoreUsesLongDurationAndOnlyTheFirstEightWords() {
        #expect(WhisperKitTerminalHallucinationGuard.resolve(
            liveText: "hello",
            decodedText: "hello stretched",
            words: [
                decodedWord("hello", probability: 0.99, start: 0.1, end: 0.5),
                decodedWord("stretched", probability: 0.99, start: 1.01, end: 4.11),
            ],
            audioDurationSeconds: 1.0
        ) == "hello")

        let suffixWords: [WhisperKitDecodedWord] = (1...9).map { index in
            let start = 1.0 + Float(index) * 0.2
            let duration: Float = index == 9 ? 4.1 : 0.2
            return decodedWord(
                "word\(index)",
                probability: index == 9 ? 0.01 : 0.99,
                start: start,
                end: start + duration
            )
        }
        let decodedText = "hello " + suffixWords.map(\.text).joined(separator: " ")
        #expect(WhisperKitTerminalHallucinationGuard.resolve(
            liveText: "hello",
            decodedText: decodedText,
            words: [decodedWord("hello", probability: 0.99, start: 0.1, end: 0.5)] + suffixWords,
            audioDurationSeconds: 1.0
        ) == decodedText)
    }

    /// Sensitivity: removing finite and probability-range validation lets at
    /// least one corrupt model value satisfy anomaly and outside-audio checks.
    @Test
    func invalidNumericWordEvidenceKeepsDecodedText() {
        let liveText = "hello"
        let decodedText = "hello merci"
        let invalidSuffixWords = [
            decodedWord("merci", probability: .nan, start: 1.01, end: 1.06),
            decodedWord("merci", probability: -0.01, start: 1.01, end: 1.21),
            decodedWord("merci", probability: 1.01, start: 1.01, end: 1.06),
            decodedWord("merci", probability: 0.05, start: .nan, end: 1.06),
            decodedWord("merci", probability: 0.05, start: 1.01, end: .nan),
            decodedWord("merci", probability: 0.05, start: .infinity, end: .infinity),
            decodedWord("merci", probability: 0.99, start: 1.01, end: .infinity),
        ]

        for invalidSuffixWord in invalidSuffixWords {
            #expect(WhisperKitTerminalHallucinationGuard.resolve(
                liveText: liveText,
                decodedText: decodedText,
                words: [
                    decodedWord("hello", probability: 0.99, start: 0.1, end: 0.5),
                    invalidSuffixWord,
                ],
                audioDurationSeconds: 1.0
            ) == decodedText)
        }
    }

    private func decodedWord(
        _ text: String,
        probability: Float,
        start: Float,
        end: Float
    ) -> WhisperKitDecodedWord {
        WhisperKitDecodedWord(
            text: text,
            probability: probability,
            startSeconds: start,
            endSeconds: end
        )
    }
}
