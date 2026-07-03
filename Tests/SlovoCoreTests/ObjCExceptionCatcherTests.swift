import Foundation
import Testing

import SlovoObjC

@Suite("Obj-C NSException catcher")
struct ObjCExceptionCatcherTests {
    /// Stated sensitivity: if the shim did not wrap the block in `@try/@catch`, the
    /// raised `NSException` would propagate uncaught and abort the test process
    /// (SIGABRT) — the whole suite would crash instead of returning an error here.
    @Test
    func convertsRaisedNSExceptionToError() {
        let error = SlovoRunCatchingNSException {
            NSException(name: .genericException, reason: "tap format mismatch", userInfo: nil).raise()
        }
        #expect(error != nil)
        #expect(error?.localizedDescription == "tap format mismatch")
    }

    /// Stated sensitivity: fabricating an error for a clean block, or failing to run
    /// the block, breaks these expectations.
    @Test
    func returnsNilAndRunsBlockWhenNoExceptionRaised() {
        var ran = false
        let error = SlovoRunCatchingNSException { ran = true }
        #expect(error == nil)
        #expect(ran)
    }
}
