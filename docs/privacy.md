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
| Personal vocabulary | Local SQLCipher-encrypted SQLite database | Used as prompt/context terms, never logged |
| Vocabulary miss events (folded vocabulary surfaces + timestamps of dictations where the cleaner corrected the term; no transcript content) | Local SQLCipher-encrypted SQLite database | Never sent; pruned to the last 90 days whenever new events are recorded; reads ignore anything older; never logged |
| App settings (hotkey, models, toggles) | `UserDefaults` | Never sent |
| Clipboard snapshot | Local pasteboard restore path | Never sent |

## Keychain

The OpenRouter key is stored as a macOS Keychain generic-password item:

- `slovo` / `openrouter-api-key`

The key is read lazily when cleanup runs. Updating the key through the app writes
the new value to Keychain.

Stable code signing matters. macOS Keychain and privacy permissions use the app's
identity when deciding whether the current binary is trusted. Ad-hoc builds or
frequently changing bundle identities can cause repeated prompts.

## Local Database Encryption

The personalization database (`~/Library/Application Support/slovo/slovo.db`) is
encrypted at rest with SQLCipher. It holds hand-entered vocabulary terms and
vocabulary-miss events today; the provisioned `corrections` table would carry
fragments of dictated text, and encryption landed before that table went live.

The key is stored nowhere. Slovo derives it on demand — at every database
connection setup — from this Mac's hardware identifier (the IOKit
`IOPlatformUUID`) through HKDF-SHA256. The Keychain is deliberately not used:
ad-hoc and development builds risk repeated Keychain prompts under unstable code
signing (see **Keychain** above), and a Keychain reset would orphan the database.

**Protected:** copies of the database made from this version onward that leave
this Mac — Time Machine, cloud sync, manual copies — and casual, untargeted reads
of the file by other programs on the machine.

**Deliberately not protected:**

- A targeted attack by a program written specifically against Slovo on this Mac.
  The derivation is public — open-source code plus a world-readable hardware
  identifier — so on this machine the encryption is obfuscation only; the real
  guarantee is for copies that leave the Mac.
- Active malware running with your privileges. No application-level mechanism
  defends against that.
- Physical remnants of the old plaintext file on disk after migration. APFS and
  SSDs offer no secure erase; FileVault covers that layer. There is also a brief
  named-file window: the migration puts the encrypted copy in place by exchanging
  it with the original, so a crash at that instant can leave the plaintext
  original beside the database as `slovo.db.encrypting`. Slovo deletes any such
  leftover on every launch, before it opens the database.
- Backups and copies made **before** this version. They stay plaintext wherever
  they already are: encryption applies from this version onward and cannot reach
  back into existing Time Machine snapshots or cloud backups.

Because the key comes from the hardware, the database opens only on the Mac that
created it. One copied from another Mac — or read after a logic-board
replacement — cannot be decrypted, so Slovo renames it to `slovo.db.unreadable`
beside `slovo.db` in `~/Library/Application Support/slovo/`, never reads it
again, and starts with an empty database. The bytes are kept, not deleted;
recovery is manual. Moving personalization to another Mac is not supported.

A database created by an earlier, pre-encryption version is re-encrypted in place
on the first launch after the update, invisibly. If re-encryption cannot complete,
that session runs on the plaintext file unchanged and the next launch retries.
The migration is **one-way**: once a build with encryption has opened the
database, older Slovo builds can no longer read it.

The feature is silent throughout — no dialogs, no notifications, no log lines. A
set-aside, or a migration that keeps failing, is therefore diagnosable only from
what is on disk, never from a log.

## Local Files

Slovo caches the WhisperKit (Whisper) model under Application Support, in
app-owned storage. It must not download the model into the user's Documents or
the Argmax OSS SDK's (formerly WhisperKit) default home Hugging Face cache;
`WhisperKitEngine` pins the download base to Application Support for exactly
this reason.

The `.gitignore` rules make these categories uncommittable, whether or not a
matching file exists on disk today:

- `data/*.db*` — any local database and its sidecars
- `data/seed*.sql` — any seed variant
- `.env*` — dotenv files
- `secrets/`, `*.key`, `*.pem`, `*.p12`, `*.p8` — key and certificate material
- `*.token`, `credentials*.json`, `id_rsa*` — tokens, credential JSON, SSH keys

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

A dictation set to translate by the translate key is translated in the same
request, so translation adds no new category of data leaving the Mac: it carries
the same transcript text already sent for cleanup, plus the name of the target
language. Raw audio still never leaves.

If OpenRouter is unavailable, rate-limited, misconfigured, or returns an
unusable response, Slovo falls back to the direct, untranslated transcript and
shows a transient error glyph instead of dropping the dictation.

While cleanup is on, Slovo also makes one metadata request to OpenRouter —
`GET /api/v1/models/user` — so the model pickers only offer models your key can
actually call. It fires at startup, whenever the API key changes, when the
recognition pipeline restarts before the list has been fetched, and once more
after a cleanup request is refused for a policy-blocked model (to refresh the
list). It carries the API key and no dictated content, consumes no credits, and
never runs while cleanup is off or before the hotkey is ready.

## Automatic Updates

When automatic updates are enabled (the default), Slovo checks GitHub about once
an hour for a newer release and downloads it silently in the background; nothing
about your dictation is sent. The **Automatically install updates** switch in
Settings → General turns scheduled checking off — with it off, Slovo makes no
update-related network requests on its own; the menu-bar **Check for Updates…**
row still performs a one-shot check, but only when you click it.
