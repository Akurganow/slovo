import SlovoCore
import Synchronization

/// A `SystemAudioController` fake whose mute returns a programmed state, returns
/// nil (a device with no lever) or throws (a failed HAL call), and whose restore
/// succeeds or throws. It records the device each restore was handed, a throwing
/// restore included.
///
/// The simulated-device initializer models one output device instead: mute sets
/// `isMuted` and returns the state it found, restore clears it unless that state was
/// already muted, and the first `failingRestores` restores throw and change nothing.
/// Every call lands in `calls`, in order.
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

    /// One call the fake received.
    public enum Call: Equatable, Sendable {
        case mute
        case restore(wasAlreadyMuted: Bool)
    }

    private struct Recorded {
        var restoredDeviceIDs: [UInt32] = []
        var muteCount = 0
        var calls: [Call] = []
        var isMuted = false
        var failingRestoresLeft = 0
    }

    private let muteOutcome: MuteOutcome
    private let restoreFails: Bool
    private let simulatedDeviceID: UInt32?
    private let recorded = Mutex<Recorded>(Recorded())

    public init(mute muteOutcome: MuteOutcome, restoreFails: Bool = false) {
        self.muteOutcome = muteOutcome
        self.restoreFails = restoreFails
        self.simulatedDeviceID = nil
    }

    /// A simulated output device whose first `failingRestores` restores throw.
    public init(simulatedDeviceID: UInt32 = 42, failingRestores: Int = 0) {
        self.muteOutcome = .noLever
        self.restoreFails = false
        self.simulatedDeviceID = simulatedDeviceID
        recorded.withLock { $0.failingRestoresLeft = failingRestores }
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

    /// Every mute and restore received, in order.
    public var calls: [Call] {
        recorded.withLock { $0.calls }
    }

    /// Whether the simulated device is muted now; always false outside simulation.
    public var isMuted: Bool {
        recorded.withLock { $0.isMuted }
    }

    public func muteSystemOutput() throws -> PriorAudioState? {
        recorded.withLock {
            $0.muteCount += 1
            $0.calls.append(.mute)
        }
        if let simulatedDeviceID {
            return recorded.withLock { current in
                let state = PriorAudioState(
                    deviceID: simulatedDeviceID, method: .mute, wasAlreadyMuted: current.isMuted, priorVolumeScalar: nil
                )
                current.isMuted = true
                return state
            }
        }
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
        let failsNow = recorded.withLock { current in
            current.restoredDeviceIDs.append(state.deviceID)
            current.calls.append(.restore(wasAlreadyMuted: state.wasAlreadyMuted))
            guard simulatedDeviceID != nil else { return restoreFails }
            if current.failingRestoresLeft > 0 {
                current.failingRestoresLeft -= 1
                return true
            }
            if !state.wasAlreadyMuted { current.isMuted = false }
            return false
        }
        if failsNow { throw HALFailure() }
    }
}
