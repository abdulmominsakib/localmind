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
dart run llamadart_server --model /path/to/model.gguf
```

Default server address: `http://127.0.0.1:8080`

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
    "max_tokens": 64
  }'
```

## What it demonstrates

- OpenAI-compatible request/response mapping.
- SSE streaming completion responses.
- Optional API key handling.
- Built-in OpenAPI and Swagger docs.
