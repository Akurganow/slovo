import Foundation
import Synchronization
import Testing

@testable import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark judge")
struct CleanupBenchmarkJudgeTests {
    /// Sample `russian-filler-check-01` of `Benchmarks/cleanup/slovo-cleanup-v1.json`; the
    /// outputs the tests score against it are stand-ins.
    private static let sample = CleanupBenchmarkSample(
        id: "s", category: .russianFiller, raw: "Ну я сейчас проверяю, как работает диктовка.", reference: "Я сейчас проверяю, как работает диктовка."
    )

    private static func run(output: String?, fuzzy: Double? = 1) -> CleanupBenchmarkRun {
        CleanupBenchmarkRun(
            sampleId: sample.id,
            sampleCategory: sample.category,
            candidateName: "fake:m",
            durationNanoseconds: 1,
            output: output,
            scores: CleanupBenchmarkScores(fuzzy: fuzzy),
            errorKind: nil
        )
    }

    private static func judge(_ transport: FakeJudgeTransport, _ settings: CleanupBenchmarkJudgeSettings) -> CleanupBenchmarkJudge {
        CleanupBenchmarkJudge(transport: transport, settings: settings)
    }

    /// Stated sensitivity: dropping one of the three state fields, changing a question
    /// away from the data file, or asking each repeat fewer times than the file says
    /// changes the wire shape and goes RED.
    @Test
    func decisionRequestCarriesTheFileQuestionsAndThreeStateFields() async throws {
        let settings = try judgeSettings()
        let transport = FakeJudgeTransport()

        _ = await Self.judge(transport, settings).score([Self.run(output: "Hello there.")], samples: [Self.sample])

        let decisions = transport.recorded().filter { $0.path == "/api/alpha/decisions" }
        #expect(decisions.count == settings.jev.repeats)
        struct Body: Decodable {
            let model: String
            let state: [String: String]
            let questions: [String: CleanupBenchmarkJudgeSettings.Question]
        }
        for decision in decisions {
            let body = try JSONDecoder().decode(Body.self, from: decision.body)
            #expect(body.model == settings.jev.model)
            #expect(body.state == [
                "dictation": "Ну я сейчас проверяю, как работает диктовка.",
                "reference_cleanup": "Я сейчас проверяю, как работает диктовка.",
                "cleaned_text": "Hello there.",
            ])
            #expect(body.questions == settings.jev.questions)
        }
    }

    /// Stated sensitivity: the coefficient is the lowest of the five questions' means.
    /// A mean of the five (0.62 here) or the mean of the first repeat would turn it red.
    @Test
    func jevCoefficientIsTheLowestQuestionMean() {
        let values: [String: [Double]] = [
            "a": [0.9, 0.9, 0.9],
            "b": [0.8, 0.6, 0.7],
            "c": [0.95, 0.95, 0.95],
            "d": [0.9, 1.0, 0.8],
            "e": [0.1, 0.3, 0.2],
        ]
        let coefficient = CleanupBenchmarkJudge.jevCoefficient(values)

        #expect(abs((coefficient ?? -1) - 0.2) < 1e-9)
    }

    /// Stated sensitivity: a refusal turned into a score (0, or skipped as if the
    /// question were not asked) would rate an output the judge declined to judge.
    @Test
    func refusalIsAJudgeErrorNotAScore() async throws {
        let settings = try judgeSettings()
        let transport = FakeJudgeTransport(refusing: "plain_text")

        let result = await Self.judge(transport, settings).score([Self.run(output: "Hello there.")], samples: [Self.sample])

        let scores = try #require(result.runs.first).scores
        #expect(scores.jev == nil)
        #expect(scores.fuzzy == 1)
        #expect(scores.embedding == 1)
        #expect(result.runs.first?.failures == ["jev-refusal"])
    }

    /// Stated sensitivity: a prefix on one side only, or a cosine that is not the
    /// normalised dot product, changes the request input or the score.
    @Test
    func embeddingsCarryThePrefixOnBothTextsAndScoreByCosine() async throws {
        let settings = try judgeSettings()
        let transport = FakeJudgeTransport()

        let result = await Self.judge(transport, settings).score([Self.run(output: "WRONG text.")], samples: [Self.sample])

        let embeddings = transport.recorded().filter { $0.path == "/api/v1/embeddings" }
        #expect(embeddings.count == 1)
        struct Body: Decodable {
            let model: String
            let input: [String]
            let provider: CleanupBenchmarkJudgeSettings.Provider
        }
        let body = try JSONDecoder().decode(Body.self, from: try #require(embeddings.first).body)
        #expect(Set(body.input) == [settings.embedding.prefix + "WRONG text.", settings.embedding.prefix + Self.sample.reference])
        #expect(body.model == settings.embedding.model)
        #expect(body.provider == settings.embedding.provider)
        // The fake embeds a WRONG text at [0, 1] and the reference at [1, 0].
        #expect(result.runs.first?.scores.embedding == 0)
        #expect(abs(CleanupBenchmarkJudge.cosine([1, 0], [1, 1]) - 0.5.squareRoot()) < 1e-12)
    }

    /// Stated sensitivity: scoring a run that has no output (a provider error) would
    /// send nothing to judge and invent coefficients.
    @Test
    func runWithoutOutputIsNotJudged() async throws {
        let settings = try judgeSettings()
        let transport = FakeJudgeTransport()

        let result = await Self.judge(transport, settings).score([Self.run(output: nil, fuzzy: nil)], samples: [Self.sample])

        #expect(transport.recorded().isEmpty)
        #expect(result.runs.first?.scores == CleanupBenchmarkScores())
    }

    /// Stated sensitivity: a judge that scores in one batch and records at the end
    /// loses every score when a process dies; `record` must see each run as it is
    /// scored, with its failures and the models that answered. A rerun of a run that
    /// failed earlier must drop the old judge failure code.
    @Test
    func recordSeesEachScoredRunAndRejudgingDropsOldJudgeFailures() async throws {
        let settings = try judgeSettings()
        let recorded = Mutex<[CleanupBenchmarkRun]>([])
        var earlier = Self.run(output: "Hello there.")
        earlier.failures = ["jev-request-failed", "embedding-failed"]

        let result = await Self.judge(FakeJudgeTransport(), settings).score([earlier], samples: [Self.sample]) { run in
            recorded.withLock { $0.append(run) }
        }

        let run = try #require(result.runs.first)
        #expect(run.failures.isEmpty)
        #expect(run.isComplete(judged: true))
        #expect(run.scores.models == ["fake/embedding-snapshot", "fake/jev-snapshot"])
        #expect(recorded.withLock { $0 } == [run])
    }

    /// Stated sensitivity: an embeddings batch that fails without a trace leaves every
    /// run with `embedding-failed` and no cause; the cause must reach the info.
    @Test
    func failedEmbeddingsBatchIsNamedInTheInfo() async throws {
        let settings = try judgeSettings()
        let transport = FakeJudgeTransport()
        transport.setDown(true)

        let result = await Self.judge(transport, settings).score([Self.run(output: "Hello there.")], samples: [Self.sample])

        #expect(result.info.embeddingErrors == ["HTTP status 500"])
        #expect(Set(result.runs.first?.failures ?? []) == ["embedding-failed", "jev-request-failed"])
    }
}
