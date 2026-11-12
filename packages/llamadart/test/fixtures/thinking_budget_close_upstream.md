# Thinking-budget close upstream

`thinking_budget_close_upstream.json` records the text llama.cpp forces when a
thinking budget runs out, for issue #1914.

`thinking_end_tags` is the end-tag list `common_chat_templates_get_thinking_tags`
returns for each vendored template, from llama.cpp
`cd959bae99ff4bed22bef2604f45241c09bbb8c8` (native `v0.9.0`). The server
forces the first one: `\n</think>` for the Qwen3-Coder XML family (Qwen3.5,
Nemotron 3 Nano, StepFun 3.5 Flash), `</think>` for the control templates.

`server_emissions` is `llama-server` at the same commit running
`unsloth/Qwen3.5-2B-GGUF` `Qwen3.5-2B-Q4_K_M.gguf` with `tool_choice: required`,
temperature 0, seed 1 and `max_tokens` 160, for each
`thinking_budget_tokens`. With a budget the reasoning ends in a line break and
the tool call parses; it is kept as provenance and not asserted.
