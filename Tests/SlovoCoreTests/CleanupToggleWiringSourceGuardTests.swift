import Foundation
import Testing

// The push funnel is an invariant, not a convention: exactly ONE call site may
// talk to updateCleanupConfig (the funnel itself), so the effective-flag
// derivation can never fork.
@Suite("Cleanup toggle wiring source guard")
struct CleanupToggleWiringSourceGuardTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func code(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8)
    }

    /// Source with `//` line and `/* */` block comments removed, so a guard can
    /// never be satisfied by a token that survives only in a comment.
    private static func strippedCode(_ relativePath: String) throws -> String {
        strippingComments(from: try code(relativePath))
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
                if character == "\n" { inLineComment = false; output.append(character) }
            } else if inBlockComment {
                if character == "*" && next == "/" { inBlockComment = false; index = nextIndex }
            } else if inString {
                output.append(character)
                if character == "\"" { inString = false }
            } else if character == "/" && next == "/" {
                inLineComment = true; index = nextIndex
            } else if character == "/" && next == "*" {
                inBlockComment = true; index = nextIndex
            } else {
                output.append(character)
                if character == "\"" { inString = true }
            }
            index = source.index(after: index)
        }
        return output
    }

    /// Stated sensitivity: re-introduce a direct `updateCleanupConfig` push in
    /// AppDelegate+Settings (today's pattern) → count rises above one → RED.
    @Test
    func exactlyOneUpdateCleanupConfigCallSiteAcrossTheAppTarget() throws {
        let sources = try [
            "Sources/slovo/AppDelegate.swift",
            "Sources/slovo/Settings/AppDelegate+Settings.swift",
        ].map { try Self.code($0) }
        let callCount = sources
            .map { $0.components(separatedBy: "orchestrator.updateCleanupConfig(").count - 1 }
            .reduce(0, +)
        #expect(callCount == 1, "all cleanup pushes must flow through pushEffectiveCleanupConfig(); found \(callCount) direct call sites")
    }

    /// Stated sensitivity: drop the key-save re-push (`pushEffectiveCleanupConfig`
    /// after `store(key)`) → RED.
    @Test
    func keySaveRefreshesAvailability() throws {
        let source = try Self.code("Sources/slovo/Settings/AppDelegate+Settings.swift")
        guard let saveBody = source.range(of: "func saveOpenRouterKey") else {
            Issue.record("saveOpenRouterKey not found")
            return
        }
        let tail = source[saveBody.lowerBound...]
        #expect(tail.prefix(600).contains("pushEffectiveCleanupConfig()"))
    }

    /// Stated sensitivity: re-inline the `&&` predicate at either site (drop
    /// the derive routing) → RED; bypass derive while leaving its name in a
    /// COMMENT → still RED (the scan runs on comment-stripped source — the
    /// token-in-comment survivor class from the mutation audit is closed).
    /// One effective-on definition, two call sites.
    @Test
    func bothPushSitesConsumeTheSingleDerivation() throws {
        // Mirror AppRuntimeSourceGuardTestsSupport.strippingComments so a
        // commented-out token can never satisfy this guard.
        let composition = try Self.strippedCode("Sources/slovo/AppComposition.swift")
        #expect(composition.contains("CleanupAvailability.derive("))
        let delegate = try Self.strippedCode("Sources/slovo/AppDelegate.swift")
        guard let funnel = delegate.range(of: "func pushEffectiveCleanupConfig") else {
            Issue.record("pushEffectiveCleanupConfig not found")
            return
        }
        #expect(delegate[funnel.lowerBound...].prefix(700).contains("CleanupAvailability.derive("))
    }

    /// Stated sensitivity: paint the glyph straight from the latched mode (drop
    /// the availability gate on either arm) → RED.
    @Test
    func recordingGlyphIgnoresTranslateWhileCleanupIsOff() throws {
        let source = try Self.code("Sources/slovo/AppDelegate.swift")
        guard let downArm = source.range(of: "case .down(let mode):"),
              let latchArm = source.range(of: "case .translateLatched:")
        else {
            Issue.record("sequencer arms not found")
            return
        }
        let downBody = source[downArm.lowerBound..<latchArm.lowerBound]
        #expect(downBody.contains("currentCleanupAvailability().isOn"))
        let latchBody = source[latchArm.lowerBound...].prefix(400)
        #expect(latchBody.contains("currentCleanupAvailability().isOn"))
    }
}
