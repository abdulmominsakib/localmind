---
title: OpenAI-Compatible Server Example
---

Path: `example/llamadart_server`

`llamadart_server` provides an OpenAI-style local HTTP API backed by
`llamadart`.

## Endpoints

- `GET /v1/models`
- `POST /v1/chat/completions`
- `GET /openapi.json`
- `GET /docs` (Swagger UI)

## Run

```bash
cd example/llamadart_server
dart pub get
dart run llamadart_server
```

Default server address: `http://127.0.0.1:8080`

The default model is Unsloth's `Qwen3.6-27B-UD-Q4_K_XL.gguf` (about 17.6 GB).
It is a text-only server configuration and needs at least 32 GB of free unified
memory or VRAM plus runtime headroom. Pass `--gpu-layers 0` to force CPU
inference when needed. The 16,384-token context is a practical server default
that leaves room for normal chat; increase it cautiously because larger contexts
need substantially more memory. The first launch downloads this default model;
pass
`--model /path/to/model.gguf` to use a local GGUF instead; remote GGUF URLs
and `hf://owner/repo/path` sources are also supported.

The server passes every `--model` value through `LlamaEngine.loadModelSource`,
so local paths, HTTP(S) URLs, and Hugging Face sources use the core runtime's
model-resolution, cache, and download behavior.

## Example requests

List models:

```bash
curl http://127.0.0.1:8080/v1/models
```

Chat completion:

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llamadart-local",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 64,
    "enable_thinking": false
  }'
```

### Thinking mode

Qwen3.6 thinks by default, but this server disables thinking unless a request
sets `"enable_thinking": true`, keeping ordinary responses in `content`.
Thinking responses use a separate `reasoning_content` channel; use streaming
and an explicit token limit. `max_tokens` covers reasoning and the final
answer; the inherited default is 4,096 tokens, so raise it for thought-heavy
requests while leaving prompt room in the 16,384-token context. A request that
ends during reasoning can correctly have `reasoning_content` but no final
`content`. The non-thinking default uses `temperature: 0.7`, `top_p: 0.8`,
`top_k: 20`, `min_p: 0.0`, and repetition penalty `1.0`; thinking uses
`temperature: 1.0` and `top_p: 0.95`. Qwen's non-thinking
presence-penalty recommendation is not exposed by this example and is not the
same control as repetition penalty.

### Thinking budget (llama.cpp extension)

`thinking_budget_tokens` follows llama.cpp server behavior and is not a
standard OpenAI Chat Completions field. Use it only with
`"enable_thinking": true`. It limits generated tokens inside a reasoning
block; `max_tokens` remains the cap for the full completion. Set it to `0` to
close the initial reasoning block immediately. Swagger's **Tool call: capped
reasoning + function request (SSE)** example streams both `reasoning_content`
and standard `tool_calls` with a 128-token budget.

### Tool calling

Function tools use the standard client-managed Chat Completions flow. The
server returns an assistant message with `tool_calls`; the client executes the
functions, appends that complete assistant message plus one `role: "tool"`
message per result, and submits the expanded transcript in a new request. Each
tool result must use the exact `tool_call_id` returned by the assistant. The
server does not execute application tools.

Set `parallel_tool_calls: true` to permit multiple calls when the active model
template supports that capability; append one result for every returned call.

Open `http://127.0.0.1:8080/docs` for ready-to-run Swagger examples:

- **Tool call: request a function** — initial non-streaming function request.
- **Tool call: request a function (SSE)** — streamed `tool_calls` deltas.
- **Tool call: capped reasoning + function request (SSE)** — Qwen reasoning
  plus tool deltas with a llama.cpp thinking budget.
- **Tool call: submit the function result** — the second request after
  client-side execution.

Swagger cannot copy a generated call ID between requests. Run the initial
example, execute the returned function in your client, then replace the
illustrative assistant message and `call_weather_example` in the follow-up
example with the actual response. A standard tool-result message needs
`tool_call_id` and `content`; it normally omits `name`.

## What it demonstrates

- OpenAI-compatible request/response mapping.
- SSE streaming completion responses.
- Client-managed OpenAI-compatible function-call continuations.
- Optional API key handling.
- Built-in OpenAPI and Swagger docs.
