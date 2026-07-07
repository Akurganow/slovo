import Foundation
import Testing

// Source-level package guards because SwiftPM dependency graph APIs
// are not available inside tests without shelling out.
@Suite("Package dependencies")
struct PackageDependencyTests {
    /// The restored WhisperKit turbo path requires the argmax-oss-swift package
    /// as a dependency and the `WhisperKit` product linked into `SlovoCore`.
    /// Stated sensitivity: drop the argmax dependency or stop linking the
    /// `WhisperKit` product into `SlovoCore` (as the abandoned Apple-Speech
    /// migration did) → the transcriber cannot be built → RED.
    @Test
    func packageLinksWhisperKitFromArgmaxOssSwift() throws {
        let source = try String(contentsOfFile: Self.packagePath, encoding: .utf8)
        let code = Self.strippingComments(from: source)
        let coreTarget = try #require(Self.targetBlock(named: "SlovoCore", in: code))

        #expect(code.contains("argmaxinc/argmax-oss-swift"))
        #expect(coreTarget.contains("WhisperKit"))
        #expect(coreTarget.contains("argmax-oss-swift"))
    }

    @Test
    func everyTargetUsesStrictSwiftSettings() throws {
        let source = try String(contentsOfFile: Self.packagePath, encoding: .utf8)
        let code = Self.strippingComments(from: source)

        for flag in [
            "\"-warnings-as-errors\"",
            "\"-strict-concurrency=complete\"",
            "\"-enable-actor-data-race-checks\"",
        ] {
            #expect(code.contains(flag), "missing strict Swift flag \(flag)")
        }

        let targetBlocks = Self.swiftTargetBlocks(in: code)
        #expect(!targetBlocks.isEmpty)
        for targetBlock in targetBlocks {
            #expect(targetBlock.contains("swiftSettings: strictSwiftSettings"),
                    "every Swift SwiftPM target must use strictSwiftSettings")
        }
    }

    @Test
    func swiftLintIsPinnedStrictAndRequired() throws {
        let packageSource = try String(contentsOfFile: Self.packagePath, encoding: .utf8)
        let packageCode = Self.strippingComments(from: packageSource)
        let lintSource = try String(
            contentsOfFile: Self.packageRoot.appending(path: "Scripts/lint.sh").path,
            encoding: .utf8
        )
        let lintConfig = try String(
            contentsOfFile: Self.packageRoot.appending(path: ".swiftlint.yml").path,
            encoding: .utf8
        )
        let compactPackageCode = packageCode.filter { !$0.isWhitespace }

        #expect(compactPackageCode.contains(#".package(url:"https://github.com/SimplyDanny/SwiftLintPlugins",exact:"0.65.0")"#))
        #expect(compactPackageCode.contains(#".plugin(name:"SwiftLintBuildToolPlugin",package:"SwiftLintPlugins")"#))
        let targetBlocks = Self.swiftTargetBlocks(in: packageCode)
        #expect(!targetBlocks.isEmpty)
        for targetBlock in targetBlocks {
            #expect(targetBlock.contains("plugins: swiftLintPlugins"),
                    "every Swift SwiftPM target must use the SwiftLint build tool plugin")
        }

        let lintCode = Self.strippingShellComments(from: lintSource)
        let lintMain = Self.shellTopLevelLines(from: lintCode)
        let pluginFunction = try #require(Self.shellFunctionBody(named: "swift_package_plugin", in: lintCode))
        let pluginInvocations = Self.shellContinuationBlocks(containing: "swift package", in: pluginFunction)
        #expect(pluginInvocations.count == 2)
        for invocation in pluginInvocations {
            let tokens = Self.shellTokens(from: invocation)
            #expect(Self.containsOrdered(["swift", "package"], in: tokens))
            #expect(tokens.contains("--disable-automatic-resolution"))
            #expect(tokens.contains("plugin"))
            #expect(tokens.contains("--allow-writing-to-package-directory"))
            #expect(Self.containsOrdered(["--allow-network-connections", "none"], in: tokens))
        }
        #expect(pluginInvocations.filter { Self.shellTokens(from: $0).contains("--disable-sandbox") }.count == 1)
        #expect(pluginFunction.contains("sandbox_apply: Operation not permitted"))

        let swiftLintStage = try #require(Self.shellContinuationBlock(
            startingWith: #"run_stage "swiftlint-strict""#,
            in: lintMain
        ))
        let swiftLintStageTokens = Self.shellTokens(from: swiftLintStage)
        #expect(Self.containsOrdered(["run_stage", "swiftlint-strict", "swift_package_plugin", "swiftlint"], in: swiftLintStageTokens))

        let compilerLogFunction = try #require(Self.shellFunctionBody(named: "generate_swiftlint_compiler_log", in: lintCode))
        let compilerLogTokens = Self.shellTokens(from: compilerLogFunction)
        #expect(Self.containsOrdered(["swift", "build"], in: compilerLogTokens))
        #expect(compilerLogTokens.contains("--disable-automatic-resolution"))
        #expect(compilerLogTokens.contains("-v"))
        #expect(compilerLogFunction.contains(".build/swiftlint-compiler.log"))

        let analyzeFunction = try #require(Self.shellFunctionBody(named: "run_swiftlint_analyze", in: lintCode))
        let analyzeTokens = Self.shellTokens(from: analyzeFunction)
        #expect(Self.containsOrdered(["swift_package_plugin", "swiftlint", "analyze"], in: analyzeTokens))
        #expect(analyzeTokens.contains("--strict"))
        #expect(analyzeTokens.contains("--force-exclude"))
        #expect(analyzeTokens.contains("--compiler-log-path"))
        #expect(analyzeFunction.contains(".build/swiftlint-analyze.log"))
        let analyzeStage = try #require(Self.shellContinuationBlock(
            startingWith: #"run_stage "swiftlint-analyze""#,
            in: lintMain
        ))
        #expect(Self.containsOrdered(
            ["run_stage", "swiftlint-analyze", "run_swiftlint_analyze"],
            in: Self.shellTokens(from: analyzeStage)
        ))

        #expect(!lintCode.contains("SKIP"))
        #expect(!lintCode.contains("command -v swiftlint"))
        #expect(!lintCode.contains("which swiftlint"))
        #expect(!lintCode.contains("type swiftlint"))

        let swiftLintConfig = Self.topLevelYaml(from: lintConfig)
        #expect(swiftLintConfig.scalars["strict"] == "true")
        #expect(swiftLintConfig.scalars["check_for_updates"] == "false")
        #expect(swiftLintConfig.lists["opt_in_rules"] == ["all"])
        #expect(swiftLintConfig.lists["analyzer_rules"] == ["all"])
    }

    private static var packagePath: String {
        packageRoot.appendingPathComponent("Package.swift").path
    }

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func targetBlock(named name: String, in source: String) -> String? {
        let needle = ".target(\n            name: \"\(name)\""
        guard let range = source.range(of: needle) else { return nil }
        return parenthesizedBlock(startingAt: range.lowerBound, in: source)
    }

    /// C-family (Objective-C) targets are exempt from the Swift-only guards:
    /// strict Swift settings and SwiftLint do not apply to `.m` sources.
    private static let nonSwiftTargetNames = ["SlovoObjC"]

    /// SwiftPM target blocks that are Swift targets; C-family targets are excluded.
    private static func swiftTargetBlocks(in source: String) -> [String] {
        swiftPmTargetBlocks(in: source).filter { block in
            !nonSwiftTargetNames.contains { block.contains("name: \"\($0)\"") }
        }
    }

    private static func swiftPmTargetBlocks(in source: String) -> [String] {
        let targetMarkers = [".target(", ".executableTarget(", ".testTarget("]
        var blocks: [String] = []
        var searchStart = source.startIndex
        while searchStart < source.endIndex {
            let nextRange = targetMarkers
                .compactMap { source.range(of: $0, range: searchStart..<source.endIndex) }
                .min { $0.lowerBound < $1.lowerBound }
            guard let range = nextRange else { break }
            if let block = parenthesizedBlock(startingAt: range.lowerBound, in: source) {
                blocks.append(block)
            }
            searchStart = range.upperBound
        }
        return blocks
    }

    private static func parenthesizedBlock(startingAt start: String.Index, in source: String) -> String? {
        var depth = 0
        var started = false
        var index = start
        while index < source.endIndex {
            let character = source[index]
            if character == "(" {
                depth += 1
                started = true
            } else if character == ")" {
                depth -= 1
                if started && depth == 0 {
                    return String(source[start...index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private struct TopLevelYaml {
        var scalars: [String: String]
        var lists: [String: [String]]
    }

    private static func topLevelYaml(from source: String) -> TopLevelYaml {
        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var currentList: String?

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = strippingHashComment(from: rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if line.first?.isWhitespace == false {
                guard let separator = trimmed.firstIndex(of: ":") else { continue }
                let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: separator)...])
                    .trimmingCharacters(in: .whitespaces)
                if value.isEmpty {
                    lists[key] = []
                    currentList = key
                } else {
                    scalars[key] = value
                    currentList = nil
                }
            } else if trimmed.hasPrefix("- "), let key = currentList {
                lists[key, default: []].append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else {
                currentList = nil
            }
        }
        return TopLevelYaml(scalars: scalars, lists: lists)
    }

    private static func strippingShellComments(from source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { strippingHashComment(from: String($0)) }
            .joined(separator: "\n")
    }

    private static func strippingHashComment(from line: String) -> String {
        var output = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false

        for character in line {
            if escaped {
                output.append(character)
                escaped = false
            } else if character == "\\" && !inSingleQuote {
                output.append(character)
                escaped = true
            } else if character == "'" && !inDoubleQuote {
                output.append(character)
                inSingleQuote.toggle()
            } else if character == "\"" && !inSingleQuote {
                output.append(character)
                inDoubleQuote.toggle()
            } else if character == "#" && !inSingleQuote && !inDoubleQuote {
                break
            } else {
                output.append(character)
            }
        }
        return output
    }

    private static func shellContinuationBlock(startingWith prefix: String, in source: String) -> String? {
        shellContinuationBlocks(startingWith: prefix, in: source).first
    }

    private static func shellContinuationBlocks(startingWith prefix: String, in source: String) -> [String] {
        shellContinuationBlocks(in: source) { $0.hasPrefix(prefix) }
    }

    private static func shellContinuationBlocks(containing pattern: String, in source: String) -> [String] {
        shellContinuationBlocks(in: source) { $0.contains(pattern) }
    }

    private static func shellContinuationBlocks(
        in source: String,
        where matchesStart: (String) -> Bool
    ) -> [String] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let starts = lines.indices.filter { matchesStart(lines[$0].trimmingCharacters(in: .whitespaces)) }
        return starts.map { start in
            var index = start
            var blockLines: [String] = []
            while index < lines.count {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                let hasContinuation = trimmed.hasSuffix("\\")
                let commandLine = hasContinuation ? String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces) : trimmed
                blockLines.append(commandLine)
                if !hasContinuation { break }
                index += 1
            }
            return blockLines.joined(separator: "\n")
        }
    }

    private static func shellTopLevelLines(from source: String) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blockLines: [String] = []
        var isInFunction = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("() {") {
                isInFunction = true
            } else if isInFunction && trimmed == "}" {
                isInFunction = false
            } else if !isInFunction {
                blockLines.append(line)
            }
        }
        return blockLines.joined(separator: "\n")
    }

    private static func shellFunctionBody(named name: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "\(name)() {"
        }) else {
            return nil
        }
        guard let end = lines[(start + 1)...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            return nil
        }
        return lines[start...end].joined(separator: "\n")
    }

    private static func shellTokens(from command: String) -> [String] {
        command
            .split(whereSeparator: { $0.isWhitespace })
            .map { token in
                token
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
    }

    private static func containsOrdered(_ needles: [String], in haystack: [String]) -> Bool {
        var searchStart = haystack.startIndex
        for needle in needles {
            guard let found = haystack[searchStart...].firstIndex(of: needle) else { return false }
            searchStart = haystack.index(after: found)
        }
        return true
    }

    private static func strippingComments(from source: String) -> String {
        var output = ""
        var index = source.startIndex
        var inLineComment = false
        var inBlockComment = false
        var inString = false

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index) < source.endIndex ? source[source.index(after: index)] : "\0"

            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    output.append(character)
                }
            } else if inBlockComment {
                if character == "*" && next == "/" {
                    inBlockComment = false
                    index = source.index(after: index)
                }
            } else if inString {
                output.append(character)
                if character == "\"" {
                    inString = false
                }
            } else if character == "/" && next == "/" {
                inLineComment = true
                index = source.index(after: index)
            } else if character == "/" && next == "*" {
                inBlockComment = true
                index = source.index(after: index)
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

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
}
