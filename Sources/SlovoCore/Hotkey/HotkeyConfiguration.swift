/// The keys one hotkey monitor watches, by role. Carries no knowledge of storage
/// or of the app's `Config` — persistence projects INTO this type, so the Hotkey
/// layer stays the dependency and never the dependent.
public struct HotkeyConfiguration: Equatable, Sendable {
    /// The push-to-talk key that opens a dictation.
    public var main: HotkeyTrigger
    /// The key that makes a dictation translate. Naming the same key as `main` is
    /// rejected where the configuration is loaded, so a tie never reaches here;
    /// consulting `main` first only settles which role owns a session.
    public var translate: HotkeyTrigger
    /// Whether `translate` acts on top of a `main` hold, latching translate for
    /// that one dictation, rather than opening a dictation of its own.
    public var translateIsAdditional: Bool

    public init(main: HotkeyTrigger, translate: HotkeyTrigger, translateIsAdditional: Bool) {
        self.main = main
        self.translate = translate
        self.translateIsAdditional = translateIsAdditional
    }

    /// The gesture the translate key asks of the user. Every surface that phrases it
    /// — menu hint, About guide, Settings caption — branches on THIS, in its own
    /// words: the wording is per-surface, the fork is not, and a new gesture would
    /// fail to compile until each surface answered for it.
    public var translateGesture: TranslateGesture {
        translateIsAdditional ? .additional : .standalone
    }

    /// Whether fn is bound at all — the only configuration a macOS fn assignment can
    /// collide with, whichever role holds the key.
    public var usesFnKey: Bool {
        main == .fn || translate == .fn
    }
}

/// How a translate dictation is asked for.
public enum TranslateGesture: Equatable, Sendable {
    /// The translate key joins a push-to-talk hold, translating that one dictation.
    case additional
    /// The translate key opens the dictation itself, and every one of them translates.
    case standalone
}
