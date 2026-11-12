# Forced-open thought upstream parses

`forced_open_thought_upstream.json` records how llama.cpp parses output after a
prompt that opens a thought, for issue #742.

The templates are the vendored `MiniMax-M2.jinja` and
`deepseek-ai-DeepSeek-V3.1.jinja` (identical at `b10549` and `620d2225c`).
Both end their generation prompt with `<think>`. The DeepSeek V3.1 entry passes
`{"thinking": true}`; `enableThinking` alone renders the same prompt.

`upstream` comes from a probe built from unchanged llama.cpp
`620d2225cc436ab0b001e3200e590e3b286ef9ab`, the source of the pinned native
runtime `v0.7.0-2`. With no model loaded, it called `common_chat_templates_init`
on the template, built a `common_chat_session` from one user message, the
`weather` tool, `enable_thinking = true` and `COMMON_REASONING_FORMAT_AUTO`
(format `peg-native`), and called `finish` on the whole output. Feeding the
output one byte at a time before `finish` gave the same result for every case.

For issue #1531 the same probe, rebuilt from llama.cpp
`cd959bae99ff4bed22bef2604f45241c09bbb8c8` (native `v0.9.0`), reproduced every
case but the six `partial-*` ones: since `a71c00f0b` a finished output keeps the
start of a tag it ends in, so those now record the newer result. Their
`upstream_partial` is the same probe's `common_chat_peg_parse` with
`is_partial = true`, which still drops that start, as a partial
`ChatTemplateEngine.parseRendered` must.

The DeepSeek V3.1 cases from `escaped-newline-in-ended-thought` on were added
for issue #750 with the same probe; `feed` and `finish` on the whole output
gave the same result as one byte at a time. A forced-open thought is the text
before the first `</think>`, kept as generated, and the rest is content.

The vendored Qwen3.5 0.8B (`test/fixtures/templates/Qwen3_5-0_8B.jinja`,
format `qwen3CoderXml`) and `Qwen-QwQ-32B.jinja` (format `hermes`) entries,
and the DeepSeek V3.1 `partial-end-tag-at-end` case, were added for issue #750
with the same probe and `enable_thinking = true` alone. Both templates end
their generation prompt with `<think>\n`. As with DeepSeek V3.1, a forced-open
thought is the text before the first `</think>`; with Qwen3.5 a `<tool_call>`
ends it first and starts the content. A thought that has not ended keeps a
trailing partial end tag. The Qwen3.5 required-call grammar, as llama.cpp's
(`cd959bae9`), takes any text without `<tool_call>`, the thought included,
before the calls, so that entry sets `required_grammar_start`. Its
`two-calls-end-unended-thought` case, added for issue #1531, sets
`parallel_tool_calls`: the probe and the test pass parallel tool calls.

The `Cohere2MoE.jinja` entry (format `cohere2Moe`), added for issue #1523
with the same probe, ends its generation prompt with `<|START_THINKING|>`. A
`<|START_TEXT|>` or `<|START_ACTION|>` before `<|END_THINKING|>` also ends the
thought and starts the content. Its required-call grammar ends the thought at
`<|END_THINKING|>`, so that entry sets `required_grammar_start` too.

A thought that never closes is reasoning, including a tool-call envelope inside
it. llamadart trims some of the whitespace llama.cpp keeps around reasoning and
content, so the test compares trimmed text.

No EXAONE MoE, Seed-OSS, Apriel 1.5 or Xiaomi MiMo template that llamadart
routes to those formats and that opens a thought in the prompt is available;
their handlers follow the same rule.
