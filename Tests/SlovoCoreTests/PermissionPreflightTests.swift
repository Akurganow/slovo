import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Preflight checks ALL THREE permissions independently and degrades if ANY is
// missing — not just Accessibility.
//
// Contract under test (the seam lives in `Sources/SlovoCore/Permissions/`, the
// fake in `Sources/SlovoTestSupport/`):
//
//     struct PermissionStatus { accessibility; inputMonitoring; microphone; allGranted }
//     protocol PermissionPreflighter { func preflight() -> PermissionStatus }
@Suite("Permission preflight")
struct PermissionPreflightTests {

    /// With Input Monitoring DENIED (others granted), preflight must report
    /// `allGranted == false` AND surface `.inputMonitoring == false` specifically.
    /// Stated sensitivity: a preflighter that checks only Accessibility (forcing
    /// IM/mic true) wrongly reports allGranted and loses the IM bit → RED.
    @Test
    func denyingInputMonitoringIsReportedAndBlocksAllGranted() {
        let preflighter = FakePermissionPreflighter(
            accessibility: true, inputMonitoring: false, microphone: true
        )
        let status = preflighter.preflight()

        #expect(status.inputMonitoring == false,
                "the denied Input Monitoring permission must be reported as false")
        #expect(status.allGranted == false,
                "allGranted must be false when Input Monitoring is denied")
    }

    /// With ALL THREE granted, preflight reports allGranted (guards against a
    /// preflighter that is never satisfied).
    @Test
    func allThreeGrantedReportsAllGranted() {
        let preflighter = FakePermissionPreflighter(
            accessibility: true, inputMonitoring: true, microphone: true
        )
        let status = preflighter.preflight()
        #expect(status.allGranted == true, "all three granted must report allGranted")
    }
}
