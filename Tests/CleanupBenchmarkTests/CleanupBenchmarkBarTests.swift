import Testing

@testable import CleanupBenchmark

@Suite("Cleanup benchmark bar")
struct CleanupBenchmarkBarTests {
    private static let floors = CleanupBenchmarkJudgeSettings.Bar.Floors(jev: 0.15, embedding: 0.02, fuzzy: 0.05)
    private static let bar = CleanupBenchmarkJudgeSettings.Bar(floors: floors, allowance: 0.05)

    /// Every coefficient has mean slack 0.10, so the floors decide.
    private static let slack = CleanupBenchmarkSlack(mean: 0.10)
    private static let flat = CleanupBenchmarkBaselineSample(fuzzy: slack, embedding: slack, jev: slack)

    private static func scores(fuzzy: Double = 0.90, embedding: Double = 0.90, jev: Double = 0.90) -> CleanupBenchmarkScores {
        CleanupBenchmarkScores(fuzzy: fuzzy, embedding: embedding, jev: jev)
    }

    private static func run(_ id: String, _ category: CleanupBenchmarkCategory, _ scores: CleanupBenchmarkScores) -> CleanupBenchmarkRun {
        CleanupBenchmarkRun(
            sampleId: id, sampleCategory: category, candidateName: "c", durationNanoseconds: 1,
            output: "text", scores: scores, errorKind: nil
        )
    }

    private static func entry(_ ids: [String]) -> CleanupBenchmarkBaselineEntry {
        CleanupBenchmarkBaselineEntry(
            judgeSHA256: "j", snapshots: [], datasetSHA256: "x", samples: Dictionary(uniqueKeysWithValues: ids.map { ($0, flat) })
        )
    }

    /// Stated sensitivity: a margin of twice the floor moves the edge past a slack of mean
    /// plus floor; a margin of zero puts that slack out; a floor applied to the wrong
    /// coefficient moves the line for it. Each coefficient sits at its edge, then one
    /// step past it.
    @Test
    func slackIsWithinMeanPlusTheFloor() {
        let atEdge = Self.scores(fuzzy: 0.85, embedding: 0.88, jev: 0.75)
        #expect(CleanupBenchmarkBar.isWithinSlack(atEdge, baseline: Self.flat, floors: Self.floors))
        for past in [
            Self.scores(fuzzy: 0.84, embedding: 0.88, jev: 0.75),
            Self.scores(fuzzy: 0.85, embedding: 0.87, jev: 0.75),
            Self.scores(fuzzy: 0.85, embedding: 0.88, jev: 0.74),
        ] {
            #expect(!CleanupBenchmarkBar.isWithinSlack(past, baseline: Self.flat, floors: Self.floors))
        }
    }

    /// Stated sensitivity: a run with an unscored coefficient (a judge error) counted
    /// as within slack would let a candidate pass on outputs nobody judged.
    @Test
    func unscoredRunIsNotWithinSlack() {
        let unscored = CleanupBenchmarkScores(fuzzy: 1, embedding: 1, jev: nil)
        #expect(!CleanupBenchmarkBar.isWithinSlack(unscored, baseline: Self.flat, floors: Self.floors))
    }

    /// `count` runs of one category, the first `misses` of them past the slack.
    private static func runs(_ category: CleanupBenchmarkCategory, count: Int, misses: Int, offset: Int = 0) -> [CleanupBenchmarkRun] {
        (0..<count).map { index in
            run("s\(offset + index)", category, index < misses ? scores(jev: 0.1) : scores())
        }
    }

    private static func verdict(_ runs: [CleanupBenchmarkRun]) -> CleanupBenchmarkVerdict {
        CleanupBenchmarkBar.verdict(
            candidateName: "c", baselineName: "b", runs: runs, entry: entry(runs.map(\.sampleId)), settings: bar
        )
    }

