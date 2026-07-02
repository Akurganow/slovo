/// Serializes push-to-talk hotkey edges through a single ordered channel so a
/// slow `.down` handler can never be overtaken by the following `.up`.
///
/// The CGEventTap run-loop thread calls `send` for every edge; a single
/// long-lived consumer drains them and runs the sink for each edge to completion
/// before dequeuing the next. Without this, each edge ran on its own `Task` and a
/// still-running `.down` (mic setup, model warm-up) could be overtaken by `.up`,
/// leaving audio muted after the key was already released (the stuck-mute race).
public final class HotkeyEdgeSequencer: Sendable {
    private let continuation: AsyncStream<HotkeyPhase>.Continuation
    private let consumer: Task<Void, Never>

    /// - Parameter sink: invoked once per edge, in receipt order; the next edge is
    ///   dequeued only after this returns.
    @preconcurrency
    public init(sink: @escaping @Sendable (HotkeyPhase) async -> Void) {
        let (stream, continuation) = AsyncStream<HotkeyPhase>.makeStream()
        self.continuation = continuation
        self.consumer = Task {
            for await phase in stream {
                await sink(phase)
            }
        }
    }

    /// Enqueues an edge. Synchronous and thread-safe so the tap thread never
    /// blocks; edges after `stop()` are dropped.
    public func send(_ phase: HotkeyPhase) {
        continuation.yield(phase)
    }

    /// Finishes the channel and joins the consumer, so a rebuilt monitor cannot
    /// leave a second consumer draining edges.
    public func stop() async {
        continuation.finish()
        await consumer.value
    }
}
