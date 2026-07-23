import Foundation
import Testing

@Suite("Cleanup hints wiring source guard")
struct CleanupHintsWiringSourceGuardTests {
    private static var packageRoot: URL {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Reads a source file with `//` line and `/* */` block comments removed, so a
    /// guard can never match a string that only appears in a comment.
    private static func source(_ relativePath: String) throws -> String {
        let raw = try String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8)
        return strippingComments(from: raw)
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

    /// Stated sensitivity: dropping either real hint provider from the Dependencies
    /// construction (so production dictation gathers no hints) turns this red.
    @Test
    func compositionWiresBothHintProviders() throws {
        let composition = try Self.source("Sources/slovo/AppComposition.swift")

        #expect(composition.contains("inputSourceLanguage: SystemInputSourceLanguageReader()"))
        #expect(composition.contains("spellCheckHints: SystemSpellCheckHintProvider()"))
    }

    /// Stated sensitivity: an `applySpellCheckHints` that rebuilds the pipeline
    /// (retrySetup/startPipeline) or omits the live push through the effective-config
    /// funnel (`pushEffectiveCleanupConfig()`) — the same mistake guarded for the
    /// cleanup-model change — turns this red.
    @Test
    func spellCheckToggleAppliesLiveWithoutRebuild() throws {
        let delegate = try Self.source("Sources/slovo/Settings/AppDelegate+Settings.swift")

        #expect(delegate.contains("func applySpellCheckHints("))
        #expect(delegate.contains("config.useSpellCheckHints = "))
        #expect(delegate.contains("ConfigStore.save(config, to: defaults)"))
        guard let applyRange = delegate.range(of: "func applySpellCheckHints(") else {
            Issue.record("applySpellCheckHints not found")
            return
        }
        // `delegate` is already comment-stripped by `source(_:)`; the method body is
        // short, so a generous window still stops before neighbors. The funnel check
        // is body-scoped because `pushEffectiveCleanupConfig()` now appears across
        // many apply methods — a file-scoped check would be vacuous.
        let body = String(delegate[applyRange.lowerBound...].prefix(1_200))
        #expect(body.contains("pushEffectiveCleanupConfig()"),
                "applySpellCheckHints must push the effective cleanup config live through the funnel")
        for forbidden in ["retrySetup", "startPipeline", "prepareModelGate"] {
            #expect(!body.contains(forbidden),
                    "toggling spell-check hints must not \(forbidden): that re-warms ASR")
        }
    }
}
