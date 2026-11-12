# Tool results as user turns: render reference

`tool_result_user_turn_render_upstream.json` holds the prompts that llama.cpp
`b6000` (`4762ad7316dcdec20016ab5985fb46a27902204d`), the last minja-based
release line, returned from `common_chat_templates_apply` with
`use_jinja = true` and `add_generation_prompt = true` for its `messages`: a
user question, one assistant tool call and one `role: tool` result. Each
template was rendered with no tools (content-only route) and with the listed
tool (generic route), with BOS and EOS overrides `<s>` and `</s>`; llama.cpp
leaves the BOS out of the prompt.

The templates reject the `tool` role through their role-alternation check, so
minja's `polyfill_tool_responses` sent the result as a user message and
`polyfill_tool_calls` moved the call into the assistant content. The pinned
template ref, `b10549`, no longer has these polyfills and fails with
`Conversation roles must alternate user/assistant/user/assistant/...` for the
same request.

- `test/fixtures/templates/gemma-3-4b-it.jinja`: Gemma 3.
- `test/fixtures/templates/Mistral-7B-Instruct-v0_2.jinja`: the
  `mistralai/Mistral-7B-Instruct-v0.2 (NOTE: Old pre-v1 without a system
  prompt)` template from llama.cpp `tests/test-chat-template.cpp`. It is
  byte-identical to the template embedded in
  `Mistral-7B-Instruct-v0.3-Q4_K_M.gguf` (SHA256
  `1270d22c0fbb3d092fb725d4d96c457b7b687a5f5a715abe1e818da303e562b6`), the
  model reported in [#885](https://github.com/leehack/llamadart/issues/885).
- `test/fixtures/llama_cpp_templates/google-gemma-2-2b-it.jinja`: Gemma 2,
  from llama.cpp `models/templates`.

`test/unit/core/template/tool_result_user_turn_render_test.dart` compares the
content-only prompts in full. On the generic route it compares from the user
question to the end: before it, llama.cpp `b6000` also wrote the tool list and
an example call into the prompt, which llamadart's generic route does not.
