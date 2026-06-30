import CryptoKit
import Foundation
import os

/// A redaction-safe wrapper around `os.Logger`.
///
/// Payload values (transcripts, dictionary terms, API error bodies, …) must
/// never reach a log sink in raw form. This wrapper exposes only redacting
/// surfaces: static, non-payload `event(_:)` text, a payload `length`, and a
/// stable correlation `hashed` value. The raw payload has no path to the sink.
///
/// The `sink` seam exists for tests: by default emission goes through
/// `os.Logger` with `.private` interpolation, but a test can inject a capturing
/// closure to assert exactly what would be emitted.
/// `@unchecked Sendable` rather than a `@Sendable`-closure sink: the production
/// default sink captures only an `os.Logger` (itself `Sendable`), and a test's
/// capturing sink is invoked only by its holder — synchronously, never
/// concurrently. Keeping the sink a plain `(String) -> Void` lets existing tests
/// pass an ordinary capturing closure (a `@Sendable` sink would forbid that) while
/// the type stays safely shareable across the `actor Orchestrator`.
public struct RedactionSafeLog: @unchecked Sendable {
    private let sink: (String) -> Void

    /// - Parameters:
    ///   - subsystem: reverse-DNS subsystem identifier for `os.Logger`.
    ///   - category: logging category within the subsystem.
    ///   - sink: emission seam; when `nil`, lines route through `os.Logger`
    ///     with `.private` interpolation so payload text is redacted by the OS.
    public init(subsystem: String, category: String, sink: ((String) -> Void)? = nil) {
        if let sink {
            self.sink = sink
        } else {
            let logger = Logger(subsystem: subsystem, category: category)
            // `.private` keeps the line out of plaintext logs on a release build;
            // this wrapper only ever hands the logger already-redacted text.
            self.sink = { message in logger.log("\(message, privacy: .private)") }
        }
    }

    /// Emits static, non-payload text verbatim. Callers must pass only fixed
    /// strings here — never an interpolated payload value.
    public func event(_ message: String) {
        sink(message)
    }

    /// Emits a payload's length to the sink, never its content.
    public func logLength(of value: some Collection) {
        sink("len=\(value.count)")
    }

    /// Emits a payload's stable correlation hash to the sink, never the raw value.
    public func logHash(of value: String) {
        sink("hash=\(Self.hashed(value))")
    }

    /// A short, stable hash usable for correlating log lines without revealing
    /// the value. Stable across calls (so two lines about the same payload
    /// correlate) and guaranteed to differ from — and not embed — the raw input.
    public static func hashed(_ value: String) -> String {
        // SHA-256 truncated to a short hex prefix: stable, non-reversible, and
        // never a substring of the input. A short prefix is enough for log
        // correlation while keeping lines compact.
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    /// Reports a payload's element count, never its content.
    public static func length(of value: some Collection) -> Int {
        value.count
    }
}
