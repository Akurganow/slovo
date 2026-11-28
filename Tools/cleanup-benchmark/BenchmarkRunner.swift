import Foundation
import SlovoCore

/// The three coefficients of one output against its sample's references (the best of them), each in
/// 0...1 where 1 is identical. `embedding` and `jev` stay nil until the judge ran.
public struct CleanupBenchmarkScores: Equatable, Sendable {
    public var fuzzy: Double?
    public var embedding: Double?
    /// The lowest of the questions' means over the repeats.
    public var jev: Double?
    /// Every repeat's answer, by question key.
    public var jevQuestions: [String: [Double]]
    /// The response models that scored this output: the dated Jev snapshots and the
    /// embedding models, sorted.
    public var models: [String]

    public init(
        fuzzy: Double? = nil,
        embedding: Double? = nil,
        jev: Double? = nil,
        jevQuestions: [String: [Double]] = [:],
        models: [String] = []
    ) {
        self.fuzzy = fuzzy
        self.embedding = embedding
        self.jev = jev
        self.jevQuestions = jevQuestions
        self.models = models
    }
}

public struct CleanupBenchmarkRun: Equatable, Sendable {
    public let sampleId: String
    public let sampleCategory: CleanupBenchmarkCategory
    /// The sample's `language`; it makes a row of the bar only in the two language categories.
    public let sampleLanguage: String?
    /// 1-based position of the sample in the dataset.
    public let sampleIndex: Int
    public let candidateName: String
    /// 1-based.
    public let repetition: Int
    public let durationNanoseconds: UInt64
    /// Nil when the provider failed.
    public let output: String?
    public var scores: CleanupBenchmarkScores
    /// Coarse failure codes: `provider-error`, `empty-output`, and the judge's
    /// `embedding-failed`, `jev-refusal`, `jev-request-failed`.
    public var failures: [String]
    /// What the provider charged for the cleanup call; nil after a provider error or when it named no cost.
    public let costUSD: Double?
    public let errorKind: CleanupBenchmarkErrorKind?

    public init(
        sampleId: String,
        sampleCategory: CleanupBenchmarkCategory = .uncategorized,
        sampleLanguage: String? = nil,
        sampleIndex: Int = 1,
        candidateName: String,
        repetition: Int = 1,
        durationNanoseconds: UInt64,
        output: String? = nil,
        scores: CleanupBenchmarkScores = CleanupBenchmarkScores(),
        failures: [String] = [],
        costUSD: Double? = nil,
        errorKind: CleanupBenchmarkErrorKind?
    ) {
        self.sampleId = sampleId
        self.sampleCategory = sampleCategory
        self.sampleLanguage = sampleLanguage
        self.sampleIndex = sampleIndex
        self.candidateName = candidateName
        self.repetition = repetition
        self.durationNanoseconds = durationNanoseconds
        self.output = output
        self.scores = scores
        self.failures = failures
        self.costUSD = costUSD
        self.errorKind = errorKind
    }
}

/// Identifies one run across processes: the outputs file is keyed by it.
public struct CleanupBenchmarkRunKey: Hashable, Sendable {
    public let candidateName: String
    public let sampleId: String
    public let repetition: Int
}

public extension CleanupBenchmarkRun {
    var key: CleanupBenchmarkRunKey {
        CleanupBenchmarkRunKey(candidateName: candidateName, sampleId: sampleId, repetition: repetition)
    }

    static let emptyOutputCode = "empty-output"

    /// The candidate answered with nothing. That is its own failure: neither a repeat of
    /// the judge nor a resume changes it.
    var hasEmptyOutput: Bool {
        failures.contains(Self.emptyOutputCode)
    }

    /// The run as a fuzzy-only report sees it: no embedding, Jev score or judge failure code.
    func withoutJudgeResults() -> CleanupBenchmarkRun {
        var run = self
        run.scores = CleanupBenchmarkScores(fuzzy: scores.fuzzy)
        run.failures.removeAll { CleanupBenchmarkJudge.ownFailures.contains($0) }
        return run
    }

