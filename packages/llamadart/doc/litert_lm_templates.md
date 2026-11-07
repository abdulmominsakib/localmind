# LiteRT-LM chat templates

This document explains how llamadart picks a chat template for `.litertlm`
model bundles, which template families are seeded out of the box, how to
validate those families against real models, and how to add a new one.

## Why a built-in registry is needed

llamadart builds every prompt the same way on both backends: it reads
`tokenizer.chat_template` from the model's metadata, detects the template
format, and renders/parses with the matching handler. For llama.cpp this
template is read straight from the GGUF.

`.litertlm` bundles also embed a chat template, but the LiteRT-LM native FFI
exposes **no way to read it back**. So the backend has to supply
`tokenizer.chat_template` itself for metadata, template inspection, Dart-side
parsing, web generation, and fallback prompt rendering. It does this by
detecting the model family from the bundle filename and mapping it to a
canonical template copied verbatim from the one llama.cpp ships — which keeps
the LiteRT-LM path byte-for-byte consistent with the llama.cpp path whenever
the Dart renderer is active.

Native LiteRT-LM text chat does not always render the full prompt in Dart. When
`LlamaEngine.create(...)` can represent a request as structured text-only
messages, it uses LiteRT-LM's native Conversation APIs for system/history
messages, tools, and per-call extra context. The registry still provides the
format handler used to parse streamed assistant output and to render prompts for
unsupported or non-native paths.

> Note: the native runtime adds the model's start token itself, so the bundled
> templates have their leading `bos_token` stripped to avoid a doubled BOS.

## Resolution order

`LiteRtLmService.getMetadata()` resolves the template in this order (later wins):

1. **Built-in registry** — if the bundle filename matches a known family
   (`kLiteRtLmChatTemplates`), its template is used.
2. **`ModelParams.chatTemplate` override** — if set, it always wins. This is the
   reliable path for any model, including families not in the registry.

If neither applies, no chat template is exposed and the engine falls back to its
generic ChatML handling — usable for plain text, but not the model's native
format.

## Template coverage

The table below is **template registry coverage** for `.litertlm` bundles. It
does not mean every quantization, runtime delegate, device, or browser path has
been exhaustively validated. GGUF models do not need this registry because
llama.cpp reads `tokenizer.chat_template` straight from the GGUF metadata.

| Family | Detected as | Filename match | Chat | Tools | Thinking |
| --- | --- | --- | --- | --- | --- |
| Gemma 4 (E2B/E4B) | `gemma4` | `gemma-4`, `gemma4` | ✅ | ✅ native `<\|tool_call>` | ✅ `<\|channel>` |
| Gemma 3n (E2B/E4B) | `gemma` | `gemma-3n`, `gemma3n` | ✅ | ⚠️ prompt-engineered, no schema¹ | — |
| Gemma 3 / 2 / 1B / 270m | `gemma` | `gemma-3`, `gemma-2` | ✅ | ⚠️ prompt-engineered, no schema¹ | — |
| Qwen 3 / 3.5 | `hermes` | `qwen3`, `qwen-3` | ✅ | ✅ `<tool_call>` | ✅ `<think>` |
| Qwen 2.5 | `hermes` | `qwen2.5`, `qwen-2.5`, `qwen2` | ✅ | ✅ `<tool_call>` | — |

¹ For Gemma 3/3n the engine injects a generic "respond with `tool_call` JSON"
instruction but does **not** render the tool schemas into the prompt. This
matches the llama.cpp backend's Gemma 3 behavior — it is a property of the Gemma
handler, not a LiteRT-LM limitation. Gemma **4** has full native tool calling.

Detection is best-effort and based on the bundle filename. If a bundle is
renamed or its family isn't listed above, pass the template explicitly via
`ModelParams.chatTemplate`.

The registry is ordered most-specific-first, so `gemma-4` and `gemma-3n` are
matched before `gemma-3`, and `qwen3` is matched before the Qwen 2.5 rules.

## Real-model smoke coverage

Use the smoke tools below when a change touches shared chat rendering,
streaming, thinking, tool-call parsing, or `LlamaEngine.create()`. They require
local model files and are intentionally outside default CI.

For GGUF / llama.cpp, `tool/gguf_chat_features_smoke.dart` loads a local GGUF
through `LlamaEngine(LlamaBackend())`, verifies that `enableThinking: false`
does not leak reasoning markers, and verifies that a required `get_weather`
tool call is emitted as a final `tool_calls` chunk with no raw tool-call marker
or content leak. When passed a multimodal projector and image path, it also
runs a short image-description turn:

```bash
dart run tool/gguf_chat_features_smoke.dart \
  models/Qwen3.5-0.8B-Q4_K_M.gguf auto

dart run tool/gguf_chat_features_smoke.dart \
  models/gemma-4-E2B-it-Q4_K_S.gguf auto

dart run tool/gguf_chat_features_smoke.dart \
  models/Qwen3.5-0.8B-Q4_K_M.gguf cpu \
  models/Qwen3.5-0.8B-mmproj-F16.gguf \
  test/fixtures/image.png
```

