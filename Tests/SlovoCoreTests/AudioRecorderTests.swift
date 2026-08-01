import AVFoundation
import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Two kinds of coverage, neither a substitute for the other. The first suite executes
// `FakeAudioRecorder` — the seam's SHAPE, not the hardware. The second reads
// `AVAudioEngineRecorder`'s source text, the only check available for a class CI never
// runs: it proves the wiring is present and ordered, never that it behaves. The timing
// arithmetic behind it is verified for real in `AudioCaptureBoundaryTests`.
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

    /// Speech captured before the cue still reaches recognition — the model may still be
    /// loading — while the suspended interval is discarded and `stop()` ends the stream.
    /// Sensitivity: start suspended → one chunk; no-op suspend → three; unfinished
    /// stream → nil. All RED.
    @Test
    func deliversFromTheFirstCallbackAndWithholdsOnlyTheSuspendedInterval() async throws {
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        let stream = try await recorder.start()
        recorder.emitCallback()
        recorder.suspendDelivery()
        recorder.emitCallback()
        recorder.resumeDelivery()
        await recorder.stop()

        let delivered = await Self.drainedFrameLengths(of: stream)
        #expect(delivered == [3, 3],
                "exactly the pre-cue and post-resume callbacks must arrive, both whole; got \(String(describing: delivered))")
        #expect(recorder.droppedCallbackCount == 1, "only the suspended callback may be discarded")
        #expect(recorder.yieldedCallbackCount == 2, "both unsuspended callbacks must be yielded")
        #expect(recorder.deliverySuspendCount == 1, "delivery suspends exactly once")
        #expect(recorder.deliveryResumeCount == 1, "delivery resumes exactly once")
        #expect(recorder.stopCount == 1, "stop() must be observed once")
    }

    /// Frame lengths an already-stopped stream still holds, or nil if it never ends. The
    /// bound keeps a stream that never finishes a FAILING test rather than a wedged suite.
    private static func drainedFrameLengths(of stream: AsyncStream<AudioChunk>) async -> [AVAudioFrameCount]? {
        await withTaskGroup(of: [AVAudioFrameCount]?.self) { group in
            group.addTask {
                var lengths: [AVAudioFrameCount] = []
                for await chunk in stream { lengths.append(chunk.buffer.frameLength) }
                return lengths
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }
            for await firstFinished in group {
                group.cancelAll()
                return firstFinished
            }
            return nil
        }
    }
}

@Suite("AVAudioEngineRecorder source guards")
struct AVAudioEngineRecorderSourceGuardTests {

    /// Both delivery edges carry a host-clock stamp and the tap hands its own timestamp
    /// to the boundary, so the cue's interval is cut where it falls rather than at the
    /// next callback — the sub-callback precision the seam fake cannot represent.
    /// Sensitivity: drop either stamp, gate on a bare Boolean, discard the tap's `when`,
    /// or yield before trimming → RED.
    @Test
    func recorderSourceTimestampsBothDeliveryEdges() throws {
        let seam = try Self.code("Sources/SlovoCore/Audio/AudioRecorder.swift")
        let recorder = try Self.code("Sources/SlovoCore/Audio/AVAudioEngineRecorder.swift")
        let startBody = try Self.functionBody(named: "start", in: recorder)
        let suspendBody = try Self.functionBody(named: "suspendDelivery", in: recorder)
        let resumeBody = try Self.functionBody(named: "resumeDelivery", in: recorder)
        let yieldBody = try Self.functionBody(named: "yield", in: recorder)

        #expect(seam.contains("func suspendDelivery()") && seam.contains("func resumeDelivery()"),
                "the production seam must expose the suspend/resume pair, not a one-shot gate opening")
        #expect(startBody.contains("AudioCaptureBoundary()"),
                "each capture session must own a fresh capture boundary")
        #expect(Self.containsInOrder([
            "buffer, when in",
            "yield(buffer, capturedAt: when, sessionToken: sessionToken)",
        ], in: startBody), "the tap must pass its AVAudioTime timestamp into delivery gating")

        for (edge, body) in [("suspendDelivery", suspendBody), ("resumeDelivery", resumeBody)] {
            #expect(body.contains("lock.withLock"), "\(edge) must reach the session under the tap's lock")
            #expect(body.contains("AudioGetCurrentHostTime()") || body.contains("mach_absolute_time()"),
                    "\(edge) must stamp its edge with the host clock")
        }
        #expect(suspendBody.contains("suspend(atHostTime:"),
                "suspendDelivery must publish its host-time edge to the boundary")
        #expect(resumeBody.contains("resume(atHostTime:"),
                "resumeDelivery must publish its host-time edge to the boundary")
        #expect(Self.containsInOrder([
            "capturedAt",
            "takeDeliverableBuffer",
            "continuation?.yield",
        ], in: yieldBody), "the callback must be trimmed against the capture boundary before it is yielded")
    }

    /// Hardware callbacks outlive `stop()` transiently, so each carries a session token
    /// and rejects a newer session under the lock.
    /// Sensitivity: delete either captured token or either guard → RED.
    @Test
    func recorderSourceRejectsStaleSessionCallbacks() throws {
        let recorder = try Self.code("Sources/SlovoCore/Audio/AVAudioEngineRecorder.swift")
        let startBody = try Self.functionBody(named: "start", in: recorder)
        let yieldFunction = try Self.functionBody(named: "yield", in: recorder, includingSignature: true)
        let yieldBody = try Self.functionBody(named: "yield", in: recorder)
        let changeFunction = try Self.functionBody(
            named: "handleConfigurationChange",
            in: recorder,
            includingSignature: true
        )
        let changeBody = try Self.functionBody(named: "handleConfigurationChange", in: recorder)
        let teardownBody = try Self.functionBody(named: "teardown", in: recorder)

        #expect(recorder.contains("final class SessionToken"), "recorder sessions need a stable callback identity")
        #expect(Self.containsInOrder([
            "let sessionToken = SessionToken()",
            "buffer, when in",
            "yield(buffer, capturedAt: when, sessionToken: sessionToken)",
            "handleConfigurationChange(sessionToken: sessionToken)",
            "token: sessionToken",
        ], in: startBody), "tap and configuration callbacks must capture the token published with their session")
        #expect(yieldFunction.contains("sessionToken: SessionToken"))
        #expect(Self.identityCheckPrecedes("session.continuation", in: yieldBody),
                "the tap must reject a stale token before reading the current continuation")
        #expect(changeFunction.contains("sessionToken: SessionToken"))
        #expect(changeBody.contains("teardown(sessionToken: sessionToken)"),
                "configuration changes must tear down only their originating session")
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
    /// the only defence.
    /// Sensitivity: delete the validator call or order `installTap` ahead of it → RED.
    /// A unit test of the validator alone stays green, which is the false green this closes.
    @Test
    func recorderSourceValidatesFormatBeforeInstallingTap() throws {
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
