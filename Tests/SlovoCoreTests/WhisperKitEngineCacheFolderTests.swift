import Foundation
import Testing

@testable import SlovoCore

@Suite("WhisperKit engine cache folder")
struct WhisperKitEngineCacheFolderTests {
    /// The folder a cached model is loaded from is the one WhisperKit's download wrote.
    /// Stated sensitivity: drop a path segment, misspell the repository or the
    /// `openai_whisper-` prefix, or build the path outside `base` → RED.
    /// A directory URL's path ends in a slash, so the expected string does too.
    @Test
    func cachedModelFolderIsWhereTheDownloadWritesTheModel() {
        let base = URL(filePath: "/tmp/slovo-test-base", directoryHint: .isDirectory)
        let folder = WhisperKitEngine.cachedModelFolder(model: "large-v3-v20240930_turbo_632MB", base: base)
        #expect(folder.path(percentEncoded: false) == "/tmp/slovo-test-base/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo_632MB/")
    }
}
