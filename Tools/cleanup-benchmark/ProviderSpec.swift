import Foundation

public enum CleanupBenchmarkProvider: String, Codable, Equatable, Sendable {
    case openRouter = "openrouter"
    case passThrough = "passthrough"
}

public struct CleanupBenchmarkProviderSpec: Equatable, Sendable {
    public let provider: CleanupBenchmarkProvider
    public let model: String

    public init(provider: CleanupBenchmarkProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    public static func parseList(_ value: String) throws -> [CleanupBenchmarkProviderSpec] {
        let specs = try value
            .split(separator: ",")
            .map { try parse(String($0)) }
        guard !specs.isEmpty else {
            throw CleanupBenchmarkProviderSpecError.empty
        }
        return specs
    }

    public static func parse(_ value: String) throws -> CleanupBenchmarkProviderSpec {
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard let rawProvider = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawProvider.isEmpty,
              let provider = CleanupBenchmarkProvider(rawValue: rawProvider)
        else {
            throw CleanupBenchmarkProviderSpecError.unknownProvider(value)
        }

        let explicitModel = parts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = try explicitModel.flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel(for: provider)
        return CleanupBenchmarkProviderSpec(provider: provider, model: model)
    }

    private static func defaultModel(for provider: CleanupBenchmarkProvider) throws -> String {
        switch provider {
        case .openRouter:
            throw CleanupBenchmarkProviderSpecError.missingModel(provider)
        case .passThrough:
            return "none"
        }
    }
}

public enum CleanupBenchmarkProviderSpecError: Error, Equatable, Sendable {
    case empty
    case missingModel(CleanupBenchmarkProvider)
    case unknownProvider(String)
}
