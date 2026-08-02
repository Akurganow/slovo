import Foundation
import Testing

@Suite("Sound cue wiring source guards")
struct SoundCueWiringSourceGuardTests {
    /// One observable preference projects both UI surfaces, persists changes, and
    /// synchronously reaches the controller before the next session snapshots it.
    /// Sensitivity: restore a local Settings copy, render the menu from ConfigStore,
    /// add an async actor hop/duplicate initial writer, or add app volume → RED.
    @Test
    func uiProjectsOnePreferenceWithSynchronousControllerUpdates() throws {
        let preferenceModel = try AppRuntimeSourceGuardTests.code(
            "Sources/SlovoCore/Config/DictationSoundCuePreferenceModel.swift"
        )
        let general = try AppRuntimeSourceGuardTests.code("Sources/slovo/Settings/GeneralSettingsPane.swift")
        let actions = try AppRuntimeSourceGuardTests.code("Sources/slovo/Settings/SettingsActions.swift")
        let builder = try AppRuntimeSourceGuardTests.code("Sources/slovo/DictationMenuBuilder.swift")
        let delegate = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate.swift")
        let soundCues = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate+SoundCues.swift")
        let composition = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppComposition.swift")
        let orchestrator = try AppRuntimeSourceGuardTests.code("Sources/SlovoCore/Orchestrator.swift")
        let pipelineFactory = try AppRuntimeSourceGuardTests.code("Sources/SlovoCore/Composition/PipelineFactory.swift")
        let makeMenu = try AppRuntimeSourceGuardTests.functionBody(named: "makeMenu", in: delegate)
        let makeLive = try AppRuntimeSourceGuardTests.functionBody(named: "makeLive", in: composition)
        let apply = try AppRuntimeSourceGuardTests.functionBody(named: "applyPlaysDictationSoundCues", in: soundCues)
        let toggle = try AppRuntimeSourceGuardTests.functionBody(named: "toggleDictationSoundCues", in: soundCues)

        #expect(preferenceModel.contains("@MainActor"))
        #expect(preferenceModel.contains("final class DictationSoundCuePreferenceModel: ObservableObject"))
        #expect(preferenceModel.contains("@Published public private(set) var isEnabled"),
                "the shared UI projection must be observable but mutated through one path")
        #expect(preferenceModel.contains("func update(_ isEnabled: Bool)"))
        #expect(actions.contains("var dictationSoundCuePreferenceModel: DictationSoundCuePreferenceModel { get }"),
                "Settings and AppDelegate must expose the same observable model instance")
        #expect(general.contains("@ObservedObject"))
        #expect(general.contains("DictationSoundCuePreferenceModel"))
        #expect(general.contains("Sound Cues") && general.contains("dictationSoundCuePreferenceModel.isEnabled"))
        #expect(!general.contains("@State private var playsDictationSoundCues"),
                "General must not cache a stale independent copy of the preference")
        #expect(builder.contains("Sound Cues") && builder.contains("state = isOn ? .on : .off"))
        #expect(builder.contains("#selector(AppDelegate.toggleDictationSoundCues(_:))"),
                "the menu row must call the real cue toggle selector")
        #expect(makeMenu.contains("playsDictationSoundCues: dictationSoundCuePreferenceModel.isEnabled"),
                "the dropdown must project the same live model as General")
        #expect(!makeMenu.contains("playsDictationSoundCues: config.playsDictationSoundCues"),
                "the menu must not bypass the observable UI source with a stale persisted reread")

        #expect(makeLive.contains("let cueController = AudioServicesDictationCueController("))
        #expect(makeLive.contains("isEnabled: config.playsDictationSoundCues"),
                "AppComposition alone owns the persisted initial controller value")
        #expect(makeLive.components(separatedBy: "cueController: cueController").count == 3,
                "one controller instance must feed Dependencies and Live ownership")
        #expect(!orchestrator.contains("playsDictationSoundCues"))
        #expect(!orchestrator.contains("updatePlaysDictationSoundCues"))
        #expect(!pipelineFactory.contains("playsDictationSoundCues"),
                "Orchestrator and PipelineFactory must not duplicate initial preference ownership")

        #expect(apply.contains("config.playsDictationSoundCues = enabled"))
        #expect(apply.contains("ConfigStore.save(config"), "the live apply path must persist the preference")
        #expect(apply.contains("composition?.cueController.updateEnabled(enabled)"),
                "the owner must receive the update synchronously before another key-down")
        #expect(apply.contains("dictationSoundCuePreferenceModel.update(enabled)"),
                "both UI surfaces must observe the successfully persisted value")
        #expect(apply.contains("installStatusMenu()"), "the live apply path must refresh the menu checkmark")
        #expect(Self.appearsInOrder([
            "ConfigStore.save(config", "composition?.cueController.updateEnabled(enabled)",
            "dictationSoundCuePreferenceModel.update(enabled)", "installStatusMenu()",
        ], in: apply), "persist, synchronously update owner/UI state, then rebuild the menu")
        #expect(!apply.contains("Task {") && !apply.contains("await ") && !apply.contains(".orchestrator."),
                "a fire-and-forget actor hop can lose the race with the next key-down snapshot")
        #expect(toggle.contains("applyPlaysDictationSoundCues(!dictationSoundCuePreferenceModel.isEnabled)"),
                "the menu selector must invert the shared observable value")
        #expect(!toggle.contains("ConfigStore.load"), "the toggle must not fork UI authority back to persistence")
    }

    /// The policy scans both production app targets, so a helper introduced away
    /// from today's cue files cannot hide an app-owned volume or alternate player.
    /// Sensitivity: any forbidden token in any production Swift file → RED; removing
    /// alert playback from the real player independently breaks the positive guard.
    @Test
    func productionSourcesUseOnlyThePublicAlertVolumePath() throws {
        let sources = try Self.productionSwiftSources()
        let violations = Self.volumePolicyViolations(in: sources)
        #expect(violations.isEmpty, "app-owned cue volume/private playback found: \(violations)")

        let cuePlayer = try AppRuntimeSourceGuardTests.code("Sources/SlovoCore/Audio/DictationCueController.swift")
        #expect(cuePlayer.contains("AudioServicesCreateSystemSoundID"))
        #expect(cuePlayer.contains("AudioServicesPlayAlertSoundWithCompletion"),
                "alert playback follows the macOS alert/notification volume")
        #expect(cuePlayer.contains("AudioServicesDisposeSystemSoundID"), "owned sound IDs must be disposed")

        let updater = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate+UpdateMenu.swift")
        #expect(!updater.contains("DictationCue") && !updater.contains("cueController"),
                "updater failures must not emit dictation cues")
    }

    /// Safe in-memory mutations prove the repository scan catches displaced cue
    /// settings/playback while allowing the unrelated CoreAudio mute and fn-key
    /// preference adapters that Slovo legitimately owns.
    @Test
    func volumePolicyRejectsCueMutationsWithoutFlaggingUnrelatedSystemAdapters() {
        let mutations = [
            ProductionSource(path: "Sources/slovo/FutureCueSettings.swift", contents: "let soundCueVolume = 0.4"),
            ProductionSource(path: "Sources/SlovoCore/Audio/FutureCuePlayer.swift", contents: "NSSound(named: nil)?.play()"),
            ProductionSource(
                path: "Sources/SlovoCore/Audio/FutureCuePlayer.swift",
                contents: "AudioServicesPlaySystemSound(soundID)"
            ),
            ProductionSource(
                path: "Sources/slovo/FutureCueSettings.swift",
                contents: #"CFPreferencesCopyAppValue("com.apple.sound.beep.volume" as CFString, domain)"#
            ),
        ]
        for mutation in mutations {
            #expect(!Self.volumePolicyViolations(in: [mutation]).isEmpty,
                    "policy failed to catch mutation in \(mutation.path)")
        }

        let legitimateAdapters = ProductionSource(
            path: "Sources/SlovoCore/SystemAdapters.swift",
            contents: "AudioObjectSetPropertyData(); CFPreferencesCopyAppValue(\"AppleFnUsageType\", domain)"
        )
        #expect(Self.volumePolicyViolations(in: [legitimateAdapters]).isEmpty,
                "generic mute/fn adapters are outside the cue-volume prohibition")
    }

    /// Sensitivity: failing to paint every classified failure red, or resetting a
    /// persistent failure title with the brief glyph, breaks these guards.
    @Test
    func failureStatusDrivesBriefRedGlyphWithoutErasingPersistentText() throws {
        let delegate = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate.swift")
        let orchestrator = try AppRuntimeSourceGuardTests.code("Sources/SlovoCore/Orchestrator.swift")
        let showStatus = try AppRuntimeSourceGuardTests.functionBody(named: "showStatus", in: delegate)
        let flash = try AppRuntimeSourceGuardTests.functionBody(named: "flashBriefStatusGlyph", in: delegate)
        let reportStatus = try AppRuntimeSourceGuardTests.functionBody(named: "reportStatus", in: orchestrator)
        #expect(showStatus.contains("status.isFailureNotice"))
        #expect(showStatus.contains("flashBriefStatusGlyph(status)"))
        #expect(showStatus.contains("statusTextItem?.title = Self.title(for: status)"))
        #expect(flash.contains("status.isPersistentNotice"),
                "brief red paint must not reset persistent failure text to the idle hint")
        #expect(reportStatus.contains("status.isFailureNotice"))
        #expect(reportStatus.contains("cueController.enqueue(.error)"),
                "the same classified failure event must enqueue one Error cue")
        #expect(reportStatus.contains("statusReporter(status)"),
                "the Error cue and red glyph must remain projections of the same status event")
    }

    /// Sensitivity: omitting resource declaration, one dev-verify assertion, the
    /// CC0 attribution/source/recipe, or user-facing behavior documentation → RED.
    @Test
    func resourcesPackagingNoticesAndDocsTravelTogether() throws {
        let manifest = try Self.source("Package.swift")
        let launcher = try Self.source("Scripts/build_and_run.sh")
        let notices = try Self.source("THIRD-PARTY-NOTICES.md")
        let readme = try Self.source("README.md")

        #expect(manifest.contains(#".copy("Resources/AudioCues")"#))
        for name in ["start.wav", "end.wav", "error.wav"] {
            #expect(launcher.contains("Resources/slovo_SlovoCore.bundle/AudioCues/\(name)"),
                    "dev --verify must assert packaged \(name)")
        }
        for required in ["AbdrTar", "CC0 1.0", "519985", "519986", "558121", "asetrate=44160", "lowpass=f=2400"] {
            #expect(notices.contains(required), "third-party notices must preserve \(required)")
        }
        #expect(readme.contains("Sound Cues"))
        #expect(readme.localizedCaseInsensitiveContains("alert volume"),
                "README must explain that cue loudness follows the system alert volume")
    }

    private struct ProductionSource {
        let path: String
        let contents: String
    }

    private static let forbiddenVolumePolicyTokens = [
        "soundCueVolume", "dictationCueVolume", "cueVolume", "alertVolume",
        "Sound Cue Volume", "AudioServicesPlaySystemSound", "AudioServicesSetProperty",
        "AVAudioPlayer", "NSSound", "com.apple.sound.beep.volume", "com.apple.systemsound",
    ]

    private static func productionSwiftSources() throws -> [ProductionSource] {
        try ["Sources/SlovoCore", "Sources/slovo"].flatMap { relativeRoot in
            let root = packageRoot.appending(path: relativeRoot, directoryHint: .isDirectory)
            return try FileManager.default.subpathsOfDirectory(atPath: root.path)
                .filter { path in
                    path.hasSuffix(".swift")
                        && !path.split(separator: "/").contains("Generated")
                        && !path.hasSuffix("resource_bundle_accessor.swift")
                }
                .map { path in
                    ProductionSource(
                        path: "\(relativeRoot)/\(path)",
                        contents: try String(contentsOf: root.appending(path: path), encoding: .utf8)
                    )
                }
        }
    }

    private static func volumePolicyViolations(in sources: [ProductionSource]) -> [String] {
        sources.flatMap { source in
            forbiddenVolumePolicyTokens.compactMap { token in
                source.contents.contains(token) ? "\(source.path): \(token)" : nil
            }
        }
    }

    private static func source(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8)
    }

    private static func appearsInOrder(_ needles: [String], in source: String) -> Bool {
        var cursor = source.startIndex
        for needle in needles {
            guard let range = source.range(of: needle, range: cursor..<source.endIndex) else { return false }
            cursor = range.upperBound
        }
        return true
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
