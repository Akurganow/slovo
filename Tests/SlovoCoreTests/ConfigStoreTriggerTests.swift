import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The typed push-to-talk trigger's persistence contract: the five curated wire
// values round-trip, an unknown value rejects the whole config (fail closed), an
// absent field stays backward compatible (fn), and the display names match the
// curated set. Split from ConfigStoreTests to keep each file under the strict
// file_length budget.
@Suite("ConfigStore trigger")
struct ConfigStoreTriggerTests {

    /// Each curated trigger wire value round-trips to its typed case.
    /// Stated sensitivity: reject a valid curated value, or map it to the wrong
    /// case → the loaded trigger differs → RED.
    @Test
    func curatedTriggerWireValuesRoundTrip() throws {
        let cases: [(raw: String, expected: HotkeyTrigger)] = [
            ("fn", .fn),
            ("right-command", .rightCommand),
            ("right-option", .rightOption),
            ("right-control", .rightControl),
            ("right-shift", .rightShift),
        ]
        for testCase in cases {
            let defaults = FakeUserDefaults(dataByKey: [
                ConfigStore.defaultKey: try ConfigFixtures.configData(trigger: testCase.raw),
            ])
            #expect(ConfigStore.load(from: defaults).trigger == testCase.expected,
                    "wire value \(testCase.raw) must load as \(testCase.expected)")
        }
    }

    /// A trigger value outside the curated set rejects the whole config (fail
    /// closed), so the app never binds a key it cannot execute.
    /// Stated sensitivity: loosen validation to accept an arbitrary string →
    /// "capslock" survives instead of falling back to defaults → RED.
    @Test
    func invalidFixedTriggerRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(trigger: "capslock"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// An absent trigger field decodes to fn — existing installs have no trigger
    /// field and must keep working unchanged (backward compatible, no migration).
    /// Stated sensitivity: default an absent trigger to anything but fn → RED.
    @Test
    func absentTriggerDecodesAsFn() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(trigger: nil),
        ])
        #expect(ConfigStore.load(from: defaults).trigger == .fn)
    }

    /// The default config uses the fn trigger.
    @Test
    func defaultTriggerIsFn() {
        #expect(Config.defaults.trigger == .fn)
    }

    /// Display names match the curated set exactly (menu hint + Settings picker).
    @Test
    func triggerDisplayNamesMatchTheCuratedSet() {
        #expect(HotkeyTrigger.fn.displayName == "fn")
        #expect(HotkeyTrigger.rightCommand.displayName == "Right ⌘")
        #expect(HotkeyTrigger.rightOption.displayName == "Right ⌥")
        #expect(HotkeyTrigger.rightControl.displayName == "Right ⌃")
        #expect(HotkeyTrigger.rightShift.displayName == "Right ⇧")
    }
}
