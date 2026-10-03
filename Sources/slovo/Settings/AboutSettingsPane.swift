import SlovoCore
import SwiftUI

/// Settings → About: the brand header, a short "how it works" guide, a privacy
/// note, and footer links. The keycaps read the observed store, so a key changed
/// in General shows here at once.
@MainActor
struct AboutSettingsPane: View {
    // Unowned, not strong: AppDelegate (the only conformer) is an app-lifetime
    // singleton that always outlives this pane, matching DictationMenuBuilder's
    // `unowned let target: AppDelegate`.
    unowned let actions: any SettingsActions
    @ObservedObject private var store: AppStore

    init(actions: any SettingsActions) {
        self.actions = actions
        _store = ObservedObject(wrappedValue: actions.store)
    }

    /// The configured keys, shown as inline keycaps so the guide states the gesture
    /// the user actually has rather than the defaults.
    private var hotkeys: HotkeyConfiguration { store.state.config.hotkeyConfiguration }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            guide
            privacyNote
            footer
        }
        .padding()
        .frame(width: 420)
    }

    private var header: some View {
        VStack(spacing: 6) {
            // The brand glyph is Glagolitic Slovo "Ⱄ" (U+2C14), the same letter the
            // menu bar shows at idle; NotoSansGlagolitic-Regular is the app's
            // Glagolitic face (see MenuBarGlyphImage), and SwiftUI falls back to the
            // system cascade if it is unavailable.
            Text("Ⱄ")
                .font(.custom("NotoSansGlagolitic-Regular", size: 64))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // The wordmark is "Slovo" transliterated into Glagolitic — ⰔⰎⰑⰂⰑ
            // (Slovo, Ljudije, Onu, Vede, Onu, capital forms) — in the same face
            // as the brand glyph; VoiceOver still reads the Latin app name.
            Text("ⰔⰎⰑⰂⰑ")
                .font(.custom("NotoSansGlagolitic-Regular", size: 24))
                .accessibilityLabel("Slovo")
            // The dev marker's Dobro glyph renders through the same Glagolitic
            // cascade the header glyphs above already rely on, and only on dev
            // builds — where the wordmark proves the face is available.
            Text(Self.versionLine)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Private, on-device push-to-talk dictation for macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // Cleanup precedes translate so the "needs cleanup on" dependency reads
    // top-down.
    private var guide: some View {
        VStack(alignment: .leading, spacing: 12) {
            dictateRow
            cleanupRow
            translateRow
            vocabularyRow
        }
    }

    private var dictateRow: some View {
        GuideRow(
            systemImage: "mic.fill",
            description: "Release — the text lands in the focused app. Works out of the box: no account, no key required."
        ) {
            HStack(spacing: 4) {
                Text("Hold")
                Keycap(label: hotkeys.main.displayName)
                Text("to dictate")
            }
        }
    }

    private var cleanupRow: some View {
        GuideRow(
            systemImage: "wand.and.stars",
            description: "Add your own OpenRouter key to polish dictations into clean prose. "
                + "Without a key — or with cleanup switched off — the transcript is inserted exactly as spoken. "
                + "Key and model: Settings ▸ Cleanup."
        ) {
            Text("Cleanup is optional")
        }
    }

    private var translateRow: some View {
        let gesture = translateGestureCopy
        return GuideRow(
            systemImage: "globe",
            description: gesture.lead
                + "; your words arrive in the target language picked in the menu. Translation needs cleanup on."
        ) {
            HStack(spacing: 4) {
                Text(gesture.verb)
                Keycap(label: hotkeys.translate.displayName)
                Text("to translate")
            }
        }
    }

    /// The row's gesture-dependent words, decided in ONE place: the keycap verb and
    /// the sentence it opens must always describe the same gesture.
    private var translateGestureCopy: (verb: String, lead: String) {
        switch hotkeys.translateGesture {
        case .additional: return ("Add", "Hold it together with your dictation key")
        case .standalone: return ("Hold", "Hold it on its own")
        }
    }

    private var vocabularyRow: some View {
        GuideRow(systemImage: "text.book.closed", description: "Names, brands, jargon — Settings ▸ Vocabulary.") {
            Text("Vocabulary keeps your terms verbatim")
        }
    }

    private var privacyNote: some View {
        Text(
            "Speech is recognized on your Mac. Nothing leaves your device unless cleanup is on "
                + "— then only the transcript text goes to your own OpenRouter account."
        )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Link("Slovo on GitHub", destination: Self.repositoryURL)
            Text("·").foregroundStyle(.secondary)
            Link("Support on Ko-fi", destination: Self.supportURL)
            Text("·").foregroundStyle(.secondary)
            Button("Acknowledgements") { actions.openAcknowledgements() }
                .buttonStyle(.link)
        }
        .font(.footnote)
    }

    /// The bundle's version, build and dev-build marker are fixed for the process,
    /// so the line is composed once.
    private static let versionLine = AboutInfo.versionLine(
        marketingVersion: bundleString("CFBundleShortVersionString"),
        buildNumber: bundleString("CFBundleVersion"),
        isDevBuild: isDevBuild
    )

    /// True only when the dev launcher stamped `SlovoDevBuild` into the staged
    /// bundle's plist. A release plist never carries the key, so absence — or any
    /// non-true value — reads as production.
    private static var isDevBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "SlovoDevBuild") as? Bool) == true
    }

    /// The bundle's `key` as a string, or an em dash when the key is missing so the
    /// pane never shows an empty or crashed version line.
    private static func bundleString(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }

    private static let repositoryURL = URL(string: "https://github.com/Akurganow/slovo")!
    private static let supportURL = URL(string: "https://ko-fi.com/akurganow")!
}

/// One "how it works" row: a decorative SF Symbol, a title line (which may embed a
/// keycap), and a plain-language description below it.
@MainActor
private struct GuideRow<Title: View>: View {
    let systemImage: String
    let description: String
    @ViewBuilder let title: () -> Title

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title()
                    .font(.callout.weight(.medium))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A key rendered as a small monospaced keycap, drawn inline within a sentence so a
/// key name reads as a physical key rather than ordinary text.
@MainActor
private struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}
