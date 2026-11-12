# Hermes double-brace tool call

`hermes_double_brace_tool_call.json` records Qwen2.5 outputs that wrap Hermes
tool calls in an extra `{` (issue #662).

`hermes_double_brace_qwen2_5.jinja` is the unchanged `tokenizer.chat_template`
of `qwen2.5-0.5b-instruct-q4_k_m.gguf` from `Qwen/Qwen2.5-0.5B-Instruct-GGUF`,
revision `9217f5db79a29953eb74d5343926648285ec7e67`.
Model SHA256: `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`.
Template UTF-8 SHA256: `d5495a1e5db0611132a97e46a65dbb64a642a499421228b9c8b93229097fa9a4`.
Its tool prompt prints `{{"name": <function-name>, "arguments": <args-json-object>}}`
literally. With no grammar constraining it, the model copies the double braces
and sometimes adds more closing braces.

Every case uses the `get_weather` tool with `ToolChoice.auto` and its own
`prompt`. `source` says where the emission came from:

- `issue`: `webgpu-bridge-v0.1.49` is the emission reported in issue #662 for
  WebGPU bridge assets `v0.1.49`, where llamadart sends no tool grammar for
  `ToolChoice.auto`.
- `recorded`: llamadart native `v0.5.0` on CPU with 4 threads, the prompt from
  `engine.chatTemplate`, and `engine.generate` without the tool grammar, with
  the recorded `sampling` (`temp: 0` is greedy). `pieces`, when present, are
  the strings `engine.generate` yielded.
- `constructed`: `two-calls-extra-closing-brace` was written by hand, not
  generated. The #695 audit reported a two-call Tokyo/London emission for which
  the base parser kept both calls and the first version of the fix kept none;
  its text is not recorded here. This case fails the same way under that
  version.

`upstream_result` comes from a probe built from unchanged llama.cpp
`7fe450e19305b828c199d602c23a8337aaa1f03b`. It loaded the model vocabulary
only, then called `common_chat_templates_init`, `common_chat_templates_apply`
with the `user_prompt`, the tool and auto tool choice (format `peg-native`), and
`common_chat_parse` with `is_partial = false`. For every case the parse throws
the recorded error and extracts no tool call. The single-brace control
`<tool_call>\n{"name": "get_weather", "arguments": {"city": "Paris"}}\n</tool_call>`
parses to one `get_weather` call with empty content.

`base_result` is `HermesHandler.parse` at llamadart
`8c62f2e9d2602622302ed9ef83f25a050221ba59`, before the double-brace fix. It
extracted each call from the inner object and left envelope text in `content`.
The tests require the current parser to keep every call in `base_result`.

`expected` is llamadart's deliberate behavior, which differs from upstream: the
calls are extracted. A well-formed envelope, including any number of extra
closing braces before its close tag, leaves no content. A double-brace call
whose envelope is otherwise malformed is parsed as the base parser did: the call
is kept and its envelope text stays in `content`.
