import Testing

@testable import CleanupBenchmark

@Suite("Cleanup benchmark bar")
struct CleanupBenchmarkBarTests {
    private static let floors = CleanupBenchmarkJudgeSettings.Bar.Floors(jev: 0.15, embedding: 0.02, fuzzy: 0.05)
    private static let bar = CleanupBenchmarkJudgeSettings.Bar(floors: floors, allowance: 0.05, repetitions: 5, dropWorst: 2)

    /// Every coefficient has recorded slack 0.10, so the floors decide.
    private static let flat = CleanupBenchmarkBaselineSample(fuzzy: 0.10, embedding: 0.10, jev: 0.10)

    private static func scores(fuzzy: Double = 0.90, embedding: Double = 0.90, jev: Double = 0.90) -> CleanupBenchmarkScores {
        CleanupBenchmarkScores(fuzzy: fuzzy, embedding: embedding, jev: jev)
    }

    private static func run(_ id: String, _ category: CleanupBenchmarkCategory, _ scores: CleanupBenchmarkScores) -> CleanupBenchmarkRun {
        CleanupBenchmarkRun(
            sampleId: id, sampleCategory: category, candidateName: "c", durationNanoseconds: 1,
            output: "text", scores: scores, errorKind: nil
        )
    }

    /// One sample's five repetitions: `bad` of them score 0.1 on every coefficient, the rest 0.9.
    private static func sample(_ id: String, _ category: CleanupBenchmarkCategory, bad: Int = 0) -> [CleanupBenchmarkRun] {
        (0..<5).map { run(id, category, $0 < bad ? scores(fuzzy: 0.1, embedding: 0.1, jev: 0.1) : scores()) }
    }

    /// `count` samples of one category, the first `badSamples` of them failing in `bad` repetitions.
    private static func samples(
        _ category: CleanupBenchmarkCategory, count: Int, badSamples: Int, bad: Int = 5, offset: Int = 0
    ) -> [CleanupBenchmarkRun] {
        (0..<count).flatMap { sample("s\(offset + $0)", category, bad: $0 < badSamples ? bad : 0) }
    }

    private static func entry(_ ids: [String]) -> CleanupBenchmarkBaselineEntry {
        CleanupBenchmarkBaselineEntry(
            judgeSHA256: "j", snapshots: [], datasetSHA256: "x", repetitions: 5, dropWorst: 2, style: .casual,
            samples: Dictionary(uniqueKeysWithValues: Set(ids).map { ($0, flat) })
        )
    }

    private static func verdict(_ runs: [CleanupBenchmarkRun]) -> CleanupBenchmarkVerdict {
        CleanupBenchmarkBar.verdict(
            candidateName: "c", baselineName: "b", runs: runs, entry: entry(runs.map(\.sampleId)), settings: bar
        )
    }

    /// Stated sensitivity: dropping the two best repetitions (0.4, 0.533, 0.667 here),
    /// dropping none (plain mean 0.3, 0.4, 0.5) or dropping one (0.25, 0.25, 0.4) leaves
    /// these pinned slacks (0.2, 0.2, 0.3). The three coefficients have different
    /// repetitions.
    @Test
    func slackIsTheMeanAfterDroppingTheTwoLargest() {
        let runs = [(0.5, 0.6, 0.8), (0.9, 0.9, 0.1), (0.7, 0.2, 0.7), (0.6, 0.6, 0.6), (0.8, 0.9, 0.3)].map { fuzzy, embedding, jev in
            Self.run("s", .shortSmoke, Self.scores(fuzzy: fuzzy, embedding: embedding, jev: jev))
        }

        let sample = CleanupBenchmarkBar.slack(of: runs, dropWorst: 2)

        // fuzzy slacks 0.5 0.1 0.3 0.4 0.2 -> keep 0.1 0.2 0.3; embedding 0.4 0.1 0.8 0.4 0.1 -> keep 0.1 0.1 0.4;
        // jev 0.2 0.9 0.3 0.4 0.7 -> keep 0.2 0.3 0.4.
        #expect(abs(sample.fuzzy - 0.2) < 1e-9)
        #expect(abs(sample.embedding - 0.2) < 1e-9)
        #expect(abs(sample.jev - 0.3) < 1e-9)
    }

    /// Stated sensitivity: an unscored coefficient (a judge error, a provider error) read
    /// as slack 0 would let a failed run be a candidate's best repetition; it is the
    /// worst, so two of them are dropped and a third is not.
    @Test
    func anUnscoredRunHasTheLargestSlack() {
        let good = Self.run("s", .shortSmoke, Self.scores())
        let unscored = Self.run("s", .shortSmoke, CleanupBenchmarkScores(fuzzy: 1, embedding: 1, jev: nil))

        let two = CleanupBenchmarkBar.slack(of: [good, good, good, unscored, unscored], dropWorst: 2)
        let three = CleanupBenchmarkBar.slack(of: [good, good, unscored, unscored, unscored], dropWorst: 2)

        #expect(abs(two.jev - 0.1) < 1e-9)
        #expect(abs(three.jev - (0.1 + 0.1 + 1) / 3) < 1e-9)
    }

