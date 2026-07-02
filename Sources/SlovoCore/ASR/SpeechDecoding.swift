import Foundation

/// The inference seam behind which the on-device WhisperKit engine sits: prompt
/// tokenization plus a single decode of accumulated samples. No WhisperKit SDK
/// type crosses this boundary, so the streaming transcriber can be driven by a
/// fake engine in tests.
public protocol SpeechDecoding {
    /// Encodes a bias prompt into engine tokens. An empty result means the
    /// tokenizer is unavailable (decode then runs without bias tokens).
    func encodePromptTokens(_ prompt: String) -> [Int]

    /// Decodes the accumulated samples once, optionally biased by `promptTokens`.
    func decode(samples: [Float], promptTokens: [Int]?) async throws -> String
}
