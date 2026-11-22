import Synchronization
import Testing

import SlovoCore

// The fn key must deliver its edges through ONE ordered, single-consumer
// channel so a slow key-down handler cannot be overtaken by the following key-up
// (the stuck-mute race). These tests pin the channel's externally visible
// contract; the AppDelegate wiring onto it is covered separately.
//
// Contract under test — `HotkeyEdgeSequencer`'s externally visible surface:
//   - init(sink: @escaping @Sendable (HotkeyEdge) async -> Void)
//   - func send(_ phase: HotkeyPhase)   // synchronous, thread-safe, non-isolated
//                                        // (called from the CGEventTap run-loop thread)
//   - func stop() async                 // teardown: drains, ends with one .cancel, consumer stops,
//                                        // later sends are dropped
//
// Every edge carries a stamp set when it was sent: true when an earlier edge was
// still queued or being handled. `OutstandingEdgeCountTests` drives that counter.
//
// Async coordination follows the repo's continuation-parking style
// (SlovoTestSupport.BlockingTranscriber): no sleeps, no timing luck — ordering is
// forced by parking a handler and releasing it under test control.
@Suite("Hotkey edge sequencer")
struct HotkeyEdgeSequencerTests {

    /// The sequencer runs one edge to completion before starting the next, in receipt
    /// order. The first handler parks under test control, so the second must not have
    /// begun while it is parked.
    /// Killing mutation: dispatch each edge on its own Task -> RED. The first
    /// expectation catches it in the schedules where the second edge's Task enters
    /// before the read: no wait can make an absence read certain. The order
    /// expectation after the release catches it in the schedules where the second
    /// edge finishes first.
    @Test
    func edgesAreHandledInReceiptOrderEvenWhenFirstHandlerIsSlow() async {
        let recorder = EdgeSinkRecorder()
        let sequencer = HotkeyEdgeSequencer { edge in await recorder.handleParkingFirstEdge(edge) }

        sequencer.send(.down(.plain))
        sequencer.send(.up(.plain))

        await recorder.awaitEntered(1)
        #expect(await recorder.entered.map(\.phase) == [.down(.plain)],
                "the following edge must not begin while the first handler is still running")

        await recorder.releaseParkedEdge()
        await recorder.awaitHandled(2)

