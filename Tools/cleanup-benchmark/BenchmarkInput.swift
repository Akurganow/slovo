import Foundation

public enum CleanupBenchmarkSampleLoader {
    private struct FileShape: Decodable {
        let samples: [CleanupBenchmarkSample]
    }

    /// Refuses duplicate ids: every consumer keys runs and references by id. Refuses an empty
    /// list too: a run over no samples would print an empty report and exit 0.
    public static func decode(_ data: Data) throws -> [CleanupBenchmarkSample] {
        let samples = try (try? JSONDecoder().decode([CleanupBenchmarkSample].self, from: data))
            ?? JSONDecoder().decode(FileShape.self, from: data).samples
        var seen = Set<String>()
        if let duplicate = samples.first(where: { !seen.insert($0.id).inserted }) {
            throw CleanupBenchmarkCommandError.duplicateSampleId(duplicate.id)
        }
        guard !samples.isEmpty else {
            throw CleanupBenchmarkCommandError.noSamples
        }
        return samples
    }
}

public enum CleanupBenchmarkEnvFile {
    public static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
            }
            guard let equals = line.firstIndex(of: "=") else { continue }

            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            if !key.isEmpty {
                values[key] = value
            }
        }
        return values
    }
}

public enum CleanupBenchmarkDefaults {
    public static let defaultSamplesPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Benchmarks/cleanup/slovo-cleanup-v1.json")
        .path

    public static func samples(
        readDataFile: (String) throws -> Data = { try Data(contentsOf: URL(fileURLWithPath: $0)) }
    ) throws -> [CleanupBenchmarkSample] {
        try CleanupBenchmarkSampleLoader.decode(readDataFile(defaultSamplesPath))
    }
}
