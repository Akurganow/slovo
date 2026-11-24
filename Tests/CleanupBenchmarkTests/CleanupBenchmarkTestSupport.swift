import Foundation
import Synchronization

import CleanupBenchmark
import SlovoCore

actor RecordingCleaner: Cleaner {
    private let output: String
    private var inputs: [String] = []
    private var models: [String] = []

    init(output: String) {
        self.output = output
    }

    func clean(_ raw: String, config: CleanupConfig, context: PersonalizationContext) async throws -> String {
        inputs.append(raw)
        models.append(config.model)
        return output
    }

    func rawInputs() -> [String] {
        inputs
    }

    func modelInputs() -> [String] {
        models
    }
}

struct ThrowingSensitiveCleaner: Cleaner {
    func clean(_ raw: String, config: CleanupConfig, context: PersonalizationContext) async throws -> String {
        throw SensitiveError(payload: "\(raw)-S3NT1NEL-KEY")
    }
}

struct SensitiveError: Error, CustomStringConvertible {
    let payload: String

    var description: String {
        payload
    }
}

// MARK: - Offline judge

/// Answers OpenRouter's embeddings and decisions endpoints without a network. Texts
/// that contain `WRONG` embed away from everything else and score low with Jev.
final class FakeJudgeTransport: CleanupBenchmarkTransport {
    private let requests = Mutex<[(path: String, body: Data)]>([])
    private let refusing: String?
    private let failingDecisionsFor: String?
    private let isDown = Mutex(false)

    /// `refusing` names a question the fake declines to answer. A decision whose
    /// output contains `failingDecisionsFor` fails with a server error.
    init(refusing: String? = nil, failingDecisionsFor: String? = nil) {
        self.refusing = refusing
        self.failingDecisionsFor = failingDecisionsFor
    }

    /// While down, every request fails with a server error.
    func setDown(_ down: Bool) {
        isDown.withLock { $0 = down }
    }

    func recorded() -> [(path: String, body: Data)] {
        requests.withLock { $0 }
    }

    func post(path: String, body: Data) async throws -> Data {
        requests.withLock { $0.append((path, body)) }
        if isDown.withLock({ $0 }) {
            throw CleanupBenchmarkJudgeError.httpStatus(500)
        }
        guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw CleanupBenchmarkJudgeError.malformedResponse
        }
        if let input = object["input"] as? [String] {
            let data = input.enumerated().map { index, text -> [String: Any] in
                ["index": index, "embedding": text.contains("WRONG") ? [0.0, 1.0] : [1.0, 0.0]]
            }
            return try JSONSerialization.data(withJSONObject: [
                "data": data, "model": "fake/embedding-snapshot", "usage": ["cost": 0.000001],
            ])
        }
        let state = object["state"] as? [String: String] ?? [:]
        let output = state["cleaned_text"] ?? ""
        if let marker = failingDecisionsFor, output.contains(marker) {
            throw CleanupBenchmarkJudgeError.httpStatus(500)
        }
        let value = output.contains("WRONG") ? 0.05 : 0.95
        var answers: [String: Any] = [:]
        for key in (object["questions"] as? [String: Any] ?? [:]).keys {
            answers[key] = key == refusing ? ["type": "refusal"] : ["type": "noul", "noul": value]
        }
        return try JSONSerialization.data(withJSONObject: [
            "answers": answers, "model": "fake/jev-snapshot", "usage": ["cost": 0.00001],
        ])
    }

    func requestCount(path: String) -> Int {
        recorded().filter { $0.path == path }.count
    }
}

func judgeSettings() throws -> CleanupBenchmarkJudgeSettings {
    try CleanupBenchmarkJudgeSettings.decode(
        Data(contentsOf: URL(fileURLWithPath: CleanupBenchmarkJudgeSettings.defaultPath))
    )
}

/// Cleans to a fixed text and tells the fixture it was called.
struct CountingCleaner: Cleaner {
    let output: String
    let called: @Sendable () -> Void

    func clean(_ raw: String, config: CleanupConfig, context: PersonalizationContext) async throws -> String {
        called()
        return output
    }
}

/// A command driver that reads and writes an in-memory file system and talks to
/// `transport`. Candidates `openrouter:good` and `openrouter:bad` become fakes named
/// `fake:good` and `fake:bad`; `bad` answers with text the judge scores low.
final class DriverFixture: Sendable {
    static let samples = """
    {"samples": [
      {"id": "one", "category": "short-smoke", "raw": "ну привет там", "reference": "Hello there."},
      {"id": "two", "category": "code-switching", "raw": "проверь latency", "reference": "Hello there."}
    ]}
    """

    let files: Mutex<[String: Data]>
    let transport: FakeJudgeTransport
    private let cleanerCalls = Mutex(0)

    init(files: [String: String] = [:], transport: FakeJudgeTransport = FakeJudgeTransport()) throws {
        var contents = files.mapValues { Data($0.utf8) }
        contents["samples.json"] = Data(Self.samples.utf8)
        contents[CleanupBenchmarkJudgeSettings.defaultPath] = try Data(
            contentsOf: URL(fileURLWithPath: CleanupBenchmarkJudgeSettings.defaultPath)
        )
        self.files = Mutex(contents)
        self.transport = transport
    }

    func file(_ path: String) -> Data? {
        files.withLock { $0[path] }
    }

    /// How many times any fake cleaner was asked to clean, over every `run`.
    var cleaned: Int {
        cleanerCalls.withLock { $0 }
    }

    func run(_ arguments: [String]) async -> CleanupBenchmarkCommandResult {
        let driver = CleanupBenchmarkCommandDriver(
            makeCandidates: { specs, _ in
                specs.map { spec in
                    CleanupBenchmarkCandidate(
                        provider: "fake",
                        model: spec.model,
                        cleaner: CountingCleaner(
                            output: spec.model == "bad" ? "WRONG text." : "Hello there.",
                            called: { self.cleanerCalls.withLock { $0 += 1 } }
                        )
                    )
                }
            },
            makeTransport: { _ in self.transport },
            readDataFile: { path in
                guard let data = self.file(path) else { throw CocoaError(.fileReadNoSuchFile) }
                return data
            },
            writeDataFile: { path, data in
                self.files.withLock { $0[path] = data }
            },
            appendDataFile: { path, data in
                self.files.withLock { $0[path, default: Data()].append(data) }
            }
        )
        return await driver.run(
            arguments: ["--samples", "samples.json"] + arguments,
            environment: [:]
        )
    }
}
