import Foundation

/// One live recognition session owned by the speech engine.
public protocol SpeechStreamingSession: Sendable {
    /// Starts recognition and returns only when the stream is ready for samples.
    func start() async throws

    /// Makes new microphone samples immediately available to live recognition.
    func append(_ samples: [Float]) async throws

    /// Stops live recognition and returns its complete transcript.
    func finish() async throws -> String

    /// Stops live recognition without producing a transcript.
    func cancel() async
}

/// Creates a fresh live recognition session for each dictation.
public protocol SpeechStreamingSessionCreating {
    func makeSpeechStreamingSession() throws -> any SpeechStreamingSession
}
