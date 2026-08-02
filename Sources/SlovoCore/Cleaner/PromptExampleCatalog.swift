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

    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

    private static func load() -> PromptExampleCatalog {
        guard
            let url = SlovoCoreResourceBundle.resolve()?.url(forResource: "PromptExamples", withExtension: "xml"),
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
