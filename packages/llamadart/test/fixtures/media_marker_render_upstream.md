# Media marker render reference

`media_marker_render_upstream.json` holds the prompts that an unmodified
`llama-server`, built from llama.cpp `d81235049` (tag `v0.6.0`, the pinned
native runtime), returned from `POST /apply-template` for conversations with
image and audio parts. It pins
[#964](https://github.com/leehack/llamadart/issues/964):

- llama-server gives a chat template the media marker in the message text,
  where the image or audio part was, and never the part itself. A template's
  own image placeholder (`<|vision_start|><|image_pad|><|vision_end|>` in
  Qwen3.5, `<|vision_bos|><|IMAGE|><|vision_eos|>` in Qwen2.5-Omni,
  `<start_of_image>` in Gemma 3, `<|image|>` in Gemma 4 and, between its
  begin and end tokens, in GLM-OCR) is therefore not in the prompt, and mtmd
  adds the image begin and end tokens when it tokenizes the marker.
- The marker is random for each server process (`media_marker` in each
  case), so a placeholder string that a message quotes is text. The
  `literal_*` conversations and `two_literals_one_image` quote `<img>`,
  `<image>`, `[IMG]` and `<__media__>` in user, system and assistant text.

`conversations` holds each conversation as ordered `parts` (`text`, `image`
or `audio`), the form the tests build typed `LlamaChatMessage`s from. The
request sent each image as an `image_url` part carrying `image_png_base64` and
each audio part as an `input_audio` part carrying `audio_wav_base64` (0.1 s of
16 kHz silence), and a message with a single text part as string content.

For each template the server ran with
`--jinja --chat-template-file <template> -c 1024 -t 2 -ngl 0 --mmproj <mmproj> --no-mmproj-offload --no-warmup -np 1`
and `LLAMA_MEDIA_MARKER` unset. The prompt comes from the fixture template,
not from the GGUF, so the model only supplies the projector that lets the
server accept the media part, and its `eos_token`:

- `media_model: vision` cases ran on `vision_model` and `vision_mmproj` from
  [LiquidAI/LFM2-VL-450M-GGUF](https://huggingface.co/LiquidAI/LFM2-VL-450M-GGUF).
- `media_model: audio` cases ran on `audio_model` and `audio_mmproj` from
  [ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF](https://huggingface.co/ggml-org/ultravox-v0_5-llama-3_2-1b-GGUF).
  `audio_model` is that repository's name for the file, whose LFS object is
  `audio_model_sha256`; the capture read the same bytes from a local copy
  named `ultravox-v0.5-1b-q4_k_m.gguf`.

llama-server returned the prompts without the template's leading `bos_token`.
`template_sha256` is the template's hash, and `supports_string_content` and
`supports_typed_content` are the `chat_template_caps` that `/props` reported.
SmolVLM is the template that reads content only as a part list; the others
read strings too.

The templates under `test/fixtures/media_templates/` are the
`tokenizer.chat_template` of:

| Template | Repository, revision | File | SHA256 |
| --- | --- | --- | --- |
| `Qwen2_5-Omni-3B.jinja` | [ggml-org/Qwen2.5-Omni-3B-GGUF](https://huggingface.co/ggml-org/Qwen2.5-Omni-3B-GGUF/tree/75f1b73b657a50f5092502799457ccb4a4a1f9df), `75f1b73b657a50f5092502799457ccb4a4a1f9df` | `Qwen2.5-Omni-3B-Q4_K_M.gguf` | `4b0bd358c1e9ec55dd3055ef6d71c958c821533d85916a10cfa89c4552a86e29` |
| `LFM2-VL-450M.jinja` | [LiquidAI/LFM2-VL-450M-GGUF](https://huggingface.co/LiquidAI/LFM2-VL-450M-GGUF) | `LFM2-VL-450M-Q4_0.gguf` | `1fbf4797e8669cdeabd97fa1d31ab046907cb1fc78b1c3d4bda1ba879574e5d7` |
| `GLM-OCR.jinja` | [mradermacher/GLM-OCR-i1-GGUF](https://huggingface.co/mradermacher/GLM-OCR-i1-GGUF/tree/d121724de822e6f4cceccd91a5d99fbf8d4cceea), `d121724de822e6f4cceccd91a5d99fbf8d4cceea` | `GLM-OCR.i1-Q4_K_M.gguf` | `43e7bfe131501d8e39b56da806abdd9161f34087680990c6b1ebe2ea0c2ef80d` |

`test/unit/core/template/media_marker_render_parity_test.dart` renders each
conversation through `ChatTemplateEngine.render` with `bos_token` empty, the
case's `eos_token` and the case's `media_marker`, and expects the exact
prompt. `test/unit/backends/llama_cpp/llama_cpp_service_media_prompt_test.dart`
hands the Qwen3.5 and Qwen2.5-Omni prompts to the llama.cpp service and
expects what reaches `mtmd_tokenize`: the same text with mtmd's `<__media__>`
where the server's marker was. As a chat prompt a quoted `<__media__>` has a
zero-width space in it; as a caller prompt, the way `chatTemplate` output
reaches the service, every quoted placeholder has one.
