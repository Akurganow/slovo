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
}
