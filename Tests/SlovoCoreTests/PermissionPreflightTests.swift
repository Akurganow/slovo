import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Epic 03 — AC-6 (CI-half): preflight checks ALL THREE permissions
// independently and degrades if ANY is missing (P22: preflight all three, not
// just Accessibility).
//
// Contract under test (implementer builds the seam in
// `Sources/SlovoCore/Permissions/` and the fake in `Sources/SlovoTestSupport/`
// per plan §4; CURRENTLY supplied by the WRONG-ON-PURPOSE
// `_RedScaffold_AudioPermSeams.swift` stub — preflight checks only
// Accessibility and forces IM + mic true — so this test goes RED on behavior).
//
//     struct PermissionStatus { accessibility; inputMonitoring; microphone; allGranted }
//     protocol PermissionPreflighter { func preflight() -> PermissionStatus }
@Suite("Epic 03 AC-6 permission preflight")
struct PermissionPreflightTests {

    /// With Input Monitoring DENIED (others granted), preflight must report
    /// `allGranted == false` AND surface `.inputMonitoring == false` specifically.
    /// Stated sensitivity: a preflighter that checks only Accessibility (forcing
    /// IM/mic true) wrongly reports allGranted and loses the IM bit → RED. (The
    /// scaffold forces IM true → RED now.)
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
