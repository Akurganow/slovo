/// The vocabulary source while the personalization database is not open: no
/// terms, so a dictation runs with no bias and no cleanup glossary.
public struct EmptyPersonalizationSource: PersonalizationSource {
    public init() {}

    public func vocabulary() -> [Term] {
        []
    }
}
