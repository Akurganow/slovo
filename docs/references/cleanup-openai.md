# OpenAI Responses API (cleanup)

> Authoritative reference for loqui's optional OpenAI text-cleanup provider:
> calling the OpenAI Responses API from native Swift via `URLSession`.

## Purpose

The OpenAI cleanup provider rewrites the already-transcribed text into clean
prose. It is a cleanup-only provider: raw audio still never leaves the machine,
and ASR remains owned by the local transcriber path.

Default model: **`gpt-5.4-mini`**. It is a fast text-capable model available on
the Responses API and is suitable for short, latency-sensitive cleanup requests.
The app's selectable OpenAI cleanup catalog also includes **`gpt-5.4-nano`** for
speed comparison.

## Endpoint And Headers

A cleanup call is a single `POST` to the Responses endpoint:

```http
POST https://api.openai.com/v1/responses
```

Required request headers:

| Header | Value | Notes |
|---|---|---|
| `authorization` | `Bearer <API key>` | Read from Keychain/env; never hardcode or log. |
| `content-type` | `application/json` | Required for the JSON body. |

## Request Shape

loqui sends a text-only request:

```json
{
  "model": "gpt-5.4-mini",
  "instructions": "<cleanup instructions + vocabulary>",
  "input": "<raw transcript text>",
  "store": false,
  "max_output_tokens": 4096
}
```

- `model` is the configured OpenAI cleanup model selected from the app's typed
  model catalog.
- `instructions` carries the cleanup instructions and vocabulary context.
- `input` carries the raw transcript.
- `store: false` prevents storing the generated model response for later API
  retrieval.
- `max_output_tokens` caps the cleanup response size.

## Response Shape

OpenAI text output appears as `output[].content[]` blocks with
`type: "output_text"` and a `text` field. Some client surfaces also expose a
convenience `output_text` string; loqui accepts both shapes and treats a missing
text block as an API error that degrades through `FallbackCleaner`.

Refusal blocks use `type: "refusal"` and must not be interpreted as cleaned
text.

## Error Mapping

- Network/transport failure -> `CleanupError.offline`.
- HTTP 429 -> `CleanupError.rateLimited(retryAfter:)`.
- Other HTTP 4xx/5xx or malformed 200 -> `CleanupError.apiError(status:)`.
- Key sourcing failure -> `CleanupError.missingKey`.

The error body, API key, transcript, cleaned text, and vocabulary terms must
never reach logs.

## Key Handling

The OpenAI key is stored separately from the Anthropic key:

- Keychain service: `loqui`
- Keychain account: `openai-api-key`
- Dev env override: `OPENAI_API_KEY`

Production startup preloads the selected provider's key into memory once, so
normal cleanup calls do not repeatedly prompt Keychain.

## Full Sources

- OpenAI Responses API, Create a model response:
  https://platform.openai.com/docs/api-reference/responses/create
- OpenAI `gpt-5.4-mini` model page:
  https://developers.openai.com/api/docs/models/gpt-5.4-mini
- OpenAI `gpt-5.4-nano` model page:
  https://developers.openai.com/api/docs/models/gpt-5.4-nano

## Verification

PASS — verified on 2026-06-30 against the official OpenAI API reference and
model pages. The Responses API reference documents `input`, `instructions`,
`store`, and output text/refusal content blocks. The model pages list
`gpt-5.4-mini` and `gpt-5.4-nano`, text output support, and the
`v1/responses` endpoint.
