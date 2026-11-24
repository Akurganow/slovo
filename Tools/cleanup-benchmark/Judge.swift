/// What a judging pass reports about itself.
public struct CleanupBenchmarkJudgeInfo: Equatable, Sendable {
    public var costUSD = 0.0
    /// One cause for each embeddings batch that failed.
    public var embeddingErrors: [String] = []

    public init() {}
}

/// Scores each output's meaning against its sample's references: the best cosine
/// similarity of the embeddings over them, and the lowest of the Jev questions' means
/// over the repeats, asked against the expected (first) reference.
public struct CleanupBenchmarkJudge: Sendable {
    private static let embeddingBatchSize = 64
    private static let concurrency = 4
    private static let ownFailures: Set = ["embedding-failed", "jev-refusal", "jev-request-failed"]

    public let settings: CleanupBenchmarkJudgeSettings
    private let client: CleanupBenchmarkJudgeClient

    public init(transport: any CleanupBenchmarkTransport, settings: CleanupBenchmarkJudgeSettings) {
        self.settings = settings
        client = CleanupBenchmarkJudgeClient(transport: transport, settings: settings)
    }

    private struct Item: Sendable {
        let index: Int
        let output: String
        let sample: CleanupBenchmarkSample
    }

    private struct Embedded {
        var vectors: [String: [Double]] = [:]
        var models: Set<String> = []
        var cost = 0.0
        var errors: [String] = []
    }

    private struct Decided: Sendable {
        var values: [String: [Double]] = [:]
        var failures: [String] = []
        var models: Set<String> = []
        var cost = 0.0
    }

    /// Scores `runs` and returns them in the same order. `record` is called with
    /// each run as soon as it is scored.
    @preconcurrency
    public func score(
        _ runs: [CleanupBenchmarkRun],
        samples: [CleanupBenchmarkSample],
        record: @Sendable (CleanupBenchmarkRun) -> Void = { _ in }
    ) async -> (runs: [CleanupBenchmarkRun], info: CleanupBenchmarkJudgeInfo) {
        var info = CleanupBenchmarkJudgeInfo()
        var scored = runs
        let bySample = Dictionary(samples.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Per candidate, so the embedding models a run names are those that served this candidate's batches.
        for indices in Dictionary(grouping: runs.indices, by: { runs[$0].candidateName }).values {
            let items = indices.compactMap { index -> Item? in
                guard let output = runs[index].output, let sample = bySample[runs[index].sampleId] else { return nil }
                return Item(index: index, output: output, sample: sample)
            }
            let embedded = await embed(Set(items.flatMap { [$0.output] + $0.sample.references }).sorted())
            info.costUSD += embedded.cost
            info.embeddingErrors += embedded.errors
            await decide(items) { item, decided in
                info.costUSD += decided.cost
                var run = runs[item.index]
                run.failures.removeAll { Self.ownFailures.contains($0) }
                run.failures += decided.failures
                var scores = run.scores
                let rights = item.sample.references.compactMap { embedded.vectors[$0] }
                if let left = embedded.vectors[item.output], rights.count == item.sample.references.count {
                    scores.embedding = rights.map { Self.cosine(left, $0) }.max()
                } else {
                    scores.embedding = nil
                    run.failures.append("embedding-failed")
                }
                scores.jevQuestions = decided.values
                scores.jev = decided.failures.isEmpty ? Self.jevCoefficient(decided.values) : nil
                scores.models = embedded.models.union(decided.models).sorted()
                run.scores = scores
                scored[item.index] = run
                record(run)
            }
        }
        return (scored, info)
    }

    /// Cosine similarity, clamped to 0...1.
    static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0
        var leftNorm = 0.0
        var rightNorm = 0.0
        for (left, right) in zip(lhs, rhs) {
            dot += left * right
            leftNorm += left * left
            rightNorm += right * right
        }
        guard leftNorm > 0, rightNorm > 0 else { return 0 }
        return min(1, max(0, dot / (leftNorm.squareRoot() * rightNorm.squareRoot())))
    }

    /// The lowest of the questions' means over their repeats.
    static func jevCoefficient(_ values: [String: [Double]]) -> Double? {
        values.values.map { $0.reduce(0, +) / Double($0.count) }.min()
    }

    private func embed(_ texts: [String]) async -> Embedded {
        var embedded = Embedded()
        for start in stride(from: 0, to: texts.count, by: Self.embeddingBatchSize) {
            let chunk = Array(texts[start..<min(start + Self.embeddingBatchSize, texts.count)])
            do {
                let batch = try await client.embeddings(for: chunk)
                for (text, vector) in zip(chunk, batch.vectors) {
                    embedded.vectors[text] = vector
                }
                if let model = batch.model {
                    embedded.models.insert(model)
                }
                embedded.cost += batch.cost ?? 0
            } catch {
                embedded.errors.append("\(error)")
            }
        }
        return embedded
    }

    /// Asks the Jev questions for every item, a few at a time, and hands each
    /// item's answers to `finish` as soon as they are in.
    private func decide(_ items: [Item], finish: (Item, Decided) -> Void) async {
        await withTaskGroup(of: (Item, Decided).self) { group in
            var pending = items[...]
            func launch() {
                guard let item = pending.popFirst() else { return }
                group.addTask { (item, await decideRepeats(item)) }
            }
            for _ in 0..<Self.concurrency {
                launch()
            }
            while let (item, decided) = await group.next() {
                finish(item, decided)
                launch()
            }
        }
    }

    private func decideRepeats(_ item: Item) async -> Decided {
        var decided = Decided()
        for _ in 0..<settings.jev.repeats {
            do {
                let decision = try await client.decide(
                    dictation: item.sample.raw, reference: item.sample.expected, output: item.output
                )
                decided.cost += decision.cost ?? 0
                if let model = decision.model {
                    decided.models.insert(model)
                }
                for (key, answer) in decision.answers {
                    switch answer {
                    case .probability(let value): decided.values[key, default: []].append(value)
                    case .refusal: decided.failures.append("jev-refusal")
                    }
                }
            } catch {
                decided.failures.append("jev-request-failed")
            }
        }
        decided.failures = Set(decided.failures).sorted()
        return decided
    }
}
