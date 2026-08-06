public enum MenuBarGlyphTint: Equatable, Sendable {
    case normal
    case error
}

/// The recording mode the menu-bar glyph encodes while the key is held — one
/// semantic family varying on a single dimension (the letter). The glyph is the
/// only signal of the mode before insertion, so it must be knowable at a glance
/// without opening a menu: a mode mixup costs one wrong paste. `raw` is the
/// cleanup-AVAILABILITY axis, not a `DictationMode` — cleanup off collapses every
/// hold to raw.
public enum RecordingGlyphMode: Equatable, Sendable {
    /// Cleanup will run: the transcript is cleaned before insertion.
    case clean
    /// Cleanup is effectively off (setting off or no key): the utterance lands as
    /// spoken, zero network.
    case raw
    /// Translate hold: the single cleanup step also translates. Requires clean mode.
    case translate
}

public enum MenuBarGlyph {
    /// Onu Ⱁ (U+2C11), the red glyph projected from every dictation failure
    /// status. The updater may reuse the visual glyph, but it is not a dictation
    /// status and therefore never enters the Error-cue path.
    public static let failureGlyph: Character = "\u{2C11}"

    /// Nash Ⱀ (U+2C10), the idle glyph shown while a downloaded update awaits
    /// the user's Restart: the menu bar itself announces the staged update
    /// without opening the dropdown.
    public static let updateReadyGlyph: Character = "\u{2C10}"

    /// The idle glyph is a projection of update state: while a downloaded update
    /// awaits restart, idle shows Nash Ⱀ instead of the Slovo Ⱄ brand glyph.
    /// Only resting idle varies — every live dictation state outranks the update
    /// marker and restores it when settling.
    public static func idleGlyph(isUpdateReady: Bool) -> Character {
        isUpdateReady ? updateReadyGlyph : forState(.idle)
    }

    public static func forState(_ state: DictationState) -> Character {
        switch state {
        case .recording:
            return forRecording(mode: .clean)
        case .idle:
            return "\u{2C14}"
        case .processing:
            return "\u{2C04}"
        }
    }

    /// Derives the recording-glyph mode from the dictation's mode and whether cleanup
    /// is effectively on. Raw wins whenever cleanup is off — however the hold came to
    /// translate — because a translate hold cannot run without cleanup; with cleanup
    /// on, a translate hold shows translate and a plain one shows clean.
    public static func recordingGlyphMode(mode: DictationMode, isCleanupOn: Bool) -> RecordingGlyphMode {
        guard isCleanupOn else { return .raw }
        switch mode {
        case .plain:
            return .clean
        case .translate:
            return .translate
        }
    }

    /// The recording glyph for a session's mode — a fully semantic family varying on
    /// one dimension (the letter). Recording has more than one branch, so a single
    /// catch-all glyph no longer suffices: Cherv Ⱍ (official Unicode name CHRIVI,
    /// U+2C1D, mnemonic "чистота"/clean — cleanup will run) marks clean mode; Glagoli
    /// Ⰳ (U+2C03, glagoli = "speak" — lands as spoken) marks raw mode; Pokoji Ⱂ
    /// (U+2C12) marks a translate hold. The menu bar tells the three apart at a glance.
    public static func forRecording(mode: RecordingGlyphMode) -> Character {
        switch mode {
        case .clean:
            return "\u{2C1D}"
        case .raw:
            return "\u{2C03}"
        case .translate:
            return "\u{2C12}"
        }
    }

    public static func forStatus(_ status: StatusMessage) -> Character? {
        status.isFailureNotice ? failureGlyph : "\u{2C06}"
    }

    public static func tint(forStatus status: StatusMessage) -> MenuBarGlyphTint {
        status.isFailureNotice ? .error : .normal
    }
}
