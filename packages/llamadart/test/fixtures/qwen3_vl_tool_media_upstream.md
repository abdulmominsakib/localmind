# Qwen3-VL tool-result media reference

`qwen3_vl_tool_media_upstream.json` holds the prompts that an unmodified
Homebrew `llama-server` 0.7.0 (llama.cpp `620d2225c`, `/props` `build_info`
`b11669-620d2225c`) returned from `POST /apply-template` for the `cases` below, whose
`role: tool` messages carry `image_url` parts in array `content`:

- `two_results`: two calls; the first result is JSON text, a caption and an
  image, the second only an image.
- `user_image_then_tool_image`: a user image, one call, and a result with
  text after its image.

`RED` and `BLUE` in each `request` stand for base64 PNG data URIs. The server
ran with `LLAMA_MEDIA_MARKER='<__media__>'`, so the marker is reproducible,
and with
`--jinja --chat-template-file test/fixtures/templates/Qwen3-VL-2B-Instruct.jinja -c 4096`
on the hashed Qwen3.5-0.8B GGUF and projector. The template is
`chat_template.json` from `Qwen/Qwen3-VL-2B-Instruct` at revision
`89644892e4d85e24eaac8bacfd4f463576704203`; `chat_template_caps` is what
`/props` reported. Qwen3.5-0.8B uses the same `qwen3vl_merger` projector type,
and the prompt does not depend on the weights.

Real Qwen3-VL-2B-Instruct weights (`ggml-org/Qwen3-VL-2B-Instruct-GGUF`
revision `ea6a11058182570be6436b9a2e4ee7f7b49f908d`, `Q8_0` GGUF
`b7802e29f71a9e5b5e3f83f613df898a2204342dcea71a231ea501d481813c39` and
`Q8_0` projector
`69066c8f279ec85ff48ab4059f6ebba0d2932ca57667f2bbdac7d9805bca9e7b`) passed
the local-only `tool-result-image-smoke` scenario on macOS arm64 CPU with the
model's own chat template: red and blue history photos read back as `Red` and
`Blue`, and both handler tool loops ended `completed` after one call and
round. `gguf-chat-features-smoke` on the same GGUF returned `tool_calls`
with one call for all four tool-call variants.

`test/unit/core/template/tool_result_media_render_test.dart` and
`test/unit/core/engine/tool_result_media_public_api_test.dart` render the
same conversations with `LlamaToolResultContent.content` and expect these
exact prompts.

`text_only_cases` also holds string-only Hermes cases rendered with
`test/fixtures/templates/Qwen3-4B.jinja` on the same server and model:
`string_only_leading_empty_result` (`result: ''` and a text part `x`) and
`string_only_null_result_leading_empty_part` (no result, parts `''` and `x`).
Both emit `x` with no leading newline. `string_only_empty_middle_part` (result
`abc`, parts `''` and `x`) keeps the newline after the non-empty `abc` for
the empty part and the one after it. `string_only_whitespace_result` (result
`' '`, part `x`) keeps the space as non-empty text, and
`string_only_newline_part_first` (no result, parts `'\n'` and `x`) adds a
newline after the first `'\n'`.

`cases` also holds `image_empty_text` (no result, an image, `''`, `x`) and
`text_empty_image_empty_text` (result `a`, parts `''`, an image, `''`, `b`):
an empty text part after a marker restores the newline before the next text.

The same server answered `/v1/chat/completions` at temperature 0 with
`The main color of the photo is **Red**.` and
`The main color of the photo is **blue**.` for the photo-color history the
local-only `tool-result-image-smoke` scenario sends, and with
`The main color of the photo is blue.` for its tool-loop follow-up.
