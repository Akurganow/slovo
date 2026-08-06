/// The keys one hotkey monitor watches, by role. Carries no knowledge of storage
/// or of the app's `Config` — persistence projects INTO this type, so the Hotkey
/// layer stays the dependency and never the dependent.
public struct HotkeyConfiguration: Equatable, Sendable {
    /// The push-to-talk key that opens a dictation.
    public var main: HotkeyTrigger
    /// The key that makes a dictation translate. Naming the same key as `main` is
    /// rejected where the configuration is loaded, so the decision core consults
    /// `main` first and never arbitrates a tie.
    public var translate: HotkeyTrigger
    /// Whether `translate` acts on top of a `main` hold, latching translate for
    /// that one dictation, rather than opening a dictation of its own.
    public var translateIsAdditional: Bool

    public init(main: HotkeyTrigger, translate: HotkeyTrigger, translateIsAdditional: Bool) {
        self.main = main
        self.translate = translate
        self.translateIsAdditional = translateIsAdditional
    }
}
