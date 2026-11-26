import Foundation
import Testing

import SlovoCore

// Contracts exist with their exact shapes, and each error enum is exhaustively
// switchable with NO `default`.
//
// Contract under test lives in `Sources/SlovoCore/Contracts/`.
//
// These are COMPILE-TIME guarantees: the assertions below pin the exact public
// surface. Stated sensitivity: rename/drop a member, change an init label, or
// add/remove an enum case → this target no longer compiles → RED.
@Suite("Contracts")
struct ContractsTests {

    // MARK: - Exact value-type memberwise inits + property access

    /// Stated sensitivity: drop/rename a stored property or change an init label
    /// (e.g. `Term(term:expansion:lang:weight:)` → `Term(word:…)`) → this body
    /// stops compiling → RED; `Term.init` stores `.auto` for `lang` → RED.
    @Test
    func valueTypesHaveExactSpecShapes() {
        let term = Term(term: "ExampleCorp", expansion: "corp", lang: .en, weight: 5)
        #expect(term.term == "ExampleCorp")
        #expect(term.expansion == "corp")
        #expect(term.weight == 5)
        #expect(term.lang == .en)
        // `expansion` is OPTIONAL — nil must be constructible.
        let noExpansion = Term(term: "slovo", expansion: nil, lang: .auto, weight: 1)
        #expect(noExpansion.expansion == nil)
        #expect(noExpansion.lang == .auto)

        // CleanupConfig: `writingStyle` is assignable (`var`).
        var config = CleanupConfig(writingStyle: .formal)
        config.writingStyle = .veryCasual
        #expect(config.writingStyle == .veryCasual)

        // PersonalizationContext: vocabulary: [Term].
        let context = PersonalizationContext(vocabulary: [term])
        #expect(context.vocabulary.count == 1)
    }

    /// The Language convenience members carry their exact wire codes.
    /// `Language` is an open raw-value STRUCT — no exhaustive switch exists to
    /// pin member addition — so the pin is on the raw values stored configs
    /// persist. WritingStyle case membership is pinned by the default-less
    /// switch below, exactly like the error enums; WritingStyle's raw values
    /// are not asserted here (`veryCasual`'s raw value is "very-casual").
    /// Stated sensitivity: change a member's wire code (e.g. `.ru` →
    /// "russian") → the raw-value pin → RED; add or drop a WritingStyle case →
    /// the switch stops compiling → RED.
    @Test
    func enumCasesMatchSpec() {
        #expect([Language.auto, .ru, .en].map(\.rawValue) == ["auto", "ru", "en"])
        for style in [WritingStyle.formal, .casual, .veryCasual] {
            switch style {
            case .formal, .casual, .veryCasual: break
            }
        }
    }

    /// Each error case (incl. associated values + labels) is constructible
    /// with the exact labels, and each error enum is switched over EVERY case
    /// with NO `default`.
    /// Stated sensitivity: change a label (`rateLimited(retryAfter:)` →
    /// `rateLimited(after:)`), or add or drop a case → won't compile → RED.
    @Test
    func errorCasesHaveExactAssociatedValues() {
        let t: [TranscriptionError] = [
            .backendUnavailable,
            .audioFormatUnsupported,
            .engineFailure(underlying: CleanupError.transport),
        ]
        let c: [CleanupError] = [
            .missingKey,
            .timedOut,
            .offline,
            .tls,
            .transport,
            .badResponse,
            .rateLimited(retryAfter: 1.5),
            .rateLimited(retryAfter: nil),
            .modelUnavailable,
            .refused,
            .noText,
        ]
        let i: [InjectionError] = [.accessibilityDenied, .secureInputActive, .pasteFailed]
        for e in t {
            switch e {
            case .backendUnavailable, .audioFormatUnsupported, .engineFailure: break
            }
        }
        for e in c {
            switch e {
            case .missingKey, .timedOut, .offline, .tls, .transport, .badResponse,
                 .rateLimited, .modelUnavailable, .refused, .noText: break
            }
        }
        for e in i {
            switch e {
            case .accessibilityDenied, .secureInputActive, .pasteFailed: break
            }
        }
    }
}
