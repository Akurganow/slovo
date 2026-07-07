import AVFoundation
import Testing

import SlovoCore

// Unit coverage for the pure format gate that must run before the
// recorder installs its tap. The live crash (slovo-2026-07-02-105347.ips) was an
// NSException raised from AVAudioEngine's InstallTapOnNode on a degenerate input
// format; Swift cannot catch it, so it became SIGABRT on key-down. The validator
// turns that un-catchable crash into a recoverable
// `AudioCaptureError.formatUnavailable`, which the FSM already surfaces as the
// `.microphoneUnavailable` menu-bar status.
@Suite("Audio tap format gate")
struct AudioTapFormatValidatorTests {

    /// The exact gap that crashed on device: a valid sample rate paired with zero
    /// channels, which the pre-existing `sampleRate > 0` guard let through.
    /// Sensitivity: drop the channel-count clause and the validator returns nil for
    /// a format that makes `installTap` raise → RED.
    @Test
    func rejectsZeroChannelCountFormat() {
        #expect(
            AudioTapFormatValidator.rejectionReason(sampleRate: 48_000, channelCount: 0) == .formatUnavailable
        )
    }

    /// The half the current recorder already guards; pinning it keeps a later
    /// refactor from dropping it. Sensitivity: drop the sample-rate clause and the
    /// validator returns nil for a zero-rate format → RED.
    @Test
    func rejectsZeroSampleRateFormat() {
        #expect(
            AudioTapFormatValidator.rejectionReason(sampleRate: 0, channelCount: 1) == .formatUnavailable
        )
    }

    /// A real microphone format must pass untouched. Sensitivity: an inverted or
    /// over-broad guard that rejects a valid format would block all capture → this
    /// expectation of nil fails → RED.
    @Test
    func acceptsValidFormat() {
        #expect(
            AudioTapFormatValidator.rejectionReason(sampleRate: 48_000, channelCount: 1) == nil
        )
    }
}
