import AVFoundation
import CryptoKit
import Foundation
import Testing

// The user-approved Lower & Soft cue triplet is a shipped product resource, not
// a replaceable test fixture. These checks pin the reviewed bytes and the compact
// mono PCM shape that keeps playback deterministic.
@Suite("Sound cue assets")
struct SoundCueAssetTests {
    private struct ApprovedAsset: Sendable {
        let name: String
        let sha256: String
        let frameCount: AVAudioFramePosition
    }

    private static let approvedAssets = [
        ApprovedAsset(
            name: "start.wav",
            sha256: "bf3bc40f1f4bcda58cd43b5b61c1d0fea302562dcb3c9b99de1e4a9738212ae2",
            frameCount: 11_746
        ),
        ApprovedAsset(
            name: "end.wav",
            sha256: "a888874b6843bb0dfdce0c53f299241d1690eb7caf9ff861e32c2b11263b3d54",
            frameCount: 11_785
        ),
        ApprovedAsset(
            name: "error.wav",
            sha256: "fb81e4e1c66e14ad930e88a0466cf72afe06a5f55dcfe8715457c79bd76c1f6e",
            frameCount: 9_413
        ),
    ]

    /// Sensitivity: replacing any approved Lower & Soft WAV, renaming it, or
    /// regenerating it with different bytes changes the digest or removes the file.
    @Test
    func approvedLowerAndSoftBytesArePinned() throws {
        for asset in Self.approvedAssets {
            let url = Self.audioCueDirectory.appending(path: asset.name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                Issue.record("Missing approved sound cue: \(url.path)")
                continue
            }

            let data = try Data(contentsOf: url)
            #expect(Self.sha256(data) == asset.sha256,
                    "\(asset.name) must remain byte-identical to the user-approved Lower & Soft cue")
        }
    }

    /// Sensitivity: transcoding a cue away from 48 kHz mono signed 16-bit PCM,
    /// padding/truncating it, or swapping start/end/error changes these assertions.
    @Test
    func approvedCuesHavePinnedPcmFormatAndDuration() throws {
        for asset in Self.approvedAssets {
            let url = Self.audioCueDirectory.appending(path: asset.name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                Issue.record("Missing approved sound cue: \(url.path)")
                continue
            }

            let file = try AVAudioFile(forReading: url)
            let description = file.fileFormat.streamDescription.pointee
            #expect(file.fileFormat.sampleRate == 48_000, "\(asset.name) must stay at 48 kHz")
            #expect(file.fileFormat.channelCount == 1, "\(asset.name) must stay mono")
            #expect(file.fileFormat.commonFormat == .pcmFormatInt16, "\(asset.name) must stay signed 16-bit PCM")
            #expect(description.mBitsPerChannel == 16, "\(asset.name) must carry 16 bits per channel")
            #expect(file.length == asset.frameCount, "\(asset.name) duration must stay pinned by its exact frame count")
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static var audioCueDirectory: URL {
        packageRoot.appending(path: "Sources/SlovoCore/Resources/AudioCues", directoryHint: .isDirectory)
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
