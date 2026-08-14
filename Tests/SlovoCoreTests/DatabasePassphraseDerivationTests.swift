import Testing

// @testable for the internal pure derivation step `derive(from:)`.
// (No Foundation import: nothing here needs it, and `swiftlint analyze`'s
// unused_import rule is active.)
@testable import SlovoCore

// The golden vector subsumes determinism and shape; those two stay for legible
// failure messages, and distinct-inputs is the one independent probe — a
// deliberate overlap, not accidental redundancy.
@Suite("Personalization database passphrase derivation")
struct DatabasePassphraseDerivationTests {
    /// Stated sensitivity: non-deterministic derivation (e.g. a random salt),
    /// or output that is not exactly 64 lowercase hex chars → RED.
    @Test
    func derivationIsDeterministicAndWellFormed() {
        let first = PersonalizationDatabasePassphrase.derive(from: "AAAA-1111")
        let second = PersonalizationDatabasePassphrase.derive(from: "AAAA-1111")
        #expect(first == second)
        #expect(first.count == 64)
        #expect(first.allSatisfy { $0.isNumber || ($0.isHexDigit && $0.isLowercase) })
    }

    /// Stated sensitivity: derivation that ignores the UUID (a constant key
    /// for every machine) → RED.
    @Test
    func distinctMachinesGetDistinctPassphrases() {
        #expect(
            PersonalizationDatabasePassphrase.derive(from: "AAAA-1111")
                != PersonalizationDatabasePassphrase.derive(from: "BBBB-2222")
        )
    }

    /// Pins salt + info + KDF + output length in one constant.
    /// Stated sensitivity: ANY change to the salt, info string, hash, or
    /// output length → RED.
    @Test
    func derivationMatchesGoldenVector() {
        #expect(
            PersonalizationDatabasePassphrase.derive(
                from: "00000000-0000-0000-0000-000000000000")
                == "5ef2581c89b84625e9642770162151095174901b361d041c5b01f99e32ea9eb9",
            """
            THE HKDF SALT/INFO ARE FROZEN. A mismatch here means the derivation \
            changed, which re-keys every installation and orphans every existing \
            database. Fix the code — NEVER update this constant.
            """
        )
    }

    /// Smoke for the production path: derivation works on the machine running
    /// the suite — one legible failure instead of obscure downstream errors if
    /// IOKit ever stops serving the UUID (e.g. under future sandboxing).
    /// Stated sensitivity: break the IOKit read (wrong service/property name)
    /// → RED here, by name.
    @Test
    func platformDerivationSucceedsOnThisMachine() throws {
        let passphrase = try PersonalizationDatabasePassphrase.derive()
        #expect(passphrase.count == 64)
    }
}
