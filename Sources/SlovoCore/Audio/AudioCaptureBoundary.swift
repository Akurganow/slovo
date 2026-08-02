import AVFoundation
import Foundation

/// Withholds the frames captured across the readiness cue; delivery is open
/// otherwise. The window is bracketed by two calls, so a cue that ends almost
/// immediately (cues off, or an asset that fails to load) still costs up to one
/// callback — an accepted loss.
///
/// A software boundary, not echo cancellation — the cue's acoustic tail in the room
/// survives it.
internal final class AudioCaptureBoundary: @unchecked Sendable {
    private enum State {
        case open
        /// Suppression starts at this host time; the straddling callback keeps the
        /// frames preceding it.
        case closing(UInt64)
        case suppressed
        /// Suppression ends at this host time; the straddling callback keeps the
        /// frames at or after it.
        case opening(UInt64)
    }

    private let lock = NSLock()
    private var state = State.open

    internal func suspend(atHostTime hostTime: UInt64) {
        lock.withLock {
            guard case .open = state else { return }
            state = .closing(hostTime)
        }
    }

    internal func resume(atHostTime hostTime: UInt64) {
        lock.withLock {
            switch state {
            case .open, .opening:
                return
            case .closing, .suppressed:
                state = .opening(hostTime)
            }
        }
    }

    /// Returns a detached whole buffer, the part of it outside the suppression
    /// window, or nil when every frame falls inside the window.
    internal func takeDeliverableBuffer(
        _ source: AVAudioPCMBuffer,
        capturedAt time: AVAudioTime
    ) -> AVAudioPCMBuffer? {
        let slice = lock.withLock {
            Self.deliverableSlice(in: source, capturedAt: time, state: &state)
        }
        guard let slice else { return nil }
        return Self.detachedCopy(of: source, firstFrame: slice.firstFrame, frameCount: slice.frameCount)
    }

    private struct Slice {
        let firstFrame: AVAudioFrameCount
        let frameCount: AVAudioFrameCount
    }

    private static func deliverableSlice(
        in buffer: AVAudioPCMBuffer,
        capturedAt time: AVAudioTime,
        state: inout State
    ) -> Slice? {
        guard buffer.frameLength > 0 else { return nil }
        switch state {
        case .open:
            return Slice(firstFrame: 0, frameCount: buffer.frameLength)

        case .suppressed:
            return nil

        case .closing(let boundaryHostTime):
            guard time.isHostTimeValid else {
                // Without a comparable timestamp the callback cannot be split, so
                // suppress it whole rather than risk delivering the cue's own sound.
                state = .suppressed
                return nil
            }
            guard time.hostTime < boundaryHostTime else {
                state = .suppressed
                return nil
            }
            let frameCount = framesElapsed(
                from: time.hostTime,
                to: boundaryHostTime,
                sampleRate: buffer.format.sampleRate,
                rounding: (floor)
            )
            guard let frameCount else { return nil }
            guard frameCount < buffer.frameLength else {
                // Wholly before the window: deliver it and keep waiting for the
                // callback that actually straddles the boundary.
                return Slice(firstFrame: 0, frameCount: buffer.frameLength)
            }
            state = .suppressed
            guard frameCount > 0 else { return nil }
            return Slice(firstFrame: 0, frameCount: frameCount)

        case .opening(let boundaryHostTime):
            guard time.isHostTimeValid else {
                // No comparable timestamp: drop this callback and admit later ones
                // instead of suppressing delivery for the rest of the hold.
                state = .open
                return nil
            }
            guard time.hostTime < boundaryHostTime else {
                state = .open
                return Slice(firstFrame: 0, frameCount: buffer.frameLength)
            }
            let firstFrame = framesElapsed(
                from: time.hostTime,
                to: boundaryHostTime,
                sampleRate: buffer.format.sampleRate,
                rounding: (ceil)
            )
            guard let firstFrame else { return nil }
            guard firstFrame < buffer.frameLength else {
                // A wholly pre-boundary callback does not consume the boundary: the
                // next timestamped callback may still straddle it.
                return nil
            }
            state = .open
            return Slice(firstFrame: firstFrame, frameCount: buffer.frameLength - firstFrame)
        }
    }

    private static func framesElapsed(
        from startHostTime: UInt64,
        to endHostTime: UInt64,
        sampleRate: Double,
        rounding: (Double) -> Double
    ) -> AVAudioFrameCount? {
        let elapsedSeconds = AVAudioTime.seconds(forHostTime: endHostTime - startHostTime)
        let frames = rounding(elapsedSeconds * sampleRate)
        guard frames.isFinite, frames >= 0, frames <= Double(AVAudioFrameCount.max) else { return nil }
        return AVAudioFrameCount(frames)
    }

    private static func detachedCopy(
        of source: AVAudioPCMBuffer,
        firstFrame: AVAudioFrameCount,
        frameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        guard frameCount > 0, firstFrame + frameCount <= source.frameLength else { return nil }
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: frameCount) else {
            return nil
        }
        copy.frameLength = frameCount

        let bytesPerFrame = Int(source.format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }
        let byteOffset = Int(firstFrame) * bytesPerFrame
        let byteCount = Int(frameCount) * bytesPerFrame
        let sourceList = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: source.audioBufferList)
        )
        let destinationList = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard sourceList.count == destinationList.count else { return nil }

        for (sourceBuffer, destinationBuffer) in zip(sourceList, destinationList) {
            guard let sourceData = sourceBuffer.mData,
                  let destinationData = destinationBuffer.mData,
                  byteOffset + byteCount <= Int(sourceBuffer.mDataByteSize),
                  byteCount <= Int(destinationBuffer.mDataByteSize) else {
                return nil
            }
            memcpy(destinationData, sourceData.advanced(by: byteOffset), byteCount)
        }
        return copy
    }
}
