import Foundation
import Testing

// The brief-glyph reset lives in the executable `slovo` target's AppDelegate, which
// the test bundle cannot import, so the repair is pinned in the source the way the
// sibling glyph guards are. A source guard is only worth its line count if it can
// go red on broken code, so the same predicate is also run against four MUTANTS
// built from that source — each must be rejected (AGENTS.md, "Tests must be able
// to fail"; issue #38).
@Suite("Brief-glyph reset supersede")
struct BriefGlyphResetSourceGuardTests {
    static let sleepStatement = "try? await Task.sleep(for: .seconds(1))"
    static let abortStatement = "guard !Task.isCancelled, let self else { return }"
    static let abortPattern = #"guard !Task\.isCancelled, let self else \{ return \}"#
    static let latchClear = "self.isShowingBriefStatus = false"
    static let pipelineGate = "guard !self.isPipelineActive else { return }"

    /// The whole repair as ONE predicate, so every mutant travels the same path:
    ///
    /// 1. The abort sits AFTER the sleep and is an executed early exit. `Task.sleep`
    ///    resumes a cancelled task by THROWING (SE-0304) and the helper's `try?`
    ///    discards that, so `cancel()` alone stops nothing — without this the
    ///    superseded body runs on and repaints idle over the flash that replaced it.
    ///    Pinned by exact statement text on its own line and scoped to the text after
    ///    the sleep, so neither an inert `if !Task.isCancelled {}` nor a copy hoisted
    ///    above the sleep satisfies it.
    /// 2. The latch clear is reached UNCONDITIONALLY: this task body is the only
    ///    writer that clears `isShowingBriefStatus`, and every idle repaint elsewhere
    ///    is gated on it, so anything that returns above this line strands the latch
    ///    set and suppresses the idle glyph for good.
    /// 3. The pipeline gate covers the PAINT ONLY, and comes after the clear — a
    ///    dictation that began inside the window keeps its recording glyph instead of
    ///    being blanked to idle mid-hold.
    static func repairsSupersededReset(in helperBody: String) -> Bool {
        guard let afterSleep = try? AppRuntimeSourceGuardTests.slice(of: helperBody, from: sleepStatement),
              AppRuntimeSourceGuardTests.statementCount(abortPattern, in: afterSleep) == 1,
              let abortToClear = try? AppRuntimeSourceGuardTests.slice(of: afterSleep, from: abortStatement, to: latchClear),
              !abortToClear.contains("isPipelineActive")
        else {
            return false
        }
        return AppRuntimeSourceGuardTests.containsInOrder(
            [abortStatement, latchClear, pipelineGate, "self.paintIdleGlyph("],
            in: afterSleep
        )
    }

    /// The repaired source with exactly one thing broken, four ways. Every one leaves
    /// the superseded reset able to clear the newer flash, or strands the latch, so
    /// the predicate must reject all four. Derived from the live source rather than
    /// written out, so a rename cannot quietly turn a mutant into a copy of the
    /// original — the test asserts each one still differs.
    static func mutants(of helperBody: String) -> [(name: String, source: String)] {
        let withoutAbort = helperBody.replacingOccurrences(of: abortStatement, with: "guard let self else { return }")
        return [
            (
                "inert cancellation check",
                helperBody.replacingOccurrences(of: abortStatement, with: "if !Task.isCancelled {}\nguard let self else { return }")
            ),
            (
                "abort hoisted above the sleep",
                withoutAbort.replacingOccurrences(of: sleepStatement, with: "\(abortStatement)\n\(sleepStatement)")
            ),
            (
                "abort gated on the pipeline",
                helperBody.replacingOccurrences(
                    of: abortStatement,
                    with: "guard !Task.isCancelled, let self, !self.isPipelineActive else { return }"
                )
            ),
            ("ungated idle paint", helperBody.replacingOccurrences(of: pipelineGate, with: ""))
        ]
    }

    /// Stated sensitivity: the helper as written before this guard (no check after the
    /// sleep) → RED. Each of the four mutants → RED, asserted here rather than recorded
    /// in prose, so loosening the needles later cannot pass unnoticed.
    @Test
    func supersededResetAbortsAfterTheSleepWithoutStrandingTheLatch() throws {
        let delegate = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate.swift")
        let helper = try AppRuntimeSourceGuardTests.functionBody(named: "flashBriefStatusGlyph", in: delegate)

        #expect(Self.repairsSupersededReset(in: helper),
                "the reset task must abort when superseded, clear the latch, then gate only the paint; got:\n\(helper)")

        for mutant in Self.mutants(of: helper) {
            #expect(mutant.source != helper, "the \"\(mutant.name)\" mutant no longer changes the source")
            #expect(!Self.repairsSupersededReset(in: mutant.source), "the \"\(mutant.name)\" mutant survives this guard")
        }
    }
}
