import Foundation
import Testing

import LoquiCore

// Epic 09c — build-only adapter surface. CI must prove the adapter exists,
// conforms to `Transcriber`, carries a config-driven multilingual model string,
// and does not claim the real WhisperKit bias field is verified in CI.
@Suite("Epic 09c WhisperKitTranscriber build-only")
struct WhisperKitTranscriberTests {
    @Test
    func adapterConformsToTranscriberAtCompileTime() {
        let _: any Transcriber = WhisperKitTranscriber(configuration: .defaults)
    }

    /// Stated sensitivity: hardcode an English-only model or drop config-driven
    /// model selection → the default model assertion fails.
    @Test
    func defaultsUseConfigDrivenMultilingualModel() {
        let config = WhisperKitTranscriber.Configuration.defaults

        #expect(config.model == "large-v3-v20240930_turbo_632MB")
        #expect(!config.model.hasSuffix(".en"))
        #expect(config.language == .auto)
    }

    /// Stated sensitivity: claiming a real bias field before the L4 SDK check
    /// closes U5 would hide an invented/no-op parameter behind a green CI build.
    @Test
    func biasFieldRemainsL4Verified() {
        #expect(WhisperKitTranscriber.biasFieldVerification == .requiresL4Verification)
    }

    /// Stated sensitivity: ignore the real `Term` values or encode an empty
    /// prompt → the captured prompt misses the expected text and this fails.
    @Test
    func biasPromptBuilderMapsTermsAndExpansionsIntoTokens() {
        let terms = [
            Term(term: "ExampleCorp", expansion: "ExampleCorp Incorporated", lang: .en, weight: 9),
            Term(term: "GitHub", expansion: nil, lang: .en, weight: 7),
        ]
        var capturedPrompt: String?

        let tokens = WhisperKitBiasPromptBuilder.promptTokens(for: terms) { prompt in
            capturedPrompt = prompt
            return prompt.utf8.map(Int.init)
        }

        #expect(tokens?.isEmpty == false)
        #expect(capturedPrompt?.contains("ExampleCorp ExampleCorp Incorporated") == true)
        #expect(capturedPrompt?.contains("GitHub") == true)
    }

    /// Stated sensitivity: pass no terms or whitespace-only terms → no prompt
    /// should be injected into WhisperKit decode options.
    @Test
    func biasPromptBuilderSkipsEmptyBiasTerms() {
        let empty = WhisperKitBiasPromptBuilder.promptTokens(for: []) { _ in [1] }
        let whitespace = WhisperKitBiasPromptBuilder.promptTokens(
            for: [Term(term: "  ", expansion: nil, lang: .en, weight: 1)]
        ) { _ in [1] }

        #expect(empty == nil)
        #expect(whitespace == nil)
    }

    /// Stated sensitivity: bypass the tested builder inside the adapter → this
    /// bridge assertion catches the drift before L4.
    @Test
    func adapterUsesTestedBiasPromptBuilder() throws {
        let source = try String(contentsOfFile: Self.adapterPath, encoding: .utf8)

        #expect(source.contains("WhisperKitBiasPromptBuilder.promptTokens"))
    }

    private static var adapterPath: String {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/LoquiCore/ASR/WhisperKitTranscriber.swift")
            .path
    }
}
