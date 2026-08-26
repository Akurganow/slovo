import Foundation
import Testing
import SlovoCore

@Suite("FallbackCleaner failure observer (spec rev 3 §4 K8)")
struct FallbackCleanerObserverTests {
    private static var config: CleanupConfig { CleanupConfig(writingStyle: .formal, language: .auto) }
    private static var context: PersonalizationContext { PersonalizationContext(vocabulary: []) }

    /// Lock-guarded recorder, same idiom as StubScenario: the observer closure is
    /// invoked synchronously inside `clean(...)`, the test reads after awaiting it.
    private final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [CleanupError] = []
        func append(_ error: CleanupError) {
            lock.lock(); defer { lock.unlock() }
            _values.append(error)
        }
        var values: [CleanupError] {
            lock.lock(); defer { lock.unlock() }
            return _values
        }
    }

    private struct Failing: Cleaner {
        let error: CleanupError
        func clean(_ raw: String, config: CleanupConfig, context: PersonalizationContext) async throws -> String { throw error }
    }
    private struct Succeeding: Cleaner {
        func clean(_ raw: String, config: CleanupConfig, context: PersonalizationContext) async throws -> String { raw }
    }

    @Test func observerReceivesTheCleanupErrorOnFailure() async throws {
        let box = ErrorBox()
        let cleaner = FallbackCleaner(
            chain: [Failing(error: .apiError(status: 404)), PassThrough()],
            statusReporter: { _ in },
            onCleanupFailure: { box.append($0) }
        )
        _ = try await cleaner.clean("raw", config: Self.config, context: Self.context)
        let seen = box.values
        #expect(seen.count == 1)
        if case .apiError(let status) = seen.first {
            #expect(status == 404)
        } else {
            Issue.record("observer received the wrong error case")
        }
    }

    @Test func observerSilentOnSuccess() async throws {
        let box = ErrorBox()
        let cleaner = FallbackCleaner(
            chain: [Succeeding(), PassThrough()],
            statusReporter: { _ in },
            onCleanupFailure: { box.append($0) }
        )
        _ = try await cleaner.clean("raw", config: Self.config, context: Self.context)
        #expect(box.values.isEmpty)
    }

    // K8 chain, link (a): the factory THREADS the observer into the FallbackCleaner
    // it assembles. `assemble` is private and `CompositionSummary` cannot carry a
    // closure, so this is a source pin — the v5-verification's G1: drop the
    // threading and every behavioral test stays green while the K4d self-heal
    // ships dead. Sensitivity: remove the argument from PipelineFactory → RED.
    @Test func factoryThreadsTheObserverIntoTheFallback() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let factory = try String(
            contentsOf: root.appendingPathComponent("Sources/SlovoCore/Composition/PipelineFactory.swift"),
            encoding: .utf8
        )
        #expect(factory.contains("onCleanupFailure: dependencies.onCleanupFailure"))
    }
}
