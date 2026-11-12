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
exposes **no way to read it back**, and a bundle that embeds none gets one the
runtime builds. So the backend has to supply
`tokenizer.chat_template` itself for metadata, template inspection, Dart-side
parsing, web generation, and fallback prompt rendering. The native backend
matches the bundle filename first, then recognizes unnamed Qwen 3 bundles
from `LlmMetadata.llm_model_type.qwen3` (field 6) or the complete canonical
Qwen 3 template in `jinja_prompt_template` (field 7). A canonical Qwen 3
`ModelParams.chatTemplate` override also opts in; arbitrary ChatML/thinking
markers do not identify a family. Unreadable or unrecognized metadata retains
the existing fallback; `ModelParams.chatTemplate` takes precedence over the
bundle template. Web uses a single-turn passthrough by default; it cannot
install a conversation template. Runtime content-shape adapters preserve the same rendered prompt for equivalent text inputs.

Native LiteRT-LM text chat does not always render the full prompt in Dart. When
`LlamaEngine.create(...)` can represent a request as structured text-only
messages, it uses LiteRT-LM's native Conversation APIs for system/history
messages, tools, and per-call extra context. The registry still provides the
format handler used to parse streamed assistant output and to render prompts for
unsupported or non-native paths.

For Qwen 3 text-only native conversations, llamadart supplies the same canonical
Jinja template to the native conversation. Older Qwen 3 bundles otherwise render
generic ChatML that ignores `enable_thinking`, so a disabled-thinking request can
spend its entire token budget on reasoning that the public API suppresses. The
native template override preserves the closed reasoning prefix for
`enableThinking: false`; it does not increase the output token budget or expose
hidden reasoning as the answer. Qwen 3.5, other families, and media conversations
retain their model-specific native templates. Native overrides lacking the
conversation-template setter fail explicitly instead of silently ignoring it.
LiteRT-LM v0.18, the pinned runtime, normalizes native conversation content
into part arrays before it renders a template: a string `content` reaches the
template as `[{"type": "text", "text": ...}]`. The Qwen 3 override accepts
both older string content and normalized text parts; `tool_response` parts
preserve object/array responses as JSON and scalar responses as text. Image
and audio parts, unknown parts, text parts without string text, and tool
responses without a response field fail during template rendering. This
compatibility adapter does not add grammar-constrained decoding.

A `ModelParams.chatTemplate` set on a filename-matched or positively identified
Qwen 3 text bundle replaces the native conversation template. For a renamed
bundle without identifying metadata, use
`ModelParams(chatTemplate: liteRtLmQwen3ChatTemplate)`. This public accessor
tracks the installed canonical template across package upgrades. Other families retain
the bundle template, content-shape probe and adapter; their overrides continue
to affect Dart-side metadata and parsing only.
It receives `enable_thinking` from the request and the same part arrays.
The supplied template must implement the thinking switch itself; llamadart
does not rewrite it. Existing filename matches, including Qwen 3.5, and
image/audio conversations keep their existing native routing. A
template that reads `message.content` as a string no longer works there: with
Qwen3 0.6B on `v0.18.0`, string concatenation (`'...' + message['content']`)
fails the generation with `LlamaInferenceException`
(`litert_lm_conversation_send_message_stream rc=13`, to which llamadart adds a
note about the content shape when `chatTemplate` is set), and interpolation
(`{{ message['content'] }}`) renders the list itself into the prompt without
an error. Both produced the intended prompt on `v0.17.0-8`. Read both shapes,
as the built-in `content_text` macro in `tool/litert_lm_templates/qwen3.jinja`
does. `LlamaEngine.chatTemplate` does not show the difference: it renders in
Dart, not in the runtime. A Flutter iOS or macOS app that links an older
`llamadart_litert_lm_flutter` still runs the older runtime, which passes
strings.

