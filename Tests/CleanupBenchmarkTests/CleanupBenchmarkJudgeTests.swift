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
        id: "s", category: .russianFiller, raw: "Ну я сейчас проверяю, как работает диктовка.", references: ["Я сейчас проверяю, как работает диктовка."]
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

    /// Stated sensitivity: a translation sample judged by the plain questions scores a correct
    /// translation near 0 on `same_language`; it must be asked the translation set and told
    /// the target's display name, and a plain sample must keep the plain set and the three
    /// state fields, so sending `target_language` or the translation set for every sample, or
    /// for neither, goes RED. Both samples must also get a Jev score: a client that reads the
    /// answers for the plain question keys instead of the set it sent fails the translation
    /// sample with `jev-request-failed` and no score → RED.
    @Test
    func translationSampleIsAskedTheTranslationQuestionsWithItsTarget() async throws {
        let settings = try judgeSettings()
        struct Body: Decodable {
            let state: [String: String]
            let questions: [String: CleanupBenchmarkJudgeSettings.Question]
        }
        func asked(for sample: CleanupBenchmarkSample) async throws -> (sent: Body, scored: CleanupBenchmarkRun) {
            let transport = FakeJudgeTransport()
            let run = CleanupBenchmarkRun(
                sampleId: sample.id, sampleCategory: sample.category, candidateName: "fake:m", durationNanoseconds: 1,
                output: "Hallo.", scores: CleanupBenchmarkScores(fuzzy: 1), errorKind: nil
            )
            let result = await Self.judge(transport, settings).score([run], samples: [sample])
            let decision = transport.recorded().first { $0.path == settings.jev.path }
            let sent = try JSONDecoder().decode(Body.self, from: try #require(decision).body)
            return (sent, result.runs[0])
        }
        let translated = CleanupBenchmarkSample(
            id: "t", category: .translation, raw: "Привет.", references: ["Hallo."], language: "ru", translationTarget: .init(code: "de")
        )

        let (translation, scoredTranslation) = try await asked(for: translated)
        let (plain, scoredPlain) = try await asked(for: Self.sample)

        #expect(translation.questions == settings.jev.translationQuestions)
        #expect(translation.state["target_language"] == RecognitionLanguageCatalog.displayName(for: "de"))
        #expect(translation.state["dictation"] == "Привет.")
        #expect(plain.questions == settings.jev.questions)
        #expect(plain.state["target_language"] == nil)
        #expect(scoredTranslation.scores.jev != nil)
        #expect(scoredTranslation.failures.isEmpty)
        #expect(scoredPlain.scores.jev != nil)
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
        #expect(Set(body.input) == [settings.embedding.prefix + "WRONG text.", settings.embedding.prefix + Self.sample.expected])
        #expect(body.model == settings.embedding.model)
        #expect(body.provider == settings.embedding.provider)
        // The fake embeds a WRONG text at [0, 1] and the reference at [1, 0].
        #expect(result.runs.first?.scores.embedding == 0)
        #expect(abs(CleanupBenchmarkJudge.cosine([1, 0], [1, 1]) - 0.5.squareRoot()) < 1e-12)
    }

    /// Stated sensitivity: scoring only the first reference gives an output in the other
    /// script of a term the embedding of a different text (0 here); averaging the
    /// references' scores gives 0.5; asking Jev against another reference than the first
    /// changes the dictated reference in the decision state. The fake embeds a WRONG text at
    /// [0, 1], so the first reference is far from the output and the second is the output.
    @Test
    func embeddingTakesTheBestReferenceAndJevAsksTheFirst() async throws {
        let settings = try judgeSettings()
        let transport = FakeJudgeTransport()
        let sample = CleanupBenchmarkSample(
            id: "s", category: .commandsEditor, raw: "Сделай коммит и пуш в мейн.",
            references: ["WRONG text.", "Hello there."]
        )

        let result = await Self.judge(transport, settings).score([Self.run(output: "Hello there.")], samples: [sample])

        #expect(result.runs.first?.scores.embedding == 1)
        let decision = try #require(transport.recorded().first { $0.path == "/api/alpha/decisions" })
        let state = try #require((JSONSerialization.jsonObject(with: decision.body) as? [String: Any])?["state"] as? [String: String])
        #expect(state["reference_cleanup"] == "WRONG text.")
    }

    /// Stated sensitivity: a run that holds its embedding and lacks only its Jev score,
    /// embedded again, loses the embedding when the embeddings request fails (the line is
    /// then written without it); the embedding must be kept, not requested, and the run
    /// complete, and its models must keep the embedding model.
    @Test
    func runKeepsItsEmbeddingWhenOnlyJevIsMissing() async throws {
        let settings = try judgeSettings()
        let transport = FakeJudgeTransport(failingEmbeddings: true)
        var held = Self.run(output: "Hello there.")
        held.scores.embedding = 0.9
        held.scores.models = ["fake/embedding-snapshot"]

        let result = await Self.judge(transport, settings).score([held], samples: [Self.sample])

        let run = try #require(result.runs.first)
        #expect(run.scores.embedding == 0.9)
        #expect(run.failures.isEmpty)
        #expect(run.isComplete(judged: true))
        #expect(run.scores.models == ["fake/embedding-snapshot", "fake/jev-snapshot"])
        #expect(transport.requestCount(path: "/api/v1/embeddings") == 0)
        #expect(result.info.embeddingErrors.isEmpty)
    }

    /// Stated sensitivity: a response whose indices are not the permutation of the texts
    /// (here two items indexed 0) read by the count alone gives the second text the vector
    /// of another; it must be refused as malformed, while a permutation is mapped by index.
    @Test
    func embeddingResponseWithRepeatedIndicesIsMalformed() async throws {
        struct FixedTransport: CleanupBenchmarkTransport {
            let indices: [Int]
            func post(path: String, body: Data) async throws -> Data {
                let items = indices.map { ["index": $0, "embedding": [Double($0), 1]] }
                return try JSONSerialization.data(withJSONObject: ["data": items, "model": "m"])
            }
        }
        let settings = try judgeSettings()

        await #expect(throws: CleanupBenchmarkJudgeError.malformedResponse) {
            _ = try await CleanupBenchmarkJudgeClient(transport: FixedTransport(indices: [0, 0]), settings: settings)
                .embeddings(for: ["a", "b"])
        }
        let swapped = try await CleanupBenchmarkJudgeClient(transport: FixedTransport(indices: [1, 0]), settings: settings)
            .embeddings(for: ["a", "b"])
        #expect(swapped.vectors == [[0, 1], [1, 1]])
    }

    /// Stated sensitivity: an embedding that comes back empty scores 0 through `cosine` with no
    /// failure, so the run looks judged; the batch must be refused, so the run ends with
    /// `embedding-failed` and the cause reaches the info → RED.
    @Test
    func emptyEmbeddingVectorFailsTheBatch() async throws {
        struct EmptyVectorTransport: CleanupBenchmarkTransport {
            let inner: FakeJudgeTransport
            func post(path: String, body: Data) async throws -> Data {
                guard path == "/api/v1/embeddings" else {
                    return try await inner.post(path: path, body: body)
                }
                let input = (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["input"] as? [String] ?? []
                let items = input.indices.map { ["index": $0, "embedding": [Double]()] as [String: Any] }
                return try JSONSerialization.data(withJSONObject: ["data": items, "model": "fake/embedding-snapshot"])
            }
        }
        let judge = CleanupBenchmarkJudge(
            transport: EmptyVectorTransport(inner: FakeJudgeTransport()), settings: try judgeSettings()
        )

        let result = await judge.score([Self.run(output: "Hello there.")], samples: [Self.sample])

        let run = try #require(result.runs.first)
        #expect(Set(run.failures) == ["embedding-failed"])
        #expect(run.scores.embedding == nil)
        #expect(result.info.embeddingErrors == ["malformed response"])
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

    /// Stated sensitivity: `record` must receive the scored run, with its failures and the
    /// models that answered, and a rerun of a run that failed earlier must drop the old
    /// judge failure codes. It does not show that `record` fires as each run is scored
    /// rather than once at the end: one run cannot tell.
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
