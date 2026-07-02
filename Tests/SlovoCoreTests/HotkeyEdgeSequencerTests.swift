import Synchronization
import Testing

import SlovoCore

// Task #14 — the fn key must deliver its edges through ONE ordered, single-consumer
// channel so a slow key-down handler cannot be overtaken by the following key-up
// (the stuck-mute race). These tests pin the channel's externally visible
// contract; the AppDelegate wiring onto it is a GREEN-phase concern.
//
// Contract under test (implementer builds HotkeyEdgeSequencer to satisfy it):
//   - init(sink: @escaping @Sendable (HotkeyPhase) async -> Void)
//   - func send(_ phase: HotkeyPhase)   // synchronous, thread-safe, non-isolated
//                                        // (called from the CGEventTap run-loop thread)
//   - func stop() async                 // teardown: consumer stops, later sends are dropped
//
// Async coordination follows the repo's continuation-parking style
// (SlovoTestSupport.BlockingTranscriber): no sleeps, no timing luck — ordering is
// forced by parking a handler and releasing it under test control.
@Suite("Task #14 hotkey edge sequencer")
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
        let sequencer = HotkeyEdgeSequencer { phase in await recorder.handleParkingDown(phase) }

        sequencer.send(.down)
        sequencer.send(.up)

        await recorder.awaitEntered(1)
        #expect(await recorder.entered == [.down],
                "the following edge must not begin while the first handler is still running")

        await recorder.releaseDown()
        await recorder.awaitHandled(2)

        #expect(await recorder.handled == [.down, .up],
                "edges must complete one at a time, in receipt order")
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
        let sequencer = HotkeyEdgeSequencer { phase in await recorder.record(phase) }

        sequencer.send(.down)
        sequencer.send(.up)
        sequencer.send(.down)
        sequencer.send(.up)

        await recorder.awaitHandled(4)
        #expect(await recorder.handled == [.down, .up, .down, .up],
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
        let sequencer = HotkeyEdgeSequencer { phase in handled.withLock { $0.append(phase) } }

        sequencer.send(.down)
        await sequencer.stop()

        #expect(handled.withLock { $0 } == [.down],
                "stop() must drain the enqueued edge and join the consumer before returning")

        sequencer.send(.up)
        #expect(handled.withLock { $0 } == [.down],
                "no edge may be delivered after teardown")
    }
}

/// Test double for the sequencer's async sink. Records the order in which edges
/// enter and finish handling, and can park the .down handler until the test
/// releases it — the parking is what forces ordering without sleeps.
private actor EdgeSinkRecorder {
    private(set) var entered: [HotkeyPhase] = []
    private(set) var handled: [HotkeyPhase] = []
    private var downGate: CheckedContinuation<Void, Never>?
    private var downReleased = false
    private var countWaiters: [(threshold: Int, useHandled: Bool, continuation: CheckedContinuation<Void, Never>)] = []

    /// Fast sink: an edge enters and finishes immediately.
    func record(_ phase: HotkeyPhase) {
        entered.append(phase)
        handled.append(phase)
        resolveCountWaiters()
    }

    /// Sink that parks the .down handler mid-flight until `releaseDown()`, so the
    /// test can observe whether the next edge is (wrongly) started meanwhile.
    func handleParkingDown(_ phase: HotkeyPhase) async {
        entered.append(phase)
        resolveCountWaiters()
        if phase == .down, !downReleased {
            await withCheckedContinuation { downGate = $0 }
        }
        handled.append(phase)
        resolveCountWaiters()
    }

    func releaseDown() {
        downReleased = true
        downGate?.resume()
        downGate = nil
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
