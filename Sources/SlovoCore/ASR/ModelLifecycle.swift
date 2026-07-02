import Foundation

/// A loadable ASR model resource. Loading is expensive (ANE warm-up), so the
/// lifecycle keeps it warm for a window after use.
public protocol ModelLoading: AnyObject {
    func load() async throws
    func release()
    var isLoaded: Bool { get }
}

/// A monotonic time source plus a sleep capability, injected so idle timing AND
/// the keep-warm release delay are testable on one virtual timeline (no real
/// waiting). `Sendable` so the transcriber actor can share one instance with its
/// `ModelLifecycle` and capture it in the release task.
public protocol Clock: Sendable {
    func now() -> TimeInterval
    func sleep(for seconds: TimeInterval) async throws
}

/// Owns ONE model's load/keep-warm/release lifecycle (spec §18.2: lifecycle
/// only — no backend selection, no degradation).
///
/// `keepWarmSeconds` selects the retention policy: `nil` keeps the model RESIDENT
/// (never released here), `0` releases immediately on `didFinishUse()`, and a
/// positive window releases once `tick()` sees it idle longer than the window.
///
/// `@unchecked Sendable`: the only mutable state, `idleSince`, is lock-guarded; the
/// injected `model`/`clock` are set once and driven only through the owning
/// transcriber actor's serialized calls (mirrors `WhisperKitEngine`).
public final class ModelLifecycle: @unchecked Sendable {
    private let model: ModelLoading
    private let keepWarmSeconds: TimeInterval?
    private let clock: Clock
    private let lock = NSLock()

    /// When the current idle period began; `nil` while in use or already released.
    private var idleSince: TimeInterval?

    public init(model: ModelLoading, keepWarmSeconds: TimeInterval?, clock: Clock) {
        self.model = model
        self.keepWarmSeconds = keepWarmSeconds
        self.clock = clock
    }

    /// Ensures the model is loaded before use.
    public func willUse() async throws {
        lock.withLock { idleSince = nil }
        if !model.isLoaded {
            try await model.load()
        }
    }

    /// Marks use finished. A `nil` window keeps the model resident; a zero window
    /// releases at once; a positive window starts the idle timer for `tick()`.
    public func didFinishUse() {
        guard let keepWarmSeconds else { return }
        if keepWarmSeconds == 0 {
            model.release()
            lock.withLock { idleSince = nil }
        } else {
            lock.withLock { idleSince = clock.now() }
        }
    }

    /// Releases the model once it has been idle for at least the keep-warm window
    /// (the release driver sleeps exactly that window, so the boundary is inclusive).
    public func tick() {
        guard let keepWarmSeconds else { return }
        let idleSince = lock.withLock { self.idleSince }
        guard let idleSince else { return }
        if clock.now() - idleSince >= keepWarmSeconds {
            model.release()
            lock.withLock { self.idleSince = nil }
        }
    }
}
