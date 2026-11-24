import Foundation
import Testing

import CleanupBenchmark

@Suite("Cleanup benchmark baseline command")
struct CleanupBenchmarkBaselineCommandTests {
    private static let other = """
    {"candidates": {"other:untouched": {"jevModel": "j", "jevSnapshots": [], "embeddingModel": "e",
      "embeddingResponseModels": [], "datasetSHA256": "x", "samples": {}}}}
    """

    private func baseline(_ fixture: DriverFixture) throws -> CleanupBenchmarkBaselineFile {
        try CleanupBenchmarkBaselineFile.decode(try #require(fixture.file("baseline.json")))
    }

    /// Stated sensitivity: a write that replaces the file loses `other:untouched`;
    /// one that skips a candidate that ran leaves it without an entry; digest, judge
    /// ids and one stat set per sample are what a later `--baseline` run reads.
    @Test
    func writeBaselineAddsEntriesForCandidatesThatRanAndKeepsTheRest() async throws {
        let fixture = try DriverFixture(files: ["baseline.json": Self.other])

        let result = await fixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--repetitions", "2",
            "--write-baseline", "baseline.json",
        ])

        #expect(result.stderr.isEmpty)
        let file = try baseline(fixture)
        #expect(Set(file.candidates.keys) == ["other:untouched", "fake:good", "fake:bad"])
        let good = try #require(file.candidates["fake:good"])
        #expect(Set(good.samples.keys) == ["one", "two"])
        #expect(good.jevSnapshots == ["fake/jev-snapshot"])
        #expect(good.embeddingResponseModels == ["fake/embedding-snapshot"])
        #expect(good.datasetSHA256.count == 64)
        #expect(abs((good.samples["one"]?.jev.mean ?? 0) - 0.05) < 1e-9)
        #expect(file.candidates["other:untouched"]?.datasetSHA256 == "x")
    }

    /// Stated sensitivity: an exit code that does not follow the verdict makes the
    /// command useless as a CI step. Each candidate is judged against its own entry
    /// (both pass, exit 0); a candidate with no entry is judged against the named
    /// entry and fails it (exit 2) with the baseline it used printed.
    @Test
    func verdictDecidesTheExitCodeAndFallsBackToTheNamedEntry() async throws {
        let fixture = try DriverFixture()
        _ = await fixture.run(["--providers", "openrouter:good,openrouter:bad", "--judge", "--write-baseline", "baseline.json"])
        let both = try #require(fixture.file("baseline.json"))

        let own = await fixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--baseline", "baseline.json",
        ])
        #expect(own.exitCode == 0)
        #expect(own.stdout.contains("fake:good,fake:good,all,2,1.000,"))
        #expect(own.stdout.contains("fake:bad,fake:bad,all,2,1.000,"))
        let verdicts = own.stdout.split(separator: "\n").filter { $0.hasSuffix(",pass") || $0.hasSuffix(",fail") }
        #expect(verdicts.count == 6)
        #expect(verdicts.allSatisfy { $0.hasSuffix(",pass") })

        // Only `good` keeps an entry; `bad` is judged against it.
        let onlyGood = try CleanupBenchmarkBaselineFile.decode(both)
        let reduced = CleanupBenchmarkBaselineFile(candidates: ["fake:good": try #require(onlyGood.candidates["fake:good"])])
        let fallbackFixture = try DriverFixture(files: ["baseline.json": String(decoding: try reduced.encoded(), as: UTF8.self)])
        let fallback = await fallbackFixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge",
            "--baseline", "baseline.json", "--baseline-candidate", "fake:good",
        ])
        #expect(fallback.exitCode == 2)
        #expect(fallback.stdout.contains("fake:good,fake:good,all,2,1.000,"))
        #expect(fallback.stdout.contains("fake:bad,fake:good,all,2,0.000,"))
        #expect(fallback.stdout.split(separator: "\n").contains { $0.hasSuffix(",fail") })
    }

    /// Stated sensitivity: a run against a baseline recorded on another dataset file,
    /// or with no entry for the candidate or the fallback, is refused before any
    /// request leaves (exit 64, nothing sent); a flag that needs `--judge` without it
    /// is refused too.
    @Test
    func unusableBaselineOrFlagsStopBeforeAnyRequest() async throws {
        let fixture = try DriverFixture(files: ["baseline.json": Self.other])

        let noEntry = await fixture.run(["--providers", "openrouter:good", "--judge", "--baseline", "baseline.json"])
        #expect(noEntry.exitCode == 64)
        #expect(noEntry.stderr.contains("baseline has no entry for fake:good"))

        let wrongDataset = await fixture.run([
            "--providers", "openrouter:good", "--judge", "--baseline", "baseline.json",
            "--baseline-candidate", "other:untouched",
        ])
        #expect(wrongDataset.exitCode == 64)
        #expect(wrongDataset.stderr.contains("different dataset"))

        let noJudge = await fixture.run(["--providers", "openrouter:good", "--baseline", "baseline.json"])
        #expect(noJudge.exitCode == 64)
        #expect(noJudge.stderr.contains("--baseline requires --judge"))
        let noJudgeWrite = await fixture.run(["--providers", "openrouter:good", "--write-baseline", "baseline.json"])
        #expect(noJudgeWrite.exitCode == 64)

        #expect(fixture.transport.recorded().isEmpty)
    }

    /// Stated sensitivity: a judge that errors on every output must make a baseline
    /// write fail and leave the file as it was, not record slack for outputs that
    /// were never scored.
    @Test
    func judgeErrorsMakeTheRunFailAndBlockTheBaselineWrite() async throws {
        let fixture = try DriverFixture(
            files: ["baseline.json": Self.other],
            transport: FakeJudgeTransport(refusing: "keeps_meaning")
        )

        let result = await fixture.run(["--providers", "openrouter:good", "--judge", "--write-baseline", "baseline.json"])

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("unscoredRuns"))
        #expect(try baseline(fixture).candidates.keys.sorted() == ["other:untouched"])
        #expect(result.stdout.contains("fake:good,2,2,"))
    }

    /// Stated sensitivity: an outputs file written without the flag leaks output text
    /// to disk; one that omits the repetition or the null of a failed run loses what
    /// it exists to show. Sample index and repetition are 1-based.
    @Test
    func outputsFileIsWrittenOnlyWithTheFlagAndHasEveryRun() async throws {
        let fixture = try DriverFixture()

        let without = await fixture.run(["--providers", "openrouter:good", "--judge"])
        #expect(without.exitCode == 0)
        #expect(fixture.file("outputs.jsonl") == nil)

        let with = await fixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--repetitions", "2", "--outputs-file", "outputs.jsonl",
        ])
        #expect(with.exitCode == 0)
        #expect(!with.stdout.contains("Hello there."))
        let lines = String(decoding: try #require(fixture.file("outputs.jsonl")), as: UTF8.self)
            .split(separator: "\n").map(String.init)
        #expect(lines.count == 8)
        let first = try #require(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        #expect(first["sample"] as? Int == 1)
        #expect(first["repetition"] as? Int == 1)
        #expect(first["candidate"] as? String == "fake:good")
        #expect(first["output"] as? String == "Hello there.")
        #expect(first["jev"] is Double)
        let last = try #require(JSONSerialization.jsonObject(with: Data(lines[7].utf8)) as? [String: Any])
        #expect(last["repetition"] as? Int == 2)
        #expect(last["sample"] as? Int == 2)
        #expect((last["jevQuestions"] as? [String: [Double]])?.count == 5)
    }
}
