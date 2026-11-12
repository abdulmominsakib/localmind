# Qwen3-Coder XML upstream parses

`qwen3_coder_xml_upstream.json` records how llama.cpp parses Qwen3-Coder XML
replies around their tool calls, for issue #1531. The templates are the
vendored Qwen3-Coder (no thinking), Qwen3.5 0.8B (thinking on: the prompt opens
the thought; off: it closes it) and StepFun3.5-Flash (the prompt opens the
thought either way; llamadart closes it with thinking off) templates, each with
`parallel_tool_calls` off and on.

`upstream` comes from a probe built from unchanged llama.cpp
`cd959bae99ff4bed22bef2604f45241c09bbb8c8`, the native `v0.9.0` pin. With no
model loaded, it called `common_chat_templates_init` on the template, built a
`common_chat_session` from one user message, the `get_weather` tool with a
required string `location`, `tool_choice` auto, the entry's
`parallel_tool_calls` and `enable_thinking`, and `COMMON_REASONING_FORMAT_AUTO`
(format `peg-native`), and called `finish` on the whole output. Feeding the
whole output first gave the same result. `upstream_partial` is
`common_chat_peg_parse` with `is_partial` on the same output.

The cases from `bare-call` on, added for issue #1531 with the same probe, hold
a `<function=…>` opening without `<tool_call>`. llama.cpp takes one that names
a declared tool as the first call, for the Qwen3-Coder template only, as it
has no thought. The two Qwen3-Coder entries with `"tool_choice": "required"`
hold those cases; the other entries pass `tool_choice` auto.

Left out:

- `upstream_partial` of a call whose scope end is missing: llama.cpp takes the
  call while the reply is partial, and llamadart only once it finishes.
- A reply cut off inside a call, which llama.cpp returns as a call with
  unterminated JSON arguments, and llamadart drops.
- The `bare-call`, `text-then-bare-call` and `bare-call-then-call` cases with
  Qwen3-Coder and tool choice auto: llamadart takes such a call only for a
  required call, so the tag and what follows it stay content.
- The `bare-call` and `text-then-bare-call` cases with StepFun3.5-Flash and
  thinking off: llama.cpp keeps the thought its prompt opened, so a reply with
  no thinking tag or `<tool_call>` is reasoning, while llamadart closed the
  thought and returns content. This is deliberate (maintainer decision on
  #1898).

Fed one byte at a time, llama.cpp's session keeps the first call of a scope
that holds two (`two-functions-in-one-scope*`), because the final parse returns
an empty message, which does not replace the partial one. The recorded value is
that final parse.
