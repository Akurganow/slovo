import Foundation

/// Converts one live microphone chunk into the decoder's raw sample format. The
/// concrete target policy lives inside the conforming type so the streaming
/// transcriber stays format-agnostic.
public protocol AudioConverting {
    /// Returns the chunk resampled to the decoder's target format as mono float
    /// samples. Throws when the chunk cannot be converted.
    func convert(_ chunk: AudioChunk) throws -> [Float]
}
