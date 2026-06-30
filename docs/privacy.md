# Privacy And Security

Loqui is designed around a narrow data boundary: raw audio stays local, and only
transcript text may leave the machine when cloud cleanup is enabled.

## Data Paths

| Data | Location | Network |
|---|---|---|
| Raw microphone audio | Local process memory | Never sent |
| Transcript text | Local process memory | Sent only to the selected cleanup provider when cleanup is enabled |
| Cleaned text | Local process memory and target app field | Not logged |
| Provider API keys | macOS Keychain | Used only as authorization headers |
| Personal vocabulary | Local SQLite database | Used as prompt/context terms, never logged |
| Clipboard snapshot | Local pasteboard restore path | Never sent |

## Keychain

Anthropic and OpenAI keys are stored as separate macOS Keychain generic-password
items:

- `loqui` / `anthropic-api-key`
- `loqui` / `openai-api-key`

The selected key is read once during startup setup and cached in process memory.
Updating a key through the app writes the new value to Keychain and replaces the
in-memory copy.

Stable code signing matters. macOS Keychain and privacy permissions use the app's
identity when deciding whether the current binary is trusted. Ad-hoc builds or
frequently changing bundle identities can cause repeated prompts.

## Local Files

These files are intentionally not tracked:

- `data/loqui.db*`
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

Cloud cleanup is optional and text-only. Turning cleanup off uses local
pass-through behavior, preserving the recognized words without contacting a
provider.
