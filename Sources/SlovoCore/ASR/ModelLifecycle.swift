import Foundation

/// A loadable ASR model resource. Loading is expensive (ANE warm-up), so the
/// lifecycle keeps it warm for a window after use.
public protocol ModelLoading: AnyObject {
    func load() async throws
    func release()
    var isLoaded: Bool { get }
}

/// A monotonic time source, injected so idle timing is testable without a real
/// clock.
public protocol Clock {
    func now() -> TimeInterval
}

/// Owns ONE model's load/keep-warm/release lifecycle (spec §18.2: lifecycle
/// only — no backend selection, no degradation).
///
/// After use, the model is kept loaded for `keepWarmSeconds`: `tick()` releases
/// it once it has been idle longer than the window. A `keepWarmSeconds` of 0
/// releases immediately on `didFinishUse()` (no tick needed).
public final class ModelLifecycle {
    private let model: ModelLoading
    private let keepWarmSeconds: TimeInterval
    private let clock: Clock

    /// When the current idle period began; `nil` while in use or already released.
    private var idleSince: TimeInterval?

    public init(model: ModelLoading, keepWarmSeconds: TimeInterval, clock: Clock) {
        self.model = model
        self.keepWarmSeconds = keepWarmSeconds
        self.clock = clock
    }

    /// Ensures the model is loaded before use.
    public func willUse() async throws {
        idleSince = nil
        if !model.isLoaded {
            try await model.load()
        }
    }

    /// Marks use finished. With a zero keep-warm window the model is released at
    /// once; otherwise the idle timer starts and `tick()` will release it later.
    public func didFinishUse() {
        if keepWarmSeconds == 0 {
            model.release()
            idleSince = nil
        } else {
            idleSince = clock.now()
        }
    }

    /// Releases the model if it has been idle longer than the keep-warm window.
    public func tick() {
        guard let idleSince else { return }
        if clock.now() - idleSince > keepWarmSeconds {
            model.release()
            self.idleSince = nil
        }
    }
}
