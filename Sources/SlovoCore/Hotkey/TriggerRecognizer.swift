/// Recognizes ONE physical key inside the reduced tap events: whether an event
/// puts it down and whether an event lifts it. Each role in the decision — the
/// push-to-talk key, the key that latches translate — owns a recognizer, so a
/// key's quirks stay with the key instead of spreading through session policy.
/// Whether a session is open is NOT kept here; the caller owns that bit and only
/// asks about the key.
struct TriggerRecognizer {
    /// How a key is told apart from every other key.
    enum Kind {
        /// fn: recognized by its modifier bit alone and hidden from the OS.
        /// Deliberately key-code-free — external keyboards report fn under their
        /// own codes.
        case suppressedFn
        /// One side of a modifier pair: the flags carry the class but never the
        /// side, so the key code is what names the single physical key.
        case passthroughModifier(HotkeyModifierFlags, keyCode: Int64)
        /// A modifier class with no side: either key of the pair matches.
        case classModifier(HotkeyModifierFlags)
    }

    /// The canonical fn virtual key code. An fn-bit-free event carrying it always
    /// releases, so even a hold that engaged on a junk code can be released by the
    /// real key — no stuck hot mic.
    private static let fnKeyCode: Int64 = 63

    private let kind: Kind
    /// The key code fn engaged on, recorded at the engage edge. External keyboards
    /// report fn under their own codes (see docs/references/macos-fn-hotkey.md), so
    /// the engage code is the only proof that a later fn-bit-free event is THIS key
    /// going up rather than unrelated noise.
    private var fnEngageKeyCode = TriggerRecognizer.fnKeyCode

    init(_ kind: Kind) {
        self.kind = kind
    }

    /// Whether the tap hides this key's event from the OS.
    var suppressesEvent: Bool {
        if case .suppressedFn = kind { return true }
        return false
    }

    /// Whether a combo can interrupt this key's hold. A suppressed key never reaches
    /// another app, so it can form no combo at all.
    var isInterruptible: Bool { !suppressesEvent }

    /// Whether this event puts the key down. Pure, so any role can ask about any
    /// key: the translate latch asks exactly this and nothing else.
    func engages(keyCode: Int64, flags: HotkeyModifierFlags) -> Bool {
        switch kind {
        // Keyed on the fn bit alone, key code ignored, so an odd-code keyboard
        // still engages.
        case .suppressedFn: return flags.contains(.secondaryFn)
        // The class bit is demanded alongside the key code, so an idle release
        // echo never reads as a press.
        case let .passthroughModifier(modifier, ownKeyCode): return keyCode == ownKeyCode && flags.contains(modifier)
        case let .classModifier(modifier): return flags.contains(modifier)
        }
    }

    /// Records what the engage looked like, so the matching release can be told
    /// from noise. Only fn carries anything across the hold.
    mutating func recordEngage(keyCode: Int64) {
        if case .suppressedFn = kind { fnEngageKeyCode = keyCode }
    }

    /// Whether this event lifts the key that `recordEngage` last saw go down.
    func releases(keyCode: Int64, flags: HotkeyModifierFlags) -> Bool {
        switch kind {
        case .suppressedFn:
            // Missing fn bit is NOT proof the key came up: macOS delivers junk and
            // foreign-modifier events without it while fn is still physically down.
            // Only an event naming the fn key releases — this hold's engage code, or
            // the canonical one, which heals a junk-code engage.
            guard !flags.contains(.secondaryFn) else { return false }
            return keyCode == fnEngageKeyCode || keyCode == Self.fnKeyCode
        case let .passthroughModifier(_, ownKeyCode):
            // While held, the key's own code IS its release: the class bit cannot
            // say which side moved while both same-class keys are down, and
            // flagsChanged has no key repeat, so a physically-down key's next own
            // event can only be its way up.
            return keyCode == ownKeyCode
        case let .classModifier(modifier):
            return !flags.contains(modifier)
        }
    }
}

extension TriggerRecognizer {
    /// The one projection that knows how each configured trigger is recognized.
    /// Every side-specific modifier names exactly ONE physical key code, which is
    /// what lets its hold be told apart from the same modifier on the other side.
    init(trigger: HotkeyTrigger) {
        switch trigger {
        case .fn: self.init(.suppressedFn)
        case .leftCommand: self.init(.passthroughModifier(.command, keyCode: 55))
        case .rightCommand: self.init(.passthroughModifier(.command, keyCode: 54))
        case .leftOption: self.init(.passthroughModifier(.option, keyCode: 58))
        case .rightOption: self.init(.passthroughModifier(.option, keyCode: 61))
        case .leftShift: self.init(.passthroughModifier(.shift, keyCode: 56))
        case .rightShift: self.init(.passthroughModifier(.shift, keyCode: 60))
        }
    }
}
