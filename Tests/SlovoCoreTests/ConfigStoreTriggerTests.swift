import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The typed push-to-talk trigger's persistence contract: the seven curated wire
// values round-trip, retired and unknown values both reject the whole config
// (fail closed, no migration machinery), an absent field stays backward
// compatible (fn), and the display names match the curated set. Split from
// ConfigStoreTests to keep each file under the strict file_length budget.
@Suite("ConfigStore trigger")
struct ConfigStoreTriggerTests {

    /// Each curated trigger wire value round-trips to its typed case.
    /// Stated sensitivity: reject a valid curated value, or map it to the wrong
    /// case → the loaded trigger differs → RED.
    @Test
    func curatedTriggerWireValuesRoundTrip() throws {
        let cases: [(raw: String, expected: HotkeyTrigger)] = [
            ("fn", .fn),
            ("left-command", .leftCommand),
            ("right-command", .rightCommand),
            ("left-option", .leftOption),
            ("right-option", .rightOption),
            ("left-shift", .leftShift),
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

    /// A RETIRED trigger value ("right-control" — the Control trigger is removed:
    /// Control is translate-only, and most Mac laptops have no right Control) and
    /// an unknown one ("capslock") ride the SAME fail-closed path: the whole
    /// config resets to defaults (trigger fn) — deliberately including non-default
    /// siblings, the owner-accepted full-reset semantics (no per-field salvage).
    /// Stated sensitivity: keep "right-control" decodable, or add salvage that
    /// preserves the sibling → the loaded config differs from `.defaults` → RED.
    /// The "capslock" row guards the pre-existing unknown-value path throughout.
    @Test
    func retiredAndUnknownTriggerValuesBothFailClosedToFnDefaults() throws {
        for triggerValue in ["right-control", "capslock"] {
            let defaults = FakeUserDefaults(dataByKey: [
                ConfigStore.defaultKey: try ConfigFixtures.configData(
                    trigger: triggerValue,
                    openRouterModel: "custom/sibling-model"
                ),
            ])
            let loaded = ConfigStore.load(from: defaults)
            #expect(loaded == .defaults, "\(triggerValue) must reset the WHOLE config, sibling included")
            #expect(loaded.trigger == .fn, "\(triggerValue) must fall back to the fn default")
        }
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
        #expect(HotkeyTrigger.leftCommand.displayName == "Left ⌘")
        #expect(HotkeyTrigger.rightCommand.displayName == "Right ⌘")
        #expect(HotkeyTrigger.leftOption.displayName == "Left ⌥")
        #expect(HotkeyTrigger.rightOption.displayName == "Right ⌥")
        #expect(HotkeyTrigger.leftShift.displayName == "Left ⇧")
        #expect(HotkeyTrigger.rightShift.displayName == "Right ⇧")
    }
}
