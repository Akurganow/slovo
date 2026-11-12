import Foundation
import Testing

@testable import SlovoCore

// `WhisperKitEngine.load()` tries the cached configuration and falls back to the
// download one. The model is never loaded here: these pin what makes each
// configuration that load, through the library's public properties.
@Suite("WhisperKit engine load configurations")
struct WhisperKitEngineLoadConfigTests {
    private static let model = "large-v3-v20240930_turbo_632MB"
    private static let base = URL(filePath: "/tmp/slovo-test-base", directoryHint: .isDirectory)

    /// The folder a cached model is loaded from is the repository folder plus the variant
    /// folder under the download base. The expected string pins the SDK's repository layout.
    /// A directory URL's path ends in a slash, so the expected string does too.
    /// Stated sensitivity: an SDK change of that layout, a misspelled repository or
    /// `openai_whisper-` prefix, or a path built outside `base` → RED.
    @Test
    func cachedModelFolderIsTheRepositoryFolderPlusTheVariantFolder() {
        let folder = WhisperKitEngine.cachedModelFolder(model: Self.model, base: Self.base)
        #expect(folder.path(percentEncoded: false) == "/tmp/slovo-test-base/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo_632MB/")
    }

    /// The cached load makes no request and loads from the folder the download wrote.
    /// Stated sensitivity: `download: true` (every cached launch lists the repository on
    /// the network), a nil model folder (the load downloads), or a model folder that
    /// never matches the cache (every launch downloads) → RED; dropping `downloadBase`
    /// from this configuration → RED.
    @Test
    func theCachedLoadMakesNoRequestAndReadsTheCacheFolder() {
        let config = WhisperKitEngine.cachedLoadConfig(model: Self.model, base: Self.base)

        #expect(config.download == false)
        #expect(config.modelFolder == WhisperKitEngine.cachedModelFolder(model: Self.model, base: Self.base).path(percentEncoded: false))
        #expect(config.downloadBase == Self.base)
    }

    /// The fallback fetches the model into the app's folder, so a missing file downloads.
    /// Stated sensitivity: `download: false` (a first run never loads), a model folder
    /// set (the library skips the download) or no `downloadBase` (the download lands
    /// under `Documents/huggingface`) → RED.
    @Test
    func theDownloadLoadFetchesTheModelIntoTheBase() {
        let config = WhisperKitEngine.downloadLoadConfig(model: Self.model, base: Self.base)

        #expect(config.download == true)
        #expect(config.modelFolder == nil)
        #expect(config.downloadBase == Self.base)
    }
}