The template a bundle embeds receives the same part arrays; every conversation
that llamadart does not override uses it: Qwen 3.5 and other families, raw
prompts and media. `v0.17.0-8` gave a template that reads `message.content` as
a string the text of a single text part. `v0.18.0` dropped that
([#991](https://github.com/leehack/llamadart/issues/991)), and what happens
then depends on how the template reads the content:

| The bundle template | On `v0.18.0` without the adapter |
| --- | --- |
| interpolates it: `{{ message.content }}` | writes `[{"text": "...", "type": "text"}]` into every prompt; replies degrade |
| applies a string operation: `'...' + message.content` | fails every request (`litert_lm_conversation_send_message_stream rc=13`) |
| handles only `message.content is string` | renders every message empty, with no error |

llamadart decides once per loaded model, on its first use. It creates a
conversation with no messages and renders a probe message through the runtime.
If the probe text comes out as text, the bundle template is left alone: a
template that reads parts or both shapes, and the one the runtime builds for a
bundle that embeds none. Otherwise llamadart reads the template from the
bundle file (`litert_lm_bundle_template.dart`) and renders the probe again
with that template behind a prelude that turns a single text part back into a
string. If that renders the text, every conversation of the model uses it,
which restores the `v0.17.0-8` prompt for the three shapes above. Content with
several parts, media parts and tool responses stay as the runtime passed them,
and so do the other keys of a message. The decision costs one more
conversation per loaded model, two when the adapter is tried.

Not adapted:

- a bundle whose template cannot be read from the file, or a template the
  prelude does not make render the text. One warning per loaded model says so,
  and a send that fails before any output carries a note about the template.
- a template that reads the message of a turn from `message` instead of
  `messages`, the runtime's single-turn `is_appending_to_prefill` form. The
  prelude rebinds `messages` only, so this ends in the warning above.
- a runtime without the render entry point
  (`LiteRtLmRuntimeClient.supportsMessageRendering`): nothing is probed.
- Web: the `@litert-lm/core` conversation API takes no template and has no
  render call. Use a bundle whose template reads content parts there.

`LITERT_LM_MODEL=/path/to/model.litertlm dart test --run-skipped -t local-only
test/e2e/backends/litert_lm_bundle_template_e2e_test.dart` checks the prelude
against the real runtime for the three shapes, and runs the service on copies
of the bundle with each shape written over its template.

Media conversations never give this template a media part. Natively they keep
the bundle template: the override is set only for a conversation with no image
or audio part. In Dart, `LlamaEngine.create`, `chatTemplate` and `ChatSession`
render the template before every request, to prepare output parsing and count
tokens, and the capability probe finds that it rejects image and audio parts,
so it gets string content with `<__media__>` in place of each media part, as
before the adapter. The request then reaches the native media boundary: a
bundle with the matching encoder gets the image or audio item, and a runtime
failure on a bundle that declares no such encoder surfaces as
`LlamaUnsupportedException`.
`test/integration/backends/litert_lm/qwen_media_boundary_test.dart` covers
this through the engine.

System instructions are passed as JSON-encoded text content: the native C API
adds the system role itself, so passing a full message object would nest it.


> Note: the native runtime adds the model's start token itself, so the bundled
> templates have their leading `bos_token` stripped to avoid a doubled BOS.

## Legacy Qwen 3 bundles without identifying metadata

The on-disk litert-community Qwen3-0.6B bundle has only `LlmMetadata` fields
1–5: start/stop tokens, generic ChatML prompt templates, sampling parameters
and a token limit. Neither a Qwen 3 declaration nor a Jinja template is present.
Those fields cannot distinguish Qwen 3 from other ChatML families reliably.
Renaming it to `qwen.litertlm` or `download` therefore still leaves
`enableThinking: false` ineffective: reasoning can exhaust the output budget
while the public content is empty. Automatic content detection is intentionally
unavailable for these legacy bundles.

Keep `Qwen3` in the filename (for example `Qwen3-0.6B.litertlm`), or set
`ModelParams.chatTemplate` to `liteRtLmQwen3ChatTemplate` (exported by
`package:llamadart/llamadart.dart`). Do not persist or copy its string across
package upgrades: obtain it from the accessor when constructing `ModelParams`.
Merely adding thinking markers to an
arbitrary override does not opt into native Qwen 3 routing. No weights need
changing. `test/e2e/backends/litert_lm_renamed_qwen3_e2e_test.dart` validates
these paths using read-only symlinks to a local legacy bundle.

### Web limitation

`@litert-lm/core@0.19.0` wraps the supplied string as a user message and exposes
no conversation-template setter. Rendering Qwen3 ChatML in Dart therefore nests
it inside the bundle's wrapper and cannot enforce the disabled-thinking prefix.
Web model loads with the complete current canonical Qwen3 override (including
leading whitespace or appended customizations) throw `LlamaUnsupportedException`
before runtime creation. Use native LiteRT-LM for this explicit contract.
Generic Web overrides and canonical-named loads without an override keep their
existing behavior; no thinking-control guarantee is added to those paths.
See [#901](https://github.com/leehack/llamadart/issues/901) and
[#1137](https://github.com/leehack/llamadart/issues/1137).

## Resolution order

`LiteRtLmService.getMetadata()` resolves the template in this order (later wins):

1. **Built-in registry** — if the bundle filename matches a known family
   (`kLiteRtLmChatTemplates`), its template is used. Without a filename match,
   the Qwen 3 declaration or canonical-template match above selects Qwen 3.
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
| Qwen 3 / 3.5 | `hermes` | `qwen3`, `qwen-3` | ✅ | ⚠️ best-effort `auto`; `required` unsupported on LiteRT-LM² | ✅ `<think>` |
| Qwen 2.5 | `hermes` | `qwen2.5`, `qwen-2.5`, `qwen2` | ✅ | ⚠️ best-effort `auto`; `required` unsupported on LiteRT-LM² | — |

¹ For Gemma 3/3n the engine injects a generic "respond with `tool_call` JSON"
instruction but does **not** render the tool schemas into the prompt. This
matches the llama.cpp backend's Gemma 3 behavior — it is a property of the Gemma
handler, not a LiteRT-LM limitation. Gemma **4** has full native tool calling.

² Hermes/Qwen required-tool rendering depends on grammar-constrained decoding
to guarantee one declared, schema-valid call. LiteRT-LM's llamadart backend does
not expose that constraint wiring, so `ToolChoice.required` fails with
`LlamaUnsupportedException` before generation. On native LiteRT-LM,
`ToolChoice.auto` remains the best-effort Conversation path;
`ToolChoice.none` still disables tool parsing and declarations on both native
and web paths.

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

For native LiteRT-LM, `tool/litert_lm_chat_features_smoke.dart` requires a
non-empty ordinary response with thinking disabled, a system/history turn that
recalls a code from an earlier message, plus both a thinking
channel and visible answer with thinking enabled. It also requires
`ChatSession.createStructuredJson` to throw the grammar-constraints
`LlamaUnsupportedException` without recording the user turn, and the next
`ChatSession` turn to answer with alternating history. For Gemma 4 it also validates
native `auto` tool history and requires exactly one schema-valid
`ToolChoice.required` call. For Hermes/Qwen it instead requires the planner's
actionable unsupported error before generation; empty output or a normal
`stop` finish still fails. The planner unit matrix separately pins unchanged
native and rendered routing for `auto` and `none`; the Qwen smoke does not
promote best-effort `auto` into a guaranteed call. Use it with models that
support thinking, such as Qwen 3/3.5 and Gemma 4. The smoke uses a brief arithmetic
question within its fixed thinking budget and prints diagnostics before asserting,
so token exhaustion and empty plain responses remain inspectable on failure.
Model/runtime decoding quality is a separate check: a non-empty response alone
does not establish correct Unicode output.

```bash
dart run tool/litert_lm_chat_features_smoke.dart \
  /path/to/Qwen3-0.6B.litertlm gpu

dart run tool/litert_lm_chat_features_smoke.dart \
  /path/to/gemma-4-E2B-it.litertlm gpu

dart run tool/testing/run_local_e2e.dart --scenario \
  litert-lm-chat-features-smoke \
  --model-path /path/to/gemma-4-E2B-it.litertlm \
  --backend gpu \
  --audio-path /path/to/known-question.wav \
  --expect 4
```

The optional audio variant reads the encoded file into bytes, asks the model
to answer the spoken question rather than transcribe it, and requires the
normalized final answer to match `--expect`. The local E2E runner forwards the
shared audio flags without including the audio path or raw bytes in result
metadata; results include the encoded byte length and a stable SHA-256 fixture
ID. Native audio preprocessing first uses the selected executor, then retries
on CPU if that executor is incompatible and remembers the working choice for
the loaded model. With the verified Gemma 4 E2B bundle, `--backend gpu` resolves
to GPU text/vision and CPU audio. That transparent fallback is bundle/runtime
compatibility behavior, not a universal LiteRT-LM CPU-audio limitation.

The smoke scripts are not a universal model certification suite. Passing them
means the representative Qwen/Gemma chat-template family can load on the chosen
backend and that the high-risk streaming parser invariants hold for the tested
artifact.

## Adding a model family

Templates are committed as jinja under `tool/litert_lm_templates/` and embedded
into `lib/src/backends/litert_lm/litert_lm_chat_templates.dart` by a generator.
Start from the canonical template llama.cpp uses. Keep any runtime
content-shape adapter in this source and cover it with prompt-parity tests.
The Dart renderer gives an adapter the media marker in the message text and
never an image or audio part. It still reports an adapter that reads content
part lists but rejects both kinds as reading strings only. Pin the result in
`test/unit/core/template/template_caps_cache_fixtures_test.dart`.

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
  through `chatTemplate(...)`, Gemma 4 required tool-choice compatibility,
  parallel tool calls, and any backend that does not expose native structured
  chat generation. Hermes/Qwen required tool-choice is rejected before this
  fallback because dropping its grammar would weaken the public contract.

- **Thinking is reassembled from a channel stream.** The native runtime streams
  reasoning and the answer on separate channels — thought as
  `{"role":"assistant","channels":{"thought":"..."}}` and the answer as
  `{"role":"assistant","content":[{"type":"text",...}]}`. `LiteRtLmChannelAssembler`
  (in `litert_lm_runtime.dart`) wraps thought runs in the active handler's
  reasoning tags (`<|channel>thought … <channel|>` for Gemma 4, `<think>…</think>`
  for Qwen/Hermes) so chat-template handlers extract them as reasoning instead
  of leaking raw JSON.
- **Grammar-constrained decoding is skipped.** Required-tool handlers including
  Hermes/Qwen and Gemma 4 can emit GBNF tool-call grammars, which the LiteRT-LM
  backend cannot consume. `NativeAutoBackend` forwards
  `supportsGrammarConstraints == false` from the active delegate. The planner
  therefore rejects Hermes/Qwen `ToolChoice.required` before generation rather
  than dropping its required-call constraint. Gemma 4 keeps its existing,
  real-model-tested rendered-prompt compatibility path, but its handler grammar
  is still not applied by LiteRT-LM and must not be reported as grammar support.
- **Native JSON Schema uses its own provider.** Canonical Qwen3 text chat and
  Gemma 4 chat with its bundle template, on macOS/iOS arm64 CPU and GPU and
  the Android arm64, Linux x64/arm64 and Windows x64 CPU, pass the
  schema directly to LLGuidance after constructing the model's provider. The
  schema must sit in the subset both LLGuidance and the GBNF converter enforce.
  Gemma 4 may think first; Qwen3 must disable thinking. Tools, media, custom
  templates, speculation, caller stops and wider schemas fail explicitly.
  Automatic model/tool constraints stay disabled and GBNF support stays false.
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
