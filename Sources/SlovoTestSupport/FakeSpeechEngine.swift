import Foundation
import SlovoCore
import Synchronization

/// A scriptable spy standing in for the on-device WhisperKit engine behind BOTH
/// ASR seams: `ModelLoading` (load / keep-warm / release) and the inference seam
/// `SpeechDecoding` (prompt-token encoding + decode). It subsumes the former
/// `FakeModel`.
///
/// It records an ordered event timeline so tests can assert call ORDER (load
/// before prompt encoding), the prompt tokens PLUMBED into `decode`, and the
/// accumulated sample count — without a real model. State is `Mutex`-guarded so
/// the spy is genuinely race-free when driven through the transcriber actor and
/// still inspectable from the test afterward.
public final class FakeSpeechEngine: ModelLoading, SpeechDecoding, Sendable {
    /// What `decode` should do when invoked.
    public enum DecodeOutcome: Sendable {
        case success(String)
        case failure
    }

    /// One recorded interaction, in invocation order.
    public enum Event: Sendable, Equatable {
        case load
        case release
        case encodePrompt(String)
        case decode(sampleCount: Int, promptTokens: [Int]?)
    }

    /// A recorded `decode` invocation's arguments.
    public struct DecodeCall: Sendable, Equatable {
        public let sampleCount: Int
        public let promptTokens: [Int]?
    }

    /// Thrown by `load`/`decode` when scripted to fail. It is deliberately NOT a
    /// `TranscriptionError`, so the production transcriber must MAP it (decode →
    /// `.engineFailure`; load → `.backendUnavailable`/`.engineFailure`, never
    /// `.assetMissing`) rather than let it escape unmapped.
    public struct ScriptedFailure: Error {
        public init() {}
    }

    private struct State {
        var events: [Event] = []
        var loaded = false
        var loadGateArmed = false
        var loadWaiters: [CheckedContinuation<Void, Never>] = []
        var loadSuspendedSignals: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    private let decodeOutcome: DecodeOutcome
    private let scriptedPromptTokens: [Int]
    private let loadSucceeds: Bool
    private let loadFailuresBeforeSuccess: Int
    private let tokenize: (@Sendable (String) -> [Int])?

    /// - Parameters:
    ///   - decode: the scripted `decode` outcome.
    ///   - promptTokens: what `encodePromptTokens` returns; empty models a
    ///     tokenizer-unavailable engine (no bias tokens).
    ///   - loadSucceeds: `false` makes every `load()` throw `ScriptedFailure`.
    ///   - loadFailuresBeforeSuccess: the first N `load()` attempts throw, then
    ///     later attempts succeed (models a transient load failure that a retry
    ///     recovers from). Ignored when `loadSucceeds` is false.
    ///   - tokenize: when set, `encodePromptTokens` returns `tokenize(prompt)`
    ///     instead of the fixed `promptTokens` array, modelling a content-
    ///     proportional tokenizer — needed to exercise prompt-token budgeting, where
    ///     a budgeted head must differ from the uncapped vocabulary.
    @preconcurrency
    public init(
        decode: DecodeOutcome = .success(""),
        promptTokens: [Int] = [],
        loadSucceeds: Bool = true,
        loadFailuresBeforeSuccess: Int = 0,
        tokenize: (@Sendable (String) -> [Int])? = nil
    ) {
        self.decodeOutcome = decode
        self.scriptedPromptTokens = promptTokens
        self.loadSucceeds = loadSucceeds
        self.loadFailuresBeforeSuccess = loadFailuresBeforeSuccess
        self.tokenize = tokenize
    }

    /// The recorded interaction timeline, in invocation order.
    public var events: [Event] {
        state.withLock { $0.events }
    }

    /// Number of `load()` attempts (successful or scripted-failure).
    public var loadCount: Int {
        events.filter { $0 == .load }.count
    }

    /// Number of `release()` calls.
    public var releaseCount: Int {
        events.filter { $0 == .release }.count
    }

