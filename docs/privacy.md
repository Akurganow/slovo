# Privacy And Security

Slovo is designed around a narrow data boundary: raw audio stays on the Mac, and
speech is recognized on the Mac. The Network column of Data Paths lists
everything Slovo sends off the Mac and when. Nothing else leaves the machine.

## Data Paths

| Data | Location | Network |
|---|---|---|
| Raw microphone audio | Local process memory | Never sent |
| Whisper ASR model | App-owned cache under `~/Library/Application Support/slovo/models` | Downloaded from Hugging Face on first use. Every launch checks it with Hugging Face, with no dictated content — see Speech Model |
| Transcript text | Local process memory | Sent to OpenRouter in each cleanup request — see Cloud Cleanup |
| Personal vocabulary | Local SQLCipher-encrypted SQLite database | Every term, with its expansion, is sent to OpenRouter in each cleanup request; never logged |
| Keyboard input language | Read at each dictation, not stored | Sent to OpenRouter in a cleanup request whenever macOS reports one; no setting turns it off |
| Spell and grammar findings (words and fragments of the transcript the on-device checker flagged, with its suggestions) | Computed at each dictation, not stored | Sent to OpenRouter in each cleanup request while **Use system spell and grammar hints** is on |
| Key model scope | OpenRouter account metadata | One `GET /api/v1/models/user` on each occasion under Cloud Cleanup; carries the API key, no dictated content |
| Cleaned text | Local process memory and target app field | Not logged |
| OpenRouter API key | macOS Keychain | Used only as the authorization header of the two OpenRouter requests |
| Vocabulary miss events (folded vocabulary surfaces + timestamps of dictations where the cleaner corrected the term; no transcript content) | Local SQLCipher-encrypted SQLite database | Never sent; pruned to the last 90 days whenever new events are recorded; reads ignore anything older; never logged |
| App settings (keys, recognition language, cleanup model id, writing style, translation target, the chosen microphone's name and identifier, switches) | `UserDefaults` | Never sent as settings. A cleanup request names the cleanup model and carries the writing style and, when translating, the target language |
| Update check and download | — | The GitHub update feed, hourly while automatic updates are on, and the release archive when a newer release exists — see Automatic Updates |
| Clipboard snapshot | Local pasteboard restore path | Never sent |

## Keychain

The OpenRouter key is stored as a macOS Keychain generic-password item:

- `slovo` / `openrouter-api-key`

Two requests use the key: the key-scope request (Cloud Cleanup says when it is
sent) and each cleanup request. Slovo reads the key's value from the Keychain
the first time one of them needs it and keeps it in memory. Saving a key writes
it to the Keychain and replaces the copy. A failed save or a successful removal
drops the copy, so the next request reads the Keychain again.

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

Slovo loads the speech model at launch, through WhisperKit. The first launch
downloads the model files, and a tokenizer, from Hugging Face (`huggingface.co`).
Every later launch asks Hugging Face for the model repository's file list twice,
then for the metadata of each model file, before it loads the cached copy. The
requests name the model's repository and files and carry no dictated content.
When the remote files are unchanged, nothing is downloaded.

Source: `argmax-oss-swift` 1.1.1 at commit `1bbc57cb`, read, not run. The first
file list and the call to `snapshot`:
[`WhisperKit.download`](https://github.com/argmaxinc/argmax-oss-swift/blob/1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4/Sources/WhisperKit/Core/WhisperKit.swift#L262-L303).
The second file list:
[`HubApi.snapshot`](https://github.com/argmaxinc/argmax-oss-swift/blob/1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4/Sources/ArgmaxCore/External/Hub/HubApi.swift#L639).
The metadata request for each file, and the return without a download when the
file is unchanged:
[`HubFileDownloader.download`](https://github.com/argmaxinc/argmax-oss-swift/blob/1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4/Sources/ArgmaxCore/External/Hub/HubApi.swift#L486-L515).

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
Settings → Cleanup. Each cleanup request carries:

- the transcript;
- every vocabulary term, with its expansion where one is stored;
- the active keyboard input language, when macOS reports one;
- while **Use system spell and grammar hints** is on (the default), the words and
  fragments the on-device checker flagged, with its suggestions;
- the cleanup model id and the chosen writing style.

It also names the app in two headers, `X-Title: Slovo` and
`HTTP-Referer: https://github.com/Akurganow/slovo`. With the setting off — or
with no OpenRouter key stored, which is the same effective off mode — the cleanup
path is never taken: the dictation makes zero network requests and the raw final
transcript is pasted once at key-up.

A dictation set to translate by the translate key is translated in the same
request. It carries everything a cleanup request carries, plus the name of the
target language. Raw audio still never leaves.

If OpenRouter is unavailable, rate-limited, misconfigured, or returns an
unusable response, Slovo falls back to the direct, untranslated transcript and
shows a transient error glyph instead of dropping the dictation.

While cleanup is on, Slovo also sends OpenRouter a metadata request,
`GET /api/v1/models/user`, so the model pickers offer only the models your key
can call. It carries the API key and no dictated content. Slovo sends it:

- once the hotkey is ready after launch, and again after each setup retry (a
  permission granted, or **Retry Setup**) while the list is still unknown;
- when cleanup turns on: the switch turned back on, or a first key saved;
- when a new key replaces the saved one;
- after a cleanup request that OpenRouter answers with HTTP status 404.

It is never sent while cleanup is off or before the hotkey is ready. When a new
key is saved, or cleanup is switched off and on, while a request is still
running, Slovo discards that request's answer and sends a new one. After a 404,
no new request starts while one is running. A failed request is not retried; the
next occasion tries again.

## Automatic Updates

When automatic updates are enabled (the default), Slovo checks GitHub about once
an hour for a newer release and downloads it silently in the background; nothing
about your dictation is sent. The check is one request for the update feed. It
names the app and its version in its `User-Agent` header and sends no system
profile. The **Automatically install updates** switch in Settings → General turns
scheduled checking off — with it off, Slovo makes no update-related network
requests on its own; the menu-bar **Check for Updates…** row still performs a
one-shot check, but only when you click it.

Source: Sparkle 2.10.0 source,
[`SPUUserAgent+Private.m`](https://github.com/sparkle-project/Sparkle/blob/eef1a539a373c1f1a320624b1130fc5de7b2e100/Sparkle/SPUUserAgent+Private.m#L18-L22);
Sparkle documentation, [Customization](https://sparkle-project.org/documentation/customization/)
(`SUEnableSystemProfiling`, default NO), read at
[`6524f21`](https://github.com/sparkle-project/sparkle-project.github.io/blob/6524f21db542632ad754264cd4d529195f8f4c55/documentation/customization/index.md#L29).
`Resources/Info.plist` sets no `SUEnableSystemProfiling`.