        #expect(await recorder.handled.map(\.phase) == [.down(.plain), .up(.plain)],
                "edges must complete one at a time, in receipt order")
        await sequencer.stop()
    }

    /// A press sent while the key-up handler was still running arrives stamped busy,
    /// though that handler finishes first. Nothing at pick-up time separates it from a
    /// fresh press, so the fact has to be taken when the press is made.
    /// Killing mutation: stamp no edge busy -> RED. Killing mutation: read the
    /// outstanding count at dequeue instead of at send -> RED.
    @Test
    func pressSentWhileTheKeyUpHandlerWasRunningIsStampedThoughItFinishedFirst() async {
        let recorder = EdgeSinkRecorder()
        let sequencer = HotkeyEdgeSequencer { edge in await recorder.handleParkingFirstEdge(edge) }

        sequencer.send(.up(.plain))
        await recorder.awaitEntered(1)
        sequencer.send(.down(.plain))
        await recorder.releaseParkedEdge()
        await recorder.awaitHandled(2)

        #expect(await recorder.handled.map(\.phase) == [.up(.plain), .down(.plain)],
                "the key-up handler must finish before the press that arrived during it is handled")
        #expect(await recorder.handled.map(\.arrivedWhileBusy) == [false, true],
                "a press sent while the key-up handler was still running must arrive stamped busy, though that handler finished first")
        await sequencer.stop()
    }

    /// "The next press dictates normally": once a dictation's own edges are handled,
    /// the press that follows must not be stamped busy. The first press of the session
    /// finds the channel free too, or the app refuses the first press of every session.
    /// Killing mutation: delete `outstandingEdges.depart()`, so the count only grows
    /// and every press after the first is refused -> RED. Killing mutation: stamp every
    /// edge busy -> RED.
    @Test
    func aPressMadeAfterTheEarlierDictationFinishedIsNotStampedBusy() async {
        let recorder = EdgeSinkRecorder()
        let sequencer = HotkeyEdgeSequencer { edge in await recorder.record(edge) }

        sequencer.send(.down(.plain))
        await recorder.awaitHandled(1)
        sequencer.send(.up(.plain))
        await recorder.awaitHandled(2)
        sequencer.send(.down(.plain))
        await recorder.awaitHandled(3)

        #expect(await recorder.handled.map(\.arrivedWhileBusy) == [false, false, false],
                "a dictation and the press after it must each find the channel free")
        await sequencer.stop()
    }

    /// A rapid burst of edges must arrive at the sink exactly once each, in order —
    /// nothing dropped, coalesced, or reordered under back-pressure.
    /// Killing mutation: a channel that drops or coalesces edges never reaches four
    /// handled (awaitHandled(4) cannot complete) or records a shorter list; a
    /// reordering channel records a different sequence -> RED.
    @Test
    func deliversEveryEdgeExactlyOnceInOrderForABurst() async {
        let recorder = EdgeSinkRecorder()
        let sequencer = HotkeyEdgeSequencer { edge in await recorder.record(edge) }

        sequencer.send(.down(.plain))
        sequencer.send(.up(.plain))
        sequencer.send(.down(.plain))
        sequencer.send(.up(.plain))

        await recorder.awaitHandled(4)
        #expect(await recorder.handled.map(\.phase) == [.down(.plain), .up(.plain), .down(.plain), .up(.plain)],
                "every edge in a rapid burst must be delivered exactly once, in order")
        await sequencer.stop()
    }

    /// Teardown must DRAIN the enqueued edges, end the stream with one `.cancel`, and
    /// JOIN the consumer before it returns. The cancel ends any dictation the drained
    /// edges left open (a press with no release, say), so a torn-down pipeline never
    /// keeps the microphone open or output muted; a rebuilt monitor cannot leave a
    /// second consumer draining the same fn edges.
    ///
    /// The recorder is read SYNCHRONOUSLY (a Mutex, not an actor) on purpose: the
    /// only suspension point between enqueuing the edges and the assertion is
    /// `stop()` itself.
    /// Killing mutation: drop the cancel from stop() → handled ends at `.up` → RED.
    /// Killing mutation: hand the cancel to the sink directly at the start of stop(),
    /// ahead of the drained edges → RED in the schedules where the consumer has not
    /// handled both edges yet. Killing mutation: drop the `await consumer.value`
    /// join → RED in the schedules where the consumer has not delivered all three
    /// edges by the read. Drop `continuation.finish()` → the consumer never ends and
    /// the join never returns → the test hangs.
    @Test
    func teardownDrainsEnqueuedEdgesThenCancelsBeforeStopReturns() async {
        let handled = Mutex<[HotkeyPhase]>([])
        let sequencer = HotkeyEdgeSequencer { edge in handled.withLock { $0.append(edge.phase) } }

        sequencer.send(.down(.plain))
        sequencer.send(.up(.plain))
        await sequencer.stop()

        #expect(handled.withLock { $0 } == [.down(.plain), .up(.plain), .cancel],
                "stop() must deliver the enqueued edges, then one cancel, and nothing after, before returning")
    }
}

/// Test double for the sequencer's async sink. Records the order in which edges
/// enter and finish handling. The parking is what forces ordering without sleeps.
private actor EdgeSinkRecorder {
    private(set) var entered: [HotkeyEdge] = []
    private(set) var handled: [HotkeyEdge] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false
    private var countWaiters: [(threshold: Int, useHandled: Bool, continuation: CheckedContinuation<Void, Never>)] = []

    /// Fast sink: an edge enters and finishes immediately.
    func record(_ edge: HotkeyEdge) {
        entered.append(edge)
        handled.append(edge)
        resolveCountWaiters()
    }

    /// Parks the FIRST edge until `releaseParkedEdge()`. The test can then watch for a
    /// later edge wrongly starting, and can send an edge provably made while a handler
    /// is still running.
    func handleParkingFirstEdge(_ edge: HotkeyEdge) async {
        entered.append(edge)
        resolveCountWaiters()
        if entered.count == 1, !released {
            await withCheckedContinuation { gate = $0 }
        }
        handled.append(edge)
        resolveCountWaiters()
    }

    func releaseParkedEdge() {
        released = true
        gate?.resume()
        gate = nil
    }

    /// Suspends until at least `count` edges have entered handling.
    func awaitEntered(_ count: Int) async {
        await awaitCount(count, useHandled: false)
    }

    /// Suspends until at least `count` edges have finished handling.
    func awaitHandled(_ count: Int) async {
        await awaitCount(count, useHandled: true)
    }

    private func awaitCount(_ threshold: Int, useHandled: Bool) async {
        if (useHandled ? handled.count : entered.count) >= threshold { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((threshold, useHandled, continuation))
        }
    }

    private func resolveCountWaiters() {
        countWaiters.removeAll { waiter in
            let current = waiter.useHandled ? handled.count : entered.count
            guard current >= waiter.threshold else { return false }
            waiter.continuation.resume()
            return true
        }
    }
}
