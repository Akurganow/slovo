import Testing

import SlovoCore

// One decision for "can Slovo mute this output device": the menu item and the
// Settings toggle both read this value instead of re-deriving it.
@Suite("OutputMuteAvailability")
struct OutputMuteAvailabilityTests {
    /// Disabled only when the device has no lever; an unreadable name falls back to
    /// a neutral subject.
    /// Stated sensitivity: report `.available` for a nil lever, report `.unavailable` for
    /// either method, or drop the name fallback → RED. The `?? true` collapse in
    /// `CoreAudioOutputMute.outputMuteAvailability()` is not covered here.
    @Test
    func derivationTable() {
        #expect(OutputMuteAvailability.derive(lever: nil, deviceName: "Example Output")
            == .unavailable(deviceName: "Example Output"))
        #expect(OutputMuteAvailability.derive(lever: .mute, deviceName: "Example Output") == .available)
        #expect(OutputMuteAvailability.derive(lever: .virtualMasterVolume, deviceName: "Example Output") == .available)
        let unnamed = OutputMuteAvailability.derive(lever: nil, deviceName: nil)
        #expect(unnamed == .unavailable(deviceName: "This output device"))
        #expect(unnamed.unavailableHint == "This output device has no volume control macOS can set.")
    }

    /// The copy is user-visible, so the hint is pinned exactly.
    /// Stated sensitivity: invert `isToggleEnabled`, return a hint for `.available`,
    /// or drop the name from the hint → RED.
    @Test
    func projectionsOfBothCases() {
        #expect(OutputMuteAvailability.available.isToggleEnabled)
        #expect(OutputMuteAvailability.available.unavailableHint == nil)
        let unavailable = OutputMuteAvailability.unavailable(deviceName: "Example Output")
        #expect(!unavailable.isToggleEnabled)
        #expect(unavailable.unavailableHint == "Example Output has no volume control macOS can set.")
    }
}
