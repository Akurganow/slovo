import Foundation
import Synchronization

/// The opt-in `--outputs-file`: append-only JSON Lines, one line each time a run
/// finishes its cleanup and each time it is judged. It holds output text, so it
/// stays local, and it is the resume record: for each run the last line wins.
enum CleanupBenchmarkOutputsFile {
    private struct Line: Codable {
        let sample: Int
        let sampleId: String
        let candidate: String
        let repetition: Int
        let output: String?
        let durationNanoseconds: UInt64
        let fuzzy: Double?
        let embedding: Double?
        let jev: Double?
        let jevQuestions: [String: [Double]]
        let models: [String]
        let failures: [String]

        init(_ run: CleanupBenchmarkRun) {
            sample = run.sampleIndex
            sampleId = run.sampleId
            candidate = run.candidateName
            repetition = run.repetition
            output = run.output
            durationNanoseconds = run.durationNanoseconds
            fuzzy = run.scores.fuzzy
            embedding = run.scores.embedding
            jev = run.scores.jev
            jevQuestions = run.scores.jevQuestions
            models = run.scores.models
            failures = run.failures
        }

        /// A missing value is written as null, never left out.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sample, forKey: .sample)
            try container.encode(sampleId, forKey: .sampleId)
            try container.encode(candidate, forKey: .candidate)
            try container.encode(repetition, forKey: .repetition)
            try container.encode(output, forKey: .output)
            try container.encode(durationNanoseconds, forKey: .durationNanoseconds)
            try container.encode(fuzzy, forKey: .fuzzy)
            try container.encode(embedding, forKey: .embedding)
            try container.encode(jev, forKey: .jev)
            try container.encode(jevQuestions, forKey: .jevQuestions)
            try container.encode(models, forKey: .models)
            try container.encode(failures, forKey: .failures)
        }
    }

    static func line(_ run: CleanupBenchmarkRun) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Line(run)) + Data("\n".utf8)
    }

    /// The last line of each run, as a run. A line that does not decode is the one a
    /// killed process left half written: its run is simply done again. A line naming
    /// a sample the dataset does not have, or at another position, refuses the file.
    static func resume(
        from data: Data,
        samples: [CleanupBenchmarkSample]
    ) throws -> [CleanupBenchmarkRunKey: CleanupBenchmarkRun] {
        var runs: [CleanupBenchmarkRunKey: CleanupBenchmarkRun] = [:]
        for text in data.split(separator: UInt8(ascii: "\n")) {
            guard let line = try? JSONDecoder().decode(Line.self, from: text) else { continue }
            guard line.sample >= 1, line.sample <= samples.count, samples[line.sample - 1].id == line.sampleId else {
                throw CleanupBenchmarkCommandError.outputsFileDatasetMismatch
            }
            let run = CleanupBenchmarkRun(
                sampleId: line.sampleId,
                sampleCategory: samples[line.sample - 1].category,
                sampleIndex: line.sample,
                candidateName: line.candidate,
                repetition: line.repetition,
                durationNanoseconds: line.durationNanoseconds,
                output: line.output,
                scores: CleanupBenchmarkScores(
                    fuzzy: line.fuzzy,
                    embedding: line.embedding,
                    jev: line.jev,
                    jevQuestions: line.jevQuestions,
                    models: line.models
                ),
                failures: line.failures,
                errorKind: line.output == nil ? .providerError : nil
            )
            runs[run.key] = run
        }
        return runs
    }
}

/// Appends each finished run to the outputs file. A failed append is kept, once,
/// to be reported with the run's report; the benchmark goes on.
final class CleanupBenchmarkOutputsRecorder: Sendable {
    private let append: @Sendable (Data) throws -> Void
    private let firstError = Mutex<String?>(nil)

    init(append: @escaping @Sendable (Data) throws -> Void) {
        self.append = append
    }

    func record(_ run: CleanupBenchmarkRun) {
        do {
            try append(try CleanupBenchmarkOutputsFile.line(run))
        } catch {
            firstError.withLock { $0 = $0 ?? "outputs file not written: \(error)" }
        }
    }

    var error: String? {
        firstError.withLock { $0 }
    }
}
