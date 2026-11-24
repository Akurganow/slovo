import Foundation
import Testing

import CleanupBenchmark

@Suite("Cleanup benchmark baseline command")
struct CleanupBenchmarkBaselineCommandTests {
    private static let other = """
    {"candidates": {"other:untouched": {"judgeSHA256": "j", "snapshots": [], "datasetSHA256": "x", "repetitions": 5, "dropWorst": 2, "samples": {}}}}
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
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--repetitions", "5",
            "--write-baseline", "baseline.json",
        ])

        #expect(result.stderr.isEmpty)
        let file = try baseline(fixture)
        #expect(Set(file.candidates.keys) == ["other:untouched", "fake:good", "fake:bad"])
        let good = try #require(file.candidates["fake:good"])
        #expect(Set(good.samples.keys) == ["one", "two"])
        #expect(good.snapshots == ["fake/embedding-snapshot", "fake/jev-snapshot"])
        #expect(good.datasetSHA256.count == 64)
        #expect(good.judgeSHA256.count == 64)
        #expect(abs((good.samples["one"]?.jev ?? 0) - 0.05) < 1e-9)
        #expect(good.repetitions == 5)
        #expect(file.candidates["other:untouched"]?.datasetSHA256 == "x")
    }

    /// Stated sensitivity: an exit code that does not follow the verdict makes the
    /// command useless as a CI step. Each candidate is judged against its own entry
    /// (both pass, exit 0); a candidate with no entry is judged against the named
    /// entry and fails it (exit 2) with the baseline it used printed.
    @Test
    func verdictDecidesTheExitCodeAndFallsBackToTheNamedEntry() async throws {
        let fixture = try DriverFixture()
        _ = await fixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--repetitions", "5", "--write-baseline", "baseline.json",
        ])
        let both = try #require(fixture.file("baseline.json"))

        let own = await fixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--repetitions", "5", "--baseline", "baseline.json",
        ])
        #expect(own.exitCode == 0)
        #expect(own.stdout.contains("candidate,baseline,category,samples,misses,allowed_misses,dropped_outside,"))
        #expect(own.stdout.contains("fake:good,fake:good,all,2,0,1,0,"))
        #expect(own.stdout.contains("fake:bad,fake:bad,all,2,0,1,0,"))
        let verdicts = own.stdout.split(separator: "\n").filter { $0.hasSuffix(",pass") || $0.hasSuffix(",fail") }
        #expect(verdicts.count == 6)
        #expect(verdicts.allSatisfy { $0.hasSuffix(",pass") })

        // Only `good` keeps an entry; `bad` is judged against it.
        let onlyGood = try CleanupBenchmarkBaselineFile.decode(both)
        let reduced = CleanupBenchmarkBaselineFile(candidates: ["fake:good": try #require(onlyGood.candidates["fake:good"])])
        let fallbackFixture = try DriverFixture(files: ["baseline.json": String(decoding: try reduced.encoded(), as: UTF8.self)])
        let fallback = await fallbackFixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--repetitions", "5",
            "--baseline", "baseline.json", "--baseline-candidate", "fake:good",
        ])
        #expect(fallback.exitCode == 2)
        #expect(fallback.stdout.contains("fake:good,fake:good,all,2,0,1,0,"))
        #expect(fallback.stdout.contains("fake:bad,fake:good,all,2,2,1,4,"))
        #expect(fallback.stdout.split(separator: "\n").contains { $0.hasSuffix(",fail") })
    }

    /// Stated sensitivity: a run against a baseline recorded on another dataset file,
    /// or with no entry for the candidate or the fallback, is refused before any
    /// request leaves (exit 64, nothing sent); a flag that needs `--judge` without it
    /// is refused too.
    @Test
    func unusableBaselineOrFlagsStopBeforeAnyRequest() async throws {
        let fixture = try DriverFixture(files: ["baseline.json": Self.other])

        let noEntry = await fixture.run(["--providers", "openrouter:good", "--judge", "--repetitions", "5", "--baseline", "baseline.json"])
        #expect(noEntry.exitCode == 64)
        #expect(noEntry.stderr.contains("baseline has no entry for fake:good"))

        let wrongDataset = await fixture.run([
            "--providers", "openrouter:good", "--judge", "--repetitions", "5", "--baseline", "baseline.json",
            "--baseline-candidate", "other:untouched",
        ])
        #expect(wrongDataset.exitCode == 64)
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
            "--providers", "openrouter:good", "--judge", "--repetitions", "5", "--write-baseline", "baseline.json",
        ])

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("no baseline entry for fake:good: 10 of its runs"))
        #expect(!result.stderr.contains("--outputs-file"))

        let withFile = await fixture.run([
            "--providers", "openrouter:good", "--judge", "--repetitions", "5", "--write-baseline", "baseline.json",
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
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--repetitions", "5", "--write-baseline", "baseline.json",
        ])

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("no baseline entry for fake:bad: 10 of its runs"))
        #expect(!result.stderr.contains("fake:good"))
        #expect(try baseline(fixture).candidates.keys.sorted() == ["fake:good", "other:untouched"])
    }

    /// Stated sensitivity: a baseline recorded with other questions must be refused,
    /// not applied: one that skips the judge digest check lets a retuned judge pass
    /// against slack another judge measured.
    @Test
    func baselineFromAnotherJudgeIsRefusedBeforeAnyRequest() async throws {
        let fixture = try DriverFixture()
        _ = await fixture.run(["--providers", "openrouter:good", "--judge", "--repetitions", "5", "--write-baseline", "baseline.json"])
        let written = try CleanupBenchmarkBaselineFile.decode(try #require(fixture.file("baseline.json")))
        let entry = try #require(written.candidates["fake:good"])
        let foreign = CleanupBenchmarkBaselineEntry(
            judgeSHA256: "other-judge", snapshots: [], datasetSHA256: entry.datasetSHA256, repetitions: 5, dropWorst: 2, samples: entry.samples
        )
        let other = try DriverFixture(files: [
            "baseline.json": String(decoding: try CleanupBenchmarkBaselineFile(candidates: ["fake:good": foreign]).encoded(), as: UTF8.self),
        ])

        let result = await other.run(["--providers", "openrouter:good", "--judge", "--repetitions", "5", "--baseline", "baseline.json"])

        #expect(result.exitCode == 64)
        #expect(result.stderr.contains("different judge settings"))
        #expect(other.transport.recorded().isEmpty)
    }

    /// Stated sensitivity: a resume that repeats a complete run pays twice; one that
    /// skips the run with no line leaves it unscored. Two samples, one cleaned and
    /// judged in the file, the other missing: only the missing one costs a cleaner
    /// call (1), a Jev decision per repeat (3) and one embeddings batch.
    @Test
    func resumedRunPaysOnlyForTheMissingRun() async throws {
        let fixture = try DriverFixture()
        _ = await fixture.run(["--providers", "openrouter:good", "--judge", "--outputs-file", "out.jsonl"])
        #expect(fixture.cleaned == 2)
        let kept = String(decoding: try #require(fixture.file("out.jsonl")), as: UTF8.self)
            .split(separator: "\n").filter { !$0.contains(#""sampleId":"two""#) }
        fixture.files.withLock { $0["out.jsonl"] = Data((kept.joined(separator: "\n") + "\n").utf8) }
        let decisionsBefore = fixture.transport.requestCount(path: "/api/alpha/decisions")
        let embeddingsBefore = fixture.transport.requestCount(path: "/api/v1/embeddings")

        let result = await fixture.run(["--providers", "openrouter:good", "--judge", "--outputs-file", "out.jsonl"])

        #expect(result.exitCode == 0)
        #expect(fixture.cleaned == 3)
        #expect(fixture.transport.requestCount(path: "/api/alpha/decisions") - decisionsBefore == 3)
        #expect(fixture.transport.requestCount(path: "/api/v1/embeddings") - embeddingsBefore == 1)
        #expect(result.stdout.contains("fake:good,2,0,"))
    }

    /// Stated sensitivity: a resume that runs the cleaner again for a run that already
    /// has an output pays for a paid cleaner call twice; one that treats a failed judge
    /// as final never scores the run. The judge is down in the first run: both runs
    /// keep their outputs and fail; the second run judges them and cleans nothing.
    @Test
    func runWithOutputButNoFullScoreIsJudgedAgainWithoutTheCleaner() async throws {
        let fixture = try DriverFixture()
        fixture.transport.setDown(true)
        let first = await fixture.run(["--providers", "openrouter:good", "--judge", "--outputs-file", "out.jsonl"])
        #expect(first.exitCode == 2)
        #expect(fixture.cleaned == 2)
        fixture.transport.setDown(false)

        let second = await fixture.run(["--providers", "openrouter:good", "--judge", "--outputs-file", "out.jsonl"])

        #expect(second.exitCode == 0)
        #expect(fixture.cleaned == 2)
        #expect(second.stdout.contains("fake:good,2,0,"))
        #expect(second.stdout.contains("0.950"))
    }

    /// Stated sensitivity: a line without `rawsSHA256`, such as one written before it
    /// existed, treated as matching would reuse outputs nobody can tie to the current ids and
    /// raws; it must be refused before any request, with the remedy named.
    @Test
    func outputsFileLineFromBeforeTheRawsDigestIsRefused() async throws {
        let fixture = try DriverFixture(files: [
            "out.jsonl": #"{"sample":1,"sampleId":"one","candidate":"fake:good","repetition":1,"output":"x","#
                + #""durationNanoseconds":1,"fuzzy":1,"embedding":null,"jev":null,"jevQuestions":{},"models":[],"failures":[],"#
                + #""datasetSHA256":"old","style":"casual"}"#
                + "\n",
        ])

        let result = await fixture.run(["--providers", "openrouter:good", "--judge", "--outputs-file", "out.jsonl"])

        #expect(result.exitCode == 64)
        #expect(result.stderr.contains("other sample ids or raws, or in an older format; name a new --outputs-file"))
        #expect(fixture.cleaned == 0)
        #expect(fixture.transport.recorded().isEmpty)
    }

    /// Stated sensitivity: a resume that matches lines by sample id alone reuses the
    /// output cleaned from a raw that has since changed; it exits 0 and cleans nothing. A
    /// line must be refused before any request when the digest of the ids and raws
    /// differs from the current one.
    @Test
    func outputsFileOfAnEditedRawIsRefused() async throws {
        let fixture = try DriverFixture()
        let arguments = ["--providers", "openrouter:good", "--judge", "--outputs-file", "out.jsonl"]
        _ = await fixture.run(arguments)
        #expect(fixture.cleaned == 2)
        let requests = fixture.transport.recorded().count
        fixture.files.withLock { files in
            let edited = String(decoding: files["samples.json"] ?? Data(), as: UTF8.self)
                .replacingOccurrences(of: "Проверь latency на staging.", with: "Проверь latency на production.")
            files["samples.json"] = Data(edited.utf8)
        }

        let result = await fixture.run(arguments)

        #expect(result.exitCode == 64)
        #expect(result.stderr.contains("other sample ids or raws"))
        #expect(fixture.cleaned == 2)
        #expect(fixture.transport.recorded().count == requests)
    }

    /// Stated sensitivity: a resume that refuses an edited reference throws away paid
    /// outputs; one that keeps its scores (a digest of the judge settings alone) compares
    /// the output with a reference it was never scored against; one that keeps its fuzzy
    /// score does the same on the cheap coefficient. The edited reference is judged
    /// again (3 repeats × 2 samples) with no cleaner call, and the fuzzy score is the new
    /// one.
    @Test
    func editedReferenceKeepsTheOutputsAndJudgesThemAgain() async throws {
        let fixture = try DriverFixture()
        let arguments = ["--providers", "openrouter:good", "--judge", "--outputs-file", "out.jsonl"]
        _ = await fixture.run(arguments)
        let decisionsBefore = fixture.transport.requestCount(path: "/api/alpha/decisions")
        fixture.files.withLock { files in
            let edited = String(decoding: files["samples.json"] ?? Data(), as: UTF8.self)
                .replacingOccurrences(of: #""references": ["Hello there."]"#, with: #""references": ["Hi there."]"#)
            files["samples.json"] = Data(edited.utf8)
        }

        let result = await fixture.run(arguments)

        #expect(result.exitCode == 0)
        #expect(fixture.cleaned == 2)
        #expect(fixture.transport.requestCount(path: "/api/alpha/decisions") - decisionsBefore == 6)
        let file = try #require(fixture.file("out.jsonl"))
        let last = try #require(String(decoding: file, as: UTF8.self).split(separator: "\n").last)
        let object = try #require(JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any])
        #expect((object["fuzzy"] as? Double ?? 1) < 1)
    }

    /// Stated sensitivity: a run whose output was empty judged again on every resume pays
    /// for a score it can never have; the judge must not see it (no decision for it), and
    /// the cleaner must not run again for it either.
    @Test
    func emptyOutputIsNeitherJudgedNorCleanedOnResume() async throws {
        let fixture = try DriverFixture()
        let arguments = ["--providers", "openrouter:good", "--judge", "--outputs-file", "out.jsonl"]
        _ = await fixture.run(arguments)
        let lines = String(decoding: try #require(fixture.file("out.jsonl")), as: UTF8.self).split(separator: "\n")
        let rewritten = try lines.map { line -> String in
            var object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] ?? [:]
            if object["sampleId"] as? String == "one" {
                object["output"] = ""
                object["fuzzy"] = 0
                object["embedding"] = NSNull()
                object["jev"] = NSNull()
                object["jevQuestions"] = [String: [Double]]()
                object["failures"] = ["empty-output"]
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        }
        fixture.files.withLock { $0["out.jsonl"] = Data((rewritten.joined(separator: "\n") + "\n").utf8) }
        let decisionsBefore = fixture.transport.requestCount(path: "/api/alpha/decisions")

        let result = await fixture.run(arguments)

        #expect(result.exitCode == 2)
        #expect(fixture.cleaned == 2)
        #expect(fixture.transport.requestCount(path: "/api/alpha/decisions") == decisionsBefore)
    }

    /// Stated sensitivity: resuming under another style would mix two styles' outputs in
    /// one report and one baseline entry; the file must be refused before any request,
    /// naming the style it was written with.
    @Test
    func outputsFileOfAnotherStyleIsRefused() async throws {
        let fixture = try DriverFixture()
        _ = await fixture.run(["--providers", "openrouter:good", "--style", "formal", "--outputs-file", "out.jsonl"])
        let cleaned = fixture.cleaned

        let result = await fixture.run(["--providers", "openrouter:good", "--style", "casual", "--outputs-file", "out.jsonl"])

        #expect(result.exitCode == 64)
        #expect(result.stderr.contains("--style formal"))
        #expect(fixture.cleaned == cleaned)
    }

    /// Stated sensitivity: a baseline written with other repetitions than the scheme's
    /// measures slack another way than the candidate is measured; both flags must refuse
    /// a run with other `--repetitions` before any request, naming the number to use.
    @Test
    func baselineFlagsNeedTheBarsRepetitions() async throws {
        let fixture = try DriverFixture()

        for flag in ["--baseline", "--write-baseline"] {
            let result = await fixture.run(["--providers", "openrouter:good", "--judge", "--repetitions", "3", flag, "baseline.json"])
            #expect(result.exitCode == 64)
            #expect(result.stderr.contains("--repetitions 5"))
        }
        #expect(fixture.transport.recorded().isEmpty)
        #expect(fixture.cleaned == 0)
    }

    /// Stated sensitivity: an entry recorded with other repetitions or another `dropWorst`
    /// than the bar's, applied to a run of that scheme, compares slacks measured two ways;
    /// checking the repetitions alone lets a changed `dropWorst` through. It must be refused
    /// before any request, naming the remedy.
    @Test(arguments: [(repetitions: 3, dropWorst: 2), (repetitions: 5, dropWorst: 1)])
    func baselineEntryOfOtherSchemeIsRefused(repetitions: Int, dropWorst: Int) async throws {
        let fixture = try DriverFixture()
        _ = await fixture.run(["--providers", "openrouter:good", "--judge", "--repetitions", "5", "--write-baseline", "baseline.json"])
        let written = try CleanupBenchmarkBaselineFile.decode(try #require(fixture.file("baseline.json")))
        let entry = try #require(written.candidates["fake:good"])
        let shorter = CleanupBenchmarkBaselineEntry(
            judgeSHA256: entry.judgeSHA256, snapshots: [], datasetSHA256: entry.datasetSHA256,
            repetitions: repetitions, dropWorst: dropWorst, samples: entry.samples
        )
        let other = try DriverFixture(files: [
            "baseline.json": String(decoding: try CleanupBenchmarkBaselineFile(candidates: ["fake:good": shorter]).encoded(), as: UTF8.self),
        ])

        let result = await other.run(["--providers", "openrouter:good", "--judge", "--repetitions", "5", "--baseline", "baseline.json"])

        #expect(result.exitCode == 64)
        #expect(result.stderr.contains("other repetitions or dropWorst than the bar in judge.json"))
        #expect(other.transport.recorded().isEmpty)
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

        let result = await fixture.run(["--providers", "openrouter:good", "--judge", "--repetitions", "5", "--baseline", "baseline.json"])

        #expect(result.exitCode == 64)
        #expect(result.stderr.contains("not a baseline in the current format"))
        #expect(result.stderr.contains("--write-baseline"))
        #expect(fixture.transport.recorded().isEmpty)
    }

    /// Stated sensitivity: an append that does not end a half-written line first joins the
    /// next line to it, and the joined line is dropped as undecodable: that paid run is
    /// lost. The half line is ended; a file that already ends in a newline gets no blank line.
    @Test
    func appendEndsAHalfWrittenLineFirst() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "outputs-\(UUID().uuidString).jsonl").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Data(#"{"sample":3,"sam"#.utf8).write(to: URL(fileURLWithPath: path))

        try CleanupBenchmarkCommandDriver.appendDataFile(path, Data("{\"a\":1}\n".utf8))
        try CleanupBenchmarkCommandDriver.appendDataFile(path, Data("{\"b\":2}\n".utf8))

        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text == "{\"sample\":3,\"sam\n{\"a\":1}\n{\"b\":2}\n")
    }

    /// Stated sensitivity: a resume that trusts the scores of a line whatever judge gave
    /// them never judges again after `judge.json` changes, so a run is compared with a
    /// baseline another judge measured; one that drops the output with the scores pays
    /// for the cleaner twice. Two samples with the three coefficients are judged again
    /// (2 repeats each), and nothing is cleaned.
    @Test
    func runScoredByOtherJudgeSettingsKeepsItsOutputAndIsJudgedAgain() async throws {
        let fixture = try DriverFixture()
        let arguments = ["--providers", "openrouter:good", "--judge", "--outputs-file", "out.jsonl"]
        _ = await fixture.run(arguments)
        #expect(fixture.cleaned == 2)
        let decisionsBefore = fixture.transport.requestCount(path: "/api/alpha/decisions")
        fixture.files.withLock { files in
            let path = CleanupBenchmarkJudgeSettings.defaultPath
            let settings = String(decoding: files[path] ?? Data(), as: UTF8.self)
                .replacingOccurrences(of: #""repeats": 3"#, with: #""repeats": 2"#)
            files[path] = Data(settings.utf8)
        }

        let result = await fixture.run(arguments)

        #expect(result.exitCode == 0)
        #expect(fixture.cleaned == 2)
        #expect(fixture.transport.requestCount(path: "/api/alpha/decisions") - decisionsBefore == 4)
    }

    /// Stated sensitivity: an outputs file written without the flag leaks output text
    /// to disk; one that omits a line when a run's cleanup finishes (before the judge),
    /// the repetition or the null of a failed run loses what it exists to show. Sample
    /// index and repetition are 1-based; each run has a cleanup line and a judged line.
    @Test
    func outputsFileIsWrittenOnlyWithTheFlagAndHasTheLinesOfEveryRun() async throws {
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
        #expect(lines.count == 16)
        let first = try #require(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        #expect(first["sample"] as? Int == 1)
        #expect(first["sampleId"] as? String == "one")
        #expect(first["repetition"] as? Int == 1)
        #expect(first["candidate"] as? String == "fake:good")
        #expect(first["output"] as? String == "Hello there.")
        #expect(first["durationNanoseconds"] is Int)
        #expect(first["jev"] is NSNull)
        let objects = try lines.map { try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        let judged = try #require(objects.first { $0["jev"] is Double && $0["repetition"] as? Int == 2 && $0["sample"] as? Int == 2 })
        #expect((judged["jevQuestions"] as? [String: [Double]])?.count == 5)
        #expect((judged["failures"] as? [String])?.isEmpty == true)
    }
}