For native LiteRT-LM, `tool/litert_lm_chat_features_smoke.dart` checks the same
tool-call path and also requires the model to emit a thinking channel. Use it
with models that support thinking, such as Qwen 3/3.5 and Gemma 4:

```bash
dart run tool/litert_lm_chat_features_smoke.dart \
  /path/to/Qwen3-0.6B.litertlm gpu

dart run tool/litert_lm_chat_features_smoke.dart \
  /path/to/gemma-4-E2B-it.litertlm gpu
```

The smoke scripts are not a universal model certification suite. Passing them
means the representative Qwen/Gemma chat-template family can load on the chosen
backend and that the high-risk streaming parser invariants hold for the tested
artifact.

## Adding a model family

Templates are committed as jinja under `tool/litert_lm_templates/` and embedded
into `lib/src/backends/litert_lm/litert_lm_chat_templates.dart` by a generator.
You never hand-author a template — copy the canonical one llama.cpp uses.

1. Copy the canonical jinja into `tool/litert_lm_templates/<id>.jinja`
   (e.g. from `.dart_tool/llama_cpp/models/templates/` or the model's GGUF /
   Hugging Face `tokenizer_config.json`).
2. Add an entry to `_manifest` in `tool/gen_litert_lm_templates.dart`:
   - `id` / `jinja` — the identifier and source filename.
   - `familyMatches` — lower-cased filename substrings; place the entry above
     any broader family it could collide with.
   - `bosToken` / `eosToken` — exposed via `tokenizer.ggml.*` metadata.
   - `stripLeadingBosToken: true` if the template emits a leading `bos_token`.
3. Regenerate: `dart run tool/gen_litert_lm_templates.dart`.
4. Verify the family is detected as the intended `ChatFormat` and renders
   correctly (a render check plus an entry in
   `test/unit/backends/litert_lm/litert_lm_chat_templates_test.dart`). The
   existing handler renders and parses it — no handler changes are needed for
   families llamadart already supports.

### Known gaps

- **Phi-4** has no dedicated handler (falls back to generic) and no canonical
  jinja vendored, so it is not seeded.
- **TranslateGemma / FunctionGemma** have handlers but no vendored canonical
  jinja yet.

## Runtime behavior (beyond templating)

LiteRT-LM-specific behaviors complement the templates above; they live in the
backend, not the registry:

- **Eligible native text chat uses LiteRT-LM Conversation APIs.**
  `LlamaEngine.create(...)` routes native `.litertlm` text-only chat through
  `litert_lm_conversation_config_set_messages`,
  `litert_lm_conversation_config_set_tools`,
  `litert_lm_conversation_config_set_extra_context`, and native message
  rendering/sending. This lets LiteRT-LM's model processors handle structured
  history, tool declarations, and runtime context instead of receiving one
  Dart-rendered prompt string.
- **The Dart template path remains the compatibility fallback.** The engine
  still renders prompts in Dart for web LiteRT-LM, custom template inspection
  through `chatTemplate(...)`, required tool-choice, parallel tool calls, and
  any backend that does not expose native structured chat generation.

- **Thinking is reassembled from a channel stream.** The native runtime streams
  reasoning and the answer on separate channels — thought as
  `{"role":"assistant","channels":{"thought":"..."}}` and the answer as
  `{"role":"assistant","content":[{"type":"text",...}]}`. `LiteRtLmChannelAssembler`
  (in `litert_lm_runtime.dart`) wraps thought runs in the active handler's
  reasoning tags (`<|channel>thought … <channel|>` for Gemma 4, `<think>…</think>`
  for Qwen/Hermes) so chat-template handlers extract them as reasoning instead
  of leaking raw JSON.
- **Grammar-constrained decoding is skipped.** Grammar-using handlers (Hermes/Qwen)
  emit a GBNF grammar for tool calls, which the LiteRT-LM backend rejects.
  `NativeAutoBackend` forwards `supportsGrammarConstraints == false` from the
  active delegate, so the engine drops the grammar and tool calls are parsed
  best-effort from the model output. Gemma 4 emits no grammar, so it is
  unaffected.
- **Native media parts use LiteRT-LM's conversation message JSON.** When
  `LlamaImageContent` or `LlamaAudioContent` reaches the native LiteRT-LM
  backend, llamadart sends matching `type: image` / `type: audio` message items
  with a local `path` or base64 `blob` through the native Conversation API. The
  native model data processor then renders the bundle template and performs
  image/audio preprocessing. This is separate from the llama.cpp `mmproj`
  lifecycle.

> The web backend (`@litert-lm/core`) uses a separate response path and does not
> share the native Conversation API or channel reassembly; web thinking remains
> limited/single-turn.

## Longer-term direction

The registry is a deliberate bridge, not the end state. The remaining "proper"
endgame is worth tracking:

1. Read the embedded template straight from the `.litertlm` bundle once the FFI
   exposes a getter — mirroring how the llama.cpp path reads it from the GGUF.
