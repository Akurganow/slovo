import Synchronization

/// One received hotkey edge. The memberwise initializer stays internal, so only
/// the sequencer that received an edge can say how it arrived.
public struct HotkeyEdge: Sendable {
    public let phase: HotkeyPhase
    /// True when an earlier edge was still queued or being handled as this one was
    /// sent. Stamped in `send`: by the time an edge reaches the sink, the earlier one
    /// has finished and left nothing to observe.
    public let arrivedWhileBusy: Bool
}

/// Counts edges sent but not yet handled, queued ones included. A count, not a
/// flag around the sink call: an edge already yielded is still an earlier edge.
/// A class because the consumer task cannot capture the sequencer, which is still
/// being initialized. Internal so `OutstandingEdgeCountTests` can drive `depart()`.
final class OutstandingEdgeCount: Sendable {
    private let count = Mutex<Int>(0)

    /// Counts an arriving edge. True when an earlier edge is still outstanding.
    func arrive() -> Bool {
        count.withLock { outstanding in
            outstanding += 1
            return outstanding > 1
        }
    }

    func depart() {
        count.withLock { $0 -= 1 }
    }
}

/// Serializes push-to-talk hotkey edges through a single ordered channel so a
/// slow `.down` handler can never be overtaken by the following `.up`.
///
/// The CGEventTap run-loop thread calls `send` for every edge; a single
/// long-lived consumer drains them and runs the sink for each edge to completion
/// before dequeuing the next. Without this, each edge ran on its own `Task` and a
/// still-running `.down` (mic setup, model warm-up) could be overtaken by `.up`,
/// leaving audio muted after the key was already released (the stuck-mute race).
///
/// The key-up handler holds the channel across the whole finalize, cleanup and
/// insert pipeline. Every edge sent during that stretch arrives stamped busy.
public final class HotkeyEdgeSequencer: Sendable {
    private let continuation: AsyncStream<HotkeyEdge>.Continuation
    private let consumer: Task<Void, Never>
    private let outstandingEdges: OutstandingEdgeCount

    /// - Parameter sink: invoked once per edge, in receipt order; the next edge is
    ///   dequeued only after this returns.
    @preconcurrency
    public init(sink: @escaping @Sendable (HotkeyEdge) async -> Void) {
        let (stream, continuation) = AsyncStream<HotkeyEdge>.makeStream()
        let outstandingEdges = OutstandingEdgeCount()
        self.continuation = continuation
        self.outstandingEdges = outstandingEdges
        self.consumer = Task {
            for await edge in stream {
                await sink(edge)
                // After the sink, never before: an edge sent while this one is being
                // handled must find it outstanding.
                outstandingEdges.depart()
            }
        }
    }

    /// Enqueues an edge, stamped with what the channel was doing when it arrived.
    /// Synchronous and thread-safe so the tap thread never blocks. Edges sent after
    /// `stop()` are dropped.
    public func send(_ phase: HotkeyPhase) {
        let arrivedWhileBusy = outstandingEdges.arrive()
        continuation.yield(HotkeyEdge(phase: phase, arrivedWhileBusy: arrivedWhileBusy))
    }

    /// Finishes the channel and joins the consumer, so a rebuilt monitor cannot
    /// leave a second consumer draining edges.
    public func stop() async {
        continuation.finish()
        await consumer.value
    }
}
