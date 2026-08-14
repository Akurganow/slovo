import Foundation
import GRDB

/// TRANSITIONAL: re-encrypts plaintext personalization databases created
/// before encryption shipped. Deletable — this file plus the `.plaintext`
/// branch in `PersonalizationDatabase.open` — the day the owner decides no
/// pre-encryption install remains in the wild.
enum PlaintextDatabaseMigration {
    static let temporarySuffix = ".encrypting"

    /// SQLCipher's documented plaintext→encrypted flow (`sqlcipher_export`):
    /// copy into a temp DB keyed with the passphrase, verify the copy opens
    /// with that same passphrase, and only then swap it over the original.
    /// A crash before the swap leaves the plaintext original (+ a temp
    /// fragment); a crash INSIDE `replaceItemAt`'s swap window can leave the
    /// plaintext original at the temp path — `PersonalizationDatabase.open`
    /// removes any leftover unconditionally on every launch, so no state
    /// strands a plaintext file beside the encrypted one.
    static func encryptInPlace(
        at path: String,
        passphrase providePassphrase: () throws -> String
    ) throws {
        let temporaryPath = path + temporarySuffix
        let fileManager = FileManager.default

        // ATTACH needs one materialized passphrase value — short-lived, unlike
        // the pool-lifetime capture the provider form exists to prevent.
        let passphrase = try providePassphrase()
        let plaintext = try DatabaseQueue(path: path)
        do {
            try plaintext.inDatabase { db in
                try db.execute(
                    sql: "ATTACH DATABASE ? AS encrypted KEY ?",
                    arguments: [temporaryPath, passphrase]
                )
                try db.execute(sql: "SELECT sqlcipher_export('encrypted')")
                try db.execute(sql: "DETACH DATABASE encrypted")
            }
            try plaintext.close()
        } catch {
            try? plaintext.close()
            try? fileManager.removeItem(atPath: temporaryPath)
            throw error
        }

        try verifyEncryptedCopy(at: temporaryPath, passphrase: passphrase)

        // No sidecar removal here: SQLite deletes -wal/-shm at the clean
        // close above (measured on this platform), so no plaintext sidecar
        // survives past this point — before the swap. Test 4b pins that
        // invariant and reddens if this ever stops being true.
        //
        // Same-directory regular-file replace: the resulting URL is the
        // original path, so the returned value carries no information here.
        _ = try fileManager.replaceItemAt(
            URL(fileURLWithPath: path),
            withItemAt: URL(fileURLWithPath: temporaryPath)
        )
    }

    /// The LAST gate before the irreversible swap: the copy must open with the
    /// SAME passphrase the final open will use. Not redundant with GRDB's own
    /// validation at the final open — that one fires only after the original
    /// is already gone. Measured: with this verify, a mis-keyed export ends in
    /// a working plaintext-fallback session and the original intact; without
    /// it, the original is destroyed and the open throws.
    private static func verifyEncryptedCopy(at path: String, passphrase: String) throws {
        let copy = try DatabaseQueue(
            path: path,
            configuration: PersonalizationDatabase.keyedConfiguration(
                passphrase: { passphrase },
                readonly: true
            )
        )
        try copy.inDatabase { db in
            _ = try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master")
        }
        try copy.close()
    }
}
