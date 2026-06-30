# Anthropic Messages API (cleanup)

> Authoritative reference for slovo's text-cleanup layer: calling the Anthropic
> Messages API with Claude Haiku to clean up raw speech-to-text transcripts.
> slovo is native Swift on macOS; there is **no official Anthropic Swift SDK**,
> so slovo calls the REST API directly via `URLSession`. Every fact below is
> verified against the official docs (see [Full sources](#full-sources)).

## Purpose

The cleanup layer takes a raw transcript produced by the speech-to-text stage
and rewrites it into clean prose: fixing punctuation/capitalization, removing
filler words and false starts, and applying a project vocabulary — **without**
adding, summarizing, or inventing content. Claude Haiku is the **default**
cleanup backend: it is the fastest and cheapest current model, and cleanup is a
short, latency-sensitive, single-turn rewrite that does not need a frontier
model.

Model id: **`claude-haiku-4-5`** (alias; the pinned snapshot is
`claude-haiku-4-5-20251001`). 200K-token context window, 64K max output,
$1 / $5 per million input / output tokens.

## Endpoint & headers

A cleanup call is a single `POST` to the Messages endpoint:

```
POST https://api.anthropic.com/v1/messages
```

Required request headers:

| Header              | Value              | Notes                                  |
| ------------------- | ------------------ | -------------------------------------- |
| `x-api-key`         | `<API key>`        | Authentication. Read from Keychain/env — **never hardcode** (see [Key handling](#key-handling)). |
| `anthropic-version` | `2023-06-01`       | API version. Constant — this is the current value. |
| `content-type`      | `application/json` | Required for the JSON body.            |

No `anthropic-beta` header is needed for basic cleanup (prompt caching, streaming,
and `stop_reason: "refusal"` handling are all GA and require no beta opt-in).

## Request shape

```jsonc
{
  "model": "claude-haiku-4-5",
  "max_tokens": 4096,
  "system": [
    {
      "type": "text",
      "text": "<cleanup instructions + stable vocabulary>",
      "cache_control": { "type": "ephemeral" }   // see Prompt caching below
    }
  ],
  "messages": [
    { "role": "user", "content": "<raw transcript text>" }
  ]
}
```

- **`model`** (required) — `claude-haiku-4-5`.
- **`max_tokens`** (required) — hard cap on output tokens. Cleanup output is
  roughly the same length as the input, so size this to the expected transcript
  length plus margin. Hitting the cap yields `stop_reason: "max_tokens"` and a
  truncated result — size generously rather than retry.
- **`system`** (optional but used here) — the cleanup instructions. Either a
  plain string or an array of text blocks. slovo uses the array form so it can
  attach `cache_control` to the stable prefix.
- **`messages`** (required) — the conversation. For cleanup this is a single
  `user` turn carrying the raw transcript. `content` is either a string (as
  above) or an array of content blocks (`{"type": "text", "text": "..."}`).
  Roles alternate `user` / `assistant`; the first message must be `user`.

A concrete cleanup request: put the **instructions** (and any stable vocabulary)
in `system`, and the **raw transcript** in the single user message. Keep the
volatile transcript out of the cached prefix (see [Prompt caching](#prompt-caching)).

## Response shape

A successful (HTTP 200) cleanup response:

```jsonc
{
  "id": "msg_01...",
  "type": "message",
  "role": "assistant",
  "model": "claude-haiku-4-5-20251001",
  "content": [
    { "type": "text", "text": "<cleaned-up transcript>" }
  ],
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "stop_details": null,
  "usage": {
    "input_tokens": 1234,
    "output_tokens": 1180,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 0
  }
}
```

- **`content[]`** — an array of content blocks. For a plain cleanup the cleaned
  text is in the first `text` block (`content[0].text`). Always filter by
  `type == "text"` rather than assuming index 0 — extra block types can appear,
  and on a refusal `content` may be empty.
- **`stop_reason`** — why generation stopped. Possible values:
  `end_turn` (normal completion), `max_tokens` (hit the cap — output truncated),
  `stop_sequence`, `tool_use`, `pause_turn`, and **`refusal`** (see below).
- **`stop_details`** — populated **only** when `stop_reason == "refusal"`
  (`null` for every other stop reason). Fields: `type: "refusal"`, `category`
  (e.g. `"cyber"`, `"bio"`, `"frontier_llm"`, `"reasoning_extraction"`),
  `explanation`. `category` and `explanation` are both `null` when the refusal
  does not map to a named category, so **branch on `stop_reason`, not on
  `stop_details` or `content`** ([refusals-and-fallback](https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback)).
- **`usage`** — `input_tokens`, `output_tokens`,
  `cache_creation_input_tokens`, `cache_read_input_tokens`. Note
  `input_tokens` is the **uncached** remainder only; total prompt size =
  `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.

### Handling `stop_reason: "refusal"`

A safety-declined request returns a **successful HTTP 200** with
`stop_reason == "refusal"` and an empty (or partial) `content`. Code that reads
`content[0].text` unconditionally will crash on a refusal. **Check
`stop_reason` before reading the cleaned text** — for cleanup, treat a refusal
as "leave the raw transcript unchanged" (or surface an error), and do not retry
the same request. Refusals are rare for benign transcript cleanup but must be
handled so a single odd input can't crash the app.

## Prompt caching

Cleanup reuses the same instructions + vocabulary prefix on every call while the
transcript changes each time — an ideal caching shape. Caching is a **prefix
match**: put the stable content (cleanup instructions, project vocabulary)
first, mark the end of it with a breakpoint, and keep the volatile transcript
**after** the breakpoint.

Place `cache_control` on the **last block of the stable prefix** — the system
block here:

```jsonc
"system": [
  { "type": "text", "text": "<instructions + vocabulary>",
    "cache_control": { "type": "ephemeral" } }
],
"messages": [
  { "role": "user", "content": "<raw transcript>" }   // no cache_control — varies every call
]
```

- **Minimum cacheable prefix for Haiku 4.5 is ~4096 tokens.** A shorter prefix
  silently won't cache — no error, just `cache_creation_input_tokens: 0` and
  `cache_read_input_tokens: 0`. slovo's vocabulary prefix must reach ~4096
  tokens for caching to engage on Haiku. (For comparison: Opus 4.8 / Sonnet 4.6
  is 1024 tokens; Opus 4.6 is also 4096.)
- **Default TTL is 5 minutes** (`{"type": "ephemeral"}`); `{"type":
  "ephemeral", "ttl": "1h"}` extends it to 1 hour for bursty usage. Write cost
  is 1.25× base input for 5m, 2× for 1h; reads are ~0.1× base input.
- **Verify hits** via `usage.cache_read_input_tokens` — if it stays `0` across
  repeated calls with the same prefix, a silent invalidator is changing the
  prefix bytes (a timestamp/UUID interpolated into the system prompt,
  non-deterministic JSON key order, or a changing vocabulary list). The prefix
  must be byte-identical across calls to hit the cache.

## Minimal Swift `URLSession` example

No SDK — build the JSON, POST it, decode the response, extract the cleaned text.
The API key is read from Keychain (placeholder accessor here; see
[Key handling](#key-handling)).

```swift
import Foundation

struct CleanupResponse: Decodable {
    struct ContentBlock: Decodable { let type: String; let text: String? }
    let content: [ContentBlock]
    let stopReason: String
    let model: String

    enum CodingKeys: String, CodingKey {
        case content, model
        case stopReason = "stop_reason"
    }
}

enum CleanupError: Error {
    case http(Int, String)
    case refused
    case noText
}

/// Calls the Anthropic Messages API with Claude Haiku to clean up a transcript.
/// `system` holds the stable cleanup instructions + vocabulary; `transcript` is
/// the raw speech-to-text output.
func cleanupTranscript(_ transcript: String, system: String) async throws -> String {
    // Placeholder — read the user-provided key from the Keychain/env.
    // NEVER hardcode the key. See "Key handling".
    let apiKey = try KeychainStore.anthropicAPIKey()

    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "content-type")

    let body: [String: Any] = [
        "model": "claude-haiku-4-5",
        "max_tokens": 4096,
        "system": [
            [
                "type": "text",
                "text": system,
                // Caches the stable prefix; needs ~4096 tokens to engage on Haiku.
                "cache_control": ["type": "ephemeral"],
            ],
        ],
        "messages": [
            ["role": "user", "content": transcript],
        ],
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
        throw CleanupError.http(status, String(decoding: data, as: UTF8.self))
    }

    let decoded = try JSONDecoder().decode(CleanupResponse.self, from: data)

    // A safety decline returns HTTP 200 with stop_reason == "refusal" and
    // (usually) empty content — check before reading the text.
    guard decoded.stopReason != "refusal" else { throw CleanupError.refused }

    guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
        throw CleanupError.noText
    }
    return text
}
```

Notes:

- Cleanup is short, so the **non-streaming** call above is the right default —
  one request, one response, simplest code. Use streaming only if a transcript
  is long enough that the response approaches a request timeout.
- `URLSession.shared.data(for:)` is the modern async entry point; pair it with a
  short request timeout if you want a tighter latency budget.

## Streaming (SSE)

For short cleanups, **non-streaming is preferred** (the example above). When you
do need incremental output, set `"stream": true` in the body; the response is a
stream of Server-Sent Events. The event flow:

1. `message_start` — `Message` with empty `content`.
2. Per content block: `content_block_start` → one or more `content_block_delta`
   (text arrives as `delta.type == "text_delta"`, field `delta.text`) →
   `content_block_stop`.
3. One or more `message_delta` (carries `stop_reason` and **cumulative**
   `usage`).
4. `message_stop`. `ping` events may appear anywhere; errors arrive as an
   `event: error` with an `overloaded_error`/etc. payload.

Wire format for a basic text response:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_...","type":"message","role":"assistant","content":[],"model":"claude-haiku-4-5-20251001","stop_reason":null,"usage":{"input_tokens":25,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":15}}

event: message_stop
data: {"type":"message_stop"}
```

To accumulate the cleaned text, concatenate every `text_delta`'s `text`. In
Swift, consume the body with `URLSession.bytes(for:)` and parse SSE lines
manually (no SDK helper exists). `stop_reason` arrives on the `message_delta`
event — check it there for refusals.

## slovo gotchas

### Refusal handling

`stop_reason: "refusal"` arrives as **HTTP 200**, not an error status. The
cleaned text is empty or partial. Guard on `stop_reason` before reading
`content[0].text` (the example does this). For cleanup, the safe fallback is to
keep the raw transcript unchanged rather than crash or block the user.

### Caching threshold

Haiku 4.5's minimum cacheable prefix is **~4096 tokens** — higher than the
Opus 4.8 / Sonnet 4.6 minimum of 1024. If slovo's cached vocabulary prefix is
below ~4096 tokens it **silently won't cache** (no error). Confirm caching is
working by checking `usage.cache_read_input_tokens > 0` on the second and later
calls; if it stays 0, either the prefix is too short or a byte in it changed
between calls (keep the prefix deterministic and identical).

### Key handling

The Anthropic API key is supplied by the user via the macOS **Keychain** (or an
environment variable for local dev).
The doc and any committed code must **never** hardcode it — read it at call time
(the `KeychainStore.anthropicAPIKey()` placeholder above) and pass it in the
`x-api-key` header. Do not log the key or include it in error messages.

## Full sources

Canonical Anthropic documentation (verified for this doc):

- Messages API reference — <https://platform.claude.com/docs/en/api/messages>
- Models overview (model ids, context, pricing) — <https://platform.claude.com/docs/en/about-claude/models/overview>
- Prompt caching (placement, Haiku minimum, verification, TTL/pricing) — <https://platform.claude.com/docs/en/build-with-claude/prompt-caching>
- Streaming (SSE event flow, wire format) — <https://platform.claude.com/docs/en/build-with-claude/streaming>
- Handling stop reasons (including `refusal`) — <https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons>
- Errors / rate limits — <https://platform.claude.com/docs/en/api/errors>, <https://platform.claude.com/docs/en/api/rate-limits>
- Pricing — <https://platform.claude.com/docs/en/about-claude/pricing>

### Error & retry notes

- **429 (`rate_limit_error`)** and **5xx / 529 (`overloaded_error`)** are
  retryable — back off and retry, honoring the `retry-after` response header
  when present. **4xx other than 429** (400 `invalid_request_error`, 401
  `authentication_error`, 403, 404) are **not** retryable — fix the request or
  credentials.
- A `429` includes a `retry-after` header (seconds to wait). Use exponential
  backoff with jitter for repeated retries; cap total attempts.
- The error body is JSON: `{"type":"error","error":{"type":"...","message":"..."},"request_id":"req_..."}`.
  Log `request_id` when reporting an issue to Anthropic.

## Verification

- **Date:** 2026-06-27
- **Verdict:** PASS

### Checked

- Endpoint `POST https://api.anthropic.com/v1/messages`; required headers
  `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`.
- Model id `claude-haiku-4-5` (alias) / snapshot `claude-haiku-4-5-20251001`;
  200K context, 64K max output, $1 in / $5 out per MTok.
- Request shape (`model`, `max_tokens`, `system` as string or text-block array,
  `messages` alternating user/assistant) and content-block forms.
- Response shape (`id`, `type`, `role`, `model`, `content[]`, `stop_reason`,
  `stop_sequence`, `stop_details`, `usage`).
- `stop_reason` values and `stop_reason: "refusal"` semantics (HTTP 200, empty
  `content`, `stop_details` shape).
- Prompt caching: `cache_control: {type:"ephemeral"}`, Haiku 4.5 cache minimum,
  default 5m TTL + 1h option, write/read cost multipliers, `usage`
  cache fields.
- Streaming SSE event flow and wire format; `event: error` / `overloaded_error`.
- Error status codes, retryability, and error body shape with `request_id`.

### Corrections (before -> after)

- `stop_details` description: clarified that `category` and `explanation` are
  **both `null` when the refusal does not map to a named category**, and that
  code should **branch on `stop_reason`, not `stop_details` or `content`** —
  added per the canonical refusals-and-fallback page. (No wrong value was
  present; this tightens a previously incomplete statement.)

### Confirmed (no change needed)

- **Haiku 4.5 prompt-cache minimum is exactly 4096 tokens** — CONFIRMED against
  the prompt-caching page. The doc's comparison values are also correct:
  Opus 4.8 / Sonnet 4.6 = 1024 tokens, Opus 4.6 = 4096 tokens. A sub-minimum
  prefix is processed without caching and returns no error (matches the doc).
- `anthropic-version: 2023-06-01` is the current/required version value.
- Refusal is HTTP 200 with `content: []` and
  `stop_details: {type:"refusal", category, explanation}` (canonical example
  matches the doc verbatim).
- Haiku 4.5 pricing $1/$5 per MTok; cache write 1.25x (5m) / 2x (1h), read 0.1x.
- Streaming event order, cumulative `message_delta` usage, and the
  `event: error` + `overloaded_error` shape all match.

### URLs validated

- <https://platform.claude.com/docs/en/api/messages>
- <https://platform.claude.com/docs/en/about-claude/models/overview>
- <https://platform.claude.com/docs/en/build-with-claude/prompt-caching>
- <https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons>
- <https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback>
- <https://platform.claude.com/docs/en/build-with-claude/streaming>
- <https://platform.claude.com/docs/en/api/errors>

### Still unverifiable

- None material. The Swift `KeychainStore.anthropicAPIKey()` / `CleanupError`
  symbols are intentionally illustrative placeholders (slovo-side), not
  Anthropic API surface, so they are out of scope for source verification.
