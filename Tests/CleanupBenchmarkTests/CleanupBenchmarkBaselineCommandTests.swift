import Foundation
import Testing

import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark baseline command")
struct CleanupBenchmarkBaselineCommandTests {
    private static let other = """
    {"candidates": {"other:untouched": {"judgeSHA256": "j", "snapshots": [], "datasetSHA256": "x",
      "repetitions": 5, "dropWorst": 2, "style": "casual", "samples": {}}}}
    """

    private func baseline(_ fixture: DriverFixture) throws -> CleanupBenchmarkBaselineFile {
        try CleanupBenchmarkBaselineFile.decode(try #require(fixture.file("baseline.json")))
    }

    /// A fixture whose baseline file holds the entries `good` and `bad` record when both run well:
    /// `bad`'s entry is the same copy of `good`'s, so `bad`'s low-scoring output fails the bar against
    /// its own entry.
    private func fixtureWhereBadFailsItsOwnEntry(transport: FakeJudgeTransport = FakeJudgeTransport()) async throws -> DriverFixture {
        let writer = try DriverFixture()
        _ = await writer.run(["--providers", "openrouter:good", "--judge", "--write-baseline", "baseline.json"])
        let good = try #require(try baseline(writer).candidates["fake:good"])
        let both = CleanupBenchmarkBaselineFile(candidates: ["fake:good": good, "fake:bad": good])
        return try DriverFixture(
            files: ["baseline.json": String(decoding: try both.encoded(), as: UTF8.self)],
            transport: transport
        )
    }

    /// Stated sensitivity: a write that replaces the file loses the entry of the catalogue
    /// model that did not run; a merge that keeps every old entry leaves `other:orphan`,
    /// a model outside the catalogue, in the file; one that drops every entry that did not
    /// run loses the catalogue model's entry; one that skips a candidate that ran leaves it
    /// without an entry; digest, judge ids and one stat set per sample are what a later
    /// `--baseline` run reads.
    @Test
    func writeBaselineAddsEntriesForCandidatesThatRanKeepsCatalogueModelsAndDropsTheRest() async throws {
        let recorded = try #require(try CleanupBenchmarkBaselineFile.decode(Data(Self.other.utf8)).candidates["other:untouched"])
        let catalogueName = "openrouter:\(Config.defaultOpenRouterModel)"
        let fixture = try DriverFixture(files: [
            "baseline.json": String(
                decoding: try CleanupBenchmarkBaselineFile(candidates: [catalogueName: recorded, "other:orphan": recorded]).encoded(),
                as: UTF8.self
            ),
        ])

        let result = await fixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge",
            "--write-baseline", "baseline.json",
        ])

