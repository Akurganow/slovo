import Testing

import SlovoCore

// The pure classifier behind the fn conflict notice: it maps the system's raw
// fn-key usage preference onto "is fn assigned to a macOS action". `nil` means
// the preference was unreadable and 0 is the explicit "Do Nothing" setting —
// both must read as unassigned so the notice never cries wolf; any non-zero
// value names a real system action.
@Suite("Fn key assignment")
struct FnKeyAssignmentTests {

    /// `nil` (unreadable preference) and 0 ("Do Nothing") are the only unassigned
    /// readings.
    /// Stated sensitivity: invert the mapping, or treat an unreadable preference
    /// as assigned → RED.
    @Test
    func unreadableAndDoNothingReadAsUnassigned() {
        #expect(!FnKeyAssignment.isAssigned(usageType: nil))
        #expect(!FnKeyAssignment.isAssigned(usageType: 0))
    }

    /// Every non-zero usage type reads as assigned — the classifier keys on
    /// "anything but Do Nothing", not on one specific action value.
    /// Stated sensitivity: delete the mapping (always false) or gate on a single
    /// specific value → one of these reads unassigned → RED.
    @Test
    func nonZeroUsageTypesReadAsAssigned() {
        #expect(FnKeyAssignment.isAssigned(usageType: 1))
        #expect(FnKeyAssignment.isAssigned(usageType: 2))
        #expect(FnKeyAssignment.isAssigned(usageType: 3))
    }
}