    /// Stated sensitivity: a margin of twice the floor moves the edge past a slack of the
    /// recorded one plus floor; a margin of zero puts that slack out; a floor applied to
    /// the wrong coefficient moves the line for it. Each coefficient sits at its edge,
    /// then one step past it.
    @Test
    func sampleIsWithinTheRecordedSlackPlusTheFloor() {
        func five(_ scores: CleanupBenchmarkScores) -> [CleanupBenchmarkRun] {
            (0..<5).map { _ in Self.run("s", .shortSmoke, scores) }
        }
        let atEdge = five(Self.scores(fuzzy: 0.85, embedding: 0.88, jev: 0.75))
        #expect(CleanupBenchmarkBar.isWithinSlack(atEdge, baseline: Self.flat, bar: Self.bar))
        for past in [
            Self.scores(fuzzy: 0.84, embedding: 0.88, jev: 0.75),
            Self.scores(fuzzy: 0.85, embedding: 0.87, jev: 0.75),
            Self.scores(fuzzy: 0.85, embedding: 0.88, jev: 0.74),
        ] {
            #expect(!CleanupBenchmarkBar.isWithinSlack(five(past), baseline: Self.flat, bar: Self.bar))
        }
    }

    /// Stated sensitivity: a run counted as within slack that carries a judge error would
    /// let a candidate pass on outputs nobody judged; with three of five repetitions
    /// unscored the sample is out, with two it is not (they are dropped).
    @Test
    func unscoredRepetitionsCountAgainstTheSampleOnlyBeyondTheDropped() {
        let unscored = Self.run("s", .shortSmoke, CleanupBenchmarkScores(fuzzy: 1, embedding: 1, jev: nil))
        let good = Self.sample("s", .shortSmoke)

        #expect(CleanupBenchmarkBar.isWithinSlack(Array(good.prefix(3)) + [unscored, unscored], baseline: Self.flat, bar: Self.bar))
        #expect(!CleanupBenchmarkBar.isWithinSlack(Array(good.prefix(2)) + [unscored, unscored, unscored], baseline: Self.flat, bar: Self.bar))
    }

    /// Stated sensitivity: counting runs in place of samples (5 run misses against 2 allowed
    /// in 10 samples × 5 repetitions would fail one bad sample whole); counting the
    /// allowance over runs lets a second bad sample through.
    @Test
    func rowsCountSamplesNotRuns() {
        let one = Self.verdict(Self.samples(.russianFiller, count: 10, badSamples: 1))
        let two = Self.verdict(Self.samples(.russianFiller, count: 10, badSamples: 2))

        #expect(one.rows.first?.samples == 10)
        #expect(one.rows.first?.misses == 1)
        #expect(one.rows.first?.allowedMisses == 1)
        #expect(one.passed)
        #expect(two.rows.first?.misses == 2)
        #expect(!two.passed)
    }

    /// Stated sensitivity: allowing zero misses in a small row fails four samples with one
    /// miss; allowing one extra miss passes two of four.
    @Test
    func smallRowToleratesOneMissAndNoMore() {
        #expect(Self.verdict(Self.samples(.shortSmoke, count: 4, badSamples: 1)).passed)
        #expect(!Self.verdict(Self.samples(.shortSmoke, count: 4, badSamples: 2)).passed)
    }

    /// Stated sensitivity: a miss count rounded up moves the edge of a large row: 3
    /// misses in 60 samples (the allowance's share) pass and a fourth fails.
    @Test
    func largeRowToleratesTheAllowancesShareOfMisses() {
        #expect(Self.verdict(Self.samples(.russianFiller, count: 60, badSamples: 3)).passed)
        #expect(!Self.verdict(Self.samples(.russianFiller, count: 60, badSamples: 4)).passed)
    }

    /// Stated sensitivity: skipping the category rows lets one collapsed category hide
    /// under the overall row (3 misses in 60 samples pass overall; the 3 sit in a
    /// category of 4).
    @Test
    func oneCollapsedCategoryFailsTheVerdict() {
        let runs = Self.samples(.russianFiller, count: 56, badSamples: 0)
            + Self.samples(.shortSmoke, count: 4, badSamples: 3, offset: 56)
        let result = Self.verdict(runs)

        #expect(result.rows.first?.passed == true)
        #expect(result.rows.first { $0.category == .shortSmoke }?.passed == false)
        #expect(!result.passed)
    }

