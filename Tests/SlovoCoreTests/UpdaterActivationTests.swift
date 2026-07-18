import Testing

import SlovoCore
import SlovoTestSupport

// The pure activation policy: the stored automatic-update preference drives the
// updater's one scheduled-check switch through exactly one assignment — OFF is
// the owner's "zero update-network activity" rule, ON restores the schedule.
@Suite("Updater activation")
struct UpdaterActivationTests {
    /// OFF configures the switch off in exactly one assignment: [false].
    /// Stated sensitivity: an inert `apply` (assigns nothing → []) → RED; a
    /// transient set-true-then-set-false ([true, false]) — a brief window of
    /// update network activity the OFF rule forbids — → the exact-sequence pin
    /// → RED.
    @Test
    func offYieldsExactlyOneFalseAssignment() {
        let updater = FakeUpdaterSwitch()

        UpdaterActivation.apply(automaticUpdatesEnabled: false, to: updater)

        #expect(updater.assignments == [false])
    }

    /// ON restores the hourly schedule in exactly one assignment: [true].
    /// Stated sensitivity: an inert `apply` → [] → RED; inverting the
    /// preference → [false] → RED.
    @Test
    func onYieldsExactlyOneTrueAssignment() {
        let updater = FakeUpdaterSwitch()

        UpdaterActivation.apply(automaticUpdatesEnabled: true, to: updater)

        #expect(updater.assignments == [true])
    }
}
