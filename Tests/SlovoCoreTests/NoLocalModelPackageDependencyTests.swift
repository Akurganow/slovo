import Foundation
import Testing

@Suite("No local cleanup model package dependency")
struct NoLocalModelPackageDependencyTests {
    /// Stated sensitivity: reintroduce any embedded MLX/Hugging Face cleanup
    /// dependency or target -> the package source guard goes RED before runtime.
    @Test
    func packageDoesNotLinkLocalCleanupRuntime() throws {
        let source = try String(contentsOf: Self.packageRoot.appending(path: "Package.swift"), encoding: .utf8)

        for forbidden in [
            "SlovoLocalModels",
            "mlx-swift-lm",
            "swift-huggingface",
            "swift-transformers",
            "MLXLLM",
            "MLXLMCommon",
            "MLXHuggingFace",
            "HuggingFace",
            "Tokenizers",
        ] {
            #expect(!source.contains(forbidden), "Package.swift must not contain \(forbidden)")
        }
    }

    /// Stated sensitivity: leaving the local runtime source in the tree lets it
    /// be re-linked accidentally without an obvious package diff.
    @Test
    func localCleanupRuntimeSourceIsAbsent() {
        #expect(!FileManager.default.fileExists(atPath: Self.packageRoot.appending(path: "Sources/SlovoLocalModels").path))
    }

    /// Stated sensitivity: leaving direct provider source files in the tree
    /// lets a future menu/config edit re-enable bypassing OpenRouter.
    @Test
    func directCleanupProviderSourcesAreAbsent() {
        for path in [
            "Sources/SlovoCore/Cleaner/AnthropicCleaner.swift",
            "Sources/SlovoCore/Cleaner/AnthropicKeyProvider.swift",
            "Sources/SlovoCore/Cleaner/AnthropicRequest.swift",
            "Sources/SlovoCore/Cleaner/KeychainAnthropicKeyProvider.swift",
            "Sources/SlovoCore/Cleaner/OpenAICleaner.swift",
            "Sources/SlovoCore/Cleaner/OpenAIKeyProvider.swift",
            "Sources/SlovoCore/Cleaner/OpenAIRequest.swift",
            "Sources/SlovoCore/Cleaner/KeychainOpenAIKeyProvider.swift",
        ] {
            #expect(!FileManager.default.fileExists(atPath: Self.packageRoot.appending(path: path).path),
                    "\(path) must not remain after the OpenRouter-only cleanup migration")
        }
    }

    /// Stated sensitivity: reintroducing direct cloud provider endpoints, env
    /// keys, or source symbols under a new filename bypasses OpenRouter-only
    /// cleanup without tripping filename checks.
    @Test
    func directProviderRuntimeTokensAreAbsent() throws {
        let files = Self.swiftFiles(under: [
            "Sources/SlovoCore",
            "Sources/slovo",
            "Tools/cleanup-benchmark",
        ])
        let forbiddenTokens = [
            "ANTHROPIC_API_KEY",
            "OPENAI_API_KEY",
            "api.anthropic.com",
            "api.openai.com",
            "/v1/responses",
            "AnthropicCleaner",
            "OpenAICleaner",
            "AnthropicKeyProvider",
            "OpenAIKeyProvider",
            "KeychainAnthropic",
            "KeychainOpenAI",
        ]

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                #expect(!source.contains(token), "\(file.path) must not contain direct provider token \(token)")
            }
        }
    }

    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func swiftFiles(under paths: [String]) -> [URL] {
        paths.flatMap { path in
            let root = packageRoot.appending(path: path)
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                return [URL]()
            }
            return enumerator
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
        }
    }
}
