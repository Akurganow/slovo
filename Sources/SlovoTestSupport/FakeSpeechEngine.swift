import Foundation
import SlovoCore
import Synchronization

/// A scriptable spy standing in for model lifecycle and live speech sessions.
///
/// It records an ordered event timeline and the samples finalized by each live
/// session. State is `Mutex`-guarded so the spy is genuinely race-free when
/// driven through the transcriber actor and still inspectable afterward.
public final class FakeSpeechEngine: ModelLoading, SpeechStreamingSessionCreating, Sendable {
    /// What live-session finalization should return.
    public enum FinalizeOutcome: Sendable {
        case success(String)
        case failure
    }

    /// One recorded interaction, in invocation order.
    public enum Event: Sendable, Equatable {
        case load
        case release
        case finalize(sampleCount: Int)
    }

    /// A recorded live-session finalization's arguments.
    public struct FinalizeCall: Sendable, Equatable {
        public let sampleCount: Int
    }

    /// Thrown by load/finalization when scripted to fail.
    public struct ScriptedFailure: Error {
        public init() {}
    }

    private struct State {
        var events: [Event] = []
        var loaded = false
        var loadGateArmed = false
        var loadWaiters: [CheckedContinuation<Void, Never>] = []
        var loadSuspendedSignals: [CheckedContinuation<Void, Never>] = []
        var streamSamples: [Float] = []
        var streamAppendCalls: [Int] = []
        var streamStartCount = 0
        var streamFinishCount = 0
        var streamCancelCount = 0
    }

    private let state = Mutex(State())
    private let finalizeOutcome: FinalizeOutcome
    private let loadSucceeds: Bool
    private let loadFailuresBeforeSuccess: Int

    /// - Parameters:
    ///   - finalize: the scripted live-session result.
    ///   - loadSucceeds: `false` makes every `load()` throw `ScriptedFailure`.
    ///   - loadFailuresBeforeSuccess: the first N `load()` attempts throw, then
    ///     later attempts succeed (models a transient load failure that a retry
    ///     recovers from). Ignored when `loadSucceeds` is false.
    @preconcurrency
    public init(
        finalize: FinalizeOutcome = .success(""),
        loadSucceeds: Bool = true,
        loadFailuresBeforeSuccess: Int = 0
    ) {
        self.finalizeOutcome = finalize
        self.loadSucceeds = loadSucceeds
        self.loadFailuresBeforeSuccess = loadFailuresBeforeSuccess
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

    /// Every live-session finalization's arguments, in order.
    public var finalizeCalls: [FinalizeCall] {
        events.compactMap { event in
            if case let .finalize(sampleCount) = event {
                FinalizeCall(sampleCount: sampleCount)
            } else {
                nil
            }
        }
    }

    public var streamAppendCalls: [Int] {
        state.withLock { $0.streamAppendCalls }
    }

    public var streamStartCount: Int {
        state.withLock { $0.streamStartCount }
    }

    public var streamFinishCount: Int {
        state.withLock { $0.streamFinishCount }
    }

    public var streamCancelCount: Int {
        state.withLock { $0.streamCancelCount }
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

    private func finalize(samples: [Float]) async throws -> String {
        let outcome = state.withLock { current -> FinalizeOutcome in
            current.events.append(.finalize(sampleCount: samples.count))
            return finalizeOutcome
        }
        switch outcome {
        case .success(let transcript):
            return transcript
        case .failure:
            throw ScriptedFailure()
        }
    }

    public func makeSpeechStreamingSession() throws -> any SpeechStreamingSession {
        FakeSpeechStreamingSession(engine: self)
    }

    fileprivate func startStream() {
        state.withLock {
            $0.streamSamples = []
            $0.streamStartCount += 1
        }
    }

    fileprivate func appendToStream(_ samples: [Float]) {
        state.withLock {
            $0.streamSamples.append(contentsOf: samples)
            $0.streamAppendCalls.append(samples.count)
        }
    }

    fileprivate func finishStream() async throws -> String {
        let samples = state.withLock { current -> [Float] in
            current.streamFinishCount += 1
            return current.streamSamples
        }
        guard !samples.isEmpty else { return "" }
        return try await finalize(samples: samples)
    }

    fileprivate func cancelStream() {
        state.withLock {
            $0.streamCancelCount += 1
            $0.streamSamples = []
        }
    }
}

private actor FakeSpeechStreamingSession: SpeechStreamingSession {
    private let engine: FakeSpeechEngine

    init(engine: FakeSpeechEngine) {
        self.engine = engine
    }

    func start() {
        engine.startStream()
    }

    func append(_ samples: [Float]) {
        engine.appendToStream(samples)
    }

    func finish() async throws -> String {
        try await engine.finishStream()
    }

    func cancel() {
        engine.cancelStream()
    }
}
