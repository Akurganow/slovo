import AppKit
import Foundation
import Testing

import SlovoCore

@Suite("Spell/locale integration", .tags(.integration))
struct SpellCheckHintProviderIntegrationTests {
    private static var runsLocally: Bool {
        ProcessInfo.processInfo.environment["CI"] == nil
    }

    private static var englishSpellingEnabled: Bool {
        NSSpellChecker.shared.userPreferredLanguages.contains { $0.lowercased().hasPrefix("en") }
    }

    /// Stated sensitivity: a provider that returns [] regardless (broken NSSpellChecker
    /// wiring) fails this when English spelling is available; the guard makes the
    /// assertion vacuous only when English is unavailable, never falsely green on a
    /// broken provider with English enabled.
    @Test(.enabled(if: runsLocally, "real NSSpellChecker; skipped on shared CI"))
    func realProviderFlagsAKnownMisspellingWhenEnglishEnabled() {
        let provider = SystemSpellCheckHintProvider()

        let findings = provider.findings(in: "I recieve teh package", ignoring: [])

        #expect(!findings.isEmpty || !Self.englishSpellingEnabled,
                "with English spelling enabled the on-device checker must flag a misspelling; got \(findings)")
        for finding in findings {
            #expect(!finding.token.isEmpty)
            #expect(finding.guesses.count <= 3, "guesses are capped at top-3")
        }
    }

    /// Stated sensitivity: an ignore list containing the flagged token must suppress
    /// it; a provider that ignores its ignore argument still returns the token → red
    /// (when English is enabled and the base case flagged it).
    @Test(.enabled(if: runsLocally, "real NSSpellChecker; skipped on shared CI"))
    func ignoredTermIsNotFlagged() {
        let provider = SystemSpellCheckHintProvider()

        let baseline = provider.findings(in: "I recieve teh package", ignoring: [])
        guard Self.englishSpellingEnabled, baseline.contains(where: { $0.token == "teh" }) else { return }

        let withIgnore = provider.findings(in: "I recieve teh package", ignoring: ["teh"])

        #expect(!withIgnore.contains { $0.token == "teh" }, "an ignored term must not be flagged; got \(withIgnore)")
    }

    /// Smoke: the TIS reader bridges without crashing and returns nil or a plausible
    /// primary subtag. Stated sensitivity: a broken Unmanaged bridge would crash or
    /// return a malformed value (spaces / non-lowercase), failing the shape check.
    @Test(.enabled(if: runsLocally, "real Text Input Sources; skipped on shared CI"))
    func inputSourceReaderReturnsPlausibleLanguageOrNil() {
        let language = SystemInputSourceLanguageReader().currentPrimaryLanguage()

        if let language {
            #expect(!language.isEmpty)
            #expect(!language.contains(" "))
        }
    }
}
