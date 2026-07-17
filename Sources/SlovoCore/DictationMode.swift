/// What a single dictation session asks the cleanup step to produce.
///
/// Latched at the hotkey layer when Control is held during the hold and carried
/// through the FSM to the cleanup step, so one press decides the whole session's
/// intent. `.plain` is today's transcription-only cleanup (the exclusive value
/// today); `.translate` renders the utterance into the configured target language.
///
/// `Equatable` keeps `HotkeyDecision`/`HotkeyPhase` synthesizing their own
/// `Equatable`, which their tests assert on.
public enum DictationMode: Equatable, Sendable {
    case plain
    case translate
}
