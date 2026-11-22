import Foundation
import Testing

// The dictation hot path (key-down → live transcription → key-up → clean → inject)
// must stay low-latency: the transcript is ready at key-up. That budget is a
// property of slovo's OWN orchestration — the pure `DictationFsm` decision table and
// the effect-executing `Orchestrator` with its helpers — never of the injected
// ASR/cleanup/injection adapters, which is why the pipeline suite drives all-instant
// fakes and why those adapters may legitimately wait (the
// clipboard-restore delay in ClipboardPasteInjector, the app-target sad-to-fail
// glyph timer).
//
// A wall-clock timing test cannot prove this on a loaded machine: OS scheduling
// variance dwarfs the ~1 ms fake pipeline (the same run was observed taking 0.24 s to
// 2.56 s on shared runners), so any fixed budget is either flaky under load or
// meaningless. This guard pins the SAME contract structurally: the orchestration
// source must contain no blocking sleep, delayed dispatch, timer, or semaphore wait —
// the primitives by which a stall would enter the hot path. Reading source is immune
// to scheduling, so the guard runs everywhere, CI included.
//
// Scope is the ORCHESTRATION source, not two literal paths, so extracting a hot
// helper (e.g. `cleanAndContinue`) into a new file cannot smuggle a wait past the
// guard: the SlovoCore top level (any sibling an actor helper could be split into)
// plus the `FSM/` subtree are scanned recursively. Adapter subtrees (`ASR/`,
// `Audio/`, `Injection/`, `Cleaner/`) are deliberately out of scope — they sit behind
// the fakes and their timing is legitimate; a blocking wait there is not an
// orchestration-latency regression.
//
// Residual gaps, stated not hidden: (1) an orchestration helper in any SlovoCore
// subdirectory other than `FSM/` escapes the scope. Today that includes `Hotkey/`
// (the edge sequencer), `Composition/`, `Store/` and `Contracts/`; the anchors below
// cannot detect that. (2) This catches a wait/sleep/timer primitive, not a stall from
// arbitrary slow synchronous computation, which no load-immune check can catch without
// reintroducing the wall-clock flakiness this replaces.
//
// Source is comment-stripped, so a primitive named only in a comment cannot trip a
// guard; the anchors fail loudly if the orchestration files are not enumerated, so a
// mis-scoped scan can never pass vacuously over empty text.
@Suite("Dictation orchestration latency source guards")
struct DictationHotPathLatencySourceGuardTests {
    /// slovo's own dictation orchestration must not sleep, block, defer, or wait on a
    /// timer: each such primitive is how a latency regression would push the transcript
    /// past its key-up readiness.
    /// Stated sensitivity: add any blocking wait to the orchestration source — the
    /// `Orchestrator`, the `DictationFsm`, an extracted top-level helper, or a new
    /// `FSM/` file (e.g. `try? await Task.sleep(...)`, `Thread.sleep(...)`,
    /// `DispatchQueue.main.asyncAfter(...)`) → the offending file is listed → RED.
    @Test
    func dictationOrchestrationContainsNoBlockingWaitOrTimer() throws {
        let sources = try Self.orchestrationSources()
        let scannedNames = Set(sources.map(\.name))

        // Anchors: prove the real orchestration was enumerated and read, so a
        // mis-scoped scan (wrong root, empty list) reddens here instead of passing
        // its negative checks over nothing.
        #expect(scannedNames.contains("Orchestrator.swift"),
                "orchestration scan must include Orchestrator.swift; scanned \(scannedNames.sorted())")
        #expect(scannedNames.contains("DictationFsm.swift"),
                "orchestration scan must include DictationFsm.swift; scanned \(scannedNames.sorted())")
        #expect(sources.contains { $0.code.contains("actor Orchestrator") },
                "orchestration scan must read the real Orchestrator body, not a stale path")
        #expect(sources.contains { $0.code.contains("enum DictationFsm") },
                "orchestration scan must read the real DictationFsm body, not a stale path")

        var offenders: [String] = []
        for source in sources {
            for primitive in Self.blockingPrimitives where source.code.contains(primitive) {
                offenders.append("\(source.name): `\(primitive)`")
            }
        }
        #expect(offenders.isEmpty,
                "slovo's own dictation orchestration must contain no blocking wait/timer — it breaks the key-up latency budget; offenders: \(offenders)")
    }

    /// The blocking/deferring primitives banned from the orchestration. `sleep(`
    /// subsumes the named sleeps, but each is listed so a failure names the exact form.
    private static let blockingPrimitives = [
        "Task.sleep",
        "Thread.sleep",
        "usleep(",
        "nanosleep(",
        "sleep(",
        ".asyncAfter(",
        "scheduledTimer",
        "DispatchSemaphore",
        "NSCondition",
    ]

    // MARK: - Scope enumeration + source scanning (comment-stripped; a missing
    // directory throws → RED, never a vacuous pass).

    private typealias ScannedSource = (name: String, code: String)

    /// The orchestration source: SlovoCore top-level files plus the `FSM/` subtree,
    /// each comment-stripped. Recursive over `FSM/`, so a new decision-table file is
    /// covered; top-level so an actor helper split into a new sibling file is covered.
    private static func orchestrationSources() throws -> [ScannedSource] {
        let core = "Sources/SlovoCore"
        return try SourceText.swiftFiles(under: core)
            .filter { path in
                let relative = path.dropFirst(core.count + 1)
                return !relative.contains("/") || relative.hasPrefix("FSM/")
            }
            .map { path in
                (name: URL(fileURLWithPath: path).lastPathComponent, code: try SourceText.code(path))
            }
    }
}
