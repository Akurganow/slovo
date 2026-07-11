import Foundation
import Testing

// The project surfaces errors and configuration through the menu bar and native
// windows — never a focus-stealing modal. After Phase 2 no `NSAlert` is
// constructed anywhere under Sources/.
@Suite("No NSAlert source guard")
struct NoNSAlertSourceGuardTests {
    /// Stated sensitivity: reintroduce any `NSAlert(` construction under Sources/ →
    /// the offending file is listed → RED. Comments/doc mentioning NSAlert are
    /// stripped first, so only real construction counts.
    @Test
    func noNSAlertIsConstructedUnderSources() throws {
        let offenders = try Self.swiftFiles(under: "Sources").filter { path in
            let code = Self.strippingComments(from: try String(contentsOfFile: path, encoding: .utf8))
            return code.contains("NSAlert(")
        }
        #expect(offenders.isEmpty, "NSAlert must not be constructed under Sources/: \(offenders)")
    }

    private static func swiftFiles(under relativeDirectory: String) throws -> [String] {
        let root = packageRoot.appending(path: relativeDirectory, directoryHint: .isDirectory).path
        return try FileManager.default.subpathsOfDirectory(atPath: root)
            .filter { $0.hasSuffix(".swift") }
            .map { "\(root)/\($0)" }
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

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
