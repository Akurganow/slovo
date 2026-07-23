import Foundation
import Testing

import SlovoCore

// The empty-result surface lives in the executable `slovo` target's AppDelegate,
// which the test bundle cannot import; this reads its source to confirm the wiring
// the SlovoCore-level tests cannot see: a no-speech notice flashes the brief red
// glyph ONLY — it never latches a persistent status line.
@Suite("Empty-result glyph wiring")
struct EmptyResultGlyphWiringSourceGuardTests {
    /// The empty result must flash the brief glyph and RETURN before the shared
    /// status-line title update — so a silent hold leaves no lingering notice (spec).
    ///
    /// Sensitivity: drop the early `return` in the `isNoSpeechNotice` branch (so the
    /// empty result falls through to `statusTextItem?.title = Self.title(for: status)`)
    /// → the ordered "return" needle no longer sits between the flash and the title →
    /// RED. Route `.isNoSpeechNotice` around `flashBriefStatusGlyph` → RED.
    ///
    /// Ordering alone does NOT prove glyph-only: writing the title line INSIDE the
    /// branch (between the flash and the return) satisfies every ordered needle yet
    /// violates "no status-line text". So the branch body is sliced and asserted to
    /// carry no title write at all — pinning glyph-only directly.
    /// Sensitivity: insert `statusTextItem?.title = ...` between the branch's flash and
    /// its return → the sliced branch contains a title write → RED (a mutant the
    /// ordering needles above would pass).
    @Test
    func emptyResultFlashesBriefGlyphThenReturnsBeforeTitleLine() throws {
        let delegate = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate.swift")
        let showStatusBody = try AppRuntimeSourceGuardTests.functionBody(named: "showStatus", in: delegate)

        #expect(AppRuntimeSourceGuardTests.containsInOrder([
            "status.isNoSpeechNotice",
            "flashBriefStatusGlyph(status)",
            "return",
            "statusTextItem?.title = Self.title(for: status)",
        ], in: showStatusBody))

        // The no-speech branch itself (from the `if` open brace to its `return`) must
        // carry NO status-line write — glyph-only, pinned directly rather than by order.
        let noSpeechBranch = try AppRuntimeSourceGuardTests.slice(
            of: showStatusBody, from: "isNoSpeechNotice {", to: "return"
        )
        #expect(!noSpeechBranch.contains("statusTextItem?.title"),
                "the empty-result branch must set no status-line text; got:\n\(noSpeechBranch)")
    }

    /// The shared brief-glyph helper must latch `isShowingBriefStatus` (so
    /// settleToIdle does not stomp the flash), paint the status glyph through the core
    /// renderer, and schedule the tracked self-clear — the mechanism the empty result
    /// reuses.
    ///
    /// Sensitivity: drop the `isShowingBriefStatus` latch (settleToIdle wipes the
    /// flash immediately) or the `setStatusGlyph(status:` paint → RED.
    @Test
    func briefGlyphHelperLatchesPaintsAndSchedulesReset() throws {
        let delegate = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate.swift")
        let helperBody = try AppRuntimeSourceGuardTests.functionBody(named: "flashBriefStatusGlyph", in: delegate)

        #expect(AppRuntimeSourceGuardTests.containsInOrder([
            "isShowingBriefStatus = true",
            "setStatusGlyph(status: status",
            "briefStatusResetTask = Task",
            "isShowingBriefStatus = false",
        ], in: helperBody))
    }
}
