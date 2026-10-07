import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The microphone choice persists by UID with the device's name, and a stored
// config that predates it loads System Default.
@Suite("Input device config")
struct InputDeviceConfigTests {
    /// Stated sensitivity: a non-nil default → RED.
    @Test
    func defaultsToSystemDefault() {
        #expect(Config.defaults.preferredInputDevice == nil)
    }

    /// The default is nil, so only a set value proves persistence.
    /// Stated sensitivity: never encode the field → RED.
    @Test
    func preferredDeviceRoundTrips() throws {
        let defaults = FakeUserDefaults()
        let interface = InputDevice(uid: "example-uid-1", name: "Example Interface")
        try ConfigStore.save(Config(preferredInputDevice: interface), to: defaults)

        #expect(ConfigStore.load(from: defaults).preferredInputDevice == interface)
    }

    /// The fixture encodes language "ru", not the `.auto` default, so the language
    /// check proves the blob decoded rather than fell back to defaults.
    /// Stated sensitivity: `decode` instead of `decodeIfPresent` → the blob fails,
    /// loads defaults, and the language check goes RED.
    @Test
    func absentFieldMeansSystemDefault() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(),
        ])

        let loaded = ConfigStore.load(from: defaults)

        #expect(loaded.language == .ru, "the fixture blob must actually decode, not fall back to defaults")
        #expect(loaded.preferredInputDevice == nil)
    }

    /// A literal stored blob pins the wire key, which a round trip cannot: encode
    /// and decode share one coding key.
    /// Stated sensitivity: a coding key raw value other than "preferredInputDevice" → RED.
    @Test
    func storedDeviceDecodesFromWireKey() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                preferredInputDevice: ["uid": "example-uid-1", "name": "Example Interface"]
            ),
        ])

        let loaded = ConfigStore.load(from: defaults)

        #expect(loaded.preferredInputDevice == InputDevice(uid: "example-uid-1", name: "Example Interface"))
    }

    /// Stated sensitivity: `encode` instead of `encodeIfPresent` writes a null → RED.
    @Test
    func systemDefaultOmitsTheWireField() throws {
        #expect(try storedKeys(of: Config.defaults).contains("preferredInputDevice") == false)

        let interface = InputDevice(uid: "example-uid-1", name: "Example Interface")
        #expect(try storedKeys(of: Config(preferredInputDevice: interface)).contains("preferredInputDevice"))
    }

    private func storedKeys(of config: Config) throws -> Set<String> {
        let defaults = FakeUserDefaults()
        try ConfigStore.save(config, to: defaults)
        let data = try #require(defaults.data(forKey: ConfigStore.defaultKey))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }
}
