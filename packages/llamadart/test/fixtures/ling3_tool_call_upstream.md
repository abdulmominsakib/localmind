# Ling 3.0 upstream parses

`ling3_tool_call_upstream.json` records how llama.cpp parses Ling 3.0 (Bailing
V3) replies, for issue #1857. The template is the vendored
`inclusionai-ling-3.0-flash.jinja`, copied from llama.cpp `v0.9.0`.

`upstream` comes from a probe built from unchanged llama.cpp
`cd959bae99ff4bed22bef2604f45241c09bbb8c8`, the native `v0.9.0` pin, whose
`common_chat_params_init_ling3` (`common/parsers/ling3.cpp`) handles the
template. With no model loaded, it called `common_chat_templates_init` on the
template, built a `common_chat_session` from one user message, the tools in
`tools` (`get_weather` with a required string `location` among them), the
entry's `parallel_tool_calls`, `enable_thinking` and `tool_choice` (auto unless
the entry sets it) and `COMMON_REASONING_FORMAT_AUTO` (format `peg-native`),
and called `finish` on the whole output. Feeding the whole output first gave
the same result. `upstream_partial` is `common_chat_peg_parse` with
`is_partial` on the same output, recorded only where llamadart's partial parse
already matches it. Each entry with calls enabled also records the prompt and
whether the grammar is lazy, and the top level the stops, preserved tokens and
grammar trigger.

`schema_tools` and `schema_templates` hold the same probe with one tool whose
arguments may be several JSON types (`mixed`). A request refuses such tools,
so the test reaches the handler directly.

`ling3_call_grammar_test.dart` holds replies with whether llama.cpp's grammar
takes them, from the same commit's `test-gbnf-validator`.

Left out:

- A reply that ends inside its first call, such as `<tool_call>get_weather`:
  llama.cpp returns a call whose JSON arguments never end, and llamadart drops
  the call. The same holds for an unfinished second call with parallel tool
  calls.
- With `"tool_choice": "required"`, every reply without a valid call: an
  invalid call, a Hermes JSON call, text only. llama.cpp fails the reply with
  an error, and llamadart returns it as content.
- A reply with a second `<|role_end|>` after text that follows the calls, or a
  `<|role_end|>` followed by text when calls are not parsed: llama.cpp fails
  the reply, and llamadart keeps the text as content.
- With `"tool_choice": "none"`, the prompt: llama.cpp renders the tools, and
  llamadart renders none, as for every format.
- The prompt of a request with a response schema, which llamadart builds with
  its generic response-schema grammar.
- Values outside the declared types of `mixed` (`5.5` or `true` for an
  integer or string, an object for an integer or string argument): llama.cpp
  takes them, and llamadart's schema validation rejects them.
- The required-call entries with parallel tool calls, which differ from the
  recorded ones only in the grammar.
