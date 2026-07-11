import SlovoCore

/// An `InputSourceLanguageReading` fake returning a fixed language (or nil).
public struct FakeInputSourceLanguageReader: InputSourceLanguageReading {
    private let language: String?

    public init(language: String?) {
        self.language = language
    }

    public func currentPrimaryLanguage() -> String? {
        language
    }
}
