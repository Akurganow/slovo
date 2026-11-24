import Testing

@testable import CleanupBenchmark

@Suite("Cleanup benchmark bar")
struct CleanupBenchmarkBarTests {
    private static let floors = CleanupBenchmarkJudgeSettings.Bar.Floors(jev: 0.15, embedding: 0.02, fuzzy: 0.05)
    private static let bar = CleanupBenchmarkJudgeSettings.Bar(floors: floors, allowance: 0.05)

    /// Every coefficient has mean slack 0.10, and no spread, so the floors decide.
    private static let slack = CleanupBenchmarkSlack(mean: 0.10, spread: 0)
    private static let flat = CleanupBenchmarkBaselineSample(fuzzy: slack, embedding: slack, jev: slack)

    private static func scores(fuzzy: Double = 0.90, embedding: Double = 0.90, jev: Double = 0.90) -> CleanupBenchmarkScores {
        CleanupBenchmarkScores(fuzzy: fuzzy, embedding: embedding, jev: jev)
    }

    private static func run(_ id: String, _ category: CleanupBenchmarkCategory, _ scores: CleanupBenchmarkScores) -> CleanupBenchmarkRun {
        CleanupBenchmarkRun(
            sampleId: id, sampleCategory: category, candidateName: "c", durationNanoseconds: 1, scores: scores, errorKind: nil
        )
    }

    private static func entry(_ ids: [String]) -> CleanupBenchmarkBaselineEntry {
        CleanupBenchmarkBaselineEntry(
            jevModel: "j", jevSnapshots: [], embeddingModel: "e", embeddingResponseModels: [],
            datasetSHA256: "x", samples: Dictionary(uniqueKeysWithValues: ids.map { ($0, flat) })
        )
    }

    /// Stated sensitivity: ignoring the margin floor (using the spread alone, 0 here)
    /// puts a slack exactly at mean plus floor out of bounds; applying a floor to the
    /// wrong coefficient moves the line for it. Each coefficient sits at its edge,
    /// then one step past it.
    @Test
    func slackIsWithinMeanPlusTheLargerOfSpreadAndFloor() {
        let atEdge = Self.scores(fuzzy: 0.85, embedding: 0.88, jev: 0.75)
        #expect(CleanupBenchmarkBar.isWithinSlack(atEdge, baseline: Self.flat, floors: Self.floors))
        for past in [
            Self.scores(fuzzy: 0.84, embedding: 0.88, jev: 0.75),
            Self.scores(fuzzy: 0.85, embedding: 0.87, jev: 0.75),
            Self.scores(fuzzy: 0.85, embedding: 0.88, jev: 0.74),
        ] {
            #expect(!CleanupBenchmarkBar.isWithinSlack(past, baseline: Self.flat, floors: Self.floors))
        }

        // A spread above the floor widens the margin: 0.30 > 0.15.
        let wide = CleanupBenchmarkBaselineSample(
            fuzzy: Self.slack, embedding: Self.slack, jev: CleanupBenchmarkSlack(mean: 0.10, spread: 0.30)
        )
        #expect(CleanupBenchmarkBar.isWithinSlack(Self.scores(jev: 0.60), baseline: wide, floors: Self.floors))
    }

    /// Stated sensitivity: a run with an unscored coefficient (a judge error) counted
    /// as within slack would let a candidate pass on outputs nobody judged.
    @Test
    func unscoredRunIsNotWithinSlack() {
        let unscored = CleanupBenchmarkScores(fuzzy: 1, embedding: 1, jev: nil)
        #expect(!CleanupBenchmarkBar.isWithinSlack(unscored, baseline: Self.flat, floors: Self.floors))
    }

    /// Stated sensitivity: skipping the category check lets one collapsed category
    /// hide under the overall share (19 of 20 runs); a missing allowance fails 19 of 20.
    @Test
    func candidatePassesOnShareOverallAndInEveryCategory() {
        let ids = (0..<20).map { "s\($0)" }
        let entry = Self.entry(ids)
        let good = Self.scores()
        let bad = Self.scores(jev: 0.1)

        var oneCategoryCollapsed = ids.dropFirst().map { Self.run($0, .russianFiller, good) }
        oneCategoryCollapsed.append(Self.run(ids[0], .shortSmoke, bad))
        let collapsed = CleanupBenchmarkBar.verdict(
            candidateName: "c", baselineName: "b", runs: oneCategoryCollapsed, entry: entry, settings: Self.bar
        )
        #expect(collapsed.rows.first?.passed == true)
        #expect(collapsed.rows.first?.withinSlack == 19)
        #expect(collapsed.rows.first { $0.category == .shortSmoke }?.passed == false)
        #expect(!collapsed.passed)

        // Both categories hold 95%: 19 of 20 in one, 20 of 20 in the other: passes.
        var spread = ids.map { Self.run($0, .russianFiller, good) }
        spread[0] = Self.run(ids[0], .russianFiller, bad)
        let passing = CleanupBenchmarkBar.verdict(
            candidateName: "c", baselineName: "b", runs: spread, entry: entry, settings: Self.bar
        )
        #expect(passing.passed)

        // 18 of 20 is below 95%.
        var tooMany = spread
        tooMany[1] = Self.run(ids[1], .russianFiller, bad)
        #expect(!CleanupBenchmarkBar.verdict(
            candidateName: "c", baselineName: "b", runs: tooMany, entry: entry, settings: Self.bar
        ).passed)
    }

    /// Stated sensitivity: the baseline's own runs are within slack by construction
    /// (the spread is never below a run's distance from the mean); if `slack(of:)`
    /// took the spread from anything smaller, the baseline would fail its own bar.
    @Test
    func baselineRunsAreWithinTheirOwnSlack() throws {
        let runs = [0.95, 0.70, 0.85].map { Self.run("s", .shortSmoke, Self.scores(fuzzy: $0, embedding: $0, jev: $0)) }
        let sample = try #require(CleanupBenchmarkBar.slack(of: runs))

        #expect(abs(sample.jev.mean - 0.5 / 3) < 1e-9)
        #expect(abs(sample.jev.spread - 0.25) < 1e-9)
        for run in runs {
            #expect(CleanupBenchmarkBar.isWithinSlack(
                run.scores, baseline: sample, floors: CleanupBenchmarkJudgeSettings.Bar.Floors(jev: 0, embedding: 0, fuzzy: 0)
            ))
        }
        #expect(CleanupBenchmarkBar.slack(of: runs + [Self.run("s", .shortSmoke, CleanupBenchmarkScores(fuzzy: 1))]) == nil)
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
}
