import SlovoCore
import Synchronization

/// A `SystemAudioController` fake that returns a programmed `PriorAudioState` on
/// mute and records what each restore targeted and whether it actually wrote.
///
/// The recorded state is `Mutex`-guarded so the fake is genuinely race-free under
/// the `actor Orchestrator`.
public final class FakeSystemAudioController: SystemAudioController {
    private struct Recorded {
        var restoredDeviceIDs: [UInt32] = []
        var restoreDeviceWrites: [Bool] = []
        var muteCount = 0
    }

    private let programmedState: PriorAudioState
    private let recorded = Mutex<Recorded>(Recorded())

    public init(muteReturns state: PriorAudioState) {
        self.programmedState = state
    }

    /// The device id each restore targeted, in order (proves restore uses the
    /// pinned `state.deviceID`, not the then-current default).
    public var restoredDeviceIDs: [UInt32] {
        recorded.withLock { $0.restoredDeviceIDs }
    }

    /// Whether each restore issued a real device write — `true` only when the
    /// device was not already muted (restore is a no-op for already-muted output).
    public var restoreDeviceWrites: [Bool] {
        recorded.withLock { $0.restoreDeviceWrites }
    }

    /// How many times mute was invoked — lets a single-flight test assert NO
    /// second mute occurs on a re-entrant Start (Epic 09 AC-4).
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
            current.restoreDeviceWrites.append(!state.wasAlreadyMuted)
        }
    }
}