    /// A run that needs no more work: it has an output, no failure and every
    /// coefficient the benchmark was asked for.
    func isComplete(judged: Bool) -> Bool {
        output != nil && failures.isEmpty && scores.fuzzy != nil
            && (!judged || (scores.embedding != nil && scores.jev != nil))
    }
}

public enum CleanupBenchmarkErrorKind: String, Equatable, Sendable {
    case providerError = "provider-error"
}

/// A cleanup call's run, with what rate limits did to it.
private struct FinishedCall: Sendable {
    let run: CleanupBenchmarkRun
    /// Attempts repeated after a rate limit.
    let retried: Int
    /// The run is a provider error because its rate-limit attempts ran out.
    let gaveUp: Bool
}

/// The cleanup calls this process made, how many of them ended in a failure code, how many
/// attempts were repeated after a rate limit and how many calls gave up on one.
private struct CleanupTally {
    var calls = 0
    var failed = 0
    var rateLimits = CleanupBenchmarkRateLimits()

    mutating func add(_ finished: FinishedCall) {
        calls += 1
        if !finished.run.failures.isEmpty { failed += 1 }
        rateLimits.retried += finished.retried
        if finished.gaveUp { rateLimits.gaveUp += 1 }
    }
}

/// Where a run sits in the matrix: both counted from 1.
private struct RunPosition {
    let sampleIndex: Int
    let repetition: Int
}

/// One cleanup call still to make: its slot in the matrix and the lane that carries it.
private struct WorkItem: Sendable {
    let slot: Int
    let lane: Int
    let candidate: CleanupBenchmarkCandidate
    let sample: CleanupBenchmarkSample
    let position: RunPosition
    let config: CleanupConfig
}

/// The calls of one lane in matrix order, and how many may be in flight at once.
private struct Lane {
    var pending: ArraySlice<WorkItem> = []
    var width: Int
}

/// The matrix split into the runs kept from `previous`, which fill their slots, and the calls to
/// make, grouped into lanes. Slots count repetition, then sample, then candidate.
private struct Plan {
    var slots: [CleanupBenchmarkRun?]
    var lanes: [Lane] = []
    let repetitions: Int
    var keptByCandidate: [String: Int] = [:]
    var toMakeByCandidate: [String: Int] = [:]
    var toMakeInRepetition: [Int: Int] = [:]

    init(
        candidates: [CleanupBenchmarkCandidate],
        samples: [CleanupBenchmarkSample],
        repetitions: Int,
        style: WritingStyle,
        previous: [CleanupBenchmarkRunKey: CleanupBenchmarkRun]
    ) {
        self.repetitions = repetitions
        slots = Array(repeating: nil, count: repetitions * samples.count * candidates.count)
        var laneIndex: [String: Int] = [:]
        let laneOfCandidate = candidates.map { candidate -> Int in
            if let lane = laneIndex[candidate.lane] {
                lanes[lane].width = min(lanes[lane].width, candidate.width)
                return lane
            }
            laneIndex[candidate.lane] = lanes.count
            lanes.append(Lane(width: candidate.width))
            return lanes.count - 1
        }
        for repetition in 1...repetitions {
            for (sampleIndex, sample) in samples.enumerated() {
                for (candidateIndex, candidate) in candidates.enumerated() {
                    let slot = ((repetition - 1) * samples.count + sampleIndex) * candidates.count + candidateIndex
                    let key = CleanupBenchmarkRunKey(candidateName: candidate.name, sampleId: sample.id, repetition: repetition)
                    if let earlier = previous[key], earlier.output != nil {
                        slots[slot] = earlier
                        keptByCandidate[candidate.name, default: 0] += 1
                        continue
                    }
                    let lane = laneOfCandidate[candidateIndex]
                    lanes[lane].pending.append(WorkItem(
                        slot: slot,
                        lane: lane,
                        candidate: candidate,
                        sample: sample,
                        position: RunPosition(sampleIndex: sampleIndex + 1, repetition: repetition),
                        config: sample.cleanupConfig(model: candidate.model, style: style)
                    ))
                    toMakeByCandidate[candidate.name, default: 0] += 1
                    toMakeInRepetition[repetition, default: 0] += 1
                }
            }
        }
    }
}

