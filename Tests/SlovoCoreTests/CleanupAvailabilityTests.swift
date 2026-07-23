import Testing

import SlovoCore

// One derivation for "cleanup is effectively off, and why" — every UI surface
// and the orchestrator push consume this value instead of re-deriving it.
@Suite("CleanupAvailability")
struct CleanupAvailabilityTests {
    /// Stated sensitivity: swap the guard order (check preference before key) →
    /// (false, false) derives `.offByChoice` instead of `.offNoKey` → RED.
    @Test
    func derivationTable() {
        #expect(CleanupAvailability.derive(preference: true, keyPresent: true) == .on)
        #expect(CleanupAvailability.derive(preference: false, keyPresent: true) == .offByChoice)
        #expect(CleanupAvailability.derive(preference: true, keyPresent: false) == .offNoKey)
        #expect(CleanupAvailability.derive(preference: false, keyPresent: false) == .offNoKey)
    }

    /// Stated sensitivity: return a non-nil line for `.on`, or swap the two off
    /// strings → RED (exact-copy assertions).
    @Test
    func statusCopyAndControlStates() {
        #expect(CleanupAvailability.on.settingsStatusLine == nil)
        #expect(CleanupAvailability.offByChoice.settingsStatusLine == "Cleanup is off.")
        #expect(CleanupAvailability.offNoKey.settingsStatusLine
            == "Cleanup is off — add an OpenRouter API key to enable it.")
        #expect(CleanupAvailability.on.isOn && !CleanupAvailability.offByChoice.isOn && !CleanupAvailability.offNoKey.isOn)
        #expect(CleanupAvailability.on.isToggleEnabled && CleanupAvailability.offByChoice.isToggleEnabled)
        #expect(!CleanupAvailability.offNoKey.isToggleEnabled)
    }
}
