import Foundation
import Testing

// Static CI check for `Scripts/sign-and-notarize.sh` notarization credential
// selection. The release pipeline notarizes on GitHub runners with an App Store
// Connect API key, while local packaging keeps using a `notarytool` keychain
// profile. The script must pick the right `notarytool` credential flags from the
// environment and reject a partial API-key set instead of silently shipping an
// unnotarized build. Exercised through the script's existing `DRY_RUN` plan, so no
// real signing, network, or Apple credentials are involved.
@Suite("Notarization credential selection")
struct SigningNotarizationCredentialTests {
    @Test
    func keychainProfileMapsToKeychainProfileFlag() throws {
        // Local path is unchanged: NOTARY_PROFILE -> notarytool --keychain-profile.
        // Sensitivity: drop the keychain-profile branch and this plan loses the flag.
        let plan = try Self.appPlan(["NOTARY_PROFILE": "slovo-notary"])
        #expect(plan.exitCode == 0, Comment(rawValue: plan.output))
        #expect(plan.output.contains("DRY-RUN xcrun notarytool"), Comment(rawValue: plan.output))
        #expect(plan.output.contains("--keychain-profile slovo-notary"), Comment(rawValue: plan.output))
        #expect(!plan.output.contains("--key-id"), Comment(rawValue: plan.output))
    }

    @Test
    func apiKeyTrioMapsToKeyKeyIdIssuerFlags() throws {
        // App Store Connect API key: the trio maps to --key/--key-id/--issuer.
        // Sensitivity: ignoring NOTARY_KEY_* (pre-change behavior) skips notarization
        // entirely, so no notarytool line is emitted and every assertion below is RED.
        let plan = try Self.appPlan([
            "NOTARY_KEY_P8": "/tmp/asc-key.p8",
            "NOTARY_KEY_ID": "ABC123KEYID",
            "NOTARY_ISSUER_ID": "11112222-3333-4444-5555-666677778888",
        ])
        #expect(plan.exitCode == 0, Comment(rawValue: plan.output))
        #expect(plan.output.contains("DRY-RUN xcrun notarytool"), Comment(rawValue: plan.output))
        #expect(plan.output.contains("--key /tmp/asc-key.p8"), Comment(rawValue: plan.output))
        #expect(plan.output.contains("--key-id ABC123KEYID"), Comment(rawValue: plan.output))
        #expect(
            plan.output.contains("--issuer 11112222-3333-4444-5555-666677778888"),
            Comment(rawValue: plan.output)
        )
        #expect(!plan.output.contains("--keychain-profile"), Comment(rawValue: plan.output))
    }

    @Test
    func keychainProfileWinsWhenBothSourcesPresent() throws {
        // Both sources set at once: the keychain profile takes precedence, so the plan
        // uses --keychain-profile and never the API key. This pins the documented
        // "local behaves exactly as before" contract.
        // Sensitivity: swap the selection so the API-key branch is the leading `if`
        // and this plan emits --key/--key-id instead, turning the profile assertions RED.
        let plan = try Self.appPlan([
            "NOTARY_PROFILE": "slovo-notary",
            "NOTARY_KEY_P8": "/tmp/asc-key.p8",
            "NOTARY_KEY_ID": "ABC123KEYID",
            "NOTARY_ISSUER_ID": "11112222-3333-4444-5555-666677778888",
        ])
        #expect(plan.exitCode == 0, Comment(rawValue: plan.output))
        #expect(plan.output.contains("--keychain-profile slovo-notary"), Comment(rawValue: plan.output))
        #expect(!plan.output.contains("--key "), Comment(rawValue: plan.output))
        #expect(!plan.output.contains("--key-id"), Comment(rawValue: plan.output))
    }

    @Test
    func partialApiKeySetFailsInsteadOfShippingUnnotarized() throws {
        // A partial API-key set must abort with a usage error and never notarize.
        // Sensitivity: falling through to "no notarization" instead of exiting 64
        // makes the exit-code assertion RED.
        let plan = try Self.appPlan(["NOTARY_KEY_ID": "ABC123KEYID"])
        #expect(plan.exitCode == 64, Comment(rawValue: plan.output))
        #expect(!plan.output.contains("DRY-RUN xcrun notarytool"), Comment(rawValue: plan.output))
    }

    @Test
    func noCredentialsSignsWithoutNotarizing() throws {
        // No credentials: signing still runs, notarization is skipped (unchanged).
        let plan = try Self.appPlan([:])
        #expect(plan.exitCode == 0, Comment(rawValue: plan.output))
        #expect(plan.output.contains("DRY-RUN codesign"), Comment(rawValue: plan.output))
        #expect(!plan.output.contains("DRY-RUN xcrun notarytool"), Comment(rawValue: plan.output))
    }

    private struct CommandResult {
        let exitCode: Int32
        let output: String
    }

    /// DRY_RUN plan for the script `app` phase under an explicit notarization
    /// credential environment. All notary variables are seeded empty first so an
    /// inherited value cannot leak into a case that does not set it (the script
    /// treats empty as unset). A unique `APP_NAME` keeps the run hermetic.
    private static func appPlan(_ notaryEnvironment: [String: String]) throws -> CommandResult {
        var environment = [
            "DRY_RUN": "1",
            "SIGNING_IDENTITY": "Developer ID Application: Example (TEAMID)",
            "APP_NAME": "NotaryPlan-\(UUID().uuidString)",
            "NOTARY_PROFILE": "",
            "NOTARY_KEY_P8": "",
            "NOTARY_KEY_ID": "",
            "NOTARY_ISSUER_ID": "",
        ]
        environment.merge(notaryEnvironment) { _, new in new }

        // Capture through a per-invocation log file that the child bash opens itself
        // (redirection inside `-c`), never a parent-held Pipe. Under the parallel
        // test runner a Pipe write end can be inherited by a concurrently spawned
        // child and mix another invocation's plan into this one; a child-owned
        // redirect target cannot be inherited that way, so the capture stays isolated.
        let logURL = FileManager.default.temporaryDirectory
            .appending(path: "notary-plan-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", #"exec /bin/bash "$1" app >"$2" 2>&1"#, "notary-plan", scriptPath, logURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        try process.run()
        process.waitUntilExit()
        let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: output)
    }

    private static var scriptPath: String {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()  // SlovoCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // <pkg>
            .appending(path: "Scripts/sign-and-notarize.sh")
            .path
    }
}
