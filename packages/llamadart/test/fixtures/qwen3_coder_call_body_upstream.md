# Qwen3-Coder XML call-body upstream parses

`qwen3_coder_call_body_upstream.json` records how llama.cpp parses the body of
a Qwen3-Coder XML call, for issue #1898: the line breaks between its tags, the
order of required and optional arguments, and string values that hold tags or
whitespace. The templates are the vendored Qwen3-Coder, Qwen3.5 0.8B,
StepFun3.5-Flash and Nemotron-3-Nano templates; llama.cpp parses all four with
its Qwen3-Coder parser.

The probe is the one `qwen3_coder_xml_upstream.md` describes, at the same
llama.cpp commit, with the two tools in `tools`: `get_weather` with a required
string `location`, and `get_time` with a required string `tz` and an optional
integer `days`. Each entry sets its `enable_thinking`, `parallel_tool_calls`
and, when not auto, `tool_choice`. Feeding the whole output first gave the
same result. `upstream_partial` is `common_chat_peg_parse` with `is_partial`.

Left out:

- With `tool_choice` required, a reply whose only call is invalid: llama.cpp
  fails the whole reply with an error, and llamadart returns the content and
  no call.
- A value that ends without the line breaks around `</parameter>`, as in
  `Paris</parameter>`: llama.cpp returns a call whose JSON arguments never
  end, and llamadart drops the call.