/// Decides when a candidate has started or finished and when a repetition has finished, against the
/// calls the plan makes in this process (the matrix less the runs kept from the outputs file).
private struct FinishTracker {
    let repetitions: Int
    let toMakeByCandidate: [String: Int]
    let toMakeInRepetition: [Int: Int]
    private(set) var total = CleanupTally()
    private var started = Set<String>()
    private var byCandidate: [String: CleanupTally] = [:]
    private var byRepetition: [Int: CleanupTally] = [:]

    init(_ plan: Plan) {
        repetitions = plan.repetitions
        toMakeByCandidate = plan.toMakeByCandidate
        toMakeInRepetition = plan.toMakeInRepetition
    }

    /// Announces a candidate at its first call made here.
    mutating func start(_ item: WorkItem, progress: @Sendable (CleanupBenchmarkProgress) -> Void) {
        if started.insert(item.candidate.name).inserted {
            progress(.candidateStarted(candidate: item.candidate.name))
        }
    }

    mutating func finish(_ finished: FinishedCall, of item: WorkItem, progress: @Sendable (CleanupBenchmarkProgress) -> Void) {
        let name = item.candidate.name
        let repetition = item.position.repetition
        total.add(finished)
        byCandidate[name, default: CleanupTally()].add(finished)
        byRepetition[repetition, default: CleanupTally()].add(finished)
        if let tally = byCandidate[name], tally.calls == toMakeByCandidate[name] {
            progress(.candidateFinished(candidate: name, calls: tally.calls, failed: tally.failed, rateLimits: tally.rateLimits))
        }
        if let tally = byRepetition[repetition], tally.calls == toMakeInRepetition[repetition] {
            progress(.repetitionFinished(repetition: repetition, total: repetitions, calls: tally.calls, failed: tally.failed))
        }
    }
}

public struct CleanupBenchmarkRunner: Sendable {
    private let timer: CleanupBenchmarkTimer
    /// Waits the given seconds before a rate-limited call is made again.
    private let sleep: @Sendable (Double) async throws -> Void

    @preconcurrency
    public init(
        timer: CleanupBenchmarkTimer = .continuous,
        sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.timer = timer
        self.sleep = sleep
    }

    @preconcurrency
    public func run(
        candidates: [CleanupBenchmarkCandidate],
        samples: [CleanupBenchmarkSample],
        config: CleanupConfig,
        repetitions: Int = 1,
        warmupRepetitions: Int = 0,
        previous: [CleanupBenchmarkRunKey: CleanupBenchmarkRun] = [:],
        record: @Sendable (CleanupBenchmarkRun) -> Void = { _ in },
        progress: @Sendable (CleanupBenchmarkProgress) -> Void = { _ in }
    ) async -> CleanupBenchmarkReport {
        let safeRepetitions = max(repetitions, 1)
        for _ in 0..<max(warmupRepetitions, 0) {
            for sample in samples {
                for candidate in candidates {
                    await warmCandidate(
                        candidate,
                        sample: sample,
                        config: sample.cleanupConfig(model: candidate.model, style: config.writingStyle)
                    )
                }
            }
        }

        let plan = Plan(
            candidates: candidates, samples: samples, repetitions: safeRepetitions, style: config.writingStyle, previous: previous
        )
        let callsPerCandidate = samples.count * safeRepetitions
        progress(.cleanupStarted(
            candidates: candidates.count,
            samples: samples.count,
            repetitions: safeRepetitions,
            kept: plan.keptByCandidate.values.reduce(0, +)
        ))
        for candidate in candidates where plan.keptByCandidate[candidate.name] == callsPerCandidate {
            progress(.candidateKept(candidate: candidate.name, kept: callsPerCandidate))
        }

        let finished = await runLanes(plan, record: record, progress: progress)
        progress(.cleanupFinished(calls: finished.total.calls, failed: finished.total.failed, rateLimits: finished.total.rateLimits))

        return CleanupBenchmarkReport(runs: finished.slots.compactMap(\.self))
    }

