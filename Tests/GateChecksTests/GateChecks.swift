import Foundation

/// One prevention-gate finding.
///
/// `rule` is a stable identifier (see ``GateChecks/Rule``) that callers and
/// tests match on; `detail` names the specific offending construct (an import,
/// a payload variable, an AC id).
///
/// Lives in the `GateChecksTests` target rather than shipped `LoquiCore`: the
/// scanners are a build-time gate, never product code, and their only consumers
/// are the gate tests here.
struct GateViolation: Equatable, Sendable {
    let file: String
    let rule: String
    let detail: String
}

/// L1 prevention gates implemented as source-tree scanners.
///
/// Each gate walks real on-disk sources (and, in tests, `.swifttext` fixtures)
/// and returns every violation it finds — no short-circuiting — so the
/// non-masking diagnostic can report the complete failure set.
enum GateChecks {
    /// Stable rule identifiers. The `rawValue` is the on-the-wire id that callers
    /// and the shell gate match on; using the symbol makes a rename a compile
    /// error rather than a silent miss.
    enum Rule: String {
        case dependencyDirection = "dependency-direction"
        case redactionLint = "redaction-lint"
        case traceability = "traceability"
    }

    // MARK: - AC-4: dependency direction

    /// Flags dependency-direction violations in a single source file.
    ///
    /// A role-tagged source (one under a role directory such as `Cleaners/`, or
    /// whose name carries a role keyword) must not `import GRDB`, and a
    /// backend-role source must not import a sibling `*Backend` module. A file
    /// with no role tag, or one importing only platform modules, yields no
    /// violations.
    static func dependencyViolations(inFileAt path: String) -> [GateViolation] {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        guard isRoleTagged(path) else { return [] }

        var violations: [GateViolation] = []
        for module in importedModules(in: source) {
            if module == "GRDB" {
                violations.append(GateViolation(
                    file: path,
                    rule: Rule.dependencyDirection.rawValue,
                    detail: "role-tagged source imports GRDB; persistence must not leak into a role module"
                ))
            } else if module.hasSuffix("Backend") {
                violations.append(GateViolation(
                    file: path,
                    rule: Rule.dependencyDirection.rawValue,
                    detail: "role-tagged source imports sibling backend \(module); backends must not import each other"
                ))
            }
        }
        return violations
    }

    /// Recursively scans every `.swift`/`.swifttext` source under `root` for
    /// dependency-direction violations.
    static func dependencyViolations(inSourceTreeAt root: String) -> [GateViolation] {
        sourceFiles(under: root).flatMap { dependencyViolations(inFileAt: $0) }
    }

    // MARK: - AC-5: redaction lint

    /// Flags every logging interpolation that leaks a payload value.
    ///
    /// A leak is an interpolation using `privacy: .public` or `String(describing:)`
    /// in a logging call, regardless of the receiver name. The check is
    /// per-payload-type: it names each leaked variable independently, so a leak of
    /// any payload type is caught — not only a single hard-coded name. Lines
    /// reduced to a length, a hash, or a `.private` interpolation pass, and a leak
    /// that lives inside a line comment (documentation, not code) is ignored.
    static func redactionViolations(inFileAt path: String) -> [GateViolation] {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }

        var violations: [GateViolation] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let code = strippingLineComment(from: String(line))
            for leaked in leakedPayloads(in: code) {
                violations.append(GateViolation(
                    file: path,
                    rule: Rule.redactionLint.rawValue,
                    detail: "payload `\(leaked)` reaches the log raw (use .private / length / hash)"
                ))
            }
        }
        return violations
    }

    /// Recursively scans every source under `root` for redaction violations.
    static func redactionViolations(inSourceTreeAt root: String) -> [GateViolation] {
        sourceFiles(under: root).flatMap { redactionViolations(inFileAt: $0) }
    }

    // MARK: - AC-7: traceability

    /// Flags traceability defects in a catalog mapping in-scope AC ids to the
    /// tests that cover them.
    ///
    /// Two defect classes are reported: an in-scope AC with no mapped test
    /// ("missing"), and an AC mapped to a placeholder/assertion-free body
    /// ("vacuous"). An AC mapped to a body with a real assertion passes.
    static func traceabilityViolations(catalogAt path: String) -> [GateViolation] {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }

        let inScope = inScopeAcs(in: source)
        let coverage = testCoverage(in: source)  // AC id → body is a real assertion

        var violations: [GateViolation] = []
        for ac in inScope {
            switch coverage[ac] {
            case .none:
                violations.append(GateViolation(
                    file: path,
                    rule: Rule.traceability.rawValue,
                    detail: "in-scope AC \(ac) has no mapped test"
                ))
            case .some(false):
                violations.append(GateViolation(
                    file: path,
                    rule: Rule.traceability.rawValue,
                    detail: "in-scope AC \(ac) maps to a vacuous/placeholder test body"
                ))
            case .some(true):
                break
            }
        }
        return violations
    }

    // MARK: - AC-8: non-masking diagnostics

    /// Runs every gate check over the given roots WITHOUT short-circuiting and
    /// returns the complete violation set, so a multi-failure state reports every
    /// failure class rather than only the first.
    ///
    /// The checks are driven from a single registry so no check can be silently
    /// dropped from the aggregate: adding a check here is the only place it is
    /// declared, and `diagnoseAll` runs all of them.
    static func diagnoseAll(
        dependencyRoot: String,
        redactionRoot: String,
        traceabilityCatalog: String
    ) -> [GateViolation] {
        let registry: [() -> [GateViolation]] = [
            { dependencyViolations(inSourceTreeAt: dependencyRoot) },
            { redactionViolations(inSourceTreeAt: redactionRoot) },
            { traceabilityViolations(catalogAt: traceabilityCatalog) },
        ]
        return registry.flatMap { check in check() }
    }

    // MARK: - Dependency-direction helpers

    /// A source is role-tagged if it lives under a role DIRECTORY, or its file
    /// name carries a role keyword and is not itself a test or a mock.
    private static func isRoleTagged(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let roleDirectories: Set<String> = ["Cleaners", "Transcribers", "Injectors"]
        if url.pathComponents.contains(where: roleDirectories.contains) {
            return true
        }

        // Filename fallback: a role keyword in the name, but never a *Tests file
        // (a test of a role is not itself a role module) or a Mock* double.
        let name = url.deletingPathExtension().lastPathComponent
        if name.hasSuffix("Tests") || name.hasPrefix("Mock") { return false }
        let roleKeywords = ["Cleaner", "Transcriber", "Injector"]
        return roleKeywords.contains { name.contains($0) }
    }

    /// Extracts the module names from top-of-file `import` statements, ignoring
    /// any `import`-looking text inside a line comment.
    private static func importedModules(in source: String) -> [String] {
        source.split(separator: "\n").compactMap { line in
            let code = strippingLineComment(from: String(line)).trimmingCharacters(in: .whitespaces)
            guard code.hasPrefix("import ") else { return nil }
            return code
                .dropFirst("import ".count)
                .trimmingCharacters(in: .whitespaces)
                .split(separator: " ")
                .first
                .map(String.init)
        }
    }

    // MARK: - Redaction helpers

    /// Names every payload variable leaked on a single line of code. A line may
    /// carry more than one leak; each is reported independently (per-payload-type).
    /// The caller passes comment-stripped code, so a leak inside a `//` comment is
    /// never seen here.
    private static func leakedPayloads(in line: String) -> [String] {
        guard isLoggingCall(line) else { return [] }

        var leaked: [String] = []
        // `\(<var>, privacy: .public)` — a variable interpolated as public.
        leaked.append(contentsOf: matches(
            in: line,
            pattern: #"\\\(\s*([A-Za-z_][A-Za-z0-9_.]*)\s*,\s*privacy:\s*\.public\s*\)"#
        ))
        // `\(String(describing: <var>))` — describing always renders the value.
        leaked.append(contentsOf: matches(
            in: line,
            pattern: #"\\\(\s*String\(describing:\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\)\s*\)"#
        ))
        // A leaked accessor like `term.value` is reported by its root variable.
        return leaked.map { $0.split(separator: ".").first.map(String.init) ?? $0 }
    }

    /// True if the line is a logging call (`.log(`/`.info(`/…) through ANY
    /// receiver — a leak through a logger named other than `logger` still counts.
    private static func isLoggingCall(_ line: String) -> Bool {
        let methods = ["log", "info", "error", "debug", "notice", "fault", "warning"]
        return methods.contains { method in
            firstMatch(in: line, pattern: #"\.\#(method)\s*\("#) != nil
        }
    }

    // MARK: - Traceability helpers

    /// Parses the `in-scope-acs:` directive line into the set of AC ids.
    private static func inScopeAcs(in source: String) -> [String] {
        for line in source.split(separator: "\n") {
            guard let range = line.range(of: "in-scope-acs:") else { continue }
            return line[range.upperBound...]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    /// Maps each AC id named in a `// covers: <AC>` comment to whether its test
    /// body carries a real assertion (true) or is a placeholder (false).
    private static func testCoverage(in source: String) -> [String: Bool] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var coverage: [String: Bool] = [:]

        for (index, line) in lines.enumerated() {
            guard let range = line.range(of: "covers:") else { continue }
            let ac = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !ac.isEmpty else { continue }
            coverage[ac] = bodyHasRealAssertion(lines, startingAfter: index)
        }
        return coverage
    }

    /// A test body has a real assertion if, before its closing brace, it contains
    /// an `#expect`/`#require` whose argument is not a constant truth.
    ///
    /// Assumes a flat fixture body (the `}` at column zero of a single-level
    /// function ends the body); nested closures with their own `}` are out of
    /// scope for these catalog fixtures.
    private static func bodyHasRealAssertion(_ lines: [String], startingAfter coversIndex: Int) -> Bool {
        for line in lines[(coversIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "}" { return false }  // reached end of body, none found
            guard trimmed.contains("#expect") || trimmed.contains("#require") else { continue }
            if isVacuousAssertion(trimmed) { continue }
            return true
        }
        return false
    }

    /// A vacuous assertion asserts a compile-time-constant truth and tests
    /// nothing: `#expect(true)`, `#expect(Bool(true))`, and the like.
    private static func isVacuousAssertion(_ line: String) -> Bool {
        let normalized = line.replacingOccurrences(of: " ", with: "")
        return normalized.contains("#expect(true)")
            || normalized.contains("#expect(Bool(true)")
            || normalized.contains("#expect(false)")
            || normalized.contains("#require(true)")
    }

    // MARK: - Shared file walking / regex / comments

    /// Drops a trailing line comment, returning only the code to its left.
    ///
    /// Literal-aware: only an UNQUOTED `//` begins a comment. A `//` inside a
    /// `"…"` string span (e.g. a URL in a logged message) is part of the string,
    /// not a comment, so the code after it — including a real `.public` leak — is
    /// preserved. Quote spans respect `\"` escapes.
    private static func strippingLineComment(from line: String) -> String {
        var inString = false
        var previous: Character?
        let characters = Array(line)
        for (index, character) in characters.enumerated() {
            if character == "\"", previous != "\\" {
                inString.toggle()
            } else if character == "/", previous == "/", !inString {
                // The comment starts at the FIRST of the two slashes.
                return String(characters[..<(index - 1)])
            }
            previous = character
        }
        return line
    }

    private static func sourceFiles(under root: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        return enumerator.compactMap { element in
            guard let relative = element as? String else { return nil }
            guard relative.hasSuffix(".swift") || relative.hasSuffix(".swifttext") else { return nil }
            return URL(fileURLWithPath: root).appendingPathComponent(relative).path
        }
    }

    /// Returns the first capture group of every match of `pattern` in `text`.
    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captured])
        }
    }

    /// Whether `pattern` matches anywhere in `text`.
    private static func firstMatch(in text: String, pattern: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return Range(match.range, in: text)
    }
}
