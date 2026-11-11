# Privacy And Security

Slovo is designed around a narrow data boundary: raw audio stays on the Mac, and
speech is recognized on the Mac. The Network column of Data Paths lists
everything Slovo sends off the Mac.

## Data Paths

| Data | Location | Network |
|---|---|---|
| Raw microphone audio | Local process memory | Never sent |
| Whisper ASR model | App-owned cache under `~/Library/Application Support/slovo/models` | Checked with Hugging Face at each model load, and downloaded where missing or changed — see Speech Model |
| Cleanup request: the transcript; every vocabulary term, with its expansion; the keyboard input language, when macOS reports one (no setting turns it off); while **Use system spell and grammar hints** is on, the words and fragments of the transcript the on-device checker flagged, with its suggestions; the cleanup model id and the writing style; when translating, the target language | Local process memory; the keyboard language and the checker's findings are computed at each dictation and not stored | Sent to OpenRouter for each dictation whose transcript has a non-whitespace character, while cleanup is on — see Cloud Cleanup |
| Personal vocabulary | Local SQLCipher-encrypted SQLite database | Only in the cleanup request; never logged |
| Key-scope request: `GET /api/v1/models/user`, carrying the API key and no dictated content | — | Sent to OpenRouter on each occasion listed under Cloud Cleanup |
| Cleaned text | Local process memory and target app field | Not logged |
| OpenRouter API key | macOS Keychain | Only as the authorization header of the cleanup and key-scope requests |
| Vocabulary miss events (the folded vocabulary term and the time, for each term a plain cleanup corrected; no transcript content) | Local SQLCipher-encrypted SQLite database | Never sent or logged; events older than 90 days are ignored, and deleted when the next event is written |
| App settings (push-to-talk and translate keys, recognition language, cleanup model id, writing style, translation target, the chosen microphone's name and identifier, switches) | `UserDefaults` | Not sent, except the values the cleanup request names |
| Update check and download | — | The GitHub update feed, hourly while **Automatically install updates** is on and at each **Check for Updates…** click; the release archive when the feed names a newer release — see Automatic Updates |
| Clipboard snapshot | Local pasteboard restore path | Never sent |

## Keychain

The OpenRouter key is stored as a macOS Keychain generic-password item:

- `slovo` / `openrouter-api-key`

Slovo reads the key from the Keychain the first time a request needs it and
keeps it in memory. When that copy is replaced or dropped is in
[docs/architecture.md](architecture.md), "Cleanup Mechanism".

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
again, and starts with an empty database. Slovo keeps one such file: a later
set-aside replaces an earlier `slovo.db.unreadable`. Recovery is manual. Moving
personalization to another Mac is not supported.

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

## Speech Model

Slovo loads the speech model through WhisperKit at launch. A load that failed
runs again at the next attempt: the next dictation, **Retry Setup**, or the
rebuild after a permission is granted. Every load asks Hugging Face
(`huggingface.co`) for the model repository's file list twice, then for the
metadata of each model file, before it loads the cached copy. The first load
downloads the model files and a tokenizer; a later load downloads only the files
that changed. A later load reads the cached tokenizer from disk, and asks Hugging
Face for it again only when that file is missing or cannot be loaded. The
requests name the model's repository and files and carry no dictated content.

Source: `argmax-oss-swift` 1.1.1 at commit `1bbc57cb`, read, not run. The first
file list and the call to `snapshot`:
[`WhisperKit.download`](https://github.com/argmaxinc/argmax-oss-swift/blob/1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4/Sources/WhisperKit/Core/WhisperKit.swift#L262-L303).
The second file list:
[`HubApi.snapshot`](https://github.com/argmaxinc/argmax-oss-swift/blob/1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4/Sources/ArgmaxCore/External/Hub/HubApi.swift#L640).
The metadata request for each file, and the return without a download when the
file is unchanged:
[`HubFileDownloader.download`](https://github.com/argmaxinc/argmax-oss-swift/blob/1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4/Sources/ArgmaxCore/External/Hub/HubApi.swift#L486-L515).
The tokenizer, read from disk when cached and requested again when the file is missing or its load fails:
[`ModelUtilities.loadTokenizer`](https://github.com/argmaxinc/argmax-oss-swift/blob/1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4/Sources/WhisperKit/Utilities/ModelUtilities.swift#L17-L77).

## Permissions

First-run setup tracks only the blockers proven by the current runtime:
Microphone and Accessibility. Input Monitoring is requested only as a targeted
hotkey recovery path if the global event tap cannot start.

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
In the clear it carries elapsed times in milliseconds, the model-load state token,
and the Error cue's reason token. It also carries three numbers about each
dictation: the transcript's length in characters, the captured audio's sample
count, and how far into the recording, in seconds, recognition had confirmed text
at key-up. The key-up decode adds two fixed tokens: its plan, one of four names,
and a 0 or 1 flag for a retry without vocabulary bias. Five cue lines carry the
cue's name (one of three), and two of them also its elapsed milliseconds. They
carry dictation timing and no user text. A cleanup failure adds its kind and the
provider's HTTP status. Error text is logged privately; transcripts, cleaned text
and keys never reach the log.

## Clipboard

Text insertion uses clipboard paste because it is reliable for mixed Cyrillic and
Latin text. The injector checks secure input before touching the pasteboard,
restores the previous clipboard contents on exit, and fails closed for secure
fields.

## Cloud Cleanup

Cleanup is text-only and runs through OpenRouter while cleanup is on (the
default): **Clean Up Dictation** in the menu bar, **Clean up dictation** in
Settings → Cleanup. What each cleanup request carries is the cleanup-request row
of Data Paths. The request also names the app in two headers, `X-Title: Slovo`
and `HTTP-Referer: https://github.com/Akurganow/slovo`. With the setting off — or
with no OpenRouter key stored, which is the same effective off mode — the cleanup
path is never taken: no cleanup request is made, nothing is sent to OpenRouter,
and the raw final transcript is pasted once at key-up.

A dictation set to translate by the translate key is translated in the same
request; there is no second request. Raw audio still never leaves.

If OpenRouter is unavailable, rate-limited, misconfigured, or returns an
unusable response, Slovo falls back to the direct, untranslated transcript and
shows a transient error glyph instead of dropping the dictation.

While cleanup is on, Slovo also sends OpenRouter the key-scope request, so the
model pickers offer only the models your key can call. Slovo sends it:

- once the hotkey is ready after launch, and again after each setup retry (a
  permission granted, or **Retry Setup**) while the list is still unknown;
- when cleanup turns on: the switch turned back on, or a first key saved;
- when a new key replaces the saved one;
- after a cleanup request that OpenRouter answers with HTTP status 404.

When a new key is saved, or cleanup is switched off and on, while a request is
still running, Slovo discards that request's answer and sends a new one. After a
404, no new request starts while one is running. A failed request is not
retried; the next occasion tries again.

## Automatic Updates

Updates download silently in the background. The feed request names the app and
its version in its `User-Agent` header and sends no system profile; nothing
about your dictation is sent.

Source: Sparkle 2.10.0 at commit `eef1a539`, read, not run. The `User-Agent`:
[`SPUUserAgent+Private.m`](https://github.com/sparkle-project/Sparkle/blob/eef1a539a373c1f1a320624b1130fc5de7b2e100/Sparkle/SPUUserAgent+Private.m#L18-L22).
A system profile is sent only while `SUSendProfileInfo` is true, and an unset key
reads as NO:
[`SPUUpdaterSettings.m`](https://github.com/sparkle-project/Sparkle/blob/eef1a539a373c1f1a320624b1130fc5de7b2e100/Sparkle/SPUUpdaterSettings.m#L349-L352),
[`SUHost.m`](https://github.com/sparkle-project/Sparkle/blob/eef1a539a373c1f1a320624b1130fc5de7b2e100/Sparkle/SUHost.m#L400-L409).
`Resources/Info.plist` sets neither `SUSendProfileInfo` nor
`SUEnableSystemProfiling`, the key that lets the permission prompt offer the
profile; the Sparkle documentation gives it the default NO
([Customization](https://github.com/sparkle-project/sparkle-project.github.io/blob/6524f21db542632ad754264cd4d529195f8f4c55/documentation/customization/index.md#L29),
read at `6524f21`).
