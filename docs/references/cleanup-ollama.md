# Ollama local API (fallback cleanup)

Authoritative reference for slovo's offline/fallback transcript-cleanup backend: a
locally running [Ollama](https://ollama.com) server hosting a small multilingual
instruct model (e.g. `qwen2.5`). slovo talks to Ollama over plain HTTP on
`localhost` only.

All endpoint shapes below are verified against the official API docs (see
[Full sources](#full-sources)). Items that could not be confirmed against an
official source are marked `[UNVERIFIED]`.

## Purpose

- slovo's primary cleanup path is a hosted LLM. When the network or a hosted key
  is unavailable, slovo falls back to a **local** model served by Ollama, so
  cleanup keeps working fully offline.
- slovo's responsibility is narrow: it **only speaks HTTP** to an Ollama server
  the user already runs. slovo does **not** install Ollama, pull models, or
  manage the model lifecycle beyond the per-request `keep_alive` hint.
- If Ollama is not running or not installed, slovo must degrade to `PassThrough`
  (return the raw transcript unchanged) rather than error — see
  [Detect not running / degrade](#detect-not-running--degrade).

## Endpoint & requests

The Ollama server listens on `http://localhost:11434` by default. The relevant
endpoint for cleanup is `POST /api/chat`.

### POST /api/chat

Request body (fields slovo uses):

| Field        | Type    | Notes                                                                 |
|--------------|---------|-----------------------------------------------------------------------|
| `model`      | string  | Required. e.g. `"qwen2.5"`. slovo does not pull it; the user must.     |
| `messages`   | array   | Required. Each item: `{ "role": "system"\|"user"\|"assistant"\|"tool", "content": "..." }`. |
| `stream`     | bool    | Optional, **defaults to `true`**. slovo sets `false` for one-shot.     |
| `options`    | object  | Optional model params (e.g. `temperature`, `seed`).                    |
| `keep_alive` | string/number | Optional. See [keep_alive](#keep_alive).                         |

Streaming vs `stream: false`:

- With `stream: true` (the default), the response is a sequence of JSON objects,
  one per token chunk, each with `done: false` until a final object with
  `done: true`. slovo would have to concatenate `message.content` across chunks.
- With `stream: false`, the server returns a **single** JSON object containing
  the full assistant message. slovo uses this for cleanup — simpler to parse.

Non-streaming response (verbatim from official docs):

```json
{
  "model": "llama3.2",
  "created_at": "2023-12-12T14:13:43.416799Z",
  "message": {
    "role": "assistant",
    "content": "Hello! How are you today?"
  },
  "done": true,
  "done_reason": "stop",
  "total_duration": 5191566416,
  "load_duration": 2154458,
  "prompt_eval_count": 26,
  "prompt_eval_duration": 383809000,
  "eval_count": 298,
  "eval_duration": 4799921000
}
```

The cleaned text is at `message.content`. `done_reason` is `"stop"` on normal
completion (also `"load"` / `"unload"` for lifecycle-only calls — see below).

Streaming response objects look like (verbatim):

```json
{
  "model": "llama3.2",
  "created_at": "2023-08-04T08:52:19.385406455-07:00",
  "message": {
    "role": "assistant",
    "content": "The"
  },
  "done": false
}
```

### POST /api/generate (alternative)

`POST /api/generate` is the single-prompt sibling of `/api/chat`. Same base URL.
Request uses `prompt` (string) instead of `messages`, plus the same `model`,
`stream`, `options`, `keep_alive`. The non-streaming response carries the text in
the `response` field (not `message.content`). slovo prefers `/api/chat` because a
`system` + `user` message split expresses the cleanup instruction more cleanly,
but `/api/generate` is a valid alternative.

### OpenAI-compatible endpoint (alternative)

Ollama also exposes an OpenAI-compatible surface at
`http://localhost:11434/v1`, including `POST /v1/chat/completions`. It accepts the
standard OpenAI Chat Completions request/response shape, so slovo could reuse an
OpenAI client by pointing `base_url` at it. An API key is **required by the
client but ignored** by Ollama — pass any non-empty string (e.g. `"ollama"`).
This is useful if slovo shares one code path between the hosted OpenAI-style
backend and the local fallback; otherwise `/api/chat` is the native choice.

## keep_alive

`keep_alive` controls how long the model stays resident in memory after a
request (default: `5m`). This maps directly to slovo's `keepWarmSeconds` idea —
"load the model only around processing, then let it go".

Accepted values (verbatim semantics from the official FAQ):

- a duration string, such as `"10m"` or `"24h"`
- a number in **seconds**, such as `3600`
- any **negative** number, which keeps the model loaded in memory indefinitely
  (e.g. `-1` or `"-1m"`)
- `0`, which unloads the model immediately after generating a response

Mapping to slovo's `keepWarmSeconds`:

- `keepWarmSeconds == 0` → send `"keep_alive": 0` to unload right after the call.
- `keepWarmSeconds == N > 0` → send `"keep_alive": N` (seconds) so the model
  stays warm for the next utterance, then unloads.
- "keep loaded for the whole session" → send `"keep_alive": -1`.

A request with only `{ "model": "...", "keep_alive": 0 }` (no messages/prompt) is
a lifecycle-only call: it returns `done_reason: "unload"`. Likewise loading a
model returns `done_reason: "load"`. slovo generally does not need these — it
sets `keep_alive` on the actual cleanup request — but they exist for explicit
warm-up/teardown if desired.

The server-wide default can also be set via the `OLLAMA_KEEP_ALIVE` environment
variable, but per-request `keep_alive` overrides it. slovo should always send an
explicit per-request value and not rely on the server default.

## Minimal Swift URLSession example

Cleans a transcript with `qwen2.5`, non-streaming, parses `message.content`, and
sets `keep_alive`. Plain `URLSession`, no third-party deps.

```swift
import Foundation

struct OllamaChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let stream: Bool
    let keep_alive: Int   // seconds; 0 = unload now, -1 = keep loaded
}

struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }
    let message: Message
    let done: Bool
    let done_reason: String?
}

enum OllamaError: Error {
    case notRunning          // connection refused / cannot connect
    case httpStatus(Int)
    case emptyResponse
}

/// Cleans `transcript` via a local Ollama model. `keepWarmSeconds` maps to
/// `keep_alive`: 0 unloads immediately, a positive value keeps the model warm
/// for that many seconds, -1 keeps it loaded indefinitely.
func cleanTranscript(
    _ transcript: String,
    model: String = "qwen2.5",
    keepWarmSeconds: Int = 30
) async throws -> String {
    let url = URL(string: "http://localhost:11434/api/chat")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = OllamaChatRequest(
        model: model,
        messages: [
            .init(role: "system",
                  content: "You clean up raw speech-to-text transcripts. "
                         + "Fix punctuation, casing, and obvious recognition "
                         + "errors. Preserve the speaker's language and meaning. "
                         + "Reply with only the cleaned text."),
            .init(role: "user", content: transcript),
        ],
        stream: false,            // single JSON object back
        keep_alive: keepWarmSeconds
    )
    request.httpBody = try JSONEncoder().encode(body)

    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(for: request)
    } catch let urlError as URLError where
                urlError.code == .cannotConnectToHost ||
                urlError.code == .cannotFindHost {
        // Ollama not running / not installed -> caller degrades to PassThrough.
        throw OllamaError.notRunning
    }

    guard let http = response as? HTTPURLResponse else {
        throw OllamaError.emptyResponse
    }
    guard http.statusCode == 200 else {
        throw OllamaError.httpStatus(http.statusCode)
    }

    let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
    let cleaned = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { throw OllamaError.emptyResponse }
    return cleaned
}
```

`[UNVERIFIED]` The exact `URLError.Code` raised when nothing is listening on
`11434` is environment-dependent; `.cannotConnectToHost` is the typical case on
macOS, but slovo should treat the broader set of "cannot reach host" `URLError`
codes (and timeouts) as "not running" and fall back. The request/response JSON
shapes and `keep_alive` semantics above are verified against the official docs.

## Detect not running / degrade

Ollama not running or not installed surfaces as a **connection failure** to
`http://localhost:11434`, not an HTTP error code — there is no server to answer.
In `URLSession` this is a thrown `URLError` (commonly `.cannotConnectToHost`),
caught in the example above.

slovo's fallback policy:

1. Attempt `POST /api/chat` against `localhost:11434`.
2. On connection refused / cannot connect / timeout → treat as "Ollama
   unavailable" and **degrade to `PassThrough`** (return the raw transcript).
3. On HTTP 404 for the model or a non-200 status (e.g. model not pulled) → also
   degrade to `PassThrough`; do not attempt to pull the model (slovo does not
   manage models).

Optional liveness probe before sending a large transcript: a cheap
`GET http://localhost:11434/api/tags` (lists locally available models) succeeds
only if the server is up, and lets slovo confirm the configured `model` is
present in the returned `models[].name` list. If the probe fails to connect,
skip straight to `PassThrough`.

## slovo gotchas

- **slovo does not manage models.** Pulling (`ollama pull qwen2.5`) and updates
  are the user's responsibility, done out-of-band via the Ollama CLI. slovo only
  issues HTTP calls; if the model is missing, degrade rather than pull.
- **`stream` defaults to `true`.** Always send `"stream": false` for one-shot
  cleanup, or you must reassemble chunked `message.content` yourself.
- **Always send an explicit `keep_alive`.** Don't rely on the server's `5m`
  default or `OLLAMA_KEEP_ALIVE`; set it from `keepWarmSeconds` so memory is held
  only around processing (`0` to unload immediately, positive seconds to stay
  warm, `-1` to pin).
- **Not running == connection error, not an HTTP status.** Catch the `URLError`;
  do not expect a JSON error body.
- **`message.content` vs `response`.** `/api/chat` returns the text under
  `message.content`; `/api/generate` returns it under `response`. Decode the
  shape that matches the endpoint you call.
- **First call after a cold start is slow** (model load), reflected in the
  response's `load_duration`. Size slovo's request timeout to allow for the cold
  load, or warm the model first with a lifecycle-only call.
- **Localhost only.** slovo targets `127.0.0.1:11434`; do not expose or assume a
  remote Ollama host.

## Full sources

- Ollama API reference (canonical, `/api/chat`, `/api/generate`, `/api/tags`,
  `/api/pull`, response shapes, streaming, `keep_alive`):
  https://github.com/ollama/ollama/blob/main/docs/api.md
- Ollama API docs portal: https://docs.ollama.com/api
- Ollama FAQ — keep_alive / model memory management (`OLLAMA_KEEP_ALIVE`, `0`,
  negative, duration strings): https://docs.ollama.com/faq
- OpenAI compatibility (`/v1/chat/completions`, base URL `…/v1`, ignored API
  key): https://docs.ollama.com/api/openai-compatibility
  and the announcement: https://ollama.com/blog/openai-compatibility
- `keep_alive` origin PR (added to generate/chat/embedding endpoints):
  https://github.com/ollama/ollama/pull/2146

## Verification

Date: 2026-06-27

Verdict: PASS

Independent verification against live canonical sources. Every endpoint shape,
field, value, and semantic in this doc was cross-checked; no corrections were
needed.

Checked:

- `POST /api/chat` request fields (`model`, `messages`, `stream`, `options`,
  `keep_alive`; also `tools`, `format`) and the non-streaming (`stream: false`)
  response shape, including `done_reason`.
- `done_reason` values: `"stop"` (normal completion), `"load"` (model-load
  call), `"unload"` (unload call) — all three appear verbatim in api.md.
- `POST /api/generate` non-streaming response: text in the `response` field
  (not `message.content`); confirmed verbatim.
- `stream` defaults to `true` (both endpoints are streaming by default).
- `keep_alive` semantics: duration string (`"10m"`/`"24h"`), number in seconds
  (`3600`), any negative number pins the model in memory (`-1`/`"-1m"`), `0`
  unloads immediately after the response; default `5m`; `OLLAMA_KEEP_ALIVE`
  env var sets the server-wide default but per-request `keep_alive` takes
  precedence — confirmed verbatim against the FAQ.
- `GET /api/tags` liveness probe returns `models[].name`.
- OpenAI-compat surface at base `http://localhost:11434/v1`,
  `POST /v1/chat/completions`; API key "required but ignored" by Ollama (docs
  use the literal `"ollama"`).
- Base URL `http://localhost:11434`.

Corrections (before → after): none — all shapes and values matched the
canonical docs.

URLs validated:

- https://github.com/ollama/ollama/blob/main/docs/api.md
- https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md
- https://docs.ollama.com/api
- https://docs.ollama.com/faq
- https://docs.ollama.com/api/openai-compatibility

Still unverifiable:

- The exact `URLError.Code` raised when nothing listens on `:11434` is an
  Apple/Foundation platform behavior, not an Ollama-documented value, so it
  cannot be confirmed against Ollama's docs. The doc already marks this
  `[UNVERIFIED]` and correctly recommends treating the broad set of
  cannot-reach-host `URLError` codes (and timeouts) as "not running" rather
  than relying on one specific code — sound, conservative guidance; no change.
- The `https://docs.ollama.com/api` portal page is a thin index (it defers to
  the api.md spec), so the GitHub `api.md` (main branch) served as the
  authoritative source for the response-shape verbatim checks.
