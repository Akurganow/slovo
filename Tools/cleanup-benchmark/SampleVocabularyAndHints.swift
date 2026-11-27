import SlovoCore

/// One vocabulary row a sample carries, as written in the dataset: an invented term and an
/// optional expansion.
public struct CleanupBenchmarkVocabularyEntry: Decodable, Equatable, Sendable {
    public let term: String
    public let expansion: String?

    public init(term: String, expansion: String? = nil) {
        self.term = term
        self.expansion = expansion
    }
}

/// The `hints` object of a sample: every member optional, at least one present.
struct CleanupBenchmarkHintsObject: Decodable {
    struct Spell: Decodable {
        let token: String
        let guesses: [String]?
    }

    struct Grammar: Decodable {
        let fragment: String
        let message: String
        let corrections: [String]?
    }

    let inputLocale: String?
    let spell: [Spell]?
    let grammar: [Grammar]?
}

extension CleanupBenchmarkSample {
    /// What the app's personalization source hands the prompt for a vocabulary a user added: a
    /// quick-added row carries the weight of `VocabularyQuickAdd` and the stored language `en`
    /// (the `VocabularyRecord` default), which `GRDBPersonalizationSource.language` maps to `.en`.
    var personalization: PersonalizationContext {
        PersonalizationContext(vocabulary: vocabulary.map {
            Term(term: $0.term, expansion: $0.expansion, lang: .en, weight: VocabularyQuickAdd.weight)
        })
    }
}
