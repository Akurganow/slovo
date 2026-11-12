import SlovoCore
import Synchronization

/// A `SystemAudioController` fake that returns a programmed `PriorAudioState` on
/// mute and records the device each restore was handed.
///
/// The recorded state is `Mutex`-guarded so the fake is genuinely race-free under
/// the `actor Orchestrator`.
public final class FakeSystemAudioController: SystemAudioController {
    private struct Recorded {
        var restoredDeviceIDs: [UInt32] = []
        var muteCount = 0
    }

    private let programmedState: PriorAudioState
    private let recorded = Mutex<Recorded>(Recorded())

    public init(muteReturns state: PriorAudioState) {
        self.programmedState = state
    }

    /// The device id each restore was handed, in order.
    public var restoredDeviceIDs: [UInt32] {
        recorded.withLock { $0.restoredDeviceIDs }
    }

    /// How many times mute was invoked — lets a single-flight test assert NO
    /// second mute occurs on a re-entrant Start.
    public var muteCount: Int {
        recorded.withLock { $0.muteCount }
    }

    public func muteSystemOutput() throws -> PriorAudioState {
        recorded.withLock { $0.muteCount += 1 }
        return programmedState
    }

    public func restoreSystemOutput(_ state: PriorAudioState) throws {
        recorded.withLock { current in
            current.restoredDeviceIDs.append(state.deviceID)
        }
    }
}
