# Qwen3 tool-call turn render reference

`qwen3_tool_turn_render_upstream.json` holds the prompt that an unmodified
`llama-server`, built from llama.cpp `7fe450e19` (tag `v0.5.0`, the pinned
native runtime; `/props` reported `build_info` `b11146-7fe450e19`), returned
from `POST /apply-template` for its `request`: a user question, one assistant
tool call with empty `reasoning_content`, and its `role: tool` result. The
request declares no tools and leaves `add_generation_prompt` and
`enable_thinking` at their defaults. The same request without
`reasoning_content` returned the same prompt.

The server ran with
`--jinja --chat-template-file test/fixtures/templates/Qwen3-4B.jinja -c 1024 -t 4 -ngl 0`
on `Qwen3-4B-Q4_K_M.gguf` (SHA256
`f6f851777709861056efcdad3af01da38b31223a3ba26e61a4f8bf3a2195813a`).
`template_sha256` is the fixture template's hash, and `chat_template_caps` is
what `/props` reported.

`test/unit/core/template/tool_call_fixture_render_test.dart` renders this
conversation with the fixture template and with the LiteRT-LM built-in
`qwen3` template, with and without an empty thinking part, and expects this
exact prompt. The assistant turn has no `<think>` block because
`reasoning_content.strip() == ''` is true.
