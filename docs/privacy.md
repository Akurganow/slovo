# Privacy And Security

Slovo is designed around a narrow data boundary: raw audio stays local, and only
transcript text may leave the machine when OpenRouter cleanup is attempted.

## Data Paths

| Data | Location | Network |
|---|---|---|
| Raw microphone audio | Local process memory | Never sent |
| Whisper ASR model | App-owned cache under Application Support | Downloaded once from Hugging Face on first use, then fully local |
| Transcript text | Local process memory | Sent only to OpenRouter for cleanup attempts (plus a target-language name when translating) |
| Cleaned text | Local process memory and target app field | Not logged |
| OpenRouter API key | macOS Keychain | Used only as an authorization header |
| Personal vocabulary | Local SQLite database | Used as prompt/context terms, never logged |
| Clipboard snapshot | Local pasteboard restore path | Never sent |

## Keychain

The OpenRouter key is stored as a macOS Keychain generic-password item:

- `slovo` / `openrouter-api-key`

The key is read lazily when cleanup runs. Updating the key through the app writes
the new value to Keychain.

Stable code signing matters. macOS Keychain and privacy permissions use the app's
identity when deciding whether the current binary is trusted. Ad-hoc builds or
frequently changing bundle identities can cause repeated prompts.

## Local Files

Slovo caches the WhisperKit (Whisper) model under Application Support, in
app-owned storage. It must not download the model into the user's Documents or
the WhisperKit SDK's default home Hugging Face cache; `WhisperKitEngine` pins the
download base to Application Support for exactly this reason.

These files are intentionally not tracked:

- `data/slovo.db*`
- `data/seed*.sql`
- `.env*`
- signing keys and certificate bundles
- credential JSON or token files

The checked-in schema is safe; user data and seed content are not.

## Permissions

First-run setup tracks only the blockers proven by the current runtime:
Microphone and Accessibility. Input Monitoring is requested only as a targeted
hotkey recovery path if the global event tap cannot start. `Info.plist` still
declares a Speech Recognition usage string left over from the earlier Apple
Speech path; WhisperKit does not use the Speech framework, so the string is
vestigial and is not a first-run blocker.

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

Cleanup is text-only and runs through OpenRouter while the **Clean Up
Dictation** setting is on (the default). With the setting off — or with no
OpenRouter key stored, which is the same effective off mode — the cleanup path
is never taken: the whole dictation stays on-device with zero network requests
and the raw final transcript is pasted once at key-up.

A dictation held with Control is translated in the same request, so translation
adds no new category of data leaving the Mac: it carries the same transcript
text already sent for cleanup, plus the name of the target language. Raw audio
still never leaves.

If OpenRouter is unavailable, rate-limited, misconfigured, or returns an
unusable response, Slovo falls back to the direct, untranslated transcript and
shows a transient error glyph instead of dropping the dictation.

## Automatic Updates

When automatic updates are enabled (the default), Slovo checks GitHub about once
an hour for a newer release and downloads it silently in the background; nothing
about your dictation is sent. The **Automatically install updates** switch in
Settings → General turns scheduled checking off — with it off, Slovo makes no
update-related network requests on its own; the menu-bar **Check for Updates…**
row still performs a one-shot check, but only when you click it.
