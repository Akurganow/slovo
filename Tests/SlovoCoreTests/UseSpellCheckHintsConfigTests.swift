import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

@Suite("Spell-check hints config")
struct UseSpellCheckHintsConfigTests {
    /// The load-bearing wire-path test. Stated sensitivity: an implementation that
    /// never persists the field (or encodes it under the wrong key) reads back the
    /// `true` default, so a saved `false` returns `true` → RED. Because the default
    /// is `true`, `false` is the only value that can prove the field survives.
    @Test
    func useSpellCheckHintsRoundTripsFalse() throws {
        let defaults = FakeUserDefaults()
        try ConfigStore.save(Config(useSpellCheckHints: false), to: defaults)

        #expect(ConfigStore.load(from: defaults).useSpellCheckHints == false)
    }

    /// Companion to the False case. NOTE: this one is tautological — the default is
    /// `true`, so a never-persisting implementation still passes; it cannot prove the
    /// wire path (that is `useSpellCheckHintsRoundTripsFalse`'s job). It only guards
    /// against an encode that corrupts an explicit `true` into a non-bool.
    @Test
    func useSpellCheckHintsRoundTripsTrue() throws {
        let defaults = FakeUserDefaults()
        try ConfigStore.save(Config(useSpellCheckHints: true), to: defaults)

        #expect(ConfigStore.load(from: defaults).useSpellCheckHints == true)
    }

    /// Stated sensitivity: defaulting an absent wire field to `false` breaks
    /// backward compatibility for existing installs — this turns red.
    @Test
    func absentWireFieldDefaultsToTrue() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(),
        ])

        #expect(ConfigStore.load(from: defaults).useSpellCheckHints == true)
    }

    /// Stated sensitivity: hard-coding `true` in the `cleanupConfig` passthrough
    /// makes the orchestrator's toggle inert — this turns red.
    @Test
    func cleanupConfigCarriesUseSpellCheckHints() {
        #expect(Config(useSpellCheckHints: false).cleanupConfig.useSpellCheckHints == false)
        #expect(Config(useSpellCheckHints: true).cleanupConfig.useSpellCheckHints == true)
    }
}
