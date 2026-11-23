import SlovoCore
import Synchronization

/// A programmable `Dependencies.settings` source. It returns one value until
/// `replace(with:)` changes it, or walks a script: each read returns the next
/// element and the last one repeats. State is guarded by a `Mutex`, so reads
/// from the orchestrator actor and writes from the test never race.
public final class FakeSettingsSource: Sendable {
    private struct Recorded {
        var value: DictationSettings
        var script: [DictationSettings]
        var readCount = 0
    }

    private let recorded: Mutex<Recorded>

    public init(
        _ value: DictationSettings = AppState(config: .defaults, isOpenRouterKeyPresent: true).dictationSettings
    ) {
        recorded = Mutex(Recorded(value: value, script: []))
    }

    /// Each read returns the next element of `script`; the last one repeats.
    public init(script: [DictationSettings]) {
        precondition(!script.isEmpty, "a script needs at least one value")
        recorded = Mutex(Recorded(value: script[0], script: script))
    }

    /// How many times the provider ran.
    public var readCount: Int {
        recorded.withLock { $0.readCount }
    }

    /// Makes every later read return `value`, ending any script.
    public func replace(with value: DictationSettings) {
        recorded.withLock {
            $0.value = value
            $0.script = []
        }
    }

    public var provider: @Sendable () async -> DictationSettings {
        { [self] in
            recorded.withLock { recorded in
                recorded.readCount += 1
                guard !recorded.script.isEmpty else { return recorded.value }
                return recorded.script[min(recorded.readCount, recorded.script.count) - 1]
            }
        }
    }
}
