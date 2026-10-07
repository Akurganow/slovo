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
    /// Stated sensitivity: never encode the field, or encode it under another key → RED.
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
}
