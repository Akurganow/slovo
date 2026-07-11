import Foundation
import Testing

import SlovoCore

// `Language` persists as a single bare string so the full WhisperKit catalog
// round-trips and pre-existing "auto"/"ru"/"en" blobs decode unchanged. The wrapper
// mirrors how the type is actually embedded (a `language` field on a stored config).
@Suite("Language wire format")
struct LanguageWireTests {
    private struct LanguageWrapper: Codable, Equatable {
        let language: Language
    }

    /// Encodes as a bare string value, not a keyed object.
    /// Stated sensitivity: encode into a keyed container (e.g. {"rawValue":"ja"}) →
    /// the field is no longer `"language":"ja"` and "rawValue" appears → RED.
    @Test
    func encodesAsBareStringValue() throws {
        let data = try JSONEncoder().encode(LanguageWrapper(language: Language(rawValue: "ja")))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"language\":\"ja\""))
        #expect(!json.contains("rawValue"))
    }

    /// Decodes a bare string into the matching code.
    /// Stated sensitivity: decode from a keyed container → decoding the bare string
    /// throws and this test errors/reddens.
    @Test
    func decodesBareStringValue() throws {
        let decoded = try JSONDecoder().decode(
            LanguageWrapper.self,
            from: Data(#"{"language":"ja"}"#.utf8)
        )
        #expect(decoded.language == Language(rawValue: "ja"))
    }

    /// Every legacy value and an exotic code survive an encode→decode round-trip.
    /// Stated sensitivity: collapse unknown codes to a fixed case (e.g. map "ja" to
    /// auto on decode) → the "ja" round-trip no longer equals its input → RED.
    @Test
    func roundTripsAutoLegacyAndExoticCodes() throws {
        for value in [Language.auto, .ru, .en, Language(rawValue: "ja")] {
            let data = try JSONEncoder().encode(LanguageWrapper(language: value))
            let decoded = try JSONDecoder().decode(LanguageWrapper.self, from: data)
            #expect(decoded.language == value)
        }
    }

    /// The static members carry exactly the legacy wire codes, so old blobs match.
    /// Stated sensitivity: change `.ru`'s rawValue to anything but "ru" → the
    /// equality fails → RED.
    @Test
    func legacyStaticMembersUseLegacyCodes() {
        #expect(Language.auto.rawValue == "auto")
        #expect(Language.ru.rawValue == "ru")
        #expect(Language.en.rawValue == "en")
    }
}
