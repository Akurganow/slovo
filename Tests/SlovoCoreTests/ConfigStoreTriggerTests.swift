import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The typed push-to-talk trigger's persistence contract: the curated wire values
// decode, an absent field stays backward compatible (fn), and the display names
// match the curated set. An unreadable value is recovered per field in
// ConfigStoreRecoveryTests. Split from ConfigStoreTests to keep each file under
// the strict file_length budget.
@Suite("ConfigStore trigger")
struct ConfigStoreTriggerTests {

    /// Each curated trigger wire value decodes to its typed case.
    /// Stated sensitivity: reject a valid curated value, or map it to the wrong
    /// case → the loaded trigger differs → RED.
    @Test
    func curatedTriggerWireValuesDecode() throws {
        let cases: [(raw: String, expected: HotkeyTrigger)] = [
            ("fn", .fn),
            ("left-command", .leftCommand),
            ("right-command", .rightCommand),
            ("left-option", .leftOption),
            ("right-option", .rightOption),
            ("left-shift", .leftShift),
            ("right-shift", .rightShift),
            ("control", .control),
        ]
        for testCase in cases {
            // Control is also the DEFAULT translate key, so a Control main key needs
            // an explicit non-colliding translate key — otherwise the pair collides,
            // both keys return to their defaults, and this row would prove nothing.
            let translateTrigger = testCase.expected == .control ? "left-shift" : nil
            let defaults = FakeUserDefaults(dataByKey: [
                ConfigStore.defaultKey: try ConfigFixtures.configData(
                    trigger: testCase.raw, translateTrigger: translateTrigger
                ),
            ])
            #expect(ConfigStore.load(from: defaults).trigger == testCase.expected,
                    "wire value \(testCase.raw) must load as \(testCase.expected)")
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
    /// Control carries no side word, because it names both Control keys at once.
    @Test
    func triggerDisplayNamesMatchTheCuratedSet() {
        #expect(HotkeyTrigger.fn.displayName == "fn")
        #expect(HotkeyTrigger.leftCommand.displayName == "Left ⌘")
        #expect(HotkeyTrigger.rightCommand.displayName == "Right ⌘")
        #expect(HotkeyTrigger.leftOption.displayName == "Left ⌥")
        #expect(HotkeyTrigger.rightOption.displayName == "Right ⌥")
        #expect(HotkeyTrigger.leftShift.displayName == "Left ⇧")
        #expect(HotkeyTrigger.rightShift.displayName == "Right ⇧")
        #expect(HotkeyTrigger.control.displayName == "⌃")
    }
}
