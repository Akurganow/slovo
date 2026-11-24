import Foundation

/// The opt-in `--outputs-file`: one JSON line per run, for reading a candidate's
/// actual outputs next to their scores. It holds output text, so it stays local.
enum CleanupBenchmarkOutputsFile {
    private struct Line: Encodable {
        let sample: Int
        let candidate: String
        let repetition: Int
        let output: String?
        let fuzzy: Double?
        let embedding: Double?
        let jev: Double?
        let jevQuestions: [String: [Double]]
        let judgeErrors: [String]

        enum CodingKeys: String, CodingKey {
            case sample, candidate, repetition, output, fuzzy, embedding, jev, jevQuestions, judgeErrors
        }

        /// A missing value is written as null, never left out.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sample, forKey: .sample)
            try container.encode(candidate, forKey: .candidate)
            try container.encode(repetition, forKey: .repetition)
            try container.encode(output, forKey: .output)
            try container.encode(fuzzy, forKey: .fuzzy)
            try container.encode(embedding, forKey: .embedding)
            try container.encode(jev, forKey: .jev)
            try container.encode(jevQuestions, forKey: .jevQuestions)
            try container.encode(judgeErrors, forKey: .judgeErrors)
        }
    }

    static func encode(_ runs: [CleanupBenchmarkRun]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = try runs.map { run -> String in
            let line = Line(
                sample: run.sampleIndex,
                candidate: run.candidateName,
                repetition: run.repetition,
                output: run.output,
                fuzzy: run.scores.fuzzy,
                embedding: run.scores.embedding,
                jev: run.scores.jev,
                jevQuestions: run.scores.jevQuestions,
                judgeErrors: run.scores.judgeErrors
            )
            return String(decoding: try encoder.encode(line), as: UTF8.self)
        }
        return Data(lines.map { $0 + "\n" }.joined().utf8)
    }
}
