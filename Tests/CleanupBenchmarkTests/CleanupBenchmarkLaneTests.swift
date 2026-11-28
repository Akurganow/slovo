import Testing

@testable import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark lanes")
struct CleanupBenchmarkLaneTests {
    /// Stated sensitivity: a lane that ignores its width starts every call at once and reaches more than
    /// 3 in flight on nearly every run (the calls are held across 20 yields) → RED; a runner that makes
    /// fewer than 3 calls at a time never opens the gate, which needs 3 in flight, so the time limit
    /// ends the test → RED. The gate opens on a count, never on time, so a runner that honours the
    /// width never waits on the clock.
    @Test(.timeLimit(.minutes(1)))
    func laneRunsUpToItsWidthOfCallsAtOnce() async {
        let samples = (1...5).map { CleanupBenchmarkSample(id: "s\($0)", raw: "Hello.", references: ["Hello."]) }
        let flight = FlightCounter()
        let gate = Gate()
        let candidate = CleanupBenchmarkCandidate(provider: "fake", model: "wide", lane: "wide", width: 3) { raw, _, _, _ in
            if flight.enter() == 3 {
                gate.open()
            }
            await gate.wait()
            await FlightCounter.hold()
            flight.leave()
            return CleanupBenchmarkCleaned(text: raw)
        }

        let report = await CleanupBenchmarkRunner().run(
            candidates: [candidate], samples: samples, config: CleanupConfig(model: "unused", writingStyle: .casual)
        )

        #expect(flight.peak == 3)
        #expect(report.runs.map(\.sampleId) == ["s1", "s2", "s3", "s4", "s5"])
    }

    /// Stated sensitivity: a lane key taken from the candidate name for a candidate made by hand
    /// lets two candidates of one provider overlap, so 2 are in flight → RED. The overlap is
    /// detected, not guaranteed: the calls are held across 20 yields, so a runner that overlaps them
    /// is caught on nearly every run, and a runner that keeps the lane never fails.
    @Test
    func candidatesOfOneProviderShareALaneOfOneCallAtATime() async {
        let samples = (1...3).map { CleanupBenchmarkSample(id: "s\($0)", raw: "Hello.", references: ["Hello."]) }
        let flight = FlightCounter()
        func candidate(_ model: String) -> CleanupBenchmarkCandidate {
            CleanupBenchmarkCandidate(provider: "fake", model: model) { raw, _, _, _ in
                _ = flight.enter()
                await FlightCounter.hold()
                flight.leave()
                return CleanupBenchmarkCleaned(text: raw)
            }
        }

        let report = await CleanupBenchmarkRunner().run(
            candidates: [candidate("a"), candidate("b")],
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            repetitions: 2
        )

        #expect(flight.peak == 1)
        #expect(report.runs.count == 12)
    }

    /// Stated sensitivity: a lane narrowed only by a candidate that still has a call to make leaves
    /// the lane at the width of `fake:b`, whose 6 calls then overlap, so 6 are in flight → RED.
    /// The overlap is detected, not guaranteed: the calls are held across 20 yields.
    @Test
    func aCandidateWithEveryRunKeptStillNarrowsItsLane() async {
        let samples = (1...3).map { CleanupBenchmarkSample(id: "s\($0)", raw: "Hello.", references: ["Hello."]) }
        let flight = FlightCounter()
        let kept = CleanupBenchmarkCandidate(provider: "fake", model: "a", lane: "x", width: 1) { _, _, _, _ in
            Issue.record("fake:a has every run kept and must make no call")
            return CleanupBenchmarkCleaned(text: "")
        }
        let wide = CleanupBenchmarkCandidate(provider: "fake", model: "b", lane: "x", width: 8) { raw, _, _, _ in
            _ = flight.enter()
            await FlightCounter.hold()
            flight.leave()
            return CleanupBenchmarkCleaned(text: raw)
        }
        let previous = Dictionary(uniqueKeysWithValues: (1...2).flatMap { repetition in
            samples.map { sample in
                let run = CleanupBenchmarkRun(
                    sampleId: sample.id, candidateName: "fake:a", repetition: repetition,
                    durationNanoseconds: 1, output: "Hello.", errorKind: nil
                )
                return (run.key, run)
            }
        })

        let report = await CleanupBenchmarkRunner().run(
            candidates: [kept, wide],
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            repetitions: 2,
            previous: previous
        )

        #expect(flight.peak == 1)
        #expect(report.runs.count == 12)
    }

    /// Stated sensitivity: one lane for every candidate makes the first call of `fake:a` wait for a
    /// start of `fake:b` that cannot come before it ends, so the time limit ends the test → RED.
    /// The first call of `fake:b` opens the gate on its start, never on time.
    @Test(.timeLimit(.minutes(1)))
    func candidatesOfDistinctLanesRunAtOnce() async {
        let sample = CleanupBenchmarkSample(id: "s", raw: "Hello.", references: ["Hello."])
        let gate = Gate()
        let first = CleanupBenchmarkCandidate(provider: "fake", model: "a", lane: "x") { raw, _, _, _ in
            await gate.wait()
            return CleanupBenchmarkCleaned(text: raw)
        }
        let second = CleanupBenchmarkCandidate(provider: "fake", model: "b", lane: "y") { raw, _, _, _ in
            gate.open()
            return CleanupBenchmarkCleaned(text: raw)
        }

        let report = await CleanupBenchmarkRunner().run(
            candidates: [first, second], samples: [sample], config: CleanupConfig(model: "unused", writingStyle: .casual)
        )

        #expect(report.runs.map(\.candidateName) == ["fake:a", "fake:b"])
    }
}
