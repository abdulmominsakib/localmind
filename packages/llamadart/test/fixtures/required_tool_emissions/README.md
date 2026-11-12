# Required tool emissions

`required_tool_emissions.json` records `ToolChoice.required` (thinking off)
emissions from three GGUF models whose tool-call grammars let them miss the
call ([#1577](https://github.com/leehack/llamadart/issues/1577)).

Each case renders `messages` and `tool` with the case's `template`, the
unchanged `tokenizer.chat_template` of `model` (SHA256 `model_sha256`).
`LFM2-1_2B-Tool.jinja` and `functionary-small-v3_2.jinja` are those of
`LFM2-1.2B-Tool-Q4_K_M.gguf` and `functionary-small-v3.2-Q4_K_M.gguf`; the
Functionary file renders no tool definitions and a literal `{role}` header.

`prompt` is `engine.chatTemplate` with no metadata overrides. Emissions are
`engine.generate` text on native llama.cpp `llamadart-native` `v0.7.0-3`
(Metal), constrained by the rendered grammar with `sampling`:

- `base_emission`: the grammar at `0bddcde0d`, which wrote `\n` as a literal
  backslash-n (DeepSeek R1, Functionary v3.2), took any number of DeepSeek
  calls, and required a free-text LFM2 `id` the model filled with prose.
- `emission`: the grammar after the fix; each parses to `tool_call`.

For the same request, llama-server at llama.cpp `5ecbe1ac1` (`v0.7.0` plus a
sampling-only commit) returns the LFM2 call, a Functionary call with empty
arguments, and a DeepSeek thought that runs to the length limit.