    /// Stated sensitivity: a share rule in place of the miss count (the baseline's own
    /// 100% less the allowance) fails four runs with one miss; allowing zero misses in
    /// a small row fails them too; allowing one extra miss passes two of four.
    @Test
    func smallRowToleratesOneMissAndNoMore() {
        #expect(Self.verdict(Self.runs(.shortSmoke, count: 4, misses: 1)).passed)
        #expect(!Self.verdict(Self.runs(.shortSmoke, count: 4, misses: 2)).passed)
    }

    /// Stated sensitivity: a miss count rounded up moves the edge of a large row: 3
    /// misses in 60 runs (the allowance's share) pass and a fourth fails.
    @Test
    func largeRowToleratesTheAllowancesShareOfMisses() {
        #expect(Self.verdict(Self.runs(.russianFiller, count: 60, misses: 3)).passed)
        #expect(!Self.verdict(Self.runs(.russianFiller, count: 60, misses: 4)).passed)
    }

    /// Stated sensitivity: skipping the category rows lets one collapsed category hide
    /// under the overall row (3 misses in 60 runs pass overall; the 3 sit in a
    /// category of 4).
    @Test
    func oneCollapsedCategoryFailsTheVerdict() {
        let runs = Self.runs(.russianFiller, count: 56, misses: 0)
            + Self.runs(.shortSmoke, count: 4, misses: 3, offset: 56)
        let result = Self.verdict(runs)

        #expect(result.rows.first?.passed == true)
        #expect(result.rows.first { $0.category == .shortSmoke }?.passed == false)
        #expect(!result.passed)
    }

    /// Stated sensitivity: a row of no runs that passes would let a candidate whose runs
    /// all vanished pass the bar.
    @Test
    func rowWithoutRunsFails() {
        #expect(!Self.verdict([]).passed)
    }

    /// Stated sensitivity: a slack taken from the largest repetition, or from a
    /// coefficient other than its own, leaves these pinned means.
    @Test
    func slackIsTheMeanOverTheRepetitions() {
        let runs = [(0.95, 0.90, 0.50), (0.70, 0.90, 0.50), (0.85, 0.60, 0.80)].map { fuzzy, embedding, jev in
            Self.run("s", .shortSmoke, Self.scores(fuzzy: fuzzy, embedding: embedding, jev: jev))
        }
        let sample = CleanupBenchmarkBar.slack(of: runs)

        #expect(abs(sample.fuzzy.mean - 0.5 / 3) < 1e-9)
        #expect(abs(sample.embedding.mean - 0.2) < 1e-9)
        #expect(abs(sample.jev.mean - 0.4) < 1e-9)
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
    /// entries, erases other models' recorded slack; an encoding with unsorted keys
    /// makes every rewrite a noisy diff.
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
        let encoded = try merged.encoded()
        #expect(encoded == (try merged.encoded()))
        #expect(try CleanupBenchmarkBaselineFile.decode(merged.encoded()) == merged)
    }

    /// Stated sensitivity: an entry built from a run with an empty output, or one a
    /// judge failed on, raises a mean (slack near 1) and loosens the bar on that
    /// sample for good; any such run must refuse the entry.
    @Test
    func entryIsRefusedWhenAnyRunIsIncomplete() throws {
        let settings = try judgeSettings()
        let complete = (1...3).map { Self.run("s\($0)", .shortSmoke, Self.scores()) }
        var empty = Self.run("s4", .shortSmoke, Self.scores(fuzzy: 0, embedding: 0.2, jev: 0.1))
        empty.failures = ["empty-output"]

        #expect(throws: CleanupBenchmarkBarError.incompleteRuns(candidate: "c", count: 1)) {
            try CleanupBenchmarkBar.makeEntry(
                candidateName: "c", runs: complete + [empty], settings: settings, datasetSHA256: "x"
            )
        }
        let entry = try CleanupBenchmarkBar.makeEntry(
            candidateName: "c", runs: complete, settings: settings, datasetSHA256: "x"
        )
        #expect(Set(entry.samples.keys) == ["s1", "s2", "s3"])
        #expect(entry.judgeSHA256 == (try settings.judgeSHA256()))
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
                floors: CleanupBenchmarkJudgeSettings.Bar.Floors(jev: 0.5, embedding: 0.5, fuzzy: 0.5), allowance: 0.5
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
