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
//   - func stop() async                 // teardown: consumer stops, later sends are dropped
//
// Every delivered edge carries a stamp, set when the edge was sent: true when an
// earlier edge was still queued or still being handled. The stamp is how the app
// tells a press made during an earlier edge from a fresh press. The counter behind
// it is driven directly in OutstandingEdgeCountTests.
//
// Async coordination follows the repo's continuation-parking style
// (SlovoTestSupport.BlockingTranscriber): no sleeps, no timing luck — ordering is
// forced by parking a handler and releasing it under test control.
@Suite("Hotkey edge sequencer")
struct HotkeyEdgeSequencerTests {

    /// A key-down handler that is still running MUST hold back the following key-up:
    /// the sequencer runs one edge to completion before starting the next, in
    /// receipt order. The .down handler parks under test control; while it is
    /// parked the .up handler must not have begun.
    /// Killing mutation: dispatch each edge on its own independent Task (today's
    /// AppDelegate shape). Then .up runs while .down is parked, so `entered`
    /// becomes [.down, .up] before release and completion order is no longer
    /// serialized -> RED.
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

    /// A press made while the previous dictation's key-up handler was still running
    /// must reach the sink stamped busy. That holds EVEN THOUGH the handler has
    /// finished by the time the press is picked up. The single consumer guarantees
    /// the key-up handler completes first, so nothing observable at pick-up time
    /// separates this press from a fresh one. The fact has to be taken when the
    /// press is made.
    /// Killing mutation: stamp no edge busy (`arrivedWhileBusy: false`). The
    /// press made during the parked handler then looks exactly like a fresh press,
    /// and the app admits it -> RED.
    /// Killing mutation: compute the fact at dequeue instead of at send (read the
    /// outstanding count inside the consumer loop, before calling the sink). The
    /// press is dequeued only after the parked handler finished and stopped being
    /// outstanding, so it arrives not stamped busy -> RED.
    /// The window in which an edge is already queued but the consumer has not yet
    /// picked it up cannot be forced from outside the sequencer. The two-arrivals
    /// step of `anEdgeIsStampedBusyOnlyWhileAnEarlierOneHasNotDeparted` pins it
    /// instead, reaching the counter with no sink running at all.
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

    /// A press made with the channel free must not be stamped busy, so the app starts
    /// a session for it. This is the half that stops an over-eager refusal. An edge
    /// wrongly stamped busy here is a press the app would refuse, and the first press
    /// of every session is such an edge.
    /// Killing mutation: stamp every edge busy (`arrivedWhileBusy: true`, or answer
    /// `outstanding > 0` after the increment instead of `outstanding > 1`). Then the
    /// very first press is refused and dictation never starts -> RED.
    @Test
    func anEdgeSentWithTheChannelFreeIsNotStampedBusy() async {
        let recorder = EdgeSinkRecorder()
        let sequencer = HotkeyEdgeSequencer { edge in await recorder.record(edge) }

        sequencer.send(.down(.plain))

        await recorder.awaitHandled(1)
        #expect(await recorder.handled.map(\.arrivedWhileBusy) == [false],
                "an edge sent while nothing else was outstanding must not be stamped busy")
        await sequencer.stop()
    }

    /// "The next press dictates normally": once a dictation's own edges have been
    /// handled, the press that follows must not be stamped busy. The app then starts
    /// a session for it. This is the product rule the refusal must not eat.
    /// Killing mutation: delete `outstandingEdges.depart()`. The count then only
    /// grows. Every edge after the first is stamped busy, so the app refuses every
    /// press for the rest of the session -> RED.
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

    /// Teardown must DRAIN the enqueued edges and JOIN the consumer before it
    /// returns, then drop everything sent afterwards — so a rebuilt monitor cannot
    /// leave a second consumer draining the same fn edges.
    ///
    /// The recorder is read SYNCHRONOUSLY (a Mutex, not an actor) on purpose: the
    /// only suspension point between enqueuing `.down` and the assertion is `stop()`
    /// itself. A correct stop() suspends there to finish the stream and await the
    /// consumer, so `.down` is delivered before it returns. A stop() that neither
    /// finishes the stream nor joins the consumer has no suspension point, so the
    /// consumer never runs before the synchronous read.
    /// Killing mutation: drop `continuation.finish()` and/or the `await
    /// consumer.value` join from stop(). Then `.down` is still undelivered at the
    /// first read (handled == []) and/or the post-teardown `.up` leaks through the
    /// still-live consumer -> RED.
    @Test
    func teardownStopsDeliveryOfSubsequentEdges() async {
        let handled = Mutex<[HotkeyPhase]>([])
        let sequencer = HotkeyEdgeSequencer { edge in handled.withLock { $0.append(edge.phase) } }

        sequencer.send(.down(.plain))
        await sequencer.stop()

        #expect(handled.withLock { $0 } == [.down(.plain)],
                "stop() must drain the enqueued edge and join the consumer before returning")

        sequencer.send(.up(.plain))
        #expect(handled.withLock { $0 } == [.down(.plain)],
                "no edge may be delivered after teardown")
    }
}

/// Test double for the sequencer's async sink. Records the order in which edges
/// enter and finish handling, and can park the first edge until the test releases
/// it. The parking is what forces ordering without sleeps.
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

    /// Sink that parks the FIRST edge mid-flight until `releaseParkedEdge()`. The
    /// parking lets the test observe whether a later edge is (wrongly) started
    /// meanwhile. It also lets the test send an edge provably made while a handler
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
