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

    /// The strings that stand for this sample's vocabulary and hints in a digest, none for a
    /// sample with neither. Each string carries a prefix naming its part, and the digest
    /// delimits strings by length, so no two different values give the same list.
    var vocabularyAndHintsDigestInput: [String] {
        var strings: [String] = []
        for entry in vocabulary {
            strings.append("vocabularyTerm=\(entry.term)")
            if let expansion = entry.expansion { strings.append("vocabularyExpansion=\(expansion)") }
        }
        if let locale = hints.inputLocale { strings.append("inputLocale=\(locale)") }
        for finding in hints.spellFindings {
            strings.append("spellToken=\(finding.token)")
            strings += finding.guesses.map { "spellGuess=\($0)" }
        }
        for finding in hints.grammarFindings {
            strings += ["grammarFragment=\(finding.fragment)", "grammarMessage=\(finding.message)"]
            strings += finding.corrections.map { "grammarCorrection=\($0)" }
        }
        return strings
    }
}