    /// Stated sensitivity: a row of no samples that passes would let a candidate whose runs
    /// all vanished pass the bar.
    @Test
    func rowWithoutSamplesFails() {
        #expect(!Self.verdict([]).passed)
    }

    /// Stated sensitivity: no dropping (a plain mean) fails a sample with two bad
    /// repetitions of five; dropping the best two fails it too; a count that is not per
    /// repetition (3 bad coefficients of one run) shows 6 for the 2 runs; a dropped
    /// repetition inside the slack is counted when the comparison ignores the floor.
    @Test
    func twoBadRepetitionsOfFiveStayWithinSlackAndAreCounted() {
        let two = Self.verdict(Self.sample("s", .shortSmoke, bad: 2))
        let three = Self.verdict(Self.sample("s", .shortSmoke, bad: 3))
        // Two dropped repetitions whose jev slack, 0.2, is above the recorded 0.1 but inside
        // the limit of 0.25.
        let near = (0..<5).map {
            Self.run("s", .shortSmoke, $0 < 2 ? Self.scores(fuzzy: 0.9, embedding: 0.9, jev: 0.8) : Self.scores())
        }

        #expect(two.rows.first?.misses == 0)
        #expect(two.rows.first?.droppedOutside == 2)
        #expect(three.rows.first?.misses == 1)
        #expect(Self.verdict(near).rows.first?.droppedOutside == 0)
    }

    /// Stated sensitivity: a lookup that ignores the candidate's own entry judges
    /// every model against the default's; one that never falls back leaves a new
    /// model without a verdict.
    @Test
    func entryLookupPrefersOwnThenFallback() throws {
        let own = Self.entry(["own"])
        let fallback = Self.entry(["fallback"])
        let file = CleanupBenchmarkBaselineFile(candidates: ["a:own": own, "a:default": fallback])

        #expect(file.entry(for: "a:own", fallback: "a:default")?.name == "a:own")
        #expect(file.entry(for: "a:own", fallback: "a:default")?.entry == own)
        #expect(file.entry(for: "a:new", fallback: "a:default")?.name == "a:default")
        #expect(file.entry(for: "a:new", fallback: "a:absent") == nil)
    }

    /// Stated sensitivity: a merge that replaces the file, or drops the untouched
    /// entries, erases other models' recorded slack.
    @Test
    func mergeReplacesNamedEntriesAndLeavesTheRestUntouched() throws {
        let kept = Self.entry(["kept"])
        let old = Self.entry(["old"])
        let new = Self.entry(["new"])
        let file = CleanupBenchmarkBaselineFile(candidates: ["a:kept": kept, "a:ran": old])

        let merged = file.merging(["a:ran": new, "a:added": new])

        #expect(merged.candidates["a:kept"] == kept)
        #expect(merged.candidates["a:ran"] == new)
        #expect(merged.candidates["a:added"] == new)
        #expect(try CleanupBenchmarkBaselineFile.decode(merged.encoded()) == merged)
    }

