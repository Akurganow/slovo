import Testing

@testable import SlovoCore

// The counter behind every edge's stamp. It is driven directly here because its
// other half is invisible from outside the sequencer: `depart()` runs after the
// sink has returned and reports to nobody, so a channel that never departs — and
// therefore refuses every press after the first — passes every behaviour test the
// sequencer has.
@Suite("Outstanding edge count")
struct OutstandingEdgeCountTests {

    /// An edge is stamped busy exactly while an earlier edge has arrived and not yet
    /// departed. Two arrivals with no departure between them is the queued case: the
    /// second edge is already in the channel while the first is still outstanding,
    /// with no sink involved at all — which is why the count, and not a flag held
    /// around the sink call, is what the sequencer keeps.
    /// Killing mutation: delete `depart()`. The count then only grows, so the second
    /// arrival after a departure is stamped busy and the app refuses every press for
    /// the rest of the session -> RED.
    /// Killing mutation: answer `outstanding > 0` after the increment. Then the very
    /// first arrival is stamped busy and dictation never starts -> RED.
    /// Killing mutation: count only while a sink is running (a flag raised around the
    /// call instead of a count of outstanding edges). The two-arrivals step then
    /// reports not-busy, because no sink ran between them -> RED.
    @Test
    func anEdgeIsStampedBusyOnlyWhileAnEarlierOneHasNotDeparted() {
        let outstandingEdges = OutstandingEdgeCount()

        #expect(outstandingEdges.arrive() == false,
                "the first edge of a free channel has nothing outstanding before it")

        outstandingEdges.depart()
        #expect(outstandingEdges.arrive() == false,
                "an edge sent after the earlier one finished must start a session, not be refused")

        #expect(outstandingEdges.arrive() == true,
                "an edge sent while an earlier one is still outstanding is stamped busy, queued or not")

        outstandingEdges.depart()
        outstandingEdges.depart()
        #expect(outstandingEdges.arrive() == false,
                "once every earlier edge has departed the channel is free again")
    }
}
