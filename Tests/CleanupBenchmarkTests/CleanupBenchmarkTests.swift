import Foundation
import Synchronization
import Testing

import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark harness")
struct CleanupBenchmarkTests {
    /// Stated sensitivity: a pass-through cleaner must not pass quality just
    /// because it is fast; the gate must catch filler words, missing casing, and
    /// missing punctuation without comparing the full answer byte-for-byte.
    @Test
    func qualityGateRejectsPassThroughAndChatResponses() {
        let sample = CleanupBenchmarkSample(
            id: "mixed-ru-en-fillers",
            raw: "ну вот запушь pr в github пожалуйста",
            expectation: CleanupQualityExpectation(
                requiredSubstrings: ["PR", "GitHub"],
                forbiddenSubstrings: ["ну", "вот"]
            )
        )

        let passThrough = CleanupQualityGate.evaluate(output: sample.raw, sample: sample)
        #expect(!passThrough.passed)
        #expect(passThrough.failures.contains("forbidden-substring:ну"))
        #expect(passThrough.failures.contains("required-substring:PR"))
        #expect(passThrough.failures.contains("terminal-punctuation"))

        let chatResponse = CleanupQualityGate.evaluate(
            output: "I'm not sure what you would like me to do with this transcript.",
            sample: sample
        )
        #expect(!chatResponse.passed)
        #expect(chatResponse.failures.contains("chat-response"))

        let wrapped = CleanupQualityGate.evaluate(
            output: "Sure: Запушь PR в GitHub, пожалуйста.",
            sample: sample
        )
        #expect(!wrapped.passed)
        #expect(wrapped.failures.contains("chat-response"))

        let cleaned = CleanupQualityGate.evaluate(
            output: "Запушь PR в GitHub, пожалуйста.",
            sample: sample
        )
        #expect(cleaned.passed)
    }

    /// Stated sensitivity: a cleanup output that keeps a long dictated stream as
    /// one run-on sentence must fail even when it preserves terms and punctuation.
    @Test
    func qualityGateCanRequireSentenceStructure() {
        let sample = CleanupBenchmarkSample(
            id: "run-on",
            raw: "сначала проверь cleanup потом запусти тесты потом открой pull request",
            expectation: CleanupQualityExpectation(
                requiredSubstrings: ["cleanup", "pull request"],
                minimumSentenceTerminators: 2
            )
        )

        let runOn = CleanupQualityGate.evaluate(
            output: "Сначала проверь cleanup, потом запусти тесты, потом открой pull request.",
            sample: sample
        )
        #expect(!runOn.passed)
        #expect(runOn.failures.contains("sentence-structure"))

        let structured = CleanupQualityGate.evaluate(
            output: "Сначала проверь cleanup. Потом запусти тесты. Потом открой pull request.",
            sample: sample
        )
        #expect(structured.passed)
    }

