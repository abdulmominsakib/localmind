# Seed-OSS tool-call upstream parses

`seed_oss_tool_call_upstream.json` records how llama.cpp parses Seed-OSS
replies whose last scope is unclosed, whose string value looks like JSON, or
whose scope start ends the text, for issue #1898. The template is the vendored
`ByteDance-Seed-OSS.jinja`.

The probe is the one `qwen3_coder_xml_upstream.md` describes, at the same
llama.cpp commit, with the tool in `tools`: `get_weather` with a required
string `location`. Each entry sets its `enable_thinking`,
`parallel_tool_calls` and, when not auto, `tool_choice`. Feeding the whole
output first gave the same result. `upstream_partial` is
`common_chat_peg_parse` with `is_partial`, recorded only where llamadart's
partial parse already matches it.

Left out:

- Without parallel tool calls, a second scope after a call: llama.cpp fails
  the whole reply with an error, and llamadart returns the calls.
- A scope start followed by text that is not a call, as in
  `Hello <seed:tool_call>\nmore`: llama.cpp fails the reply, and llamadart
  keeps it as content.
- A finished reply cut off inside its last call, after `</function>` without
  its line break or inside a value: llama.cpp returns a call whose JSON
  arguments never end, and llamadart drops the call.
