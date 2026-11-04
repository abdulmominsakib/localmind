# LiteRT-LM strict structured output

This note tracks the current boundary for strict structured output on
`.litertlm` models.

## Current behavior

`LlamaEngine.create(...)` accepts OpenAI-style `responseFormat` requests.
Backends that support grammar-constrained decoding use the generated grammar to
enforce `json_object` / `json_schema` output. `LlamaEngine.chatTemplate(...)`
keeps a deprecated legacy `jsonSchema` shortcut for template inspection, but new
callers should use `responseFormat`.

LiteRT-LM native and web do **not** currently enforce those strict response
formats. If callers pass strict `responseFormat` through
`LlamaEngine.create(...)` while a LiteRT-LM backend is active, llamadart fails
early with an unsupported-backend error instead of silently running
unconstrained generation.

Tool-call parsing remains separate. LiteRT-LM can still run best-effort
tool-call parsing through the high-level chat-template parser for compatible
models, but this is not strict JSON-schema constrained decoding.

## Runtime boundary

The upstream LiteRT-LM C++ `Conversation::OptionalArgs` type has a
`decoding_constraint` field, and `ConversationConfig::Builder` accepts a
constraint provider config. The public C API exposed by the pinned runtime does
not currently expose an equivalent setter for per-request JSON-schema or Lark
constraints.

The public C API does expose:

- `litert_lm_conversation_config_set_enable_constrained_decoding`
- `litert_lm_conversation_optional_args_set_max_output_tokens`
- `litert_lm_conversation_optional_args_set_visual_token_budget`

That is enough to toggle LiteRT-LM's built-in constrained-decoding path for
runtime-managed features, but not enough for llamadart to map arbitrary
`responseFormat` schemas onto native LiteRT-LM constraints.

## Implementation direction

Strict LiteRT-LM structured output needs one of these runtime surfaces before
llamadart can honestly report grammar support:

1. A public LiteRT-LM C API setter that accepts a JSON-schema or Lark
   constraint for `Conversation::OptionalArgs`.
2. A public LiteRT-LM C API setter that accepts a `ConstraintProviderConfig`
   on `ConversationConfig`.
3. A higher-level LiteRT-LM conversation option that directly models
   OpenAI-style `response_format`.

Until that exists, `LiteRtLmBackend.supportsGrammarConstraints` and
`LiteRtLmBackendWeb.supportsGrammarConstraints` remain `false`.

Relevant upstream files:

- <https://github.com/google-ai-edge/LiteRT-LM/blob/main/runtime/conversation/conversation.h>
- <https://github.com/google-ai-edge/LiteRT-LM/blob/main/c/engine.h>
