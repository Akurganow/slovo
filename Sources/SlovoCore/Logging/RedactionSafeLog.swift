import CryptoKit
import Foundation
import os
import Synchronization

/// Serializes sink invocation. The sink is a plain `(String) -> Void` so tests
/// can pass an ordinary capturing closure, but callers log from several
/// executors at once (the detached `TermMissReporter` task alongside the
/// `actor Orchestrator`), so every call runs under one lock. A reference box
/// because `Mutex` is non-copyable: copies of the value-type log must share it.
private final class SerializedSink: @unchecked Sendable {
    private let lock = Mutex<Void>(())
    private let emitLine: (String) -> Void

    init(_ emitLine: @escaping (String) -> Void) {
        self.emitLine = emitLine
    }

    func emit(_ message: String) {
        lock.withLock { _ in emitLine(message) }
    }
}

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
///
/// - Important: the sink MAY be invoked from any executor — the same log value
///   is shared across the `actor Orchestrator` and the detached miss-reporting
///   task. Invocations are serialized by an internal lock, so a capturing test
///   sink observes one call at a time; ordering between concurrent producers is
///   not defined, and a test that reads its captured lines must first await the
///   work that emits them. The lock is NOT recursive: a sink must never log
///   back into the same `RedactionSafeLog`, which would deadlock.
public struct RedactionSafeLog: Sendable {
    private let sink: SerializedSink

    /// - Parameters:
    ///   - subsystem: reverse-DNS subsystem identifier for `os.Logger`.
    ///   - category: logging category within the subsystem.
    ///   - sink: emission seam; when `nil`, lines route through `os.Logger`
    ///     with `.private` interpolation so payload text is redacted by the OS.
    public init(subsystem: String, category: String, sink: ((String) -> Void)? = nil) {
        if let sink {
            self.sink = SerializedSink(sink)
        } else {
            let logger = Logger(subsystem: subsystem, category: category)
            // `.private` keeps the line out of plaintext logs on a release build;
            // this wrapper only ever hands the logger already-redacted text.
            self.sink = SerializedSink { message in logger.log("\(message, privacy: .private)") }
        }
    }

    /// Emits static, non-payload text verbatim. Callers must pass only fixed
    /// strings here — never an interpolated payload value.
    public func event(_ message: String) {
        sink.emit(message)
    }

    /// Emits a payload's length to the sink, never its content.
    public func logLength(of value: some Collection) {
        sink.emit("len=\(value.count)")
    }

    /// Emits a payload's stable correlation hash to the sink, never the raw value.
    public func logHash(of value: String) {
        sink.emit("hash=\(Self.hashed(value))")
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
