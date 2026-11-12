import Foundation
import Testing

// `.gitignore` ignores build artifacts, the seed/db globs, and key
// material. The probe: `git check-ignore` against an ISOLATED temp
// repo seeded with the REAL `.gitignore` (touches nothing real).
//
// Stated sensitivity: drop ANY required pattern from `.gitignore` → that probe is
// no longer ignored → RED. Reverting the glob to the literal list re-breaks the
// `data/seed.dev.sql` / `data/slovo.db.x` probes specifically. Narrowing `data/seed*.sql`
// to `data/seed.*.sql` re-breaks `data/seed.sql`; narrowing `data/*.db*` to `data/*.db.*`
// re-breaks `data/slovo.db` and `data/slovo.db-shm`. A re-admit (`!data/seed.2.sql`,
// `!data/slovo.db`) re-breaks its probe. Narrowing `credentials*.json` to
// `credentials.json` re-breaks `credentials-prod.json`; narrowing `id_rsa*` to `id_rsa`
// re-breaks `id_rsa.pub`.
@Suite(".gitignore hardening")
struct GitignoreHardeningTests {
    /// Each probe must be IGNORED by the hardened `.gitignore`. Build artifacts
    /// are already covered; the seed/db globs and key material are what hardening
    /// adds. Glob-only seed/db names catch a revert to the literal list; the literal
    /// names `data/seed.sql` and `data/slovo.db` catch a glob narrowed past them.
    private static let mustBeIgnored = [
        ".build/some-artifact.o",
        "DerivedData/Index/index.db",
        "data/seed.dev.sql",     // glob data/seed*.sql, missed by the literal list
        "data/slovo.db.x",       // glob data/*.db*, missed by the literal list
        "data/seed.sql",         // the literal seed name: the glob must still match it
        "data/seed.2.sql",       // alone caught by a re-admit: !data/seed.2.sql
        "data/slovo.db-shm",     // a SQLite sidecar: data/*.db* must match it
        "data/slovo.db",         // alone caught by a re-admit: !data/slovo.db
        "secrets/anthropic.key",  // key material must be ignored
        "secrets/notes.txt",      // only secrets/ ignores it
        "signing.key",            // only *.key ignores it
        "signing.pem",            // only *.pem ignores it
        // Env files and credential bundles: the `.gitignore` must cover dotenv
        // files, PKCS#12 / PEM-8 signing keys, opaque token files, dropped
        // credential JSON, and SSH private keys.
        ".env",
        ".env.local",
        "config.p12",
        "signing.p8",
        "session.token",
        "credentials.json",
        "credentials-prod.json",  // alone caught by narrowing credentials*.json to credentials.json
        "id_rsa",
        "id_rsa.pub",             // alone caught by narrowing id_rsa* to id_rsa
    ]

    @Test
    func gitignoreIgnoresEveryRequiredPattern() throws {
        let repo = try Self.makeTempRepoWithRealGitignore()
        defer { try? FileManager.default.removeItem(atPath: repo) }

        for probe in Self.mustBeIgnored {
            let full = URL(fileURLWithPath: repo).appendingPathComponent(probe).path
            try FileManager.default.createDirectory(
                atPath: URL(fileURLWithPath: full).deletingLastPathComponent().path,
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: full, contents: Data())

            let check = try Self.run("/usr/bin/git", ["-C", repo, "check-ignore", "-q", probe])
            #expect(check.exitCode == 0, "\(probe) is NOT ignored by .gitignore")
        }
    }

    // MARK: - Isolated temp repo helpers (touch nothing real)

    private static func makeTempRepoWithRealGitignore() throws -> String {
        let repo = NSTemporaryDirectory() + "slovo-gitignore-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        _ = try run("/usr/bin/git", ["-C", repo, "init", "-q"])

        let realGitignore = URL(fileURLWithPath: GateTestPaths.packageRoot)
            .appendingPathComponent(".gitignore").path
        let contents = try String(contentsOfFile: realGitignore, encoding: .utf8)
        try contents.write(
            toFile: URL(fileURLWithPath: repo).appendingPathComponent(".gitignore").path,
            atomically: true,
            encoding: .utf8
        )
        return repo
    }

    private struct ProcessResult {
        let exitCode: Int32
        let combinedOutput: String
    }

    private static func run(_ launchPath: String, _ args: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(
            exitCode: process.terminationStatus,
            combinedOutput: String(data: data, encoding: .utf8) ?? ""
        )
    }
}
