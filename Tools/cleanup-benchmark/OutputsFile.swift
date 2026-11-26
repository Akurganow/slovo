import Foundation
import SlovoCore
import Synchronization

/// The opt-in `--outputs-file`: append-only JSON Lines, one line each time a run
/// finishes its cleanup and each time it is judged. It holds output text, so it
/// stays local, and it is the resume record: for each run the last line wins. Each
/// line carries what it was written under (`CleanupBenchmarkOutputsBinding`).
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
        /// Optional so that a line written before it existed decodes, with no cost.
        let costUSD: Double?
        /// Optional so that a line without one, such as one written before it existed,
        /// decodes and is refused.
        let rawsSHA256: String?
        let promptSHA256: String?
        let scoringSHA256: String?
        let jevSHA256: String?
        let style: String?

        init(_ run: CleanupBenchmarkRun, binding: CleanupBenchmarkOutputsBinding) {
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
            costUSD = run.costUSD
            rawsSHA256 = binding.rawsSHA256
            promptSHA256 = binding.promptSHA256
            scoringSHA256 = binding.scoringSHA256(sampleId: run.sampleId)
            jevSHA256 = binding.jevSHA256(sampleId: run.sampleId)
            style = binding.style.rawValue
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
            try container.encode(costUSD, forKey: .costUSD)
            try container.encode(rawsSHA256, forKey: .rawsSHA256)
            try container.encode(promptSHA256, forKey: .promptSHA256)
            try container.encode(scoringSHA256, forKey: .scoringSHA256)
            try container.encode(jevSHA256, forKey: .jevSHA256)
            try container.encode(style, forKey: .style)
        }
    }

    static func line(_ run: CleanupBenchmarkRun, binding: CleanupBenchmarkOutputsBinding) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Line(run, binding: binding)) + Data("\n".utf8)
    }

    /// The last line of each run, as a run. A line that does not decode is the one a
    /// killed process left half written: its run is simply done again. A line written
    /// for other ids or raws, or by another style, refuses the file. A line scored under
    /// other judge settings or references keeps its output and loses its judge scores. The
    /// fuzzy score is computed again from the output, against the current references.
    static func resume(
        from data: Data,
        samples: [CleanupBenchmarkSample],
        binding: CleanupBenchmarkOutputsBinding
    ) throws -> [CleanupBenchmarkRunKey: CleanupBenchmarkRun] {
        var runs: [CleanupBenchmarkRunKey: CleanupBenchmarkRun] = [:]
        for text in data.split(separator: UInt8(ascii: "\n")) {
            guard let line = try? JSONDecoder().decode(Line.self, from: text) else { continue }
            guard line.rawsSHA256 == binding.rawsSHA256 else {
                throw CleanupBenchmarkCommandError.outputsFileDatasetMismatch
            }
            guard line.style == binding.style.rawValue else {
                throw CleanupBenchmarkCommandError.outputsFileStyleMismatch(line.style ?? "unrecorded")
            }
            guard line.promptSHA256 == binding.promptSHA256 else {
                throw CleanupBenchmarkCommandError.outputsFilePromptMismatch
            }
            // With the dataset file unchanged this only guards a line made by hand.
            guard line.sample >= 1, line.sample <= samples.count, samples[line.sample - 1].id == line.sampleId else {
                throw CleanupBenchmarkCommandError.outputsFileDatasetMismatch
            }
            let sample = samples[line.sample - 1]
            let otherScoring = binding.judgeSHA256 != nil && line.scoringSHA256 != nil
                && line.scoringSHA256 != binding.scoringSHA256(sampleId: line.sampleId)
            let fuzzy = line.output.map { FuzzyScore.best($0, sample.references) }
            // Jev reads the dictation, the first reference and the output only, so a change of the
            // other references keeps its scores and leaves just the embedding to do again.
            let jevHeld = line.jevSHA256 != nil && line.jevSHA256 == binding.jevSHA256(sampleId: line.sampleId)
            let run = CleanupBenchmarkRun(
                sampleId: line.sampleId,
                sampleCategory: sample.category,
                sampleIndex: line.sample,
                candidateName: line.candidate,
                repetition: line.repetition,
                durationNanoseconds: line.durationNanoseconds,
                output: line.output,
                scores: CleanupBenchmarkScores(
                    fuzzy: fuzzy,
                    embedding: otherScoring ? nil : line.embedding,
                    jev: otherScoring && !jevHeld ? nil : line.jev,
                    jevQuestions: otherScoring && !jevHeld ? [:] : line.jevQuestions,
                    models: otherScoring && !jevHeld ? [] : line.models
                ),
                failures: line.failures,
                costUSD: line.costUSD,
                errorKind: line.output == nil ? .providerError : nil
            )
            runs[run.key] = run
        }
        return runs
    }
}

/// What every line of the outputs file was written under. A resume refuses a file
/// written for other ids or raws (the cleanup output depends on nothing else of the
/// dataset), under another cleanup prompt or by another style. A line scored under other
/// judge settings or other references (nil without `--judge`) is judged again, or only
/// embedded again when just its alternative references changed.
struct CleanupBenchmarkOutputsBinding: Sendable {
    let rawsSHA256: String
    /// The system message every candidate is sent for `style`: the instruction block, with no
    /// vocabulary and no hints, which the benchmark never passes.
    let promptSHA256: String
    let judgeSHA256: String?
    let style: WritingStyle
    /// By sample id.
    let references: [String: [String]]

    init(samples: [CleanupBenchmarkSample], judgeSHA256: String?, style: WritingStyle) {
        rawsSHA256 = CleanupBenchmarkDigest.sha256(of: samples.flatMap { [$0.id, $0.raw] })
        let prompt = PromptBuilder().buildPrompt(
            raw: "", config: CleanupConfig(writingStyle: style), context: PersonalizationContext(vocabulary: [])
        )
        promptSHA256 = CleanupBenchmarkDigest.sha256(Data(prompt.systemText.utf8))
        self.judgeSHA256 = judgeSHA256
        self.style = style
        references = Dictionary(samples.map { ($0.id, $0.references) }, uniquingKeysWith: { first, _ in first })
    }

    /// What Jev scored a line under: the judge settings and the sample's first reference.
    func jevSHA256(sampleId: String) -> String? {
        guard let judgeSHA256, let expected = references[sampleId]?.first else { return nil }
        return CleanupBenchmarkDigest.sha256(of: [judgeSHA256, expected])
    }

    /// What scored a line: the judge settings and the sample's references.
    func scoringSHA256(sampleId: String) -> String? {
        guard let judgeSHA256, let references = references[sampleId] else { return nil }
        return CleanupBenchmarkDigest.sha256(of: [judgeSHA256] + references)
    }
}

/// Appends each finished run to the outputs file. A failed append is kept, once,
/// to be reported with the run's report; the benchmark goes on.
final class CleanupBenchmarkOutputsRecorder: Sendable {
    private let binding: CleanupBenchmarkOutputsBinding
    private let append: @Sendable (Data) throws -> Void
    private let firstError = Mutex<String?>(nil)

    init(binding: CleanupBenchmarkOutputsBinding, append: @escaping @Sendable (Data) throws -> Void) {
        self.binding = binding
        self.append = append
    }

    func record(_ run: CleanupBenchmarkRun) {
        do {
            try append(try CleanupBenchmarkOutputsFile.line(run, binding: binding))
        } catch {
            firstError.withLock { $0 = $0 ?? "outputs file not written: \(error)" }
        }
    }

    var error: String? {
        firstError.withLock { $0 }
    }
}
