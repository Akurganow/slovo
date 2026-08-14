import Foundation

/// One prevention-gate finding.
///
/// `rule` is a stable identifier (see ``GateChecks/Rule``) that callers and
/// tests match on; `detail` names the specific offending construct (an import or
/// a leaked payload variable).
///
/// Lives in the `GateChecksTests` target rather than shipped `SlovoCore`: the
/// scanners are a build-time gate, never product code, and their only consumers
/// are the gate tests here.
struct GateViolation: Equatable, Sendable {
    let file: String
    let rule: String
    let detail: String
}

/// Prevention gates implemented as source-tree scanners.
///
/// Each gate walks real on-disk sources (and, in tests, `.swifttext` fixtures)
/// and returns every violation it finds — no short-circuiting — so a caller can
/// report the complete failure set rather than only the first.
enum GateChecks {
    /// Stable rule identifiers. The `rawValue` is the on-the-wire id that callers
    /// and the shell gate match on; using the symbol makes a rename a compile
    /// error rather than a silent miss.
    enum Rule: String {
        case dependencyDirection = "dependency-direction"
        case redactionLint = "redaction-lint"
        case singleRelaunchCallSite = "single-relaunch-call-site"
    }

    // MARK: - Dependency direction

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

    // MARK: - Redaction lint

    /// Flags every logging interpolation that leaks a payload value.
    ///
    /// Two leak shapes are matched on comment-stripped code:
    /// - `\(EXPR, privacy: .public)` — anywhere in the file. The `privacy:`
    ///   argument exists only inside log-message interpolations, so no
    ///   logging-call anchor is needed, and a payload on a continuation line of a
    ///   multi-line call is caught like any single-line one. Any expression is a
    ///   payload — a bare variable, an accessor chain, or a call — unless it is
    ///   a dotted length reduction (`value.count`) or an exact entry in the
    ///   metric allowlist (`allowedMetricPayloads`).
    /// - `\(String(describing: VAR))` — only on a logging-call line
    ///   (`.log(`/`.info(`/… through any receiver name): `String(describing:)`
    ///   is ordinary Swift everywhere else, but in a log message it renders the
    ///   raw value.
    static func redactionViolations(inFileAt path: String) -> [GateViolation] {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { strippingLineComment(from: String($0)) }

        var leaked = publicPayloads(in: code.joined(separator: "\n"))
        for line in code where isLoggingCall(line) {
            leaked += describedPayloads(in: line)
        }
        return leaked.map { payload in
            GateViolation(
                file: path,
                rule: Rule.redactionLint.rawValue,
                detail: "payload `\(payload)` reaches the log raw (use .private / length / hash)"
            )
        }
    }

    /// Recursively scans every source under `root` for redaction violations.
    static func redactionViolations(inSourceTreeAt root: String) -> [GateViolation] {
        sourceFiles(under: root).flatMap { redactionViolations(inFileAt: $0) }
    }

    // MARK: - Single relaunch call site

    /// The never-self-restart tripwire: exactly ONE invocation of the relaunch
    /// coordinator `installDownloadedUpdateAndRelaunch` may exist in the scanned
    /// tree (its `func` definition excluded). Zero sites means the Restart path
    /// is missing; two or more re-open the self-restart door the design closed.
    static func singleRelaunchViolations(inSourceTreeAt root: String) -> [GateViolation] {
        let sites = relaunchInvocationSites(under: root)
        if sites.count == 1 { return [] }
        if sites.isEmpty {
            let missingRestartPath = GateViolation(
                file: root,
                rule: Rule.singleRelaunchCallSite.rawValue,
                detail: "no installDownloadedUpdateAndRelaunch invocation; the Restart path is missing"
            )
            return [missingRestartPath]
        }
        return sites.map { site in
            GateViolation(
                file: site,
                rule: Rule.singleRelaunchCallSite.rawValue,
                detail: "\(sites.count) relaunch invocation sites; the never-self-restart design allows exactly one"
            )
        }
    }

    /// One entry per invocation occurrence of the relaunch token, comment-stripped;
    /// the `func` definition line is not a call site.
    private static func relaunchInvocationSites(under root: String) -> [String] {
        let token = "installDownloadedUpdateAndRelaunch"
        var sites: [String] = []
        for path in sourceFiles(under: root) {
            guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in source.split(separator: "\n") {
                let code = strippingLineComment(from: String(line))
                guard code.contains(token) else { continue }
                if firstMatch(in: code, pattern: #"\bfunc\s+installDownloadedUpdateAndRelaunch\b"#) != nil { continue }
                sites.append(path)
            }
        }
        return sites
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

    /// The runbook's latency-attribution marks: metric expressions deliberately
    /// logged `.public` — never payload text — matched EXACTLY as captured, so
    /// any new `.public` payload (even a lookalike name) must be added here, a
    /// deliberate review step, before the gate passes it.
    /// Entries: `decodeMs`/`drainMs`/`requestMs` are millisecond durations;
    /// `planCase` is a decode-plan case NAME (associated values dropped at the
    /// call site); `confirmedEndSeconds` is a stream-position offset in seconds;
    /// `biasRetried ? 1 : 0` is a 0/1 flag for whether the tail decode was
    /// retried without the bias prompt — a decision bit, never transcript.
    private static let allowedMetricPayloads: Set<String> = [
        "biasRetried ? 1 : 0",
        "decodeMs",
        "drainMs",
        "planCase",
        "requestMs",
        "streamState.confirmedEndSeconds, format: .fixed(precision: 2)",
    ]

    /// Every `\(EXPR, privacy: .public)` payload expression in the given code,
    /// reported verbatim. Exactly two exemptions: a dotted length
    /// (`value.count`) and the exact-match metric allowlist above. A BARE
    /// `count` variable is not exempt — it can alias arbitrary payload.
    /// Residual: a `.count` accessor returning sensitive non-length data — or an
    /// allowlisted metric name reused for sensitive content — cannot be
    /// distinguished by a syntactic lint; the allowlist is not a guarantee that
    /// those names are always safe.
    private static func publicPayloads(in code: String) -> [String] {
        matches(in: code, pattern: #"\\\(\s*([^\\\n]+?)\s*,\s*privacy:\s*\.public\s*\)"#)
            .filter { firstMatch(in: $0, pattern: #"[A-Za-z_][A-Za-z0-9_]*\.count$"#) == nil }
            .filter { !allowedMetricPayloads.contains($0) }
    }

    /// Every `\(String(describing: <var>))` payload on one logging-call line —
    /// describing always renders the raw value into the message.
    private static func describedPayloads(in line: String) -> [String] {
        matches(in: line, pattern: #"\\\(\s*String\(describing:\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\)\s*\)"#)
    }

    /// True if the line is a logging call (`.log(`/`.info(`/…) through ANY
    /// receiver — a leak through a logger named other than `logger` still counts.
    private static func isLoggingCall(_ line: String) -> Bool {
        let methods = ["log", "info", "error", "debug", "notice", "fault", "warning"]
        return methods.contains { method in
            firstMatch(in: line, pattern: #"\.\#(method)\s*\("#) != nil
        }
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

    /// The scanned set — internal (not private) so gate tests can assert the
    /// walk actually visits real sources instead of greening on an empty walk.
    static func sourceFiles(under root: String) -> [String] {
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
