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

    /// The baseline name of the candidate built from this spec.
    public var name: String {
        "\(provider.rawValue):\(model)"
    }

    /// The runner keeps at most `width` calls in flight across the candidates that share this key. The
    /// switch is exhaustive, so a new provider names its own lane, such as one lane shared by the whole provider.
    var lane: String {
        switch provider {
        case .openRouter, .passThrough: name
        }
    }

    /// Calls in flight per lane. OpenRouter's limits page says paid models have "no platform-level request cap"
    /// and "different rate limits for different models", so a lane is one model
    /// (https://openrouter.ai/docs/api_reference/limits.md; documentation, no published revision).
    /// The Jev cookbook gives the one published figure, "Start with 8 workers, which is what the captured run
    /// used with no `429`s" (https://openrouter.ai/docs/cookbook/evaluate-and-optimize/jev-classification.md;
    /// documentation, no published revision). Pass-through makes no request and takes the same width, so free
    /// runs exercise the concurrent path.
    var width: Int {
        switch provider {
        case .openRouter, .passThrough: 8
        }
    }

    /// One OpenRouter spec per model of the app's cleanup list.
    public static var catalog: [CleanupBenchmarkProviderSpec] {
        CleanupModelCatalog.options(for: .openRouter).map { CleanupBenchmarkProviderSpec(provider: .openRouter, model: $0.id) }
    }

    public static func parseList(_ value: String) throws -> [CleanupBenchmarkProviderSpec] {
        let specs = try value
            .split(separator: ",")
            .flatMap { token in
                token.trimmingCharacters(in: .whitespaces) == "catalog"
                    ? catalog
                    : [try parse(String(token))]
            }
        guard !specs.isEmpty else {
            throw CleanupBenchmarkProviderSpecError.empty
        }
        var seen = Set<String>()
        if let duplicate = specs.first(where: { !seen.insert($0.name).inserted }) {
            throw CleanupBenchmarkProviderSpecError.duplicate(duplicate.name)
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
