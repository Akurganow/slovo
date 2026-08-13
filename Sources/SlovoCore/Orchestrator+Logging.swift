/// Payload-free names for the orchestrator's coarse log lines. Pure mappings
/// over closed enums, kept out of the actor: they touch no session state, and
/// `Orchestrator.swift` sits close enough to the file-length gate that adding
/// pipeline behavior there should not compete with lookup tables.
extension Orchestrator {
    /// The static case name of a feed error, for the payload-free health log —
    /// never the wrapped cause or any associated value.
    nonisolated static func feedErrorKindName(_ error: TranscriptionError) -> String {
        switch error {
        case .backendUnavailable:
            return "backendUnavailable"
        case .assetMissing:
            return "assetMissing"
        case .audioFormatUnsupported:
            return "audioFormatUnsupported"
        case .engineFailure:
            return "engineFailure"
        }
    }

    nonisolated static func logName(for event: FsmLogEvent) -> String {
        switch event {
        case .singleFlightIgnored:
            return "fsm.singleFlightIgnored"
        case .unexpectedEvent:
            return "fsm.unexpectedEvent"
        case .stageFailed:
            return "fsm.stageFailed"
        }
    }
}
