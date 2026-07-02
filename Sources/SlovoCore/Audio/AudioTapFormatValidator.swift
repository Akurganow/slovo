import AVFoundation

/// Pure gate that decides whether an input format is safe to install a tap on.
///
/// `AVAudioEngine`'s `installTap` validates the format through
/// `IsFormatSampleRateAndChannelCountValid`, which raises an Objective-C
/// `NSException` (not a Swift error) on a degenerate format — a zero sample rate
/// OR zero channels. Swift cannot catch that exception, so on device it became a
/// `SIGABRT` on key-down. Rejecting the format here, before the call, turns the
/// un-catchable crash into a recoverable `AudioCaptureError.formatUnavailable`.
public enum AudioTapFormatValidator {
    /// The reason the format must not be tapped, or `nil` when it is safe.
    public static func rejectionReason(
        sampleRate: Double,
        channelCount: AVAudioChannelCount
    ) -> AudioCaptureError? {
        guard sampleRate > 0, channelCount > 0 else {
            return .formatUnavailable
        }
        return nil
    }
}
