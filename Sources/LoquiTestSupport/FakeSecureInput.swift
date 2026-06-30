import Foundation
import LoquiCore
import Synchronization

/// A `SecureInput` fake whose successive `isSecureInputActive()` calls return
/// `values[0]`, `values[1]`, … and then repeat the last value. Models the
/// "clear at start, secure on re-check" focus-moved-to-password scenario.
///
/// The call cursor is `Mutex`-guarded so the fake is genuinely race-free.
public final class FakeSecureInput: SecureInput {
    private let values: [Bool]
    private let cursor = Mutex<Int>(0)

    public init(values: [Bool]) {
        self.values = values
    }

    public func isSecureInputActive() -> Bool {
        // Consumes one value per call; the LAST value repeats for every further
        // call. So `[false, true]` = first guard false, then the re-check AND all
        // later calls true — the injector only calls this twice (start + re-check),
        // but the repeat-last rule keeps a test robust if call count changes.
        guard !values.isEmpty else { return false }
        return cursor.withLock { index in
            let value = values[index]
            if index < values.count - 1 { index += 1 }
            return value
        }
    }
}
