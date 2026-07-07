import AVFoundation
import Foundation
import Testing

import SlovoCore

// Contracts exist with their exact shapes, and each error enum is exhaustively
// switchable with NO `default`.
//
// Contract under test (implementer builds VERBATIM in
// `Sources/SlovoCore/Contracts/`; the symbols are CURRENTLY supplied by the
// `_RedScaffold_Contracts.swift` stub so this target compiles — the implementer
// deletes the scaffold and these tests bind to the real `import SlovoCore`).
//
// These are COMPILE-TIME guarantees: the assertions below pin the exact
// public surface. They are GREEN against the correct scaffold; their RED is the
// MUTATION "rename/drop a member or change a label" or "add/remove an
// enum case" → the file no longer compiles. That mutation RED is
// demonstrated out-of-band (see the RED-evidence report) because a wrong shape
// breaks the whole target's compilation rather than a single test.
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

    /// Every Language / WritingStyle case exists.
    @Test
    func enumCasesMatchSpec() {
        let langs: [Language] = [.auto, .ru, .en]
        let styles: [WritingStyle] = [.formal, .casual, .veryCasual]
        #expect(langs.count == 3)
        #expect(styles.count == 3)
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

    /// Exercises the exhaustive describers so they are not dead code; the real
    /// guarantee is the compile-time exhaustiveness above.
    @Test
    func exhaustiveSwitchesCoverEveryCase() {
        #expect(describe(TranscriptionError.backendUnavailable) == "backendUnavailable")
        #expect(describe(CleanupError.refused) == "refused")
        #expect(describe(InjectionError.pasteFailed) == "pasteFailed")
    }
}
