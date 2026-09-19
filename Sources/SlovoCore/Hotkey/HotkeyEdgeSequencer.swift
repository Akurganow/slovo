import Synchronization

/// One received hotkey edge. The memberwise initializer stays internal, so the
/// only thing that can claim an edge arrived a given way is the sequencer that
/// received it.
public struct HotkeyEdge: Sendable {
    public let phase: HotkeyPhase
    /// True when an earlier edge was still queued or still being handled at the
    /// moment this one was sent. Stamped in `send`, because by the time an edge
    /// reaches the sink the earlier one has finished and left nothing to observe.
    public let arrivedWhileBusy: Bool
}

/// Edges sent but not yet handled, queued ones included. An edge already yielded
/// but not yet picked up is just as much an earlier edge. That is what separates
/// this count from a flag held around the sink call.
///
/// A reference box because `Mutex` is non-copyable, so the consumer task cannot
/// take the count out of the sequencer. Nor can the task capture the sequencer,
/// which is still being initialized when the task is created. `RedactionSafeLog`'s
/// `SerializedSink` is boxed for the same underlying reason.
///
/// Internal rather than private so `OutstandingEdgeCountTests` can drive it
/// directly. `depart()` runs after the sink returns and has no outward signal, so
/// a channel that never departs is invisible from outside the sequencer.
final class OutstandingEdgeCount: Sendable {
    private let count = Mutex<Int>(0)

    /// Counts an arriving edge, answering whether an earlier one was outstanding
    /// when it arrived.
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
/// Run-to-completion also means a handler can occupy the channel for a long
/// stretch. The key-up handler holds it across the whole finalize, cleanup and
/// insert pipeline. Edges sent during such a stretch are still delivered, in order
/// and exactly once. Each carries a stamp, so the sink can tell a press made while
/// the channel was free from one made while it was not.
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
