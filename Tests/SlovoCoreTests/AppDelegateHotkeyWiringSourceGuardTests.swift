import Foundation
import Testing

import SlovoCore

// Wiring guards. The behavior tests in HotkeyEdgeSequencerTests prove the
// sequencer serializes edges, but nothing forced AppDelegate to actually ROUTE the
// fn hotkey through it — reverting onTrigger to per-edge `Task { ... }` dispatch
// (the original stuck-mute bug) reddened no test. These source guards close that
// gap and pin the single-rebuild re-entrancy guard on retrySetup.
@Suite("AppDelegate hotkey wiring source guards")
struct AppDelegateHotkeyWiringSourceGuardTests {

    /// The fn hotkey must deliver every edge through the ordered sequencer, never
    /// on its own per-edge Task. Killing mutation (either direction): delete the
    /// `sequencer.send` routing, or restore `onTrigger = { phase in Task { ... } }`
    /// per-edge dispatch. Then the closure no longer routes through the sequencer,
    /// or it dispatches concurrently again -> RED.
    @Test
    func onTriggerRoutesEveryEdgeThroughTheSequencer() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try Self.functionBody(named: "startPipeline", in: delegate)
        let onTriggerClosure = try Self.closureBody(afterAnchor: "hotkeyMonitor.onTrigger =", in: startPipeline)