    /// Every prompt string passed to `encodePromptTokens`, in order.
    public var encodedPrompts: [String] {
        events.compactMap { event in
            if case let .encodePrompt(prompt) = event { prompt } else { nil }
        }
    }

    /// Every `decode` invocation's arguments, in order.
    public var decodeCalls: [DecodeCall] {
        events.compactMap { event in
            if case let .decode(sampleCount, promptTokens) = event {
                DecodeCall(sampleCount: sampleCount, promptTokens: promptTokens)
            } else {
                nil
            }
        }
    }

    // MARK: - ModelLoading

    public var isLoaded: Bool {
        state.withLock { $0.loaded }
    }

    public func load() async throws {
        let (gated, attempt): (Bool, Int) = state.withLock { current in
            current.events.append(.load)
            let attempt = current.events.filter { $0 == .load }.count
            return (current.loadGateArmed, attempt)
        }
        if gated {
            // Park until releaseLoad(); `loaded` stays false while in flight so a
            // concurrent begin models the real "load not yet complete" race.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let signals: [CheckedContinuation<Void, Never>] = state.withLock { current in
                    current.loadWaiters.append(continuation)
                    let pending = current.loadSuspendedSignals
                    current.loadSuspendedSignals = []
                    return pending
                }
                signals.forEach { $0.resume() }
            }
        }
        if loadSucceeds && attempt > loadFailuresBeforeSuccess {
            state.withLock { $0.loaded = true }
        } else {
            throw ScriptedFailure()
        }
    }

    /// Arms gated-load mode: subsequent `load()` calls park until `releaseLoad()`.
    public func gateLoad() {
        state.withLock { $0.loadGateArmed = true }
    }

    /// Releases all parked `load()` calls and disarms the gate.
    public func releaseLoad() {
        let waiters: [CheckedContinuation<Void, Never>] = state.withLock { current in
            current.loadGateArmed = false
            let parked = current.loadWaiters
            current.loadWaiters = []
            return parked
        }
        waiters.forEach { $0.resume() }
    }

    /// Suspends until at least one `load()` has parked on the gate.
    public func waitForLoadSuspended() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow: Bool = state.withLock { current in
                if current.loadWaiters.isEmpty {
                    current.loadSuspendedSignals.append(continuation)
                    return false
                }
                return true
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    /// Waits until `target` loads have parked on the gate, or relents after a bounded
    /// yield budget (used to observe a buggy SECOND concurrent load without hanging
    /// when the correct single-flight path never issues one).
    public func waitForGatedLoadCountOrRelent(_ target: Int, maxYields: Int = 500) async {
        for _ in 0..<maxYields {
            if state.withLock({ $0.loadWaiters.count >= target }) {
                return
            }
            await Task.yield()
        }
    }

    /// Waits until `release()` has been called at least `target` times, or relents
    /// after a bounded yield budget (so a "must NOT release" assertion still gives a
    /// buggy release time to manifest before asserting zero).
    public func waitForReleaseCount(atLeast target: Int, maxYields: Int = 500) async {
        for _ in 0..<maxYields {
            if releaseCount >= target {
                return
            }
            await Task.yield()
        }
    }

    public func release() {
        state.withLock { current in
            current.events.append(.release)
            current.loaded = false
        }
    }

    // MARK: - SpeechDecoding

    public func encodePromptTokens(_ prompt: String) -> [Int] {
        state.withLock { $0.events.append(.encodePrompt(prompt)) }
        return tokenize?(prompt) ?? scriptedPromptTokens
    }

    public func decode(samples: [Float], promptTokens: [Int]?) async throws -> String {
        let outcome = state.withLock { current -> DecodeOutcome in
            current.events.append(.decode(sampleCount: samples.count, promptTokens: promptTokens))
            return decodeOutcome
        }
        switch outcome {
        case .success(let transcript):
            return transcript
        case .failure:
            throw ScriptedFailure()
        }
    }
}
