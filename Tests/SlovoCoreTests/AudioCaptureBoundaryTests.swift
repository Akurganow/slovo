import AVFoundation
import Testing

@testable import SlovoCore

/// The boundary withholds exactly the interval in which the readiness cue is
/// audible. Every edge test therefore feeds a callback that genuinely straddles
/// the edge — starting strictly before it and ending strictly after — because a
/// callback lying wholly on one side passes under any implementation and proves
/// nothing about where the cut lands.
@Suite("Audio capture boundary")
struct AudioCaptureBoundaryTests {
    private static let sampleRate = 48_000.0

    /// Sensitivity: starting the boundary in a closed state drops the frames
    /// spoken while the speech model is still loading.
    @Test
    func deliversEveryFrameBeforeAnySuspend() throws {
        let boundary = AudioCaptureBoundary()

        let delivered = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [10, 20, 30]),
            capturedAt: AVAudioTime(hostTime: Self.hostTime(seconds: 10))
        )

        #expect(Self.markers(in: delivered) == [10, 20, 30])
    }

    /// Straddles the suspend edge 2.5 frames into a 5-frame callback.
    /// Sensitivity: rounding the prefix up leaks frame 30 into the cue window;
    /// leaving the trim out delivers all five frames or none of them.
    @Test
    func suspendEdgeKeepsFramesStrictlyBeforeTheBoundary() throws {
        let callbackHostTime = Self.hostTime(seconds: 10)
        let boundary = AudioCaptureBoundary()
        boundary.suspend(atHostTime: callbackHostTime + Self.hostDuration(frames: 2.5))

        let delivered = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [10, 20, 30, 40, 50]),
            capturedAt: AVAudioTime(hostTime: callbackHostTime)
        )

        #expect(Self.markers(in: delivered) == [10, 20])
    }

    /// Straddles the suspend edge inside the very first frame.
    /// Sensitivity: rounding the prefix up hands over frame 10, which was
    /// captured while the cue was already sounding.
    @Test
    func suspendEdgeInsideTheFirstFrameKeepsNothing() throws {
        let callbackHostTime = Self.hostTime(seconds: 11)
        let boundary = AudioCaptureBoundary()
        boundary.suspend(atHostTime: callbackHostTime + Self.hostDuration(frames: 0.4))

        let delivered = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [10, 20, 30]),
            capturedAt: AVAudioTime(hostTime: callbackHostTime)
        )

        #expect(delivered == nil)
    }

    /// Sensitivity: a callback that opens at or after the suspend edge lies wholly
    /// inside the cue window; delivering any of it feeds the cue back to the
    /// microphone, and failing to latch suppression admits every later callback.
    @Test
    func callbacksInsideTheSuppressionWindowAreDroppedWhole() throws {
        let suspendHostTime = Self.hostTime(seconds: 12)
        let boundary = AudioCaptureBoundary()
        boundary.suspend(atHostTime: suspendHostTime)

        let atEdge = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [10, 20, 30]),
            capturedAt: AVAudioTime(hostTime: suspendHostTime)
        )
        let insideWindow = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [40, 50, 60]),
            capturedAt: AVAudioTime(hostTime: suspendHostTime + Self.hostDuration(frames: 3))
        )

        #expect(atEdge == nil)
        #expect(insideWindow == nil)
    }

    /// The second callback straddles the suspend edge 2.5 frames in.
    /// Sensitivity: letting a wholly pre-boundary callback latch suppression drops
    /// the straddling callback entirely, losing speech captured before the cue.
    @Test
    func whollyPreBoundaryCallbackWhileClosingDeliversAndKeepsTheBoundaryArmed() throws {
        let firstHostTime = Self.hostTime(seconds: 13)
        let boundary = AudioCaptureBoundary()
        boundary.suspend(atHostTime: firstHostTime + Self.hostDuration(frames: 10))

        let beforeWindow = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [1, 2, 3, 4, 5]),
            capturedAt: AVAudioTime(hostTime: firstHostTime)
        )
        let straddling = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [10, 20, 30, 40, 50]),
            capturedAt: AVAudioTime(hostTime: firstHostTime + Self.hostDuration(frames: 7.5))
        )

        #expect(Self.markers(in: beforeWindow) == [1, 2, 3, 4, 5])
        #expect(Self.markers(in: straddling) == [10, 20])
    }

    /// Straddles the resume edge 2.5 frames into a 5-frame callback.
    /// Sensitivity: rounding the suffix down leaks frame 30, still inside the cue;
    /// a `resume` that does not reopen delivery keeps the rest of the hold silent.
    @Test
    func resumeEdgeKeepsFramesAtOrAfterTheBoundary() throws {
        let callbackHostTime = Self.hostTime(seconds: 20)
        let boundary = AudioCaptureBoundary()
        boundary.suspend(atHostTime: callbackHostTime - Self.hostDuration(frames: 100))
        boundary.resume(atHostTime: callbackHostTime + Self.hostDuration(frames: 2.5))

        let delivered = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [10, 20, 30, 40, 50]),
            capturedAt: AVAudioTime(hostTime: callbackHostTime)
        )

        #expect(Self.markers(in: delivered) == [40, 50])
    }

    /// The second callback straddles the resume edge 2.5 frames in.
    /// Sensitivity: letting a wholly pre-boundary callback consume the edge makes
    /// the straddling callback bypass the cut and hand over cue-contaminated frames.
    @Test
    func whollyPreBoundaryCallbackWhileOpeningDropsAndKeepsTheBoundaryArmed() throws {
        let firstHostTime = Self.hostTime(seconds: 21)
        let boundary = AudioCaptureBoundary()
        boundary.suspend(atHostTime: firstHostTime - Self.hostDuration(frames: 100))
        boundary.resume(atHostTime: firstHostTime + Self.hostDuration(frames: 10))

        let insideWindow = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [1, 2, 3, 4, 5]),
            capturedAt: AVAudioTime(hostTime: firstHostTime)
        )
        let straddling = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [10, 20, 30, 40, 50]),
            capturedAt: AVAudioTime(hostTime: firstHostTime + Self.hostDuration(frames: 7.5))
        )

        #expect(insideWindow == nil)
        #expect(Self.markers(in: straddling) == [40, 50])
    }

    /// Sensitivity: without the timestamp check an untimed callback is compared
    /// against host time zero and delivered whole, which is exactly the cue's own
    /// sound; without latching suppression the rest of the window is delivered too.
    @Test
    func invalidHostTimeWhileClosingSuppressesTheRestOfTheWindow() throws {
        let callbackHostTime = Self.hostTime(seconds: 30)
        let boundary = AudioCaptureBoundary()
        boundary.suspend(atHostTime: callbackHostTime + Self.hostDuration(frames: 10))

        let untimed = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [1, 2, 3]),
            capturedAt: Self.untimedCapture()
        )
        let laterButBeforeTheEdge = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [4, 5, 6]),
            capturedAt: AVAudioTime(hostTime: callbackHostTime)
        )

        #expect(untimed == nil)
        #expect(laterButBeforeTheEdge == nil)
    }

    /// Sensitivity: keeping the window armed after an untimed callback leaves
    /// delivery closed for the rest of the hold — the second callback proves
    /// delivery reopened by arriving with a timestamp still before the edge.
    @Test
    func invalidHostTimeWhileOpeningDropsOneCallbackThenReopens() throws {
        let callbackHostTime = Self.hostTime(seconds: 31)
        let boundary = AudioCaptureBoundary()
        boundary.suspend(atHostTime: callbackHostTime - Self.hostDuration(frames: 100))
        boundary.resume(atHostTime: callbackHostTime + Self.hostDuration(frames: 10))

        let untimed = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [1, 2, 3]),
            capturedAt: Self.untimedCapture()
        )
        let afterReopening = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [4, 5, 6]),
            capturedAt: AVAudioTime(hostTime: callbackHostTime)
        )

        #expect(untimed == nil)
        #expect(Self.markers(in: afterReopening) == [4, 5, 6])
    }

    /// Straddles the resume edge 2.5 frames into a 5-frame stereo callback.
    /// Sensitivity: treating the frame offset as a sample offset shifts the copy
    /// half a frame and swaps the channels of the delivered suffix.
    @Test
    func resumeEdgeInInterleavedStereoKeepsFrameAndChannelAlignment() throws {
        let callbackHostTime = Self.hostTime(seconds: 40)
        let boundary = AudioCaptureBoundary()
        boundary.suspend(atHostTime: callbackHostTime - Self.hostDuration(frames: 100))
        boundary.resume(atHostTime: callbackHostTime + Self.hostDuration(frames: 2.5))

        let delivered = boundary.takeDeliverableBuffer(
            try Self.interleavedStereoBuffer(frames: [[10, 11], [20, 21], [30, 31], [40, 41], [50, 51]]),
            capturedAt: AVAudioTime(hostTime: callbackHostTime)
        )

        #expect(delivered?.format.isInterleaved == true)
        #expect(delivered?.format.channelCount == 2)
        #expect(delivered?.frameLength == 2)
        #expect(Self.interleavedMarkers(in: delivered) == [40, 41, 50, 51])
    }

    /// Straddles the resume edge 2.5 frames into a 5-frame stereo callback.
    /// Sensitivity: copying one channel into both, or copying only the first plane,
    /// loses the right channel of the delivered suffix.
    @Test
    func resumeEdgeInNonInterleavedStereoTrimsEveryChannelIdentically() throws {
        let callbackHostTime = Self.hostTime(seconds: 41)
        let boundary = AudioCaptureBoundary()
        boundary.suspend(atHostTime: callbackHostTime - Self.hostDuration(frames: 100))
        boundary.resume(atHostTime: callbackHostTime + Self.hostDuration(frames: 2.5))

        let delivered = boundary.takeDeliverableBuffer(
            try Self.planarBuffer(channels: [[10, 20, 30, 40, 50], [11, 21, 31, 41, 51]]),
            capturedAt: AVAudioTime(hostTime: callbackHostTime)
        )

        #expect(delivered?.format.isInterleaved == false)
        #expect(delivered?.format.channelCount == 2)
        #expect(Self.markers(in: delivered, channel: 0) == [40, 50])
        #expect(Self.markers(in: delivered, channel: 1) == [41, 51])
    }

    /// Sensitivity: skipping the empty-callback case *and* sizing the copy by the
    /// source's capacity yields a zero-frame buffer instead of nothing. No single
    /// length guard can be named here — a zero-capacity `AVAudioPCMBuffer` has no
    /// data pointer, so dropping either one still fails the copy. The straddling
    /// callback pins the resume edge.
    @Test
    func zeroLengthCallbacksAreInertInEveryState() throws {
        let callbackHostTime = Self.hostTime(seconds: 50)
        let boundary = AudioCaptureBoundary()

        let whileOpen = boundary.takeDeliverableBuffer(
            try Self.emptyBuffer(),
            capturedAt: AVAudioTime(hostTime: callbackHostTime)
        )
        boundary.suspend(atHostTime: callbackHostTime - Self.hostDuration(frames: 100))
        boundary.resume(atHostTime: callbackHostTime + Self.hostDuration(frames: 2.5))
        let whileOpening = boundary.takeDeliverableBuffer(
            try Self.emptyBuffer(),
            capturedAt: AVAudioTime(hostTime: callbackHostTime)
        )
        let straddling = boundary.takeDeliverableBuffer(
            try Self.buffer(markers: [10, 20, 30, 40, 50]),
            capturedAt: AVAudioTime(hostTime: callbackHostTime)
        )

        #expect(whileOpen == nil)
        #expect(whileOpening == nil)
        #expect(Self.markers(in: straddling) == [40, 50])
    }

    private static func hostTime(seconds: Double) -> UInt64 {
        AVAudioTime.hostTime(forSeconds: seconds)
    }

    private static func hostDuration(frames: Double) -> UInt64 {
        AVAudioTime.hostTime(forSeconds: frames / sampleRate)
    }

    /// A capture timestamp carrying only a sample position, as macOS reports when
    /// the host clock reading is unavailable.
    private static func untimedCapture() -> AVAudioTime {
        AVAudioTime(sampleTime: 0, atRate: sampleRate)
    }

    private static func format(channels: AVAudioChannelCount, interleaved: Bool) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: interleaved
        ) else {
            throw BoundaryFixtureError.unavailableBuffer
        }
        return format
    }

    private static func buffer(markers: [Float]) throws -> AVAudioPCMBuffer {
        try planarBuffer(channels: [markers])
    }

    private static func planarBuffer(channels: [[Float]]) throws -> AVAudioPCMBuffer {
        let frameCount = channels.first?.count ?? 0
        guard channels.allSatisfy({ $0.count == frameCount }) else {
            throw BoundaryFixtureError.unavailableBuffer
        }
        let format = try format(channels: AVAudioChannelCount(channels.count), interleaved: false)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ), let planes = buffer.floatChannelData else {
            throw BoundaryFixtureError.unavailableBuffer
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for (channelIndex, markers) in channels.enumerated() {
            for (frameIndex, marker) in markers.enumerated() {
                planes[channelIndex][frameIndex] = marker
            }
        }
        return buffer
    }

    /// A callback that carries no frames yet, as macOS delivers while capture is
    /// still spinning up.
    private static func emptyBuffer() throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: try format(channels: 1, interleaved: false),
            frameCapacity: 4
        ) else {
            throw BoundaryFixtureError.unavailableBuffer
        }
        buffer.frameLength = 0
        return buffer
    }

    private static func interleavedStereoBuffer(frames: [[Float]]) throws -> AVAudioPCMBuffer {
        guard frames.allSatisfy({ $0.count == 2 }) else {
            throw BoundaryFixtureError.unavailableBuffer
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: try format(channels: 2, interleaved: true),
            frameCapacity: AVAudioFrameCount(frames.count)
        ), let data = buffer.mutableAudioBufferList.pointee.mBuffers.mData else {
            throw BoundaryFixtureError.unavailableBuffer
        }
        buffer.frameLength = AVAudioFrameCount(frames.count)
        let samples = data.assumingMemoryBound(to: Float.self)
        for (index, marker) in frames.joined().enumerated() {
            samples[index] = marker
        }
        return buffer
    }

    private static func markers(in buffer: AVAudioPCMBuffer?, channel: Int = 0) -> [Float] {
        guard let buffer,
              let planes = buffer.floatChannelData,
              channel < Int(buffer.format.channelCount) else { return [] }
        return Array(UnsafeBufferPointer(start: planes[channel], count: Int(buffer.frameLength)))
    }

    private static func interleavedMarkers(in buffer: AVAudioPCMBuffer?) -> [Float] {
        guard let buffer,
              let data = buffer.audioBufferList.pointee.mBuffers.mData else { return [] }
        let samples = data.assumingMemoryBound(to: Float.self)
        let count = Int(buffer.frameLength) * Int(buffer.format.channelCount)
        return Array(UnsafeBufferPointer(start: samples, count: count))
    }
}

private enum BoundaryFixtureError: Error {
    case unavailableBuffer
}
