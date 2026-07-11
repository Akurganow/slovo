import Carbon.HIToolbox

/// Real `InputSourceLanguageReading` backed by the active keyboard input source
/// (Text Input Sources). Reads on demand each dictation; needs no permission or
/// entitlement. Stateless, so `Sendable` is safe. The read must happen on the main
/// actor (the caller hops there).
public struct SystemInputSourceLanguageReader: InputSourceLanguageReading {
    public init() {}

    public func currentPrimaryLanguage() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return nil
        }
        let languages = Unmanaged<CFArray>.fromOpaque(value).takeUnretainedValue() as? [String]
        return languages?.first
    }
}
