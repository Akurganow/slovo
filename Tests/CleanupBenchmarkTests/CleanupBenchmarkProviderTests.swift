import Testing

import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark providers")
struct CleanupBenchmarkProviderTests {
    /// Stated sensitivity: if the env-file parser logs or mangles dotenv keys,
    /// benchmark credentials cannot be supplied locally without touching
    /// Keychain; quoted values and comments are the common failure case.
    @Test
    func envFileParserReadsDotenvShapeWithoutComments() {
        let parsed = CleanupBenchmarkEnvFile.parse(
            """
            # local only
            OPENROUTER_API_KEY="openrouter-key"
            EMPTY=
            EXPORT_ME=plain
            """
        )

        #expect(parsed == [
            "OPENROUTER_API_KEY": "openrouter-key",
            "EMPTY": "",
            "EXPORT_ME": "plain",
        ])
    }

    /// Stated sensitivity: drop the `catalog` expansion, or expand it to anything
    /// but the app's catalog in its order → RED.
    @Test
    func catalogProviderExpandsToTheAppCatalog() throws {
        let specs = try CleanupBenchmarkProviderSpec.parseList("catalog,passthrough")

        #expect(specs.dropLast().map(\.model) == CleanupModelCatalog.options.map(\.id))
        #expect(specs.dropLast().allSatisfy { $0.provider == .openRouter })
        #expect(specs.last == CleanupBenchmarkProviderSpec(provider: .passThrough, model: "none"))
    }

    /// Stated sensitivity: if provider selection stays stringly typed, a typo or
    /// direct-provider reintroduction silently benchmarks the wrong cleanup path.
    @Test
    func providerSpecParserPinsOpenRouterModelSelection() throws {
        let specs = try CleanupBenchmarkProviderSpec.parseList(
            "openrouter:openai/gpt-6-luna,passthrough"
        )

        #expect(specs == [
            CleanupBenchmarkProviderSpec(provider: .openRouter, model: "openai/gpt-6-luna"),
            CleanupBenchmarkProviderSpec(provider: .passThrough, model: "none"),
        ])
        for forbidden in [
            "anthropic:claude-test",
            "openai:gpt-test",
            "mlx:mlx-community/Qwen3-4B-4bit",
            "local",
        ] {
            #expect(throws: CleanupBenchmarkProviderSpecError.unknownProvider(forbidden)) {
                try CleanupBenchmarkProviderSpec.parse(forbidden)
            }
        }
        #expect(throws: CleanupBenchmarkProviderSpecError.missingModel(.openRouter)) {
            try CleanupBenchmarkProviderSpec.parse("openrouter")
        }
    }

    /// Stated sensitivity: swapping key names in the real benchmark factory
    /// leaves the CLI benchmarking a provider that the app cannot run.
    @Test
    func candidateFactorySelectsOpenRouterAndKey() throws {
        let environment = [
            "OPENROUTER_API_KEY": "openrouter-key",
        ]

        let openRouter = try CleanupBenchmarkCandidateFactory.makeCandidate(
            for: CleanupBenchmarkProviderSpec(provider: .openRouter, model: "openai/gpt-6-luna"),
            environment: environment
        )
        let passThrough = try CleanupBenchmarkCandidateFactory.makeCandidate(
            for: CleanupBenchmarkProviderSpec(provider: .passThrough, model: "none"),
            environment: [:]
        )

        #expect(openRouter.cleaner is OpenRouterCleaner)
        #expect(passThrough.cleaner is PassThrough)
        #expect(throws: CleanupBenchmarkCandidateFactoryError.missingEnvironmentKey("OPENROUTER_API_KEY")) {
            _ = try CleanupBenchmarkCandidateFactory.makeCandidate(
                for: CleanupBenchmarkProviderSpec(provider: .openRouter, model: "openai/gpt-6-luna"),
                environment: [:]
            )
        }
    }
}
