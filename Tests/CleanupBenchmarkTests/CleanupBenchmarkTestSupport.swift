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