    /// Stated sensitivity: an encoding without sorted keys writes the entries in the
    /// dictionary's order, which changes from process to process, so every rewrite of the
    /// baseline is a noisy diff; with eight names, an unsorted order is sorted by luck
    /// once in 40320 runs.
    @Test
    func baselineIsEncodedWithSortedKeys() throws {
        let names = ["a:h", "a:c", "a:f", "a:a", "a:g", "a:d", "a:b", "a:e"]
        let file = CleanupBenchmarkBaselineFile(candidates: Dictionary(uniqueKeysWithValues: names.map { ($0, Self.entry(["s"])) }))

        let text = String(decoding: try file.encoded(), as: UTF8.self)

        let positions = try names.sorted().map { try #require(text.range(of: "\"\($0)\"")).lowerBound }
        #expect(positions == positions.sorted())
    }

    /// Stated sensitivity: an entry built from a run a judge failed on raises a slack
    /// (near 1) and loosens the bar on that sample for good, so such a run refuses the
    /// entry. An empty output is the candidate's own failure: it is named as one, since
    /// resuming cannot change it.
    @Test
    func entryIsRefusedWhenAnyRunIsIncompleteOrEmpty() throws {
        let settings = try judgeSettings()
        let complete = (1...3).map { Self.run("s\($0)", .shortSmoke, Self.scores()) }
        var empty = Self.run("s4", .shortSmoke, Self.scores(fuzzy: 0, embedding: 0.2, jev: 0.1))
        empty.failures = ["empty-output"]
        var failed = Self.run("s5", .shortSmoke, CleanupBenchmarkScores(fuzzy: 1, embedding: 1, jev: nil))
        failed.failures = ["jev-refusal"]

        #expect(throws: CleanupBenchmarkBarError.emptyOutputs(candidate: "c", count: 1)) {
            try CleanupBenchmarkBar.makeEntry(
                candidateName: "c", runs: complete + [empty, failed], settings: settings, datasetSHA256: "x", style: .casual
            )
        }
        #expect(throws: CleanupBenchmarkBarError.incompleteRuns(candidate: "c", count: 1)) {
            try CleanupBenchmarkBar.makeEntry(
                candidateName: "c", runs: complete + [failed], settings: settings, datasetSHA256: "x", style: .casual
            )
        }
        let entry = try CleanupBenchmarkBar.makeEntry(
            candidateName: "c", runs: complete, settings: settings, datasetSHA256: "x", style: .casual
        )
        #expect(Set(entry.samples.keys) == ["s1", "s2", "s3"])
        #expect(entry.judgeSHA256 == (try settings.judgeSHA256()))
    }

    /// Stated sensitivity: an entry that keeps the plain mean stores a slack the candidate is
    /// not measured by; an entry that records other repetitions or `dropWorst` than the bar's
    /// is refused at the next run for the wrong reason. The entry holds the trimmed slack,
    /// `bar.repetitions` and `bar.dropWorst`, here set by the test.
    @Test
    func entryStoresTheTrimmedSlackAndTheRepetitions() throws {
        let committed = try judgeSettings()
        let settings = CleanupBenchmarkJudgeSettings(
            jev: committed.jev,
            embedding: committed.embedding,
            bar: CleanupBenchmarkJudgeSettings.Bar(floors: Self.floors, allowance: 0.05, repetitions: 5, dropWorst: 2)
        )
        let runs = [0.9, 0.9, 0.9, 0.2, 0.2].map { Self.run("s", .shortSmoke, Self.scores(jev: $0)) }

        let entry = try CleanupBenchmarkBar.makeEntry(candidateName: "c", runs: runs, settings: settings, datasetSHA256: "x", style: .casual)

        #expect(entry.repetitions == 5)
        #expect(entry.dropWorst == 2)
        #expect(abs((entry.samples["s"]?.jev ?? 0) - 0.1) < 1e-9)
    }

    /// Stated sensitivity: a digest over the bar section would force a new baseline
    /// for every floor change; one that ignores the questions or the embedding section
    /// lets a retuned judge pass against slack another judge measured.
    @Test
    func judgeDigestFollowsTheQuestionsAndNotTheBar() throws {
        let settings = try judgeSettings()
        let looser = CleanupBenchmarkJudgeSettings(
            jev: settings.jev,
            embedding: settings.embedding,
            bar: CleanupBenchmarkJudgeSettings.Bar(
                floors: CleanupBenchmarkJudgeSettings.Bar.Floors(jev: 0.5, embedding: 0.5, fuzzy: 0.5),
                allowance: 0.5,
                repetitions: 3,
                dropWorst: 1
            )
        )
        var questions = settings.jev.questions
        questions["plain_text"] = nil
        let fewer = CleanupBenchmarkJudgeSettings(
            jev: CleanupBenchmarkJudgeSettings.Jev(
                model: settings.jev.model, path: settings.jev.path, repeats: settings.jev.repeats, questions: questions
            ),
            embedding: settings.embedding,
            bar: settings.bar
        )

        let otherPrefix = CleanupBenchmarkJudgeSettings(
            jev: settings.jev,
            embedding: CleanupBenchmarkJudgeSettings.Embedding(
                model: settings.embedding.model,
                path: settings.embedding.path,
                prefix: "",
                provider: settings.embedding.provider
            ),
            bar: settings.bar
        )

        #expect(try looser.judgeSHA256() == settings.judgeSHA256())
        #expect(try fewer.judgeSHA256() != settings.judgeSHA256())
        #expect(try otherPrefix.judgeSHA256() != settings.judgeSHA256())
    }

    /// Stated sensitivity: retrying a 400 or a 401 spends the attempts on a request that
    /// cannot succeed; never retrying a dropped connection or a 5xx lets one blip void
    /// a paid run; sleeping after the last attempt wastes the wait; a `Retry-After`
    /// above the cap, or none, changes the wait.
    @Test
    func retryPolicyRetriesTransientFailuresWithinTheAttempts() {
        typealias Policy = CleanupBenchmarkRetryPolicy
        #expect(Policy.delay(after: .network, attempt: 0) == 1)
        #expect(Policy.delay(after: .status(500, retryAfter: nil), attempt: 2) == 4)
        #expect(Policy.delay(after: .status(429, retryAfter: 3), attempt: 0) == 3)
        #expect(Policy.delay(after: .status(402, retryAfter: 100), attempt: 0) == 30)
        for final in [400, 401, 404] {
            #expect(Policy.delay(after: .status(final, retryAfter: nil), attempt: 0) == nil)
        }
        #expect(Policy.delay(after: .network, attempt: Policy.attempts - 1) == nil)
    }
}
