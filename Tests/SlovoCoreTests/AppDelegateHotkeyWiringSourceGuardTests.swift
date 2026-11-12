import Foundation
import Testing

import SlovoCore

// Source guards for wiring no behavioural test can reach: no test target depends on the
// `slovo` executable. Behaviour tests such as HotkeyEdgeSequencerTests and
// HotkeyDecision*Tests cover the logic; these guards check that the app calls it. They
// read the source with comments stripped. The three guards over `CGEventTapHotkeyMonitor`
// in SlovoCore each state their own reason.
@Suite("AppDelegate hotkey wiring source guards")
struct AppDelegateHotkeyWiringSourceGuardTests {

    /// The fn hotkey must deliver every edge through the ordered sequencer, never
    /// on its own per-edge Task. Killing mutation (either direction): delete the
    /// `sequencer.send` routing, send a constant phase (`sequencer.send(.cancel)`)
    /// instead of the monitor's, or restore `onTrigger = { phase in Task { ... } }`
    /// per-edge dispatch. Then the closure no longer forwards the monitor's phase
    /// through the sequencer, or it dispatches concurrently again -> RED. Renaming
    /// the closure parameter also turns it red: nothing else guards the forwarding.
    @Test
    func onTriggerRoutesEveryEdgeThroughTheSequencer() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try SourceText.functionBody(named: "startPipeline", in: delegate)
        let onTriggerClosure = try SourceText.block(after: "hotkeyMonitor.onTrigger =", in: startPipeline)