    /// Stated sensitivity: a runner that times only one provider, reuses one
    /// provider output for all candidates, skips samples, or compares providers
    /// in candidate-major batches will miss the recorded interleaved call matrix.
    @Test
    func runnerInvokesEveryCandidateForEverySampleAndRecordsTiming() async {
        let samples = [
            CleanupBenchmarkSample(
                id: "one",
                raw: "ну проверь pr",
                expectation: CleanupQualityExpectation(requiredSubstrings: ["PR"], forbiddenSubstrings: ["ну"])
            ),
            CleanupBenchmarkSample(
                id: "two",
                raw: "вот github работает",
                expectation: CleanupQualityExpectation(requiredSubstrings: ["GitHub"], forbiddenSubstrings: ["вот"])
            ),
        ]
        let first = RecordingCleaner(output: "Проверь PR.")
        let second = RecordingCleaner(output: "GitHub работает.")
        let durations = Mutex<[UInt64]>([10, 20, 30, 40])
        let timer = CleanupBenchmarkTimer { operation in
            let output = try await operation()
            let duration = durations.withLock { $0.removeFirst() }
            return TimedCleanupOutput(output: output, durationNanoseconds: duration)
        }

        let report = await CleanupBenchmarkRunner(timer: timer).run(
            candidates: [
                CleanupBenchmarkCandidate(provider: "fake-a", model: "a", cleaner: first),
                CleanupBenchmarkCandidate(provider: "fake-b", model: "b", cleaner: second),
            ],
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(report.runs.map(\.durationNanoseconds) == [10, 20, 30, 40])
        #expect(report.runs.map(\.sampleId) == ["one", "one", "two", "two"])
        #expect(report.runs.map(\.candidateName) == ["fake-a:a", "fake-b:b", "fake-a:a", "fake-b:b"])
        #expect(await first.rawInputs() == ["ну проверь pr", "вот github работает"])
        #expect(await second.rawInputs() == ["ну проверь pr", "вот github работает"])
        #expect(await first.modelInputs() == ["a", "a"])
        #expect(await second.modelInputs() == ["b", "b"])
    }

    /// Stated sensitivity: if the env-file parser logs or mangles dotenv keys,
    /// benchmark credentials cannot be supplied locally without touching
    /// Keychain; quoted values and comments are the common failure case.
    @Test
    func envFileParserReadsDotenvShapeWithoutComments() {
        let parsed = CleanupBenchmarkEnvFile.parse(
            """
            # local only
            ANTHROPIC_API_KEY='anthropic-key'
            OPENAI_API_KEY="openai-key"
            EMPTY=
            EXPORT_ME=plain
            """
        )

        #expect(parsed == [
            "ANTHROPIC_API_KEY": "anthropic-key",
            "OPENAI_API_KEY": "openai-key",
            "EMPTY": "",
            "EXPORT_ME": "plain",
        ])
    }

    /// Stated sensitivity: if provider selection stays stringly typed, a typo or
    /// missing model silently benchmarks the wrong cleanup path.
    @Test
    func providerSpecParserPinsProviderAndModelSelection() throws {
        let specs = try CleanupBenchmarkProviderSpec.parseList(
            "anthropic:claude-test,openai:gpt-test,passthrough"
        )

        #expect(specs == [
            CleanupBenchmarkProviderSpec(provider: .anthropic, model: "claude-test"),
            CleanupBenchmarkProviderSpec(provider: .openAI, model: "gpt-test"),
            CleanupBenchmarkProviderSpec(provider: .passThrough, model: "none"),
        ])
        #expect(throws: CleanupBenchmarkProviderSpecError.unknownProvider("local")) {
            try CleanupBenchmarkProviderSpec.parse("local")
        }
        #expect(throws: CleanupBenchmarkProviderSpecError.missingModel(.anthropic)) {
            try CleanupBenchmarkProviderSpec.parse("anthropic")
        }
        #expect(throws: CleanupBenchmarkProviderSpecError.missingModel(.openAI)) {
            try CleanupBenchmarkProviderSpec.parse("openai")
        }
    }

    /// Stated sensitivity: swapping cloud cleaners or key names in the real
    /// benchmark factory leaves the CLI benchmarking a different provider.
    @Test
    func candidateFactorySelectsConcreteProviderAndKey() throws {
        let environment = [
            "ANTHROPIC_API_KEY": "anthropic-key",
            "OPENAI_API_KEY": "openai-key",
        ]

        let anthropic = try CleanupBenchmarkCandidateFactory.makeCandidate(
            for: CleanupBenchmarkProviderSpec(provider: .anthropic, model: "claude-test"),
            environment: environment
        )
        let openAI = try CleanupBenchmarkCandidateFactory.makeCandidate(
            for: CleanupBenchmarkProviderSpec(provider: .openAI, model: "gpt-test"),
            environment: environment
        )
        let passThrough = try CleanupBenchmarkCandidateFactory.makeCandidate(
            for: CleanupBenchmarkProviderSpec(provider: .passThrough, model: "none"),
            environment: [:]
        )

        #expect(anthropic.cleaner is AnthropicCleaner)
        #expect(openAI.cleaner is OpenAICleaner)
        #expect(passThrough.cleaner is PassThrough)
        #expect(throws: CleanupBenchmarkCandidateFactoryError.missingEnvironmentKey("ANTHROPIC_API_KEY")) {
            _ = try CleanupBenchmarkCandidateFactory.makeCandidate(
                for: CleanupBenchmarkProviderSpec(provider: .anthropic, model: "claude-test"),
                environment: ["OPENAI_API_KEY": "openai-key"]
            )
        }
        #expect(throws: CleanupBenchmarkCandidateFactoryError.missingEnvironmentKey("OPENAI_API_KEY")) {
            _ = try CleanupBenchmarkCandidateFactory.makeCandidate(
                for: CleanupBenchmarkProviderSpec(provider: .openAI, model: "gpt-test"),
                environment: ["ANTHROPIC_API_KEY": "anthropic-key"]
            )
        }
    }

    /// Stated sensitivity: breaking the CLI exit decision or bypassing argument
    /// parsing leaves the executable path green while the library pieces pass.
    @Test
    func commandDriverRunsCliPathAndReturnsQualityFailureExit() async {
        let result = await CleanupBenchmarkCommandDriver().run(
            arguments: ["--providers", "passthrough"],
            environment: [:]
        )

        #expect(result.exitCode == 2)
        #expect(result.stdout.contains("passthrough:none"))
        #expect(result.stderr.isEmpty)
    }

    /// Stated sensitivity: a thin executable wrapper can silently bypass the
    /// testable command driver unless the production entrypoint is guarded too.
    @Test
    func executableEntrypointDelegatesToCommandDriver() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appending(path: "Tools/cleanup-benchmark-cli/main.swift"),
            encoding: .utf8
        )

        #expect(source.contains("import CleanupBenchmark"))
        #expect(!source.contains("import SlovoCore"))
        #expect(source.contains("CleanupBenchmarkCommandDriver().run("))
        #expect(source.contains("Array(CommandLine.arguments.dropFirst())"))
        #expect(source.contains("ProcessInfo.processInfo.environment"))
        #expect(source.contains("print(result.stdout)"))
        #expect(source.contains("fputs(result.stderr, stderr)"))
        #expect(source.contains("Foundation.exit(result.exitCode)"))
    }

    /// Stated sensitivity: source-shape checks alone can leave a broken
    /// executable green if the real entrypoint exits before running the driver.
    @Test
    func executableEntrypointRunsBenchmarkCommand() throws {
        let scratch = NSTemporaryDirectory() + "slovo-cleanup-benchmark-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: scratch) }

        let result = try runSwift(
            [
                "run",
                "--disable-automatic-resolution",
                "--scratch-path",
                scratch,
                "slovo-cleanup-benchmark",
                "--providers",
                "passthrough",
            ]
        )

        #expect(result.exitCode == 2)
        #expect(result.stdout.contains("candidate,runs,passed,errors,p50_ms,p95_ms"))
        #expect(result.stdout.contains("passthrough:none,30,"))
    }

    /// Stated sensitivity: changing the command driver to exit non-zero even
    /// when every run passes is not caught by lower-level runner tests.
    @Test
    func commandDriverReturnsSuccessWhenEveryRunPasses() async {
        let driver = CleanupBenchmarkCommandDriver(runBenchmark: { candidates, _, _, _, _ in
            CleanupBenchmarkReport(runs: [
                CleanupBenchmarkRun(
                    sampleId: "hidden",
                    candidateName: candidates[0].name,
                    durationNanoseconds: 1_000_000,
                    quality: CleanupQualityResult(passed: true, failures: []),
                    errorKind: nil
                ),
            ])
        })

        let result = await driver.run(arguments: ["--providers", "passthrough"], environment: [:])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("passthrough:none"))
        #expect(result.stderr.isEmpty)
    }

    /// Stated sensitivity: raw transcripts, cleaned text, sample ids, and raw
    /// provider errors must not reach the rendered benchmark report.
    @Test
    func reportFormatterShowsMetricsWithoutPayloadText() {
        let report = CleanupBenchmarkReport(runs: [
            CleanupBenchmarkRun(
                sampleId: "sample-secret",
                candidateName: "openai:gpt-test",
                durationNanoseconds: 12_000_000,
                quality: CleanupQualityResult(passed: true, failures: []),
                errorKind: nil
            ),
        ])

        let rendered = CleanupBenchmarkReportFormatter.render(report)

        #expect(rendered.contains("openai:gpt-test"))
        #expect(rendered.contains("p50_ms"))
        #expect(!rendered.contains("raw"))
        #expect(!rendered.contains("cleaned"))
        #expect(!rendered.contains("sample-secret"))
    }

    /// Stated sensitivity: if the runner stores `String(describing: error)`, a
    /// provider error can persist payload text even when the formatter hides it.
    @Test
    func runnerStoresCoarseErrorKindOnly() async {
        let sample = CleanupBenchmarkSample(
            id: "sensitive-sample",
            raw: "S3NT1NEL-RAW",
            expectation: CleanupQualityExpectation()
        )
        let report = await CleanupBenchmarkRunner().run(
            candidates: [
                CleanupBenchmarkCandidate(
                    provider: "fake",
                    model: "throwing",
                    cleaner: ThrowingSensitiveCleaner()
                ),
            ],
            samples: [sample],
            config: CleanupConfig(model: "unused", writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(report.runs.map(\.errorKind) == [.providerError])
        #expect(report.runs.map(\.quality.failures) == [["provider-error"]])
        #expect(report.runs.map(\.sampleId) == ["sensitive-sample"])
        #expect(!String(describing: report.runs).contains("S3NT1NEL"))
        let rendered = CleanupBenchmarkReportFormatter.render(report)
        #expect(!rendered.contains("S3NT1NEL"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func runSwift(_ arguments: [String]) throws -> CommandResult {
        let captureDirectory = FileManager.default.temporaryDirectory
            .appending(path: "slovo-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: captureDirectory) }

        let outputURL = captureDirectory.appending(path: "stdout.txt")
        let errorURL = captureDirectory.appending(path: "stderr.txt")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: errorURL.path, contents: nil)

        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer {
            try? output.close()
            try? errors.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift"] + arguments
        process.currentDirectoryURL = repositoryRoot()
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: try String(contentsOf: outputURL, encoding: .utf8),
            stderr: try String(contentsOf: errorURL, encoding: .utf8)
        )
    }
}

private struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
