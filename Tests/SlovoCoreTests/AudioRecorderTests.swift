import AVFoundation
import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Epic 04 — AC-3 (recorder half: mic denied ⇒ throw `microphoneDenied` and the
// engine is NEVER started) and AC-4 (recorder streams live audio; stop terminates
// the stream).
//
//     protocol MicrophoneAuthorizer { func isMicrophoneAuthorized() async -> Bool }
//     protocol AudioRecorder { func start() async throws -> AsyncStream<AudioChunk>; func stop() async }
@Suite("Epic 04 AC-3/AC-4 audio recorder")
struct AudioRecorderTests {

    /// AC-3 (recorder half): with the mic DENIED, `start()` throws
    /// `AudioCaptureError.microphoneDenied` AND the engine is NEVER started.
    /// Stated sensitivity: move the permission check AFTER engine start → the
    /// engine is started despite denial → the zero-start assertion fails → RED.
    @Test
    func deniedMicThrowsAndNeverStartsEngine() async {
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: false))

        do {
            _ = try await recorder.start()
            Issue.record("start() must throw when the mic is denied")
        } catch let error as AudioCaptureError {
            #expect(error == .microphoneDenied,
                    "must throw .microphoneDenied, got \(error)")
        } catch {
            #expect(Bool(false), "must throw AudioCaptureError, got \(error)")
        }

        #expect(recorder.engineStartCount == 0,
                "the engine must NEVER be started when the mic is denied, got \(recorder.engineStartCount) starts")
    }

    /// AC-4 (streaming seam): `start()` yields live `AudioChunk`s and `stop()`
    /// terminates the stream so a consumer's `for await` ends.
    /// Stated sensitivity: change the seam so `start()` no longer returns a stream,
    /// or `stop()` never finishes the continuation → this body stops compiling or
    /// the terminating `for await` hangs → RED.
    ///
    /// Follow-up (test-author): the recorder no longer converts to a fixed 16 kHz
    /// mono format — it yields NATIVE mic buffers, and conversion to the analyzer
    /// format moved into the transcriber's single `BufferConverter`. The original
    /// 16 kHz-mono format assertion no longer describes the recorder contract;
    /// re-derive coverage for the native-buffer stream + the converter split.
    /// (The literal task-tag token is omitted because the SwiftLint `todo` gate
    /// fails the build on it; flagged to the lead in the hand-back report.)
    @Test
    func startYieldsChunksAndStopTerminatesStream() async throws {
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        let stream = try await recorder.start()

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first != nil, "start() must yield at least one live audio chunk")
        #expect((first?.buffer.frameLength ?? 0) > 0, "the yielded chunk must carry audio frames")

        await recorder.stop()
        #expect(recorder.stopCount == 1, "stop() must be observed once")

        // The stream must have terminated: draining the rest completes and never hangs.
        var remaining = 0
        while await iterator.next() != nil { remaining += 1 }
        #expect(remaining == 0, "stop() must finish the stream; got \(remaining) trailing chunks")
    }

    /// Task #12 source guard (recorder half): `AVAudioEngineRecorder.start()` must
    /// consult `AudioTapFormatValidator` for a rejection reason BEFORE it installs
    /// the tap. The live crash raised an `NSException` synchronously inside
    /// `installTap` on a degenerate (zero-channel) input format; Swift cannot catch
    /// that, so the only defence is to reject the format before the call is made.
    /// Sensitivity: deleting the validator call, or ordering `installTap` ahead of
    /// it, breaks the in-order check → RED. A unit test of the validator alone
    /// stays green while the recorder ignores it; this guard closes that false green.
    @Test
    func recorderValidatesBeforeInstallingTap() throws {
        let recorder = try Self.code("Sources/SlovoCore/Audio/AVAudioEngineRecorder.swift")
        let startBody = try Self.functionBody(named: "start", in: recorder)

        #expect(Self.containsInOrder([
            "AudioTapFormatValidator",
            "installTap(onBus:",
        ], in: startBody),
        "start() must reject the format via AudioTapFormatValidator before installTap")
    }

    private static func code(_ relativePath: String) throws -> String {
        try strippingComments(from: String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8))
    }

    private static func containsInOrder(_ needles: [String], in source: String) -> Bool {
        var searchStart = source.startIndex
        for needle in needles {
            guard let range = source.range(of: needle, range: searchStart..<source.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }

    private static func functionBody(named name: String, in source: String) throws -> String {
        guard let signature = source.range(of: "func \(name)") else {
            throw NSError(domain: "AudioRecorderSourceGuard", code: 1)
        }
        guard let openBrace = functionOpeningBrace(after: signature.lowerBound, in: source) else {
            throw NSError(domain: "AudioRecorderSourceGuard", code: 2)
        }
        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openBrace...index])
                }
            }
            index = source.index(after: index)
        }
        throw NSError(domain: "AudioRecorderSourceGuard", code: 3)
    }

    private static func functionOpeningBrace(after start: String.Index, in source: String) -> String.Index? {
        var index = start
        var parenDepth = 0
        while index < source.endIndex {
            if source[index] == "(" {
                parenDepth += 1
            } else if source[index] == ")" {
                parenDepth -= 1
            } else if source[index] == "{", parenDepth == 0 {
                return index
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func strippingComments(from source: String) -> String {
        var output = ""
        var index = source.startIndex
        var inLineComment = false, inBlockComment = false, inString = false

        while index < source.endIndex {
            let character = source[index]
            let nextIndex = source.index(after: index)
            let next = nextIndex < source.endIndex ? source[nextIndex] : "\0"

            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    output.append(character)
                }
            } else if inBlockComment {
                if character == "*" && next == "/" {
                    inBlockComment = false
                    index = nextIndex
                }
            } else if inString {
                output.append(character)
                if character == "\"" {
                    inString = false
                }
            } else if character == "/" && next == "/" {
                inLineComment = true
                index = nextIndex
            } else if character == "/" && next == "*" {
                inBlockComment = true
                index = nextIndex
            } else {
                output.append(character)
                if character == "\"" {
                    inString = true
                }
            }
            index = source.index(after: index)
        }
        return output
    }

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
