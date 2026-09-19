import Testing

@testable import SlovoCore

// The counter behind every edge's stamp, driven here directly. Two edges can be
// outstanding with no sink running between them, and that case cannot be reached
// from outside the sequencer.
@Suite("Outstanding edge count")
struct OutstandingEdgeCountTests {

    /// An edge is stamped busy exactly while an earlier edge has arrived and not yet
    /// departed. Two arrivals with no departure between them is the queued case, and
    /// no sink runs there. That is why the sequencer counts rather than holds a flag.
    /// Killing mutation: delete `depart()` -> RED. Answer `outstanding > 0` after the
    /// increment -> RED. Count only while a sink runs -> RED.
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
