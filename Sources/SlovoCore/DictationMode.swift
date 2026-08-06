/// What a single dictation session asks the cleanup step to produce.
///
/// Fixed at the hotkey layer and carried through the FSM to the cleanup step, so one
/// hold decides the whole session's intent. `.translate` is settled at the down edge
/// — a standalone translate key opened the session, or an additional key recognized
/// by its modifier bit alone (⌃, fn) was already held as it opened — or later, when
/// an additional key's own press latches onto the live hold. `.plain` is
/// transcription-only cleanup; `.translate` renders the utterance into the
/// configured target language.
///
/// `Equatable` keeps `HotkeyDecision`/`HotkeyPhase` synthesizing their own
/// `Equatable`, which their tests assert on.
public enum DictationMode: Equatable, Sendable {
    case plain
    case translate
}
