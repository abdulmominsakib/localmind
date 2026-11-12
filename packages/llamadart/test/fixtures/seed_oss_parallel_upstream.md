# Seed-OSS parallel-call upstream parses

`seed_oss_parallel_upstream.json` records how llama.cpp parses Seed-OSS
replies with two or three consecutive tool calls, each in its own
`<seed:tool_call>` scope, for issue #1540. It has the layout of
`qwen3_coder_parallel_upstream.json`, which documents the probe, on the vendored
`ByteDance-Seed-OSS.jinja` template.

Every case returned one `get_weather` call per city, in order, with the
`location` value as generated, line breaks included.

Cases where llamadart already differs from that probe for a single call are
left out: text after the last call, which llama.cpp rejects and llamadart keeps
as content, a `</seed:think>` without its opening tag, which llama.cpp keeps as
content, and a thought with thinking off, which llamadart does not stream as
reasoning.

## Intentional divergences

Where llama.cpp (`cd959bae9`) fails the reply with an error, llamadart
deliberately keeps the call (maintainer decision,
[#1542](https://github.com/leehack/llamadart/pull/1542#issuecomment-6758592134);
tracker [#1531](https://github.com/leehack/llamadart/issues/1531)). These are
not cases here; `seed_oss_handler_test.dart` pins them:

- An unknown tool name is returned as a call: `SeedOssHandler.parse` takes no
  tool schemas, and Seed-OSS requests refuse `ToolDefinition.fromJsonSchema`
  tools at render, so validate the name before running the call.
- A call missing a required argument is returned with the arguments present;
  validate the arguments before running it.
- A later scope whose `<seed:tool_call>` is not followed by a line break stays
  content after the calls before it.

Both start calls at the first `<seed:tool_call>` followed by a line break
(`\n\n` included) and keep the text before it as content, including a
`<seed:tool_call>` followed by anything else.
