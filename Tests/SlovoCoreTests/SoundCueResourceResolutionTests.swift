import Testing

@testable import SlovoCore

// The only runtime check of the lookup that decides whether a cue is heard: asset
// tests read the source tree, source guards match strings, packaging runs outside
// `swift test`. Production reports what it resolved, so no literals are repeated here.
@Suite("Sound cue resource resolution")
struct SoundCueResourceResolutionTests {
    /// Sensitivity: a changed subdirectory or extension empties the set; a changed cue
    /// name drops that one cue.
    @Test
    func everyDictationCueResolvesFromTheBundleAtRuntime() {
        let player = AudioServicesAlertCuePlayer(log: Self.log)

        #expect(player.resolvedCues == [.start, .end, .error],
                "every dictation cue must resolve from the packaged SlovoCore bundle at runtime")
    }

    /// Sensitivity: separates "bundle missing" from "cue misnamed" when resolution fails.
    @Test
    func slovoCoreBundleResolvesInThisProcess() {
        #expect(SlovoCoreResourceBundle.resolve() != nil,
                "the SlovoCore resource bundle must resolve outside a packaged app too")
    }

    private static let log = RedactionSafeLog(subsystem: "slovo", category: "cue-resource-test")
}
