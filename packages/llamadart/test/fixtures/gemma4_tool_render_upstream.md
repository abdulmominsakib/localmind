# Gemma 4 tool-turn render reference

`gemma4_tool_render_upstream.json` holds the prompts that an unmodified
`llama-server`, built from llama.cpp `7fe450e19` (tag `v0.5.0`), returned from
`POST /apply-template` for each request in its `requests` map. Every request
declares tools, uses `tool_choice: auto` and sets `enable_thinking: false`.

Templates:

- `templates/gemma-4-E2B-it.jinja` is the exact `tokenizer.chat_template` of
  `unsloth/gemma-4-E2B-it-GGUF`, revision
  `90f9618340396838ee7ff5b0ba2da27da62953d3`, file
  `gemma-4-E2B-it-Q4_K_S.gguf` (SHA256
  `0a2fac16f388b4839f075dedb681357aec3e73a96bd66b413e462b6853550c99`). It
  reads OpenAI-style `role: tool` messages.
- `llama_cpp_templates/google-gemma-4-31B-it-interleaved.jinja` is llama.cpp's
  copy of an older Gemma 4 template, which reads `tool_responses` on the
  assistant message. It is identical at `7fe450e19` and at the ref in
  `tool/testing/llama_cpp_templates.ref`. The server loaded it with
  `--chat-template-file`, and llama.cpp applied its outdated-template
  conversion.

The server ran the GGUF above with `-c 1024 -t 4 -ngl 0`. `/props` reported
`supports_object_arguments: true` for both templates. llama.cpp removes the
leading BOS text from the returned prompt, because its tokenizer adds BOS.

`test/unit/core/template/handlers/gemma4_handler_test.dart` renders the same
conversations from typed messages and compares them with these prompts.
