import Foundation
import SlovoCore

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
            .flatMap { token in
                token.trimmingCharacters(in: .whitespaces) == "catalog"
                    ? CleanupModelCatalog.options.map { CleanupBenchmarkProviderSpec(provider: .openRouter, model: $0.id) }
                    : [try parse(String(token))]
            }
        guard !specs.isEmpty else {
            throw CleanupBenchmarkProviderSpecError.empty
        }
        var seen = Set<String>()
        if let duplicate = specs.first(where: { !seen.insert("\($0.provider.rawValue):\($0.model)").inserted }) {
            throw CleanupBenchmarkProviderSpecError.duplicate("\(duplicate.provider.rawValue):\(duplicate.model)")
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
        guard !model.contains(where: \.isNewline) else {
            throw CleanupBenchmarkProviderSpecError.lineBreakInModel(provider)
        }
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

public enum CleanupBenchmarkProviderSpecError: Error, Equatable, CustomStringConvertible, Sendable {
    case empty
    case duplicate(String)
    case missingModel(CleanupBenchmarkProvider)
    case lineBreakInModel(CleanupBenchmarkProvider)
    case unknownProvider(String)

    public var description: String {
        switch self {
        case .empty: "--providers names no candidate"
        case .missingModel(let provider): "--providers needs a model after \(provider.rawValue):"
        case .lineBreakInModel(let provider): "--providers takes a model name on one line after \(provider.rawValue):"
        case .unknownProvider(let value): "--providers names an unknown provider: \(value)"
        case .duplicate(let name): "--providers names \(name) more than once; every candidate needs its own name"
        }
    }
}
