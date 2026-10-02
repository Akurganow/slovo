import Foundation
import Testing

// The recording glyph reads cleanup availability in one place: both sequencer arms
// route the glyph through `applyRecordingGlyph`, which reads the store.
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

    /// Availability stays out of the sequencer arms: `applyRecordingGlyph` reads
    /// `store.state.cleanupAvailability.isOn` once, as the derivation argument, so no
    /// arm carries a separate gate read that a mutant could leave dead while still
    /// ungating the paint. Both arms route the glyph through it.
    /// Stated sensitivity: read `cleanupAvailability` in either arm, or drop an arm's
    /// `applyRecordingGlyph` routing → RED.
    @Test
    func recordingGlyphIgnoresTranslateWhileCleanupIsOff() throws {
        let source = try Self.strippedCode("Sources/slovo/AppDelegate.swift")
        guard let downArm = source.range(of: "case .down(let mode):"),
              let latchArm = source.range(of: "case .translateLatched:"),
              let upArm = source.range(of: "case .up(let mode):")
        else {
            Issue.record("sequencer arms not found")
            return
        }
        let downBody = source[downArm.lowerBound..<latchArm.lowerBound]
        let latchBody = source[latchArm.lowerBound..<upArm.lowerBound]

        #expect(!downBody.contains("cleanupAvailability"),
                "the .down arm must not read availability; it is consumed once inside applyRecordingGlyph")
        #expect(!latchBody.contains("cleanupAvailability"),
                "the .translateLatched arm must not read availability; it is consumed once inside applyRecordingGlyph")
        #expect(downBody.contains("applyRecordingGlyph(mode)"),
                "the .down arm must route the glyph through applyRecordingGlyph")
        #expect(latchBody.contains("applyRecordingGlyph(.translate)"),
                "the translate latch must route the glyph through applyRecordingGlyph")
    }
}
