---
title: OpenAI-compatible server example
sidebar_label: OpenAI-compatible server
description: Serve an on-device model over an OpenAI-style HTTP API with llamadart, with streaming, tool calls, embeddings and Swagger docs.
---

Path: `example/llamadart_server` · Platforms: Dart server on macOS, Linux and
Windows · First-run download: `Qwen3.6-27B-UD-Q4_K_XL.gguf` (17.6 GB)

A local HTTP server with OpenAI-style chat completion and embedding endpoints,
backed by one `LlamaEngine`.

## Run

```bash
cd example/llamadart_server
dart pub get
dart run llamadart_server
```

The server listens on `http://127.0.0.1:8080`. The default model needs at
least 32 GB of free unified memory or VRAM plus runtime headroom.

Variants:

```bash
# A local GGUF on the CPU
dart run llamadart_server --model /path/to/model.gguf --gpu-layers 0

# Require a bearer token on /v1 routes
dart run llamadart_server --api-key <key>

# Send a chat completion
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llamadart-local",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 64
  }'
```

## What it demonstrates

- `GET /v1/models`, `POST /v1/chat/completions` and `POST /v1/embeddings`
  mapped onto `LlamaEngine`, plus `GET /healthz`
  ([Generation and streaming](../guides/generation-and-streaming),
  [Embeddings](../guides/embeddings)).
- SSE streaming with `stream: true`, ending in `data: [DONE]`.
- Client-managed tool calls: the server returns `tool_calls` and the client
  runs them and sends the results back ([Tool calling](../guides/tool-calling)).
- Qwen thinking off by default, turned on per request with
  `"enable_thinking": true` and capped with llama.cpp's
  `thinking_budget_tokens`
  ([Generation and streaming](../guides/generation-and-streaming)).
- Local paths, HTTP(S) URLs and `hf://` sources through
  `LlamaEngine.loadModelSource` ([Downloads and cache](../guides/model-downloads)).
- Optional bearer auth, CORS, an OpenAPI spec at `/openapi.json` and Swagger UI
  with ready-made requests at `/docs`.

## Test

```bash
cd example/llamadart_server
dart test
```

Full options: every flag, exit codes, sampling defaults, thinking mode, the
tool-call sequence and more request examples are in the
[example README](https://github.com/leehack/llamadart/tree/main/example/llamadart_server).
