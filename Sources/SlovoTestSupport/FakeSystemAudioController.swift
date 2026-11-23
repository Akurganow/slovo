import SlovoCore
import Synchronization

/// A `SystemAudioController` fake whose mute returns a programmed state, returns
/// nil (a device with no lever) or throws (a failed HAL call), and whose restore
/// succeeds or throws. It records the device each restore was handed, a throwing
/// restore included.
///
/// The recorded state is `Mutex`-guarded so the fake is genuinely race-free under
/// the `actor Orchestrator`.
public final class FakeSystemAudioController: SystemAudioController {
    /// What a mute does.
    public enum MuteOutcome: Sendable {
        case returns(PriorAudioState)
        case noLever
        case fails
    }

    /// The error a programmed failure throws.
    public struct HALFailure: Error {}

    private struct Recorded {
        var restoredDeviceIDs: [UInt32] = []
        var muteCount = 0
    }

    private let muteOutcome: MuteOutcome
    private let restoreFails: Bool
    private let recorded = Mutex<Recorded>(Recorded())

    public init(mute muteOutcome: MuteOutcome, restoreFails: Bool = false) {
        self.muteOutcome = muteOutcome
        self.restoreFails = restoreFails
    }

    public convenience init(muteReturns state: PriorAudioState) {
        self.init(mute: .returns(state))
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

    public func muteSystemOutput() throws -> PriorAudioState? {
        recorded.withLock { $0.muteCount += 1 }
        switch muteOutcome {
        case .returns(let state):
            return state
        case .noLever:
            return nil
        case .fails:
            throw HALFailure()
        }
    }

    public func restoreSystemOutput(_ state: PriorAudioState) throws {
        recorded.withLock { current in
            current.restoredDeviceIDs.append(state.deviceID)
        }
        if restoreFails { throw HALFailure() }
    }
}
