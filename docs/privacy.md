# Privacy And Security

Slovo is designed around a narrow data boundary: raw audio stays local, and only
transcript text may leave the machine when cloud cleanup is enabled.

## Data Paths

| Data | Location | Network |
|---|---|---|
| Raw microphone audio | Local process memory | Never sent |
| Transcript text | Local process memory | Sent only to OpenRouter when cleanup is enabled |
| Cleaned text | Local process memory and target app field | Not logged |
| OpenRouter API key | macOS Keychain | Used only as an authorization header |
| Personal vocabulary | Local SQLite database | Used as prompt/context terms, never logged |
| Clipboard snapshot | Local pasteboard restore path | Never sent |

## Keychain

The OpenRouter key is stored as a macOS Keychain generic-password item:

- `slovo` / `openrouter-api-key`

The key is read once during startup setup and cached in process memory. Updating
the key through the app writes the new value to Keychain and replaces the
in-memory copy.

Stable code signing matters. macOS Keychain and privacy permissions use the app's
identity when deciding whether the current binary is trusted. Ad-hoc builds or
frequently changing bundle identities can cause repeated prompts.

## Local Files

These files are intentionally not tracked:

- `data/slovo.db*`
- `data/seed*.sql`
- `.env*`
- signing keys and certificate bundles
- credential JSON or token files

The checked-in schema is safe; user data and seed content are not.

## Logging

Logs must not contain:

- transcript text
- cleaned text
- prompts
- API keys
- API response bodies
- database row payloads
- raw Accessibility context

Runtime logging is limited to coarse status, counts, lengths, and failure classes.

## Clipboard

Text insertion uses clipboard paste because it is reliable for mixed Cyrillic and
Latin text. The injector checks secure input before touching the pasteboard,
restores the previous clipboard contents on exit, and fails closed for secure
fields.

## Cloud Cleanup

Cleanup is optional and text-only. Turning cleanup off uses local pass-through
behavior, preserving the recognized words without contacting OpenRouter.

If OpenRouter is unavailable, rate-limited, misconfigured, or returns an
unusable response, Slovo falls back to the direct transcript and shows a
transient error glyph instead of dropping the dictation.