        #expect(result.stderr.isEmpty)
        let file = try baseline(fixture)
        #expect(Set(file.candidates.keys) == [catalogueName, "fake:good", "fake:bad"])
        let good = try #require(file.candidates["fake:good"])
        #expect(Set(good.samples.keys) == ["one", "two"])
        #expect(good.snapshots == ["fake/embedding-snapshot", "fake/jev-snapshot"])
        #expect(good.datasetSHA256.count == 64)
        #expect(good.judgeSHA256.count == 64)
        #expect(abs((good.samples["one"]?.jev ?? 0) - 0.05) < 1e-9)
        #expect(good.repetitions == (try judgeSettings()).bar.repetitions)
        #expect(good.style == .casual)
        #expect(file.candidates[catalogueName]?.datasetSHA256 == "x")
    }

    /// Stated sensitivity: an exit code that does not follow the verdict makes the
    /// command useless as a CI step. Each candidate is judged against its own entry
    /// (both pass, exit 0); a candidate with no entry is judged against the named
    /// entry and fails it with the baseline it used printed, and that is still exit 0:
    /// a fail against the fallback entry is no degradation, so counting it as one
    /// turns the exit to 3.
    @Test
    func verdictDecidesTheExitCodeAndFallsBackToTheNamedEntry() async throws {
        let fixture = try DriverFixture()
        _ = await fixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--write-baseline", "baseline.json",
        ])
        let both = try #require(fixture.file("baseline.json"))

        let own = await fixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--baseline", "baseline.json",
        ])
        #expect(own.exitCode == 0)
        #expect(own.stdout.contains("candidate,baseline,category,samples,misses,allowed_misses,dropped_outside,"))
        #expect(own.stdout.contains("fake:good,fake:good,all,2,0,1,0,"))
        #expect(own.stdout.contains("fake:bad,fake:bad,all,2,0,1,0,"))
        let verdicts = own.stdout.split(separator: "\n").filter { $0.hasSuffix(",pass") || $0.hasSuffix(",fail") }
        #expect(verdicts.count == 8)
        #expect(verdicts.allSatisfy { $0.hasSuffix(",pass") })

        // Only `good` keeps an entry; `bad` is judged against it.
        let onlyGood = try CleanupBenchmarkBaselineFile.decode(both)
        let reduced = CleanupBenchmarkBaselineFile(candidates: ["fake:good": try #require(onlyGood.candidates["fake:good"])])
        let fallbackFixture = try DriverFixture(files: ["baseline.json": String(decoding: try reduced.encoded(), as: UTF8.self)])
        let fallback = await fallbackFixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge",
            "--baseline", "baseline.json", "--baseline-candidate", "fake:good",
        ])
        #expect(fallback.exitCode == 0)
        #expect(fallback.stdout.contains("fake:good,fake:good,all,2,0,1,0,"))
        #expect(fallback.stdout.contains("fake:bad,fake:good,all,2,2,1,4,"))
        #expect(fallback.stdout.split(separator: "\n").contains { $0.hasSuffix(",fail") })
    }

    /// Stated sensitivity: a candidate that fails the bar against its own entry and has no
    /// failed run exits 3; an exit that ignores the verdict returns 0 and one that reads it as
    /// a failed run returns 2. The same run with a failed run exits 2: a swapped precedence
    /// returns 3 there.
    @Test
    func failingOwnEntryExits3AndAFailedRunMakesItExit2() async throws {
        let degraded = try await fixtureWhereBadFailsItsOwnEntry()

        let degradedOnly = await degraded.run(["--providers", "openrouter:good,openrouter:bad", "--judge", "--baseline", "baseline.json"])
        #expect(degradedOnly.exitCode == 3)
        #expect(degradedOnly.stdout.contains("fake:bad,fake:bad,all,2,2,1,"))
        #expect(degradedOnly.stderr.isEmpty)

        let failing = try await fixtureWhereBadFailsItsOwnEntry(transport: FakeJudgeTransport(failingDecisionsFor: "WRONG"))
        let both = await failing.run(["--providers", "openrouter:good,openrouter:bad", "--judge", "--baseline", "baseline.json"])
        #expect(both.stdout.contains("fake:bad,10,10,"))
        #expect(both.stdout.split(separator: "\n").contains { $0.hasSuffix(",fail") })
        #expect(both.exitCode == 2)
    }

    /// Stated sensitivity: a run against a baseline recorded on another dataset file,
    /// or with no entry for the candidate or the fallback, is refused before any
    /// request leaves (exit 64 for no entry, exit 4 for the other dataset; nothing sent); a
    /// flag that needs `--judge` without it is refused too.
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
        #expect(wrongDataset.exitCode == 4)
        #expect(wrongDataset.stderr.contains("different dataset file; rewrite it with --write-baseline"))

        let noJudge = await fixture.run(["--providers", "openrouter:good", "--baseline", "baseline.json"])
        #expect(noJudge.exitCode == 64)
        #expect(noJudge.stderr.contains("--baseline requires --judge"))
        let noJudgeWrite = await fixture.run(["--providers", "openrouter:good", "--write-baseline", "baseline.json"])
        #expect(noJudgeWrite.exitCode == 64)

        #expect(fixture.transport.recorded().isEmpty)
    }

    /// Stated sensitivity: a judge that refuses on every output must make a baseline
    /// write produce no entry and leave the file as it was, not record slack for outputs
    /// that were never scored; stderr names the candidate and how many runs are missing, and
    /// advises the same `--outputs-file` only when one was given.
    @Test
    func judgeErrorsMakeTheRunFailAndBlockTheBaselineWrite() async throws {
        let fixture = try DriverFixture(
            files: ["baseline.json": Self.other],
            transport: FakeJudgeTransport(refusing: "keeps_meaning")
        )

        let result = await fixture.run([
            "--providers", "openrouter:good", "--judge", "--write-baseline", "baseline.json",
        ])

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("baseline entry for fake:good not written: runs with no full score or with a failure: 10"))
        #expect(!result.stderr.contains("--outputs-file"))

        let withFile = await fixture.run([
            "--providers", "openrouter:good", "--judge", "--write-baseline", "baseline.json",
            "--outputs-file", "out.jsonl",
        ])
        #expect(withFile.stderr.contains("run again with the same --outputs-file to finish them"))
        #expect(try baseline(fixture).candidates.keys.sorted() == ["other:untouched"])
        #expect(result.stdout.contains("fake:good,10,10,"))
    }

    /// Stated sensitivity: a write that stops at the first incomplete candidate, or that
    /// writes nothing when one candidate failed, loses the entry of a candidate that is
    /// complete; one that writes the incomplete candidate records unscored slack.
    @Test
    func baselineIsWrittenOnlyForCandidatesWhoseRunsAreAllComplete() async throws {
        let fixture = try DriverFixture(
            files: ["baseline.json": Self.other],
            transport: FakeJudgeTransport(failingDecisionsFor: "WRONG")
        )

        let result = await fixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--write-baseline", "baseline.json",
        ])

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("baseline entry for fake:bad not written: runs with no full score or with a failure: 10"))
        #expect(!result.stderr.contains("fake:good"))
        #expect(try baseline(fixture).candidates.keys.sorted() == ["fake:good"])
    }

    /// Stated sensitivity: a baseline recorded with other questions must be refused,
    /// not applied: one that skips the judge digest check lets a retuned judge pass
    /// against slack another judge measured.
    @Test
    func baselineFromAnotherJudgeIsRefusedBeforeAnyRequest() async throws {
        let fixture = try DriverFixture()
        _ = await fixture.run(["--providers", "openrouter:good", "--judge", "--write-baseline", "baseline.json"])
        let written = try CleanupBenchmarkBaselineFile.decode(try #require(fixture.file("baseline.json")))
        let entry = try #require(written.candidates["fake:good"])
        let foreign = CleanupBenchmarkBaselineEntry(
            judgeSHA256: "other-judge", snapshots: [], datasetSHA256: entry.datasetSHA256,
            repetitions: 5, dropWorst: 2, style: entry.style, samples: entry.samples
        )
        let other = try DriverFixture(files: [
            "baseline.json": String(decoding: try CleanupBenchmarkBaselineFile(candidates: ["fake:good": foreign]).encoded(), as: UTF8.self),
        ])

        let result = await other.run(["--providers", "openrouter:good", "--judge", "--baseline", "baseline.json"])

        #expect(result.exitCode == 4)
        #expect(result.stderr.contains("different judge settings"))
        #expect(other.transport.recorded().isEmpty)
    }

    /// Stated sensitivity: a baseline written with other repetitions than the scheme's
    /// measures slack another way than the candidate is measured; both flags must refuse
    /// an explicit `--repetitions` that differs from `bar.repetitions` before any request,
    /// naming the number to use. Without `--repetitions` the same flags run (the default is
    /// the bar's), so a guard that also refuses the omitted flag fails the last line.
    @Test
    func baselineFlagsRefuseOtherExplicitRepetitions() async throws {
        let fixture = try DriverFixture()
        let required = try judgeSettings().bar.repetitions

        for flag in ["--baseline", "--write-baseline"] {
            let result = await fixture.run([
                "--providers", "openrouter:good", "--judge", "--repetitions", "\(required + 1)", flag, "baseline.json",
            ])
            #expect(result.exitCode == 64)
            #expect(result.stderr.contains("--repetitions \(required)"))
        }
        #expect(fixture.transport.recorded().isEmpty)
        #expect(fixture.cleaned == 0)

        let omitted = await fixture.run(["--providers", "openrouter:good", "--judge", "--write-baseline", "baseline.json"])
        #expect(omitted.exitCode == 0)
        #expect(fixture.cleaned == 2 * required)
    }

    /// Stated sensitivity: an entry recorded with other repetitions or another `dropWorst`
    /// than the bar's, applied to a run of that scheme, compares slacks measured two ways;
    /// checking the repetitions alone lets a changed `dropWorst` through. It must be refused
    /// before any request, naming the remedy.
    @Test(arguments: [(repetitions: 3, dropWorst: 2), (repetitions: 5, dropWorst: 1)])
    func baselineEntryOfOtherSchemeIsRefused(repetitions: Int, dropWorst: Int) async throws {
        let fixture = try DriverFixture()
        _ = await fixture.run(["--providers", "openrouter:good", "--judge", "--write-baseline", "baseline.json"])
        let written = try CleanupBenchmarkBaselineFile.decode(try #require(fixture.file("baseline.json")))
        let entry = try #require(written.candidates["fake:good"])
        let shorter = CleanupBenchmarkBaselineEntry(
            judgeSHA256: entry.judgeSHA256, snapshots: [], datasetSHA256: entry.datasetSHA256,
            repetitions: repetitions, dropWorst: dropWorst, style: entry.style, samples: entry.samples
        )
        let other = try DriverFixture(files: [
            "baseline.json": String(decoding: try CleanupBenchmarkBaselineFile(candidates: ["fake:good": shorter]).encoded(), as: UTF8.self),
        ])

        let result = await other.run(["--providers", "openrouter:good", "--judge", "--baseline", "baseline.json"])

        #expect(result.exitCode == 4)
        #expect(result.stderr.contains("other repetitions or dropWorst than the bar in judge.json"))
        #expect(other.transport.recorded().isEmpty)
    }

    /// Stated sensitivity: an entry recorded under one writing style applied to a run under
    /// another compares outputs of two prompts; a missing check lets the run through, and an
    /// entry that always records the default style is refused for a run in the style it was
    /// written under, or lets a run in another style through. The refusal comes before any
    /// request and names the entry's style; the same style passes.
    @Test
    func baselineEntryOfAnotherStyleIsRefused() async throws {
        let fixture = try DriverFixture()
        _ = await fixture.run(["--providers", "openrouter:good", "--judge", "--style", "formal", "--write-baseline", "baseline.json"])
        let requests = fixture.transport.recorded().count

        let other = await fixture.run(["--providers", "openrouter:good", "--judge", "--style", "casual", "--baseline", "baseline.json"])
        #expect(other.exitCode == 4)
        #expect(other.stderr.contains("recorded with --style formal"))
        #expect(fixture.transport.recorded().count == requests)

        let same = await fixture.run(["--providers", "openrouter:good", "--judge", "--style", "formal", "--baseline", "baseline.json"])
        #expect(same.exitCode == 0)
    }

    /// Stated sensitivity: a baseline in the old format (a stored centre, not one slack per
    /// sample) that surfaces a decoding error instead of a sentence leaves no way to find
    /// the remedy; it must be refused before any request, saying what to do.
    @Test
    func baselineInAnOldFormatIsRefusedWithARemedy() async throws {
        let old = """
        {"candidates": {"fake:good": {"judgeSHA256": "j", "snapshots": [], "datasetSHA256": "x",
          "samples": {"one": {"fuzzy": {"largest": 0.1}, "embedding": {"largest": 0.1}, "jev": {"largest": 0.1}}}}}}
        """
        let fixture = try DriverFixture(files: ["baseline.json": old])

        let result = await fixture.run(["--providers", "openrouter:good", "--judge", "--baseline", "baseline.json"])

        #expect(result.exitCode == 64)
        #expect(result.stderr.contains("not a baseline in the current format"))
        #expect(result.stderr.contains("--write-baseline"))
        #expect(fixture.transport.recorded().isEmpty)
    }
}