        #expect(startPipeline.contains("HotkeyEdgeSequencer"),
                "startPipeline must build the ordered edge sequencer")
        #expect(onTriggerClosure.contains("sequencer.send(phase)"),
                "the hotkey onTrigger must forward the monitor's phase through the sequencer")
        #expect(!onTriggerClosure.contains("Task"),
                "the onTrigger closure must not dispatch each edge on its own Task (the stuck-mute race)")
        #expect(!onTriggerClosure.contains("orchestrator.handle"),
                "the onTrigger closure must not drive the orchestrator directly; ordering lives in the single consumer")
    }

    /// A second retrySetup while a teardown+rebuild is still pending must not spawn
    /// a parallel rebuild, so the re-entrancy guard has to be checked BEFORE the
    /// rebuild Task.
    /// Stated sensitivity: remove the guard, or move it below the `Task` → RED, since a
    /// concurrent retrySetup then spawns a second consumer; drop the join of the
    /// previous sequencer → RED. The guard is pinned by the flag it reads, so a second
    /// `guard` above the `Task` cannot stand in for it.
    @Test
    func retrySetupGuardsAgainstConcurrentRebuild() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let retrySetup = try SourceText.functionBody(named: "retrySetup", in: delegate)

        #expect(SourceText.containsInOrder([
            "guard !isRebuildingPipeline",
            "return",
            "Task {",
            "?.stop()",
            "startPipeline()",
        ], in: retrySetup),
        "retrySetup must guard against a second rebuild BEFORE spawning the teardown+rebuild Task")
    }

    /// A press stamped busy must be refused before the arm touches anything. Setting
    /// `isPipelineActive` first would make the following key-up drive a session that
    /// was never started.
    /// Killing mutation: delete the refusal guard, or move it below the readiness gate
    /// or below `isPipelineActive = true` -> RED. Add a second read of the stamp -> RED.
    @Test
    func keyDownMadeDuringProcessingIsRefusedBeforeAnySessionState() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try SourceText.functionBody(named: "startPipeline", in: delegate)

        #expect(SourceText.containsInOrder([
            "case .down(let mode):",
            "guard !edge.arrivedWhileBusy",
            "isModelReady",
            "self?.isPipelineActive = true",
            "orchestrator.handle(.startRequested)",
        ], in: startPipeline),
        "a press stamped busy must be refused before any session state is touched")
        #expect(startPipeline.components(separatedBy: "arrivedWhileBusy").count - 1 == 1,
                "the stamp must be read exactly once. A decoy read could satisfy the order while a second path still starts the session")
    }

    /// Key-down before the ASR model is resident must not open a session: a cold
    /// start opens the mic and then sits inside `begin` for the whole model load,
    /// with the key-up queued behind it. Killing mutation: remove the readiness
    /// guard from the `.down` arm -> RED.
    @Test
    func keyDownIsGatedOnModelReadiness() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try SourceText.functionBody(named: "startPipeline", in: delegate)

        #expect(SourceText.containsInOrder([
            "case .down(let mode):",
            "isModelReady",
            "showModelLoadingState",
            "orchestrator.handle(.startRequested)",
        ], in: startPipeline),
        "the .down arm must gate on model readiness and re-assert the loading state before any session starts")
    }

    /// The recording glyph must be DERIVED from the session's mode and the LIVE
    /// cleanup availability, through ONE shared path so the derivation cannot fork:
    /// both the `.down` and `.translateLatched` arms route the glyph through
    /// `applyRecordingGlyph`, and that helper derives it via `recordingGlyphMode` fed
    /// the live `store.state.cleanupAvailability.isOn` (the single, consumed read). The
    /// latch still surfaces the mode change LIVE while the key is held; a plain hold
    /// paints clean, and cleanup-off collapses either to raw.
    /// Killing mutation: paint a hard-coded glyph in either arm (drop the
    /// `applyRecordingGlyph` routing); hard-code `isCleanupOn:` in the helper so the
    /// live availability no longer flows into the derivation; add a SECOND, hardcoded
    /// `recordingGlyphMode(` call to drive the paint while a decoy live call satisfies
    /// the availability pin (the exactly-one-call count catches this); or decouple the
    /// derived value from the paint, e.g. `recording: mode == .translate ? .translate
    /// : glyphMode` (the `recording: glyphMode` bind catches this) → RED.
    @Test
    func recordingGlyphTracksTheLatchedMode() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try SourceText.functionBody(named: "startPipeline", in: delegate)

        #expect(SourceText.containsInOrder([
            "case .down(let mode):",
            "applyRecordingGlyph(mode)",
        ], in: startPipeline),
        "the .down arm must route the recording glyph through applyRecordingGlyph")
        #expect(SourceText.containsInOrder([
            "case .translateLatched:",
            "applyRecordingGlyph(.translate)",
        ], in: startPipeline),
        "the translate latch must route the recording glyph through applyRecordingGlyph, live")

        let helper = try SourceText.functionBody(named: "applyRecordingGlyph", in: delegate)
        #expect(SourceText.containsInOrder([
            "MenuBarGlyph.recordingGlyphMode(",
            "isCleanupOn: store.state.cleanupAvailability.isOn",
        ], in: helper),
        "applyRecordingGlyph must derive the glyph via recordingGlyphMode fed the live availability")
        #expect(helper.contains("setStatusGlyph(recording: glyphMode"),
                "the paint must bind the DERIVED glyphMode directly, not a decoupled expression")
        #expect(helper.components(separatedBy: "recordingGlyphMode(").count - 1 == 1,
                "the helper must derive exactly once — a second, hardcoded call could drive the paint while a live decoy satisfies the availability pin")
    }

    /// App-level key facts (has-key, save-key, cleanup availability) must read a
    /// provider the AppDelegate OWNS, never one pulled out of the pipeline
    /// composite: before the composition exists, a `?? false` fallback would
    /// fabricate "no key" and freeze the launch menu in offNoKey. Key presence
    /// lives in the store. It is written at launch, before each composition is
    /// built, and in the one helper that ends every key save or removal, each time
    /// read straight from the app-owned provider. A composition is seeded from the
    /// store, so the `startPipeline` write must precede `AppComposition.makeLive(`.
    /// Stated sensitivity: a key-presence write that does not read the app-owned
    /// provider → RED; a read through `composition?.openRouterKeyProvider`, or a
    /// `?? false` fallback, → RED, also after a provider member is added back to
    /// `AppComposition.Live`; drop one of the three write sites → the count reddens;
    /// move the `startPipeline` write back below `AppComposition.makeLive(` → the
    /// order assert reddens.
    @Test
    func appLayerKeyFactsReadTheAppOwnedProviderNotThePipeline() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let settings = try SourceText.code("Sources/slovo/Settings/AppDelegate+Settings.swift")

        #expect(delegate.contains("KeychainOpenRouterKeyProvider("),
                "AppDelegate must own the key provider so key facts never depend on the pipeline's lifetime")
        #expect(delegate.contains("openRouterKeyProvider: openRouterKeyProvider"),
                "the app-owned provider must be injected into AppComposition.makeLive")
        for source in [delegate, settings] {
            #expect(!source.contains("composition?.openRouterKeyProvider"),
                    "app-layer key facts must use the AppDelegate-owned provider, not the pipeline composite")
        }
        let writes = (delegate + "\n" + settings)
            .components(separatedBy: "\n")
            .filter { $0.contains("isOpenRouterKeyPresent") }
        #expect(writes.count == 3, "key presence is written at launch, before each composition, and in the key-save/removal helper")
        for write in writes {
            #expect(write.contains("openRouterKeyProvider.hasConfiguredKey()"),
                    "each key-presence write must read the app-owned provider: \(write)")
            #expect(!write.contains("?? false"), "a key-presence write must not fabricate 'no key': \(write)")
        }
        let startPipeline = try SourceText.functionBody(named: "startPipeline", in: delegate)
        let write = try #require(startPipeline.range(of: "isOpenRouterKeyPresent"))
        let build = try #require(startPipeline.range(of: "AppComposition.makeLive("))
        #expect(write.lowerBound < build.lowerBound, "the composition must be seeded with key presence read just before it")
    }

    /// A key-up whose key-down was swallowed by the readiness gate must be
    /// swallowed too, and so must the release of a refused press.
    /// Killing mutation: drop the active-pipeline guard from the `.up` arm and an
    /// idle key-up drives stopRequested and overwrites the loading glyph -> RED.
    @Test
    func keyUpPairsWithTheGatedKeyDown() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try SourceText.functionBody(named: "startPipeline", in: delegate)

        #expect(SourceText.containsInOrder([
            "case .up(let mode):",
            "isPipelineActive",
            "orchestrator.handle(.stopRequested(",
        ], in: startPipeline),
        "the .up arm must never stop a session that was never started")
    }

    /// The model warm-up must be an observable gate end to end: the composition
    /// exposes the preload as an awaitable task; the delegate enters the loading
    /// state in startPipeline and opens the gate (stopping the pulse) only when the
    /// warm-up task succeeds, which it does only on a loaded model — and only for the
    /// composition still wired, so a superseded preload's outcome cannot answer for
    /// the current one.
    /// Killing mutation: return to fire-and-forget preload, never flip
    /// isModelReady, open the gate on any completion (`_ = await
    /// live.modelWarmUp.result`, which also passes a cancelled warm-up), or delete
    /// the currency comparison from the gate task -> RED.
    @Test
    func modelWarmUpOpensTheDictationGate() throws {
        let composition = try SourceText.code("Sources/slovo/AppComposition.swift")
        #expect(SourceText.containsInOrder(["modelWarmUp", "startWarmUp()"], in: composition),
                "the composition must expose the model preload as an awaitable task")

        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try SourceText.functionBody(named: "startPipeline", in: delegate)
        #expect(startPipeline.contains("prepareModelGate"),
                "startPipeline must enter the gated loading state")

        let gate = try SourceText.code("Sources/slovo/AppDelegate+ModelGate.swift")
        #expect(SourceText.containsInOrder([
            "showModelLoadingState",
            "try? await live.modelWarmUp.value",
            "composition?.modelWarmUp",
            "isModelReady = true",
            "stopModelLoadingPulse",
        ], in: gate),
        "the CURRENT composition's warm-up must open the gate and stop the loading pulse")
    }

    /// A composition that is never gated must leave no pulse behind. The onboarding
    /// early return happens before `prepareModelGate`, so no gate task exists to stop
    /// the pulse, and the superseded composition's task now returns at the currency
    /// guard — the infinite loading animation would run for the rest of the launch
    /// with dictation refused. Reachable by hitting Retry Setup, or losing a
    /// permission, while the first download is still going.
    /// Killing mutation: drop the loading-state clear from `presentOnboarding`, or
    /// move the early return below `prepareModelGate` → RED.
    @Test
    func aCompositionThatSkipsTheGateClearsTheLoadingState() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try SourceText.functionBody(named: "startPipeline", in: delegate)
        let presentOnboarding = try SourceText.functionBody(named: "presentOnboarding", in: delegate)

        #expect(SourceText.containsInOrder([
            "guard live.onboardingSteps == [.ready] else",
            "presentOnboarding(live.onboardingSteps)",
            "return",
            "prepareModelGate",
        ], in: startPipeline),
        "the onboarding return is the path that reaches no model gate")
        #expect(presentOnboarding.contains("clearModelLoadingState()"),
                "an ungated composition must stop the loading pulse it inherited")
    }

    /// The speech model is built ONCE for the process and injected into every
    /// composition — the ownership inversion the key provider already uses. A
    /// composition that builds its own engine starts its own load, so a permission
    /// grant during a first run downloads the same artifact a second time while the
    /// first download is still running.
    /// Killing mutation: construct `WhisperKitTranscriber(` or `WhisperKitEngine(`
    /// inside makeLive again, or build a second `SharedSpeechModel(` anywhere in the
    /// delegate → RED. `SharedSpeechModelTests` proves what the shared model then
    /// does; only this guard proves the production composition uses it.
    @Test
    func theSpeechModelIsBuiltOnceForTheProcessAndInjected() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let composition = try SourceText.code("Sources/slovo/AppComposition.swift")
        let makeLive = try SourceText.functionBody(named: "makeLive", in: composition)

        #expect(delegate.components(separatedBy: "SharedSpeechModel(").count - 1 == 1,
                "exactly one speech model may be built, and the app must own it")
        #expect(delegate.contains("speechModel: speechModel"),
                "the app-owned speech model must be injected into AppComposition.makeLive")
        for forbidden in ["WhisperKitTranscriber(", "WhisperKitEngine("] {
            #expect(!makeLive.contains(forbidden),
                    "makeLive must receive the process's speech model, never construct \(forbidden)")
        }
        #expect(makeLive.contains("speechModel.transcriber"),
                "the pipeline must be wired to the shared transcriber")
    }

    /// The tap must be built with the persisted key configuration — BOTH roles, the
    /// push-to-talk key and the translate key — not a hard-coded or hand-built value.
    /// Killing mutation: construct the monitor from a literal configuration (e.g.
    /// `HotkeyConfiguration(main: .fn, translate: .control, translateIsAdditional:
    /// true)`) or from anything but `config.hotkeyConfiguration` → RED.
    @Test
    func monitorIsBuiltWithConfiguredTrigger() throws {
        let composition = try SourceText.code("Sources/slovo/AppComposition.swift")
        #expect(composition.contains("CGEventTapHotkeyMonitor(configuration: config.hotkeyConfiguration)"),
                "the monitor must be constructed with the persisted key configuration")
    }

    /// The tap must observe keyDown so a combo can interrupt a passthrough-modifier
    /// hold. The event mask is a local inside `start()`, which installs the real tap,
    /// so no test can read it.
    /// Killing mutation: drop keyDown from the event mask → the interrupt is
    /// never seen → RED.
    @Test
    func hotkeyTapObservesKeyDownForInterrupt() throws {
        let monitor = try SourceText.code("Sources/SlovoCore/Hotkey/CGEventTapHotkeyMonitor.swift")
        #expect(monitor.contains("CGEventType.keyDown.rawValue"),
                "the event mask must include keyDown so the interrupt is observable")
    }

    /// The stop the tap synthesizes after a tap death must carry the mode the
    /// decision core reports for the dead hold — a standalone translate dictation, or
    /// one the additional key latched, must not be downgraded to plain on the way
    /// out. `process(type:event:)` is `fileprivate` and only the installed tap calls it,
    /// so no test can drive this arm.
    /// Killing mutation: restore the hardcoded `onTrigger?(.up(.plain))` in the
    /// resync arm → RED.
    @Test
    func synthesizedStopCarriesTheDeadHoldsMode() throws {
        let monitor = try SourceText.code("Sources/SlovoCore/Hotkey/CGEventTapHotkeyMonitor.swift")
        #expect(monitor.contains("onTrigger?(.up(synthesizedStop))"),
                "the resync arm must emit the mode the decision core reported")
        #expect(!monitor.contains(".up(.plain)"),
                "the synthesized stop must never be hardcoded to plain")
    }

    /// Privacy invariant: a non-trigger keyDown contributes only the fact that a
    /// key went down — never its typed character or key code. `process(type:event:)` is
    /// `fileprivate` and only the installed tap calls it, so no test can feed it a keyDown,
    /// and the absence is read from the source. Killing mutations:
    /// read the typed character (add `keyboardGetUnicodeString`), or read the key
    /// code outside the flagsChanged arm to retain key identity → RED. Zero the key
    /// code in the flagsChanged arm → RED.
    @Test
    func keyDownCarriesNoKeyContent() throws {
        let monitor = try SourceText.code("Sources/SlovoCore/Hotkey/CGEventTapHotkeyMonitor.swift")
        #expect(SourceText.containsInOrder(["case .keyDown:", "= .keyDown"], in: monitor),
                "the keyDown arm must map to the payload-free input, not read the event")
        #expect(!monitor.contains("keyboardGetUnicodeString"),
                "the tap must never read a keystroke's typed character")
        // Only the flagsChanged trigger detection reads a key code. A read in the keyDown
        // arm, or before the switch, would retain the pressed key.
        let flagsChangedArm = try SourceText.slice(of: monitor, from: "case .flagsChanged:", to: "case ")
        #expect(!monitor.replacingOccurrences(of: flagsChangedArm, with: "").contains(".keyboardEventKeycode"),
                "only the flagsChanged arm may read a key code")
        #expect(flagsChangedArm.contains(".keyboardEventKeycode"),
                "the trigger detection reads the modifier key code")
    }

    /// All three key settings apply live through the store's hotkey subscriber,
    /// which hands the tap the saved configuration. The app target holds the one
    /// reconfigure call, inside the target closure.
    /// Stated sensitivity: add a second `hotkeyMonitor.reconfigure(configuration:`
    /// call anywhere in Sources/slovo, or reconfigure from anything but the
    /// subscriber's value → RED.
    @Test
    func everyKeySettingAppliesInPlaceWithoutRebuild() throws {
        var reconfigureCount = 0
        for file in try SourceText.swiftFiles(under: "Sources/slovo") {
            reconfigureCount += try SourceText.code(file).components(separatedBy: "hotkeyMonitor.reconfigure(configuration:").count - 1
        }
        #expect(reconfigureCount == 1, "the app target must reconfigure the tap from exactly one place")
        let storeWiring = try SourceText.code("Sources/slovo/AppDelegate+Store.swift")
        #expect(storeWiring.contains("hotkeyMonitor.reconfigure(configuration: $0)"),
                "the one reconfigure call must pass the value the store's subscriber hands the hotkey target")
    }

    /// The system facts the dropdown shows must be re-read on every menu OPEN, not
    /// only at a rebuild: the user changes the fn assignment in System Settings, the
    /// default output device or the input devices while the app runs, and the very
    /// next open must reflect it. menuWillOpen writes the three live values into
    /// state; the row listeners update the fn notice, the mute item and the
    /// Microphone submenu.
    /// Stated sensitivity: drop any write from menuWillOpen → RED.
    @Test
    func systemFactsAreReReadOnMenuOpen() throws {
        let updateMenu = try SourceText.code("Sources/slovo/AppDelegate+UpdateMenu.swift")
        let menuWillOpen = try SourceText.functionBody(named: "menuWillOpen", in: updateMenu)
        #expect(menuWillOpen.contains("isFnKeySystemAssigned = fnKeyAssignmentReader.isFnKeySystemAssigned"),
                "menuWillOpen must write the live fn-assignment value into state")
        #expect(menuWillOpen.contains("outputMuteAvailability = CoreAudioOutputMute().outputMuteAvailability()"),
                "menuWillOpen must write the live output mute availability into state")
        #expect(menuWillOpen.contains("inputDevices = CoreAudioInputDevices().inputDevices()"),
                "menuWillOpen must write the live input devices into state")
    }

    /// The fn verdict reaches the menu only through state: the init seed and
    /// menuWillOpen read the reader, the build subscriber passes the state's verdict,
    /// and makeMenu passes its `rows` argument to `make`. The fn rendering itself is
    /// pinned in DictationMenuTests through `items`.
    /// Stated sensitivity: hardcode the build subscriber's argument, build fresh rows
    /// inside makeMenu, hardcode the verdict in the init seed or menuWillOpen — e.g.
    /// `isFnKeySystemAssigned: false` — or drop the reader from the seed → RED.
    @Test
    func makeMenuPassesTheLiveFnAssignmentValue() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let updateMenu = try SourceText.code("Sources/slovo/AppDelegate+UpdateMenu.swift")
        let makeMenu = try SourceText.functionBody(named: "makeMenu", in: delegate)
        let initBody = try SourceText.slice(
            of: delegate,
            from: "fnKeyAssignmentReader: FnKeyAssignmentReading =",
            to: "func applicationDidFinishLaunching"
        )
        let menuWillOpen = try SourceText.functionBody(named: "menuWillOpen", in: updateMenu)
        let storeWiring = try SourceText.code("Sources/slovo/AppDelegate+Store.swift")
        #expect(storeWiring.contains("isFnKeySystemAssigned: state.isFnKeySystemAssigned"),
                "the build subscriber must pass the verdict held in state")
        #expect(makeMenu.contains("rows: rows"),
                "makeMenu must pass its rows argument, which carries the fn verdict, to the menu builder")
        #expect(initBody.contains("isFnKeySystemAssigned: fnKeyAssignmentReader.isFnKeySystemAssigned"),
                "the store seed must read the live fn assignment")
        let literals = [
            "isFnKeySystemAssigned: false", "isFnKeySystemAssigned: true",
            "isFnKeySystemAssigned = false", "isFnKeySystemAssigned = true",
        ]
        for (name, body) in [("init", initBody), ("menuWillOpen", menuWillOpen), ("AppDelegate+Store", storeWiring)] {
            for literal in literals {
                #expect(!body.contains(literal), "\(name) must never hardcode the fn verdict: \(literal)")
            }
        }
    }
}
