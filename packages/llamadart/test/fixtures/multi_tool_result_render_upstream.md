# Parallel tool-result render reference

`multi_tool_result_render_upstream.json` holds the prompts that an unmodified
`llama-server`, built from llama.cpp `7fe450e19` (tag `v0.5.0`, the pinned
native runtime), returned from `POST /apply-template` for its `request`: a user
question, one assistant message with two tool calls, and one OpenAI-style
`role: tool` message per call, holding `RESULT_ONE` and `RESULT_TWO`. The request
declares two tools and sets `tool_choice: auto`, `parallel_tool_calls: true` and
`enable_thinking: false`.

For each fixture template the server ran with
`--jinja --chat-template-file test/fixtures/<template> -c 1024 -t 4 -ngl 0` on
the GGUF named in its `model` entry, so the prompt comes from the fixture
template, not from the template embedded in the GGUF. `template_sha256` is the
fixture's hash, and `chat_template_caps` is what `/props` reported.

GGUF SHA256:

- `Qwen3-4B-Q4_K_M.gguf`: `f6f851777709861056efcdad3af01da38b31223a3ba26e61a4f8bf3a2195813a`
- `Qwen3.5-0.8B-Q4_K_M.gguf`: `bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517`
- `Ministral-3-3B-Reasoning-2512-Q4_K_M.gguf`: `a2648395d533b6d1408667d00e0b778f3823f3f3179ba371f89355f2e957e42e`
- `functiongemma-270m-it-Q4_K_M.gguf`: `7474135cf63b5de86bd29d2feb92c644d48e9df5e1ac31550662af373c67d0fc`
- `Phi-4-mini-instruct-Q4_K_M.gguf`: `88c00229914083cd112853aab84ed51b87bdf6b9ce42f532d8c85c7c63b1730a`
- `LFM2.5-1.2B-Thinking-Q4_K_M.gguf`: `251867cddd9e1240ec0d8a733cf705629631fbe36c9170c54b968388fae3ba7e`

`test/unit/core/template/tool_call_fixture_render_test.dart` renders the same
conversation with both results in one typed tool message, and with one typed
tool message per result, and compares each prompt with these prompts from
where the template opens the first tool result to the end. The earlier
part of the prompt is not compared: there llamadart and llama.cpp already
differ in ways unrelated to tool results, such as JSON spacing in tool
declarations.
