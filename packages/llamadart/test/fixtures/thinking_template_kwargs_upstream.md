# Template thinking kwargs upstream renders

`thinking_template_kwargs_upstream.json` records the prompts llama.cpp renders,
for a conversation with an earlier assistant thought, when a chat template
kwarg sets a template's own thinking switch, for issue #750: `reasoning_effort`
or `reasoning` for Cohere2 MoE, `reasoning_effort` for Hy3, `thinking_mode` for
MiniMax M3 and `thinking_effort` for Kimi K3. The cases with
`upstream_chat_template_kwargs` pin that llamadart renders as llama.cpp does
with those kwargs: `enableThinking: false` as the template's own off setting,
MiniMax M3's `enableThinking: true` as `thinking_mode: enabled`, a Cohere2
MoE `skip_thinking` kwarg over the one `enableThinking: false` sets, and a
Cohere2 MoE thought that a `reasoning: true` kwarg opens, closed for
`enableThinking: false` as the template closes its own (issue #1523).

`prompt` comes from a probe built from unchanged llama.cpp
`620d2225cc436ab0b001e3200e590e3b286ef9ab`. With no model loaded, it called
`common_chat_templates_init` on the vendored template with empty BOS and EOS
tokens, then `common_chat_templates_apply` with the messages, the tool when
`tools` is true, `enable_thinking`, the kwargs and
`COMMON_REASONING_FORMAT_AUTO`.
