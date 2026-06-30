import Foundation

public enum CleanupBenchmarkSampleLoader {
    private struct FileShape: Decodable {
        let samples: [CleanupBenchmarkSample]
    }

    public static func decode(_ data: Data) throws -> [CleanupBenchmarkSample] {
        if let samples = try? JSONDecoder().decode([CleanupBenchmarkSample].self, from: data) {
            return samples
        }
        return try JSONDecoder().decode(FileShape.self, from: data).samples
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
    public static let samples = [
        CleanupBenchmarkSample(
            id: "short-repeat",
            raw: "1 2 3 проверяем 1 2 3",
            expectation: CleanupQualityExpectation(
                requiredSubstrings: ["1", "2", "3", "проверяем"],
                forbiddenSubstrings: [],
                maxLengthRatio: 1.8
            )
        ),
        CleanupBenchmarkSample(
            id: "mixed-command",
            raw: "ну вот запушь pr в github пожалуйста",
            expectation: CleanupQualityExpectation(
                requiredSubstrings: ["PR", "GitHub"],
                forbiddenSubstrings: ["ну", "вот"],
                maxLengthRatio: 1.8
            )
        ),
        CleanupBenchmarkSample(
            id: "filler-structure",
            raw: "короче я сейчас попробую поговорить подольше ну чтобы проверить как работает cleanup",
            expectation: CleanupQualityExpectation(
                requiredSubstrings: ["cleanup"],
                forbiddenSubstrings: ["короче", "ну"],
                maxLengthRatio: 1.8,
                minimumSentenceTerminators: 2
            )
        ),
    ]
}
