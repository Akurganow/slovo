import AppKit
import SlovoCore
import SwiftUI

/// The About window's content: brand header, a short "how it works" guide, a
/// privacy note, and footer links. It takes its dynamic values (version, build,
/// trigger key name) as plain parameters so it renders in previews and tests
/// without reaching into `Bundle` or the config store — the window supplies them.
@MainActor
struct AboutView: View {
    let version: String
    let build: String
    /// The push-to-talk key's display name (e.g. `fn`, `Right ⌘`), shown as a keycap
    /// in the first guide row so the guide matches the user's actual binding.
    let triggerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            guide
            privacyNote
            footer
        }
        .padding()
        .frame(width: 400)
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
            Text(AboutInfo.versionLine(marketingVersion: version, buildNumber: build))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Private push-to-talk dictation for macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideRow(systemImage: "mic.fill", description: "Release — the cleaned text lands in the focused app.") {
                HStack(spacing: 4) {
                    Text("Hold")
                    Keycap(label: triggerName)
                    Text("to dictate")
                }
            }
            GuideRow(systemImage: "globe", description: "Hold Control too; your words arrive in the target language picked in the menu.") {
                HStack(spacing: 4) {
                    Text("Add")
                    Keycap(label: "⌃")
                    Text("to translate")
                }
            }
            GuideRow(
                systemImage: "wand.and.stars",
                description: "Cleanup and translation need your OpenRouter API key — without it you get the raw transcript. Key and model: Settings ▸ Cleanup."
            ) {
                Text("Cleanup polishes every dictation")
            }
            GuideRow(systemImage: "text.book.closed", description: "Names, brands, jargon — Settings ▸ Vocabulary.") {
                Text("Vocabulary keeps your terms verbatim")
            }
        }
    }

    private var privacyNote: some View {
        Text("Speech is recognized on your Mac. Only the text leaves your device, and only to your OpenRouter account for cleanup.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Link("Releases on GitHub", destination: Self.releasesURL)
            Text("·").foregroundStyle(.secondary)
            Link("Support on Ko-fi", destination: Self.supportURL)
            Text("·").foregroundStyle(.secondary)
            // A file, not a web URL, so it is a link-styled Button rather than a
            // `Link`: it resolves the bundled notices at tap time, keeping this
            // view's rendering free of `Bundle` access (previews/tests still draw).
            Button("Acknowledgements") { Self.openAcknowledgements() }
                .buttonStyle(.link)
        }
        .font(.footnote)
    }

    /// Opens the third-party license notices bundled in the app's Resources
    /// (THIRD-PARTY-NOTICES.md, staged there by the packaging scripts) in the
    /// user's default handler.
    private static func openAcknowledgements() {
        guard let url = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md") else { return }
        NSWorkspace.shared.open(url)
    }

    private static let releasesURL = URL(string: "https://github.com/Akurganow/slovo/releases")!
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
