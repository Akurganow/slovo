import Foundation
import Testing

import LoquiCore
import LoquiTestSupport

// Epic 05 — AC-5 (composition builds ONE): the factory constructs EXACTLY ONE
// `Transcriber` for the configured backend — not a switchable multi-backend
// manager (§18.1/§18.2: ship ONE winner, no runtime switch).
//
// Contract under test (implementer builds the PRODUCT `TranscriberFactory` in
// `Sources/LoquiCore/ASR/TranscriberFactory.swift` per plan §5; CURRENTLY
// supplied by the WRONG-ON-PURPOSE `_RedScaffold_AsrBakeoff.swift` stub that
// constructs ALL THREE backends via the provider — so the single-construction
// count fails → RED).
@Suite("Epic 05 AC-5 transcriber factory builds one")
struct TranscriberFactoryTests {

    /// The factory must call the provider EXACTLY ONCE — for the requested
    /// backend only — and return that single `Transcriber`.
    /// Stated sensitivity: a switchable multi-backend manager constructs all
    /// backends (provider called 3×) → the single-construction count fails → RED.
    /// (The scaffold constructs all three → providerCallCount == 3 → RED now.)
    @Test
    func makesExactlyOneTranscriberForTheConfiguredBackend() {
        var providerCallCount = 0
        var requestedBackends: [AsrBackend] = []

        let provider: (AsrBackend) -> any Transcriber = { backend in
            providerCallCount += 1
            requestedBackends.append(backend)
            return FakeTranscriber(outcome: .success("ok"))
        }

        _ = TranscriberFactory.makeTranscriber(for: .speechTranscriber, provider: provider)

        #expect(providerCallCount == 1,
                "the factory must construct exactly ONE backend, provider was called \(providerCallCount)×")
        #expect(requestedBackends == [.speechTranscriber],
                "the factory must construct ONLY the configured backend, got \(requestedBackends)")
    }
}
