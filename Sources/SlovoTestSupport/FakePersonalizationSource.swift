import SlovoCore

/// A `PersonalizationSource` fake that returns its configured terms unchanged,
/// preserving order and values.
public final class FakePersonalizationSource: PersonalizationSource {
    private let terms: [Term]

    public init(terms: [Term]) {
        self.terms = terms
    }

    public func vocabulary() -> [Term] {
        terms
    }
}
