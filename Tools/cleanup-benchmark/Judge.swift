/// What the judge reports about itself: which models answered and what it cost.
public struct CleanupBenchmarkJudgeInfo: Equatable, Sendable {
    public var jevModelIDs: [String]
    public var embeddingModelIDs: [String]
    public var costUSD: Double

    public init(jevModelIDs: [String] = [], embeddingModelIDs: [String] = [], costUSD: Double = 0) {
        self.jevModelIDs = jevModelIDs
        self.embeddingModelIDs = embeddingModelIDs
        self.costUSD = costUSD
    }
}

/// Scores each output's meaning against its sample's reference: cosine similarity
/// of the embeddings, and the lowest of the Jev questions' means over the repeats.
public struct CleanupBenchmarkJudge: Sendable {
    private static let embeddingBatchSize = 64
    private static let concurrency = 4

    private let client: CleanupBenchmarkJudgeClient
    private let settings: CleanupBenchmarkJudgeSettings

    public init(client: CleanupBenchmarkJudgeClient, settings: CleanupBenchmarkJudgeSettings) {
        self.client = client
        self.settings = settings
    }

    public func score(
        _ runs: [CleanupBenchmarkRun],
        samples: [CleanupBenchmarkSample]
    ) async -> (runs: [CleanupBenchmarkRun], info: CleanupBenchmarkJudgeInfo) {
        var info = CleanupBenchmarkJudgeInfo()
        let bySample = Dictionary(samples.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scorable = runs.indices.filter { runs[$0].output != nil && bySample[runs[$0].sampleId] != nil }

        var texts = Set<String>()
        for index in scorable {
            texts.insert(runs[index].output ?? "")
            texts.insert(bySample[runs[index].sampleId]?.reference ?? "")
        }
        let vectors = await embed(texts.sorted(), info: &info)

        let decisions = await decide(runs, scorable: scorable, bySample: bySample)

        var scored = runs
        var jevModels = Set<String>()
        for index in scorable {
            guard let output = runs[index].output, let reference = bySample[runs[index].sampleId]?.reference else { continue }
            var scores = runs[index].scores
            if let left = vectors[output], let right = vectors[reference] {
                scores.embedding = Self.cosine(left, right)
            } else {
                scores.judgeErrors.append("embedding-failed")
            }
            let outcome = decisions[index] ?? DecisionOutcome()
            jevModels.formUnion(outcome.models)
            info.costUSD += outcome.cost
            scores.jevQuestions = outcome.values
            scores.judgeErrors += outcome.errors
            scores.jev = outcome.errors.isEmpty ? Self.jevCoefficient(outcome.values, questions: settings.jev.questions.keys) : nil
            scored[index].scores = scores
            if !scores.judgeErrors.isEmpty {
                scored[index].failures.append("judge-error")
            }
        }
        info.jevModelIDs = jevModels.sorted()
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

    /// The lowest of the questions' means over their repeats. Nil when a question has
    /// no answers.
    static func jevCoefficient(_ values: [String: [Double]], questions: Dictionary<String, CleanupBenchmarkJSON>.Keys) -> Double? {
        let means = questions.map { key -> Double? in
            guard let repeats = values[key], !repeats.isEmpty else { return nil }
            return repeats.reduce(0, +) / Double(repeats.count)
        }
        let present = means.compactMap(\.self)
        guard !means.isEmpty, present.count == means.count else { return nil }
        return present.min()
    }

    private func embed(_ texts: [String], info: inout CleanupBenchmarkJudgeInfo) async -> [String: [Double]] {
        var vectors: [String: [Double]] = [:]
        var models = Set<String>()
        var start = 0
        while start < texts.count {
            let chunk = Array(texts[start..<min(start + Self.embeddingBatchSize, texts.count)])
            start += Self.embeddingBatchSize
            guard let batch = try? await client.embeddings(for: chunk) else { continue }
            for (text, vector) in zip(chunk, batch.vectors) {
                vectors[text] = vector
            }
            if let model = batch.model {
                models.insert(model)
            }
            info.costUSD += batch.cost ?? 0
        }
        info.embeddingModelIDs = models.sorted()
        return vectors
    }

    private struct DecisionOutcome: Sendable {
        var values: [String: [Double]] = [:]
        var errors: [String] = []
        var models: Set<String> = []
        var cost = 0.0
    }

    private func decide(
        _ runs: [CleanupBenchmarkRun],
        scorable: [Int],
        bySample: [String: CleanupBenchmarkSample]
    ) async -> [Int: DecisionOutcome] {
        var outcomes: [Int: DecisionOutcome] = [:]
        await withTaskGroup(of: (Int, DecisionOutcome).self) { group in
            var next = 0
            func launch() {
                guard next < scorable.count else { return }
                let index = scorable[next]
                next += 1
                let run = runs[index]
                guard let output = run.output, let sample = bySample[run.sampleId] else { return }
                group.addTask { (index, await decideRepeats(sample: sample, output: output)) }
            }
            for _ in 0..<Self.concurrency {
                launch()
            }
            while let (index, outcome) = await group.next() {
                outcomes[index] = outcome
                launch()
            }
        }
        return outcomes
    }

    private func decideRepeats(sample: CleanupBenchmarkSample, output: String) async -> DecisionOutcome {
        var outcome = DecisionOutcome()
        for _ in 0..<settings.jev.repeats {
            do {
                let decision = try await client.decide(dictation: sample.raw, reference: sample.reference, output: output)
                outcome.cost += decision.cost ?? 0
                if let model = decision.model {
                    outcome.models.insert(model)
                }
                for (key, answer) in decision.answers {
                    switch answer {
                    case .probability(let value): outcome.values[key, default: []].append(value)
                    case .refusal: outcome.errors.append("jev-refusal")
                    }
                }
            } catch {
                outcome.errors.append("jev-request-failed")
            }
        }
        outcome.errors = Array(Set(outcome.errors)).sorted()
        return outcome
    }
}
