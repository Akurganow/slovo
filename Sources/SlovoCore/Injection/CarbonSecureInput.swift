import Carbon.HIToolbox

/// Real `SecureInput` backed by the process-global `IsSecureEventInputEnabled()`
/// (Carbon HIToolbox; TN2150). Returns whether ANY process currently has secure
/// event input on — most commonly a focused password field.
///
/// Build-only: compiles in CI, behavior validated by the manual runbook.
/// Stateless, so `Sendable` is safe.
public struct CarbonSecureInput: SecureInput, Sendable {
    public init() {}

    public func isSecureInputActive() -> Bool {
        IsSecureEventInputEnabled()
    }
}
