import Foundation
import Testing

import SlovoCore

@Suite("ASR backend wire format")
struct AsrBackendWireFormatTests {
    /// `AsrBackend` is a single-case enum: the shipped WhisperKit runtime persists
    /// as the §10 wire id "whisperkit". Apple Speech left the runtime entirely and
    /// FluidAudio was refuted (no adapter), so neither has a case; raw-value
    /// additivity keeps any future case wire-safe.
    /// Stated sensitivity: change the raw value away from "whisperkit" → persisted
    /// configs no longer round-trip to the runtime backend → RED.
    @Test
    func whisperKitWireValueIsStable() throws {
        let encoded = try JSONEncoder().encode(AsrBackend.whisperKit)

        #expect(String(decoding: encoded, as: UTF8.self) == #""whisperkit""#)
        #expect(try JSONDecoder().decode(AsrBackend.self, from: encoded) == .whisperKit)
    }
}
