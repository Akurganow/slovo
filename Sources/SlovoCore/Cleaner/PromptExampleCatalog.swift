import Foundation
import os

/// One few-shot pair rendered into a prompt's examples block.
public struct PromptExample: Equatable, Sendable {
    public let transcript: String
    public let output: String

    public init(transcript: String, output: String) {
        self.transcript = transcript
        self.output = output
    }
}

/// The few-shot example sets bundled with the app. The XML resource in the
/// repository is the source of truth; the build imports it into the app bundle
/// and it is parsed exactly once here. A missing resource BUNDLE, missing XML,
/// or malformed XML all degrade to empty sets — prompts still work, only
/// without examples — and the test suite pins the bundled resource's content,
/// so breakage surfaces in CI, not as a runtime failure while the user dictates.
public struct PromptExampleCatalog: Sendable {
    /// Language-neutral examples (mathematical notation) rendered in BOTH
    /// modes and for every translation target: their outputs carry no prose
    /// in a fixed language, so they need no per-language verification.
    public let shared: [PromptExample]
    public let cleanup: [PromptExample]
    /// Per-target translation examples keyed by recognition language CODE
    /// ("en", "es", …), never by display name — codes are the stable wire
    /// values, display names are presentation.
    public let translation: [String: [PromptExample]]

    public init(cleanup: [PromptExample], translation: [String: [PromptExample]], shared: [PromptExample] = []) {
        self.shared = shared
        self.cleanup = cleanup
        self.translation = translation
    }

    public static let bundled: PromptExampleCatalog = load()

    /// `Bundle.module` traps when the staged resource bundle is absent — at the
    /// first prompt build, mid-dictation — and its SwiftPM-generated lookup never
    /// checks Contents/Resources (it falls back to this dev machine's absolute
    /// .build path, so a staging mistake stays invisible locally and crashes
    /// everywhere else). Resolve the bundle by hand across the packaged-app, CLI,
    /// and test-runner locations, and return nil so a packaging mistake degrades
    /// to example-free prompts instead of crashing the app.
    private static func resourceBundle() -> Bundle? {
        let bundleName = "slovo_SlovoCore.bundle"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: BundleLocator.self).bundleURL.deletingLastPathComponent(),
            Bundle(for: BundleLocator.self).resourceURL,
        ]
        for candidate in candidates {
            if let url = candidate?.appendingPathComponent(bundleName),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }

    /// Anchor for `Bundle(for:)` so the lookup lands in whatever binary actually
    /// links SlovoCore (the app, a tool, or the test bundle).
    private final class BundleLocator {}

    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

    private static func load() -> PromptExampleCatalog {
        guard
            let url = resourceBundle()?.url(forResource: "PromptExamples", withExtension: "xml"),
            let document = try? XMLDocument(contentsOf: url),
            let root = document.rootElement()
        else {
            // The degradation is deliberate but must not be invisible: one static,
            // payload-free line makes a staging regression diagnosable in the field.
            diagnosticLog.error("prompt examples resource missing or unreadable; prompts run example-free")
            return PromptExampleCatalog(cleanup: [], translation: [:])
        }
        let shared = root.elements(forName: "shared").first.map(examples(in:)) ?? []
        let cleanup = root.elements(forName: "cleanup").first.map(examples(in:)) ?? []
        var translation: [String: [PromptExample]] = [:]
        let targets = root.elements(forName: "translation").first?.elements(forName: "target") ?? []
        for target in targets {
            guard let code = target.attribute(forName: "code")?.stringValue, !code.isEmpty else { continue }
            let pairs = examples(in: target)
            if !pairs.isEmpty {
                translation[code] = pairs
            }
        }
        return PromptExampleCatalog(cleanup: cleanup, translation: translation, shared: shared)
    }

    private static func examples(in element: XMLElement) -> [PromptExample] {
        element.elements(forName: "example").compactMap { node in
            guard
                let transcript = node.elements(forName: "transcript").first?.stringValue,
                let output = node.elements(forName: "output").first?.stringValue,
                !transcript.isEmpty, !output.isEmpty
            else { return nil }
            return PromptExample(transcript: transcript, output: output)
        }
    }
}
