import AVFoundation
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
    /// stops compiling → RED.
    @Test
    func valueTypesHaveExactSpecShapes() {
        let term = Term(term: "ExampleCorp", expansion: "corp", lang: .en, weight: 5)
        #expect(term.term == "ExampleCorp")
        #expect(term.expansion == "corp")
        #expect(term.weight == 5)
        // `expansion` is OPTIONAL — nil must be constructible.
        let noExpansion = Term(term: "slovo", expansion: nil, lang: .auto, weight: 1)
        #expect(noExpansion.expansion == nil)

        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AudioBuffer(samples: [0.0, 0.5, -0.5], format: format)
        #expect(buffer.samples.count == 3)
        #expect(buffer.format.sampleRate == 16_000)

        // CleanupConfig: writingStyle + language; both mutable (`var`).
        var config = CleanupConfig(writingStyle: .formal, language: .ru)
        config.writingStyle = .veryCasual
        #expect(config.language == .ru)

        // PersonalizationContext: vocabulary: [Term].
        let context = PersonalizationContext(vocabulary: [term])
        #expect(context.vocabulary.count == 1)
    }

    /// The Language convenience members carry their exact wire codes.
    /// `Language` is an open raw-value STRUCT — no exhaustive switch exists to
    /// pin member addition — so the pin is on the raw values stored configs
    /// persist. WritingStyle case coverage is pinned by the default-less
    /// `describe` switch below, exactly like the error enums; that switch pins
    /// CASE MEMBERSHIP (compile-time exhaustiveness) only — WritingStyle's raw
    /// values are not asserted here (`describe`'s literals are case names, not
    /// wire codes: `veryCasual`'s raw value is "very-casual").
    /// Stated sensitivity: change a member's wire code (e.g. `.ru` →
    /// "russian") → the raw-value pin → RED; add a WritingStyle case → the
    /// describe switch stops compiling → RED.
    @Test
    func enumCasesMatchSpec() {
        #expect([Language.auto, .ru, .en].map(\.rawValue) == ["auto", "ru", "en"])
        #expect(describe(WritingStyle.formal) == "formal")
        #expect(describe(WritingStyle.veryCasual) == "veryCasual")
    }

    /// Each error case (incl. associated values + labels) is constructible
    /// with the exact labels.
    /// Stated sensitivity: change a label (`assetMissing(locale:)` →
    /// `assetMissing(loc:)`) or drop a case → won't compile → RED.
    @Test
    func errorCasesHaveExactAssociatedValues() {
        let t: [TranscriptionError] = [
            .backendUnavailable,
            .assetMissing(locale: "en_US"),
            .audioFormatUnsupported,
            .engineFailure(underlying: CleanupError.offline),
        ]
        let c: [CleanupError] = [
            .offline,
            .missingKey,
            .rateLimited(retryAfter: 1.5),
            .rateLimited(retryAfter: nil),
            .apiError(status: 503),
            .refused,
        ]
        let i: [InjectionError] = [.accessibilityDenied, .secureInputActive, .pasteFailed]
        #expect(t.count == 4)
        #expect(c.count == 6)
        #expect(i.count == 3)
    }

    // MARK: - Exhaustive switch with NO `default` (compile-time)

    // These helpers switch over EVERY case with NO `default`. If a case is added
    // to (or removed from) the enum, the switch becomes non-exhaustive and the
    // BUILD FAILS ("switch must be exhaustive") — that is the RED. The test
    // author writes NO `default`; the reviewer confirms its absence.

    private func describe(_ e: TranscriptionError) -> String {
        switch e {
        case .backendUnavailable: return "backendUnavailable"
        case .assetMissing(let locale): return "assetMissing:\(locale)"
        case .audioFormatUnsupported: return "audioFormatUnsupported"
        case .engineFailure: return "engineFailure"
        }
    }

    private func describe(_ e: CleanupError) -> String {
        switch e {
        case .offline: return "offline"
        case .missingKey: return "missingKey"
        case .rateLimited(let retryAfter): return "rateLimited:\(String(describing: retryAfter))"
        case .apiError(let status): return "apiError:\(status)"
        case .refused: return "refused"
        }
    }

    private func describe(_ e: InjectionError) -> String {
        switch e {
        case .accessibilityDenied: return "accessibilityDenied"
        case .secureInputActive: return "secureInputActive"
        case .pasteFailed: return "pasteFailed"
        }
    }

    private func describe(_ style: WritingStyle) -> String {
        switch style {
        case .formal: return "formal"
        case .casual: return "casual"
        case .veryCasual: return "veryCasual"
        }
    }

    /// Exercises the exhaustive describers so they are not dead code; the real
    /// guarantee is the compile-time exhaustiveness above.
    @Test
    func exhaustiveSwitchesCoverEveryCase() {
        #expect(describe(TranscriptionError.backendUnavailable) == "backendUnavailable")
        #expect(describe(CleanupError.refused) == "refused")
        #expect(describe(InjectionError.pasteFailed) == "pasteFailed")
    }
}
