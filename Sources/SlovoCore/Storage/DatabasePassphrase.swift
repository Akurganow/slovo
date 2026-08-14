import CryptoKit
import Foundation
import IOKit

/// Derives the SQLCipher passphrase for the personalization database from this
/// Mac's IOPlatformUUID (the stable logic-board identifier).
///
/// Derived on demand, never stored. No Keychain by design: dev and ad-hoc
/// builds risk repeated keychain prompts under unstable signing, and a
/// Keychain reset would orphan the database (spec Decision 2 records the
/// accepted trade: the derivation is public, so local protection is
/// obfuscation only — the guarantee is for copies that leave the Mac).
/// Consequence: the database is readable only on the Mac that created it; a
/// copy from another machine hits the wrong-key policy in
/// `PersonalizationDatabase.open`. The IOKit read relies on slovo being
/// unsandboxed.
public enum PersonalizationDatabasePassphrase {
    /// HKDF domain separation. FROZEN: changing either value re-keys every
    /// installation and orphans every existing database (pinned by the
    /// golden-vector test). The `-v1` suffix marks the derivation scheme; the
    /// rotation procedure is documented in docs/references/storage-grdb.md.
    private static let salt = Data("com.slovo.personalization-db".utf8)
    private static let context = Data("sqlcipher-passphrase-v1".utf8)

    /// The IOPlatformUUID could not be read — practically unreachable on real
    /// hardware. A throw here fails composition loudly rather than deriving a
    /// bogus key and orphaning the real database. One transitional exception:
    /// in the pre-encryption (plaintext) state the failure first surfaces
    /// inside the migration and lands in its broad catch — that session runs
    /// on the plaintext file unchanged (still no bogus key) and the migration
    /// retries next launch.
    public enum ReadError: Error {
        case serviceUnavailable
        case uuidMissing
    }

    /// Derives this Mac's database passphrase.
    ///
    /// # Errors
    /// `ReadError` when the IOKit platform-expert read fails.
    public static func derive() throws -> String {
        derive(from: try platformUuid())
    }

    /// Pure derivation step, separated so tests can pin it: platform UUID in,
    /// 64-hex-char SQLCipher passphrase out. Hex-string form (never raw key
    /// bytes) so `usePassphrase` and `ATTACH … KEY ?` share identical key
    /// semantics at every site.
    static func derive(from platformUuid: String) -> String {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(platformUuid.utf8)),
            salt: salt,
            info: context,
            outputByteCount: 32
        )
        return key.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func platformUuid() throws -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != IO_OBJECT_NULL else { throw ReadError.serviceUnavailable }
        defer { IOObjectRelease(service) }
        let property = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )
        guard let uuid = property?.takeRetainedValue() as? String, !uuid.isEmpty else {
            throw ReadError.uuidMissing
        }
        return uuid
    }
}
