# Template message JSON render reference

`template_message_json_upstream.json` holds the prompts that an unmodified
`llama-server`, built from llama.cpp `7fe450e19` (tag `v0.5.0`, the pinned
native runtime), returned from `POST /apply-template` for each case's
`request`. Each case names the issue it pins:

- [#715](https://github.com/leehack/llamadart/issues/715): assistant turns
  with only tool calls or only reasoning (`content: null` in the request).
- [#717](https://github.com/leehack/llamadart/issues/717): Map and List tool
  results. llama-server accepts only string tool content, so the request
  carries the compact JSON text that llamadart sends for the typed result.
- [#702](https://github.com/leehack/llamadart/issues/702): earlier tool-call
  arguments written as compact JSON. The Functionary v3.2 case is a control:
  llama-server reports `supports_object_arguments: false` for that template,
  so its arguments stay a string.
- [#716](https://github.com/leehack/llamadart/issues/716): an LFM2.5 template
  that lists tools without `<|tool_list_start|>`. The LFM2 handler passes each
  tool in the flat shape LiquidAI's model cards show, where llama-server
  passes the OpenAI shape, so this case (`lfm2_flat_tool_list`) takes each
  tool's `function` from the server's list and compares the rest exactly.
- [#720](https://github.com/leehack/llamadart/issues/720): templates whose
  content caps llamadart detected differently from llama-server: SmolVLM
  (typed content only), Ministral 3 and TranslateGemma 2B with an image
  followed by a reasoning-only assistant turn, and Ministral 3 14B with an
  image followed by an assistant turn without text. These cases record the
  `chat_template_caps` that `/props` reported. SmolVLM-500M-Instruct.jinja is
  the template in `SmolVLM-500M-Instruct-Q8_0.gguf` from
  [ggml-org/SmolVLM-500M-Instruct-GGUF](https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF)
  (SHA256
  `9d4612de6a42214499e301494a3ecc2be0abdd9de44e663bda63f1152fad1bf4`).
  The Kimi-K2 `media_tool_call_only` case also pins its string tool result
  after an image.

`conversations` holds each conversation in the form the test builds typed
`LlamaChatMessage`s from; `request` is the same conversation in OpenAI form.

For each template the server ran with
`--jinja --chat-template-file <template> -c 512 -t 2 -ngl 0` on
`stories15M.gguf` from
[ggml-org/tiny-llamas](https://huggingface.co/ggml-org/tiny-llamas), whose
SHA256 is `model_sha256`. The prompt comes from the fixture template, not from
the GGUF. That model's `bos_token` is `<s>` and its `eos_token` is `</s>`;
llama-server returned the prompts without the template's leading `<s>`. `template_sha256` is the
template's hash, and `supports_object_arguments` is what `/props` reported.

The `media_tool_call_only` cases (an image, then a tool-call-only assistant
turn) ran with `--mmproj` on `media_model` from
[LiquidAI/LFM2-VL-450M-GGUF](https://huggingface.co/LiquidAI/LFM2-VL-450M-GGUF)
and its `media_mmproj`, with `-c 1024 --no-mmproj-offload --no-warmup -np 1`
and the request's `tools`. The `media_reasoning_only` and `media_empty_assistant` cases ran the same way
without tools; that model's `eos_token` is `<|im_end|>`, which the case's
`eos_token` records. llama-server prints each image as a random
`<__media_…__>` marker, which the test reads as llamadart's `<__media__>`.
The `media_tool_call_only` cases render images in a different form, and the
TranslateGemma handler fills in language codes that llama.cpp leaves empty,
so these cases compare only the prompt segments their `checks` name:
`same_after` (everything after a marker), `same_between` (between two
markers), and `contains_between` (values that both prompts hold between two
markers). llama.cpp renders Apriel 1.6 tool calls in its own format, which
llamadart's generic tool format does not match, so that case checks that the
call is rendered and that the rest of the prompt is the same.

`test/unit/core/template/template_message_json_parity_test.dart` renders each
conversation through `ChatTemplateEngine.render` with `bos_token` empty and
`eos_token` `</s>` (or the case's `eos_token`), expects the exact prompt (or
the `checks`), and expects `TemplateCaps.detect` to report the same
`supports_object_arguments` and, where a case records them, the same
`chat_template_caps`. The gpt-oss and Solar Open templates print the current date with `strftime_now`, which reads the wall
clock, so the test masks that date on both sides.
