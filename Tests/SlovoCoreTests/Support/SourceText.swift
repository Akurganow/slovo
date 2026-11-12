import Foundation

/// Reads this repository's source text for the tests that guard it as text: every
/// `*SourceGuard*Tests` suite, `AboutPaneTests` and `ThirdPartyNoticesTests`. No test
/// target links the `slovo` executable, so these guards read its source instead.
/// The comment stripper keeps string literals, so a guard can forbid a token inside one.
/// Its known limits: an escaped `\"` flips its string state, and block comments do not
/// nest. Neither stripper understands raw (`#"…"#`) or multi-line (`"""`) literals.
enum SourceText {
    /// A guard's anchor text is missing from the source, or its braces never balance.
    enum Failure: Error {
        case anchorNotFound(String)
        case unbalancedBraces(String)
    }

    /// The package root: this file sits at `Tests/SlovoCoreTests/Support/`.
    static var packageRoot: URL {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The file's raw text, comments included.
    static func read(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8)
    }

    /// The file's text with comments stripped and string literals kept.
    static func code(_ relativePath: String) throws -> String {
        try strippingComments(from: read(relativePath))
    }

    /// Every `.swift` file under the directory, recursively, as package-relative paths.
    static func swiftFiles(under relativeDirectory: String) throws -> [String] {
        let root = packageRoot.appending(path: relativeDirectory, directoryHint: .isDirectory).path
        return try FileManager.default.subpathsOfDirectory(atPath: root)
            .filter { $0.hasSuffix(".swift") }
            .map { "\(relativeDirectory)/\($0)" }
    }

    /// Lines that hold exactly `pattern` (a regular expression) as their whole statement,
    /// counted with string literals emptied so a quoted copy never counts.
    static func statementCount(_ pattern: String, in source: String) -> Int {
        let code = withoutStringLiterals(source)
        let expression = try? NSRegularExpression(pattern: #"(?m)^\s*\#(pattern)\s*$"#)
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        return expression?.numberOfMatches(in: code, range: range) ?? 0
    }

    static func containsInOrder<S: StringProtocol>(_ needles: [String], in source: S) -> Bool {
        var searchStart = source.startIndex
        for needle in needles {
            guard let range = source.range(of: needle, range: searchStart..<source.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }

    /// The text from `start` (inclusive) to `end` (exclusive), or to the source's
    /// end when `end` is nil — scopes an assertion to a single switch arm, so a
    /// whole-body ordered search cannot go green off a match in a sibling arm.
    static func slice(of source: String, from start: String, to end: String? = nil) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Failure.anchorNotFound(start)
        }
        guard let end else {
            return String(source[startRange.lowerBound...])
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Failure.anchorNotFound(end)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    /// The brace-balanced body of the first `func <name>`, braces included.
    static func functionBody(named name: String, in source: String) throws -> String {
        guard let signature = source.range(of: "func \(name)") else {
            throw Failure.anchorNotFound("func \(name)")
        }
        guard let openBrace = functionOpeningBrace(after: signature.lowerBound, in: source) else {
            throw Failure.anchorNotFound("{ of func \(name)")
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
        throw Failure.unbalancedBraces("func \(name)")
    }

    /// The first `{` after `start` outside parentheses: a default argument's closure
    /// or a parameter's braces never count as the body's opening brace.
    static func functionOpeningBrace(after start: String.Index, in source: String) -> String.Index? {
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

    /// The source with every string literal's content removed and its quotes kept.
    static func withoutStringLiterals(_ source: String) -> String {
        var output = ""
        var inString = false
        var escaped = false

        for character in source {
            if inString {
                if character == "\n" {
                    output.append(character)
                } else if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                    output.append(character)
                }
            } else {
                output.append(character)
                if character == "\"" {
                    inString = true
                }
            }
        }
        return output
    }

    static func strippingComments(from source: String) -> String {
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
}