        #expect(startPipeline.contains("HotkeyEdgeSequencer"),
                "startPipeline must build the ordered edge sequencer")
        #expect(onTriggerClosure.contains("sequencer.send(phase)"),
                "the hotkey onTrigger must route every edge through the sequencer")
        #expect(!onTriggerClosure.contains("Task"),
                "the onTrigger closure must not dispatch each edge on its own Task (the stuck-mute race)")
        #expect(!onTriggerClosure.contains("orchestrator.handle"),
                "the onTrigger closure must not drive the orchestrator directly; ordering lives in the single consumer")
    }

    /// A second retrySetup while a teardown+rebuild is still pending must not spawn
    /// a parallel rebuild, so the re-entrancy guard has to be checked BEFORE the
    /// rebuild Task. Killing mutation: remove the guard (the current state) and a
    /// concurrent retrySetup spawns a second consumer -> RED.
    /// Pinned shape (coordinated with the implementer): an early `guard ... return`
    /// precedes the teardown+rebuild `Task`; the exact flag naming is free.
    @Test
    func retrySetupGuardsAgainstConcurrentRebuild() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let retrySetup = try Self.functionBody(named: "retrySetup", in: delegate)

        #expect(Self.containsInOrder([
            "guard",
            "return",
            "Task {",
            "await previousSequencer?.stop()",
            "startPipeline()",
        ], in: retrySetup),
        "retrySetup must guard against a second rebuild BEFORE spawning the teardown+rebuild Task")
    }

    /// Key-down before the ASR model is resident must not open a session: a cold
    /// start opens the mic and mutes system audio for the whole model load (the
    /// stranded-mute incident shape, log 2026-07-02 22:45). Killing mutation:
    /// remove the readiness guard from the `.down` arm -> RED.
    @Test
    func keyDownIsGatedOnModelReadiness() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try Self.functionBody(named: "startPipeline", in: delegate)

        #expect(Self.containsInOrder([
            "case .down(let mode):",
            "isModelReady",
            "showModelLoadingState",
            "orchestrator.handle(.startRequested)",
        ], in: startPipeline),
        "the .down arm must gate on model readiness and re-assert the loading state before any session starts")
    }

    /// The recording glyph must reflect the session's mode: the `.down` arm paints
    /// the mode's glyph (Ⰸ plain, Ⱂ translate), and a mid-hold Control latch surfaces
    /// as a `.translateLatched` edge that switches the glyph to translate LIVE, while
    /// the key is still held. Killing mutation: hard-code the plain glyph in `.down`
    /// (drop `recording: mode`), or delete the `.translateLatched` arm / its glyph
    /// switch → RED.
    @Test
    func recordingGlyphTracksTheLatchedMode() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try Self.functionBody(named: "startPipeline", in: delegate)

        #expect(Self.containsInOrder([
            "case .down(let mode):",
            "setStatusGlyph(recording: mode",
        ], in: startPipeline),
        "the .down arm must paint the recording glyph for the session's mode")
        #expect(Self.containsInOrder([
            "case .translateLatched:",
            "setStatusGlyph(recording: .translate",
        ], in: startPipeline),
        "a mid-hold Control latch must switch the recording glyph to translate live")
    }

    /// A key-up whose key-down was swallowed by the readiness gate must be
    /// swallowed too. Killing mutation: drop the active-pipeline guard from the
    /// `.up` arm and an idle key-up drives stopRequested and overwrites the
    /// loading glyph -> RED.
    @Test
    func keyUpPairsWithTheGatedKeyDown() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try Self.functionBody(named: "startPipeline", in: delegate)

        #expect(Self.containsInOrder([
            "case .up(let mode):",
            "isPipelineActive",
            "orchestrator.handle(.stopRequested(",
        ], in: startPipeline),
        "the .up arm must never stop a session that was never started")
    }

    /// The model warm-up must be an observable gate end to end: the composition
    /// exposes the preload as an awaitable task; the delegate enters the loading
    /// state in startPipeline and opens the gate (stopping the pulse) when the
    /// warm-up completes. Killing mutation: return to fire-and-forget preload,
    /// or never flip isModelReady -> RED.
    @Test
    func modelWarmUpOpensTheDictationGate() throws {
        let composition = try Self.code("Sources/slovo/AppComposition.swift")
        #expect(Self.containsInOrder(["modelWarmUp", "warmUp()"], in: composition),
                "the composition must expose the model preload as an awaitable task")

        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try Self.functionBody(named: "startPipeline", in: delegate)
        #expect(startPipeline.contains("prepareModelGate"),
                "startPipeline must enter the gated loading state")

        let gate = try Self.code("Sources/slovo/AppDelegate+ModelGate.swift")
        #expect(Self.containsInOrder([
            "showModelLoadingState",
            "modelWarmUp",
            "isModelReady = true",
            "stopModelLoadingPulse",
        ], in: gate),
        "warm-up completion must open the gate and stop the loading pulse")
    }

    /// The interrupt-cancel edge must route through the sequencer sink into the
    /// orchestrator's cancelRequested — the silent-cancel contract. Killing
    /// mutation: drop the `.cancel` arm or route it to stopRequested → RED.
    @Test
    func cancelEdgeRoutesToCancelRequested() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let startPipeline = try Self.functionBody(named: "startPipeline", in: delegate)

        #expect(Self.containsInOrder([
            "case .cancel:",
            "orchestrator.handle(.cancelRequested)",
        ], in: startPipeline),
        "the sequencer sink must handle a .cancel edge by cancelling the in-flight dictation")
    }

    /// The tap must be built with the configured trigger, not a hard-coded fn.
    /// Killing mutation: construct `CGEventTapHotkeyMonitor(trigger: .fn)` (ignore
    /// config) → RED.
    @Test
    func monitorIsBuiltWithConfiguredTrigger() throws {
        let composition = try Self.code("Sources/slovo/AppComposition.swift")
        #expect(composition.contains("CGEventTapHotkeyMonitor(trigger: config.trigger)"),
                "the monitor must be constructed with the persisted trigger")
    }

    /// The tap must observe keyDown so a combo can interrupt a right-modifier hold.
    /// Killing mutation: drop keyDown from the event mask → the interrupt is never
    /// seen → RED.
    @Test
    func hotkeyTapObservesKeyDownForInterrupt() throws {
        let monitor = try Self.code("Sources/SlovoCore/Hotkey/CGEventTapHotkeyMonitor.swift")
        #expect(monitor.contains("CGEventType.keyDown.rawValue"),
                "the event mask must include keyDown so the interrupt is observable")
    }

    /// Privacy invariant: a non-trigger keyDown contributes only the fact that a
    /// key went down — never its typed character or key code. Killing mutations:
    /// read the typed character (add `keyboardGetUnicodeString`), or read the key
    /// code in the keyDown arm (a second `getIntegerValueField`) to retain key
    /// identity → RED.
    @Test
    func keyDownCarriesNoKeyContent() throws {
        let monitor = try Self.code("Sources/SlovoCore/Hotkey/CGEventTapHotkeyMonitor.swift")
        #expect(Self.containsInOrder(["case .keyDown:", "= .keyDown"], in: monitor),
                "the keyDown arm must map to the payload-free input, not read the event")
        #expect(!monitor.contains("keyboardGetUnicodeString"),
                "the tap must never read a keystroke's typed character")
        // Exactly one key-code read is allowed — the flagsChanged side detection. A
        // second read means the keyDown arm reads key identity (privacy leak).
        let keyCodeReads = monitor.components(separatedBy: "getIntegerValueField").count - 1
        #expect(keyCodeReads == 1,
                "only the flagsChanged arm may read a key code, got \(keyCodeReads) reads")
    }

    /// A key change applies live via reconfigure, NOT a pipeline rebuild — no ASR
    /// re-warm, no loading pulse (the applyCleanupModel principle). Killing
    /// mutation: route applyTrigger through retrySetup/startPipeline (a rebuild) →
    /// RED.
    @Test
    func applyTriggerReconfiguresInPlaceWithoutRebuild() throws {
        let hotkeyMenu = try Self.code("Sources/slovo/AppDelegate+HotkeyMenu.swift")
        let applyTrigger = try Self.functionBody(named: "applyTrigger", in: hotkeyMenu)
        #expect(applyTrigger.contains("hotkeyMonitor.reconfigure(trigger:"),
                "applyTrigger must reconfigure the live tap in place")
        #expect(!applyTrigger.contains("startPipeline"),
                "applyTrigger must not rebuild the pipeline")
        #expect(!applyTrigger.contains("retrySetup"),
                "applyTrigger must not rebuild the pipeline via retrySetup")
    }

    private static func code(_ relativePath: String) throws -> String {
        try strippingComments(from: String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8))
    }

    private static func containsInOrder(_ needles: [String], in source: String) -> Bool {
        var searchStart = source.startIndex
        for needle in needles {
            guard let range = source.range(of: needle, range: searchStart..<source.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }

    private static func functionBody(named name: String, in source: String) throws -> String {
        guard let signature = source.range(of: "func \(name)") else {
            throw NSError(domain: "AppDelegateHotkeyWiringSourceGuard", code: 1)
        }
        return try blockBody(from: functionOpeningBrace(after: signature.lowerBound, in: source), in: source, code: 2)
    }

    /// The closure literal assigned right after `anchor`, e.g. `onTrigger = { ... }`.
    private static func closureBody(afterAnchor anchor: String, in source: String) throws -> String {
        guard let anchorRange = source.range(of: anchor) else {
            throw NSError(domain: "AppDelegateHotkeyWiringSourceGuard", code: 4)
        }
        return try blockBody(from: source[anchorRange.upperBound...].firstIndex(of: "{"), in: source, code: 5)
    }

    private static func blockBody(from openBrace: String.Index?, in source: String, code: Int) throws -> String {
        guard let openBrace else {
            throw NSError(domain: "AppDelegateHotkeyWiringSourceGuard", code: code)
        }
        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openBrace...index])
                }
            }
            index = source.index(after: index)
        }
        throw NSError(domain: "AppDelegateHotkeyWiringSourceGuard", code: code)
    }

    private static func functionOpeningBrace(after start: String.Index, in source: String) -> String.Index? {
        var index = start
        var parenDepth = 0
        while index < source.endIndex {
            if source[index] == "(" {
                parenDepth += 1
            } else if source[index] == ")" {
                parenDepth -= 1
            } else if source[index] == "{", parenDepth == 0 {
                return index
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func strippingComments(from source: String) -> String {
        var output = ""
        var index = source.startIndex
        var inLineComment = false, inBlockComment = false, inString = false

        while index < source.endIndex {
            let character = source[index]
            let nextIndex = source.index(after: index)
            let next = nextIndex < source.endIndex ? source[nextIndex] : "\0"

            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    output.append(character)
                }
            } else if inBlockComment {
                if character == "*" && next == "/" {
                    inBlockComment = false
                    index = nextIndex
                }
            } else if inString {
                output.append(character)
                if character == "\"" {
                    inString = false
                }
            } else if character == "/" && next == "/" {
                inLineComment = true
                index = nextIndex
            } else if character == "/" && next == "*" {
                inBlockComment = true
                index = nextIndex
            } else {
                output.append(character)
                if character == "\"" {
                    inString = true
                }
            }
            index = source.index(after: index)
        }
        return output
    }

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
