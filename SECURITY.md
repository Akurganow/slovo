# Security Policy

Slovo is an early-stage local dictation app. The security model is intentionally
simple: raw audio stays on the Mac.

## Supported Versions

Only the latest release is supported; fixes ship only in a new release. With
**Automatically install updates** on (the default), Slovo downloads it and
offers **Restart** in the menu to install it.

## Reporting A Vulnerability

Please do not include secrets, transcripts, local vocabulary, personal data,
private work terminology, or local database contents in a public issue.

Report privately through GitHub's [private vulnerability reporting](https://github.com/Akurganow/slovo/security/advisories/new),
which is enabled for this repository (Security → Advisories → Report a
vulnerability). If you cannot use it, open a minimal public issue that describes
the class of problem without sensitive details, and the maintainer will arrange a
private channel.

## Sensitive Data

Do not share:

- OpenRouter API keys.
- `.env` files or credential bundles.
- Signing keys, certificates, or notarization profiles.
- The personalization database (`~/Library/Application Support/slovo/slovo.db*`) or a local `data/*.db*` file.
- `data/seed*.sql` files.
- Raw transcripts containing personal or sensitive content.

## Current Boundaries

- API keys are stored in macOS Keychain.
- Raw audio is intended to stay local.
- While cleanup is on, each dictation's transcript goes to OpenRouter;
  [docs/privacy.md](docs/privacy.md), "Data Paths", lists the rest of what
  leaves the Mac.
- The app is not sandboxed because it needs Accessibility/Input Monitoring
  behavior for the global push-to-talk workflow.
