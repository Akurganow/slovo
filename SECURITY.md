# Security Policy

Slovo is an early-stage local dictation app. The security model is intentionally
simple: raw audio stays on the Mac, while transcript text may be sent to
OpenRouter when cleanup is enabled.

## Supported Versions

| Version | Supported |
|---|---|
| 0.0.x | Yes |

## Reporting A Vulnerability

Please do not include secrets, transcripts, local vocabulary, personal data,
private work terminology, or local database contents in a public issue.

Use GitHub private vulnerability reporting if it is enabled for this repository.
If it is not available, open a minimal public issue that describes the class of
problem without sensitive details, and the maintainer will arrange a private
channel.

## Sensitive Data

Do not share:

- OpenRouter API keys.
- `.env` files or credential bundles.
- Signing keys, certificates, or notarization profiles.
- Local `data/slovo.db*` files.
- `data/seed*.sql` files.
- Raw transcripts containing personal or sensitive content.

## Current Boundaries

- API keys are stored in macOS Keychain.
- Raw audio is intended to stay local.
- Transcript text can leave the machine only through OpenRouter when cleanup is
  enabled.
- The app is not sandboxed because it needs Accessibility/Input Monitoring
  behavior for the global push-to-talk workflow.
