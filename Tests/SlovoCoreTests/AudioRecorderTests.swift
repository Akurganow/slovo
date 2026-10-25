import AVFoundation
import Foundation
import Testing

// `@testable` only for `AVAudioEngineRecorder.detachedChunk`, the one recorder step that
// can run without a microphone.
@testable import SlovoCore
import SlovoTestSupport

// Three kinds of coverage, none a substitute for another. The first suite executes
// `FakeAudioRecorder` — the seam's SHAPE, not the hardware. The second reads
// `AVAudioEngineRecorder`'s source text, the only check available for a class CI never
// runs: it proves the wiring is present and ordered, never that it behaves. The third
// executes the helper that detaches each chunk from the tap's buffer; a `yield` that
// bypasses it, or hands it another pair than the session's, is caught only on hardware.
@Suite("AudioRecorder seam (FakeAudioRecorder)")
struct AudioRecorderSeamTests {

    /// A denied mic throws, and the engine is never started.
    /// Sensitivity: check permission after starting the engine → RED.
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
}

@Suite("AVAudioEngineRecorder source guards")
struct AVAudioEngineRecorderSourceGuardTests {

    /// Tap callbacks outlive `stop()` transiently, so each carries a session token
    /// and rejects a newer session under the lock.
    /// Sensitivity: delete the captured token or either guard → RED.
    @Test
    func recorderSourceRejectsStaleSessionCallbacks() throws {
        let recorder = try Self.code("Sources/SlovoCore/Audio/AVAudioEngineRecorder.swift")
        let startBody = try Self.functionBody(named: "start", in: recorder)
        let yieldFunction = try Self.functionBody(named: "yield", in: recorder, includingSignature: true)
        let yieldBody = try Self.functionBody(named: "yield", in: recorder)
        let teardownBody = try Self.functionBody(named: "teardown", in: recorder)

        #expect(recorder.contains("final class SessionToken"), "recorder sessions need a stable callback identity")
        #expect(Self.containsInOrder([
            "let sessionToken = SessionToken()",
            "sessionToken: sessionToken)",
            "token: sessionToken",
        ], in: startBody), "the tap callback must capture the token published with its session")
        #expect(yieldFunction.contains("sessionToken: SessionToken"))
        #expect(Self.identityCheckPrecedes("session.continuation", in: yieldBody),
                "the tap must reject a stale token before reading the current continuation")
        #expect(teardownBody.contains("sessionToken"))
        #expect(Self.identityCheckPrecedes("self.session = nil", in: teardownBody),
                "teardown must reject a stale token before clearing the current session")
    }

    /// The predicate above must reject every way the guard can be lost, and must not be
    /// fooled by a decoy comparison or a second one further down.
    /// Sensitivity: widen the pattern to a bare `=== sessionToken`, or pick the
    /// comparison by pattern order instead of position → RED.
    @Test
    func identityOrderPredicateRejectsMissingLateAndDecoyComparisons() {
        let guarded = "lock.withLock { guard session.token === sessionToken else { return }; session.continuation }"
        let missing = guarded.replacingOccurrences(of: "session.token === sessionToken", with: "true")
        let late = "lock.withLock { session.continuation; guard session.token === sessionToken else { return } }"
        // An identity comparison against some OTHER value is not the session guard.
        let decoy = "lock.withLock { guard cached === sessionToken else { return }; session.continuation }"
        // Genuinely guarded in its negated form; a later comparison must not hide it.
        let negatedGuardBeforeLaterComparison = "lock.withLock { guard session.token !== sessionToken else { return };"
            + " session.continuation; log(session.token === sessionToken) }"

        #expect(Self.identityCheckPrecedes("session.continuation", in: guarded))
        #expect(!Self.identityCheckPrecedes("session.continuation", in: missing))
        #expect(!Self.identityCheckPrecedes("session.continuation", in: late))
        #expect(!Self.identityCheckPrecedes("session.continuation", in: decoy))
        #expect(Self.identityCheckPrecedes("session.continuation", in: negatedGuardBeforeLaterComparison))
    }

    /// The format is validated BEFORE `installTap`: a degenerate format raises an
    /// `NSException` inside the call that Swift cannot catch, so rejecting it first is
    /// the only defence. A chosen device is assigned before the format is read, and
    /// the tap takes the node's input format: after an assignment the output format
    /// can still be the previous device's, and a tap in it fails to start or
    /// delivers nothing.
    /// Sensitivity: delete the validator call or order `installTap` ahead of it → RED.
    /// A unit test of the validator alone stays green, which is the false green this closes.
    /// Stated sensitivity: read the format before assigning, read the output format
    /// instead of the input format, assign after the tap, or tap with `format: nil` → RED.
    @Test
    func recorderSourceValidatesFormatBeforeInstallingTap() throws {
        let recorder = try Self.code("Sources/SlovoCore/Audio/AVAudioEngineRecorder.swift")
        let startBody = try Self.functionBody(named: "start", in: recorder)

        #expect(Self.containsInOrder([
            "AudioUnitSetProperty",
            "inputFormat(forBus: 0)",
            "AudioTapFormatValidator",
            "installTap(onBus:",
            "format: inputFormat)",
        ], in: startBody),
        "start() must assign the chosen device, then read the node's input format and validate it before installTap")
    }

    /// The stereo pair is read once per start, from the device the capture uses. On the
    /// default path that device comes from the default-input read: there the audio unit's
    /// current device names no input device.
    /// Stated sensitivity: read the pair from the audio unit instead of the default-input
    /// id, or drop the pair read → RED. `WhisperSampleConverterTests` cannot catch either.
    @Test
    func recorderSourceReadsThePairOfTheDefaultInputDevice() throws {
        let recorder = try Self.code("Sources/SlovoCore/Audio/AVAudioEngineRecorder.swift")
        let startBody = try Self.functionBody(named: "start", in: recorder)

        #expect(Self.containsInOrder([
            "defaultInputDeviceID(",
            "preferredStereoChannels(of:",
        ], in: startBody), "start() must read the pair of the default input device")
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

    /// True when a token check inside the lock precedes `protectedUse`. Both operands are
    /// pinned so an unrelated comparison cannot pose as the guard, and the FIRST protected
    /// use is measured so a later comparison cannot cover for a guard that no longer runs.
    private static func identityCheckPrecedes(_ protectedUse: String, in source: String) -> Bool {
        guard let lockRange = source.range(of: "lock.withLock"),
              let protectedRange = source.range(of: protectedUse),
              let comparisonRange = ["session.token === sessionToken", "session.token !== sessionToken"]
              .compactMap({ source.range(of: $0) })
              .min(by: { $0.lowerBound < $1.lowerBound }) else {
            return false
        }
        return lockRange.lowerBound < comparisonRange.lowerBound
            && comparisonRange.lowerBound < protectedRange.lowerBound
    }

    private static func functionBody(
        named name: String,
        in source: String,
        includingSignature: Bool = false
    ) throws -> String {
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
                    let lowerBound = includingSignature ? signature.lowerBound : openBrace
                    return String(source[lowerBound...index])
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

@Suite("AVAudioEngineRecorder chunk detachment")
struct AVAudioEngineRecorderChunkTests {

    /// The tap's buffer is the engine's: the chunk must keep its samples, in every
    /// channel, after the tap's buffer is overwritten, and carry the session's pair.
    /// Stated sensitivity: handing out the tap's own buffer → RED. Dropping or nulling
    /// the pair → RED.
    @Test
    func detachedChunkKeepsEveryChannelAfterTheTapBufferIsOverwritten() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let tapBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        tapBuffer.frameLength = 3
        let tapChannels = try #require(tapBuffer.floatChannelData)
        let left: [Float] = [0.1, 0.2, 0.3]
        let right: [Float] = [-0.1, -0.2, -0.3]
        for frame in 0..<3 {
            tapChannels[0][frame] = left[frame]
            tapChannels[1][frame] = right[frame]
        }

        let chunk = try #require(AVAudioEngineRecorder.detachedChunk(of: tapBuffer, preferredStereoChannels: [2, 1]))
        for frame in 0..<3 {
            tapChannels[0][frame] = 9
            tapChannels[1][frame] = 9
        }

        let kept = try #require(chunk.buffer.floatChannelData)
        #expect(Array(UnsafeBufferPointer(start: kept[0], count: 3)) == left, "channel 0 must keep the captured samples")
        #expect(Array(UnsafeBufferPointer(start: kept[1], count: 3)) == right, "channel 1 must keep the captured samples")
        #expect(chunk.preferredStereoChannels == [2, 1], "the chunk must carry the pair it was given")
    }

    /// An empty tap callback carries no audio, so it must not reach recognition.
    /// Stated sensitivity: dropping the empty-buffer guard → RED.
    @Test
    func zeroFrameBufferYieldsNoChunk() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let emptyBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        emptyBuffer.frameLength = 0

        #expect(AVAudioEngineRecorder.detachedChunk(of: emptyBuffer, preferredStereoChannels: nil) == nil)
    }
}
