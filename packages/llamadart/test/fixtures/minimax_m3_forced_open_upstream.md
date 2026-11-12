# MiniMax M3 forced-open thought upstream parses

`minimax_m3_forced_open_upstream.json` records how llama.cpp parses output after
a prompt that opens a thought, for issue #1905.

The template is the vendored `MiniMax-M3.jinja` with
`chat_template_kwargs: {"thinking_mode": "enabled"}`, which ends the generation
prompt with `<mm:think>`. `auto` and `none` are the tool choice.

The results come from a probe built from unchanged llama.cpp
`cd959bae99ff4bed22bef2604f45241c09bbb8c8` (native `v0.9.0`). With no model
loaded, it called `common_chat_templates_init` on the template, built the
request from one user message, the `weather` tool and
`enable_thinking = true`, and called `common_chat_peg_parse` on each output
(`is_partial = true` for the `partial` case). The thought is the text before
the first `</mm:think>`, kept as generated, and the rest is content in which
thinking tags are text. llama.cpp keeps the whitespace around the content; the
tests compare it trimmed, as the engine returns it.
