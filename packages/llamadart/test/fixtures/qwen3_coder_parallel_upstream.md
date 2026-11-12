# Qwen3-Coder XML parallel-call upstream parses

`qwen3_coder_parallel_upstream.json` records how llama.cpp parses Qwen3-Coder
XML replies with two or three consecutive tool calls, each in its own
`<tool_call>` scope, for issue #1530.

The templates are the vendored Qwen3-Coder, Qwen3.5 0.8B and StepFun3.5-Flash
templates. Each case builds its output from `prefix`, one `call` per city
joined by `separator`, and `suffix`.

`upstream` comes from a probe built from unchanged llama.cpp
`620d2225cc436ab0b001e3200e590e3b286ef9ab`, the source of the pinned native
runtime. With no model loaded, it called `common_chat_templates_init` on the
template, built a `common_chat_session` from one user message, the
`get_weather` tool with a required string `location`, `tool_choice` auto,
`parallel_tool_calls = true`, the case's `enable_thinking` and
`COMMON_REASONING_FORMAT_AUTO` (format `peg-native`), and called `finish` on
the whole output; `upstream` holds its content, reasoning and tool calls.
Feeding the output one byte at a time gave the same result for every case.
Every case returned one `get_weather` call per city, in order.

Cases where llamadart differed from that probe for a single call were left
out: text after the last call, a thought in the Qwen3-Coder template, which has
no thinking, and a StepFun3.5-Flash thought with thinking off.
`qwen3_coder_xml_upstream.json` now records them (#1531).