    /// Runs the planned calls: every lane starts up to its width at once, and each finished call
    /// starts its lane's next. This loop alone records, tallies and reports, so a finished call is
    /// recorded at once and files its run into its slot.
    private func runLanes(
        _ planned: Plan,
        record: @Sendable (CleanupBenchmarkRun) -> Void,
        progress: @Sendable (CleanupBenchmarkProgress) -> Void
    ) async -> (slots: [CleanupBenchmarkRun?], total: CleanupTally) {
        var plan = planned
        var tracker = FinishTracker(planned)

        await withTaskGroup(of: (WorkItem, FinishedCall).self) { group in
            func launch(_ lane: Int) {
                guard let item = plan.lanes[lane].pending.popFirst() else { return }
                tracker.start(item, progress: progress)
                group.addTask {
                    (item, await runCandidate(item.candidate, sample: item.sample, position: item.position, config: item.config))
                }
            }
            for lane in plan.lanes.indices {
                for _ in 0..<plan.lanes[lane].width {
                    launch(lane)
                }
            }
            while let (item, finished) = await group.next() {
                record(finished.run)
                plan.slots[item.slot] = finished.run
                tracker.finish(finished, of: item, progress: progress)
                launch(item.lane)
            }
        }
        return (plan.slots, tracker.total)
    }

    private func warmCandidate(
        _ candidate: CleanupBenchmarkCandidate,
        sample: CleanupBenchmarkSample,
        config: CleanupConfig
    ) async {
        _ = try? await candidate.clean(sample.raw, config, sample.personalization, sample.hints)
    }

    /// Makes the call, and makes it again after a rate limit for as long as `CleanupBenchmarkRetryPolicy` allows.
    /// The wait stays inside the lane's slot. The duration is the last attempt's, never a wait.
    private func runCandidate(
        _ candidate: CleanupBenchmarkCandidate,
        sample: CleanupBenchmarkSample,
        position: RunPosition,
        config: CleanupConfig
    ) async -> FinishedCall {
        var retried = 0
        var gaveUp = false
        var answered: TimedCleanupOutput?
        while true {
            do {
                answered = try await timer.measure {
                    try await candidate.clean(sample.raw, config, sample.personalization, sample.hints)
                }
                break
            } catch {
                // Only a rate limit is repeated: the route turns every other status into a final error.
                guard case CleanupError.rateLimited(let retryAfter) = error else { break }
                let wait = CleanupBenchmarkRetryPolicy.delay(after: .status(429, retryAfter: retryAfter), attempt: retried)
                guard let wait else {
                    gaveUp = true
                    break
                }
                guard (try? await sleep(wait)) != nil else { break }
                retried += 1
            }
        }
        let isEmpty = answered.map { $0.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let run = CleanupBenchmarkRun(
            sampleId: sample.id,
            sampleCategory: sample.category,
            sampleLanguage: sample.language,
            sampleIndex: position.sampleIndex,
            candidateName: candidate.name,
            repetition: position.repetition,
            durationNanoseconds: answered?.durationNanoseconds ?? 0,
            output: answered?.output,
            scores: CleanupBenchmarkScores(fuzzy: answered.map { FuzzyScore.best($0.output, sample.references) }),
            failures: answered == nil ? ["provider-error"] : (isEmpty ? [CleanupBenchmarkRun.emptyOutputCode] : []),
            costUSD: answered?.costUSD,
            errorKind: answered == nil ? .providerError : nil
        )
        return FinishedCall(run: run, retried: retried, gaveUp: gaveUp)
    }
}
