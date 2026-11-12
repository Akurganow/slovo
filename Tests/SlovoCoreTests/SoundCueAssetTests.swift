import CryptoKit
import Foundation
import Testing

// The user-approved Lower & Soft cue triplet is a shipped product resource, not
// a replaceable test fixture. Its SHA-256 digests pin the reviewed bytes.
@Suite("Sound cue assets")
struct SoundCueAssetTests {
    private struct ApprovedAsset: Sendable {
        let name: String
        let sha256: String
    }

    private static let approvedAssets = [
        ApprovedAsset(
            name: "start.wav",
            sha256: "bf3bc40f1f4bcda58cd43b5b61c1d0fea302562dcb3c9b99de1e4a9738212ae2"
        ),
        ApprovedAsset(
            name: "end.wav",
            sha256: "a888874b6843bb0dfdce0c53f299241d1690eb7caf9ff861e32c2b11263b3d54"
        ),
        ApprovedAsset(
            name: "error.wav",
            sha256: "fb81e4e1c66e14ad930e88a0466cf72afe06a5f55dcfe8715457c79bd76c1f6e"
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
