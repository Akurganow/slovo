import SlovoCore
import Synchronization

/// A session-aware cue spy. It mirrors the public preference snapshot contract
/// while keeping playback immediate, so orchestrator tests observe cue decisions
/// without touching the system audio service.
public final class FakeDictationCueController: DictationCueController {
    public enum Event: Equatable, Sendable {
        case updateEnabled(Bool)
        case beginSession(isEnabled: Bool)
        case beginPlayback(DictationCue)
        case enqueue(DictationCue)
        case endSession
    }

    private struct State {
        var configuredEnabled: Bool
        var isSessionActive = false
        var sessionIsEnabled = false
        var events: [Event] = []
    }

    private let state: Mutex<State>
    private let onEvent: @Sendable (Event) -> Void

    @preconcurrency
    public init(isEnabled: Bool = true, onEvent: @escaping @Sendable (Event) -> Void = { _ in }) {
        state = Mutex(State(configuredEnabled: isEnabled))
        self.onEvent = onEvent
    }

    public var events: [Event] {
        state.withLock { $0.events }
    }

    public var playedCues: [DictationCue] {
        events.compactMap { event in
            switch event {
            case .beginPlayback(let cue), .enqueue(let cue): cue
            default: nil
            }
        }
    }

    public func updateEnabled(_ isEnabled: Bool) {
        record(.updateEnabled(isEnabled)) { $0.configuredEnabled = isEnabled }
    }

    public func beginSession() {
        let event = state.withLock { current -> Event in
            current.isSessionActive = true
            current.sessionIsEnabled = current.configuredEnabled
            let event = Event.beginSession(isEnabled: current.configuredEnabled)
            current.events.append(event)
            return event
        }
        onEvent(event)
    }

    public func beginPlayback(_ cue: DictationCue) -> DictationCuePlayback {
        // Mirrors the real controller: a cue it would not play yields no playback.
        let didRecord = recordIfSessionEnabled(.beginPlayback(cue))
        return didRecord ? .completed : .inaudible
    }

    public func enqueue(_ cue: DictationCue) {
        _ = recordIfSessionEnabled(.enqueue(cue))
    }

    public func endSession() {
        record(.endSession) { $0.isSessionActive = false }
    }

    @discardableResult
    private func recordIfSessionEnabled(_ event: Event) -> Bool {
        let didRecord = state.withLock { current -> Bool in
            guard current.isSessionActive, current.sessionIsEnabled else { return false }
            current.events.append(event)
            return true
        }
        if didRecord { onEvent(event) }
        return didRecord
    }

    private func record(_ event: Event, mutation: (inout State) -> Void) {
        state.withLock { current in
            mutation(&current)
            current.events.append(event)
        }
        onEvent(event)
    }
}
