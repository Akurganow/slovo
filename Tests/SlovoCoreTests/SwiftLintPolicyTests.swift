import Foundation
import Testing

@Suite("SwiftLint policy")
struct SwiftLintPolicyTests {
    @Test
    func criticalCheckerRulesCannotBeDisabled() throws {
        let config = try String(contentsOf: Self.packageRoot.appending(path: ".swiftlint.yml"), encoding: .utf8)
        let disabledRules = Self.disabledRules(in: config)
        for forbiddenRule in ["incompatible_concurrency_annotation", "unused_import"] {
            #expect(!disabledRules.contains(forbiddenRule),
                    "strict lint must not disable critical checker rule \(forbiddenRule)")
        }

        #expect(Self.disabledRules(in: "disabled_rules: [unused_import, incompatible_concurrency_annotation]") == [
            "unused_import",
            "incompatible_concurrency_annotation",
        ])
        #expect(Self.disabledRules(in: #"disabled_rules: ["unused_import", 'incompatible_concurrency_annotation']"#) == [
            "unused_import",
            "incompatible_concurrency_annotation",
        ])
        #expect(Self.disabledRules(in: """
        disabled_rules:
          - unused_import
          - incompatible_concurrency_annotation
        """) == ["unused_import", "incompatible_concurrency_annotation"])
        #expect(Self.disabledRules(in: #"""
        disabled_rules:
          - "unused_import"
          - 'incompatible_concurrency_annotation'
        """#) == ["unused_import", "incompatible_concurrency_annotation"])
    }

    private static func disabledRules(in yaml: String) -> [String] {
        var rules: [String] = []
        var readingBlockList = false

        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = strippingHashComment(from: rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if line.first?.isWhitespace == false {
                readingBlockList = false
                guard let separator = trimmed.firstIndex(of: ":") else { continue }
                let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: separator)...])
                    .trimmingCharacters(in: .whitespaces)
                guard key == "disabled_rules" else { continue }
                if let inlineRules = inlineYamlList(value) {
                    rules.append(contentsOf: inlineRules)
                } else if value.isEmpty {
                    readingBlockList = true
                }
            } else if readingBlockList, trimmed.hasPrefix("- ") {
                rules.append(normalizedYamlScalar(String(trimmed.dropFirst(2))))
            } else {
                readingBlockList = false
            }
        }
        return rules
    }

    private static func inlineYamlList(_ value: String) -> [String]? {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return nil }
        return value.dropFirst().dropLast()
            .split(separator: ",")
            .map { normalizedYamlScalar(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedYamlScalar(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        if trimmed.first == "\"", trimmed.last == "\"" {
            return String(trimmed.dropFirst().dropLast())
        }
        if trimmed.first == "'", trimmed.last == "'" {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func strippingHashComment(from line: String) -> String {
        var output = ""
        var inDoubleQuote = false
        for character in line {
            if character == "\"" {
                inDoubleQuote.toggle()
            } else if character == "#", !inDoubleQuote {
                break
            }
            output.append(character)
        }
        return output
    }

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
