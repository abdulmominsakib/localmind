# User follow-up after tool results: upstream render reference

`tool_result_follow_up_render_upstream.json` records llama.cpp `b10549`
(`upstream_sha` in the JSON) on the six real templates listed in `renders`.
No model weights are needed. The legacy Mistral fixture is byte-identical to
that in the reported v0.3 GGUF; its provenance is in
`tool_result_user_turn_render_upstream.md`.

For each template, run the pinned `test-chat-template` with:

```bash
test-chat-template --no-common --json INPUT --output OUTPUT TEMPLATE
```

Build INPUT from `template_globals` and one of these `messages` lists:

- `original_messages`: user, assistant call, tool result, user follow-up.
- The old retry: `merged_messages`, but split the final content at its last
  newline into two user messages (result JSON and follow-up).
- `merged_messages`: user, assistant call serialized as generic JSON, and one
  user turn holding result JSON, a newline and the follow-up.

The first two inputs fail with `Conversation roles must alternate
user/assistant/user/assistant/...` (SIGABRT/exit -6 in the reference process).
The merged input exits 0; `prompt` is its exact output file. BOS is empty,
EOS is `</s>`, and no tools are supplied, avoiding a tool-instruction prefix.
The unit tests compare the complete prompt. Separate per-template tests cover
all tool choices, tools present/absent, thinking enabled/disabled and unchanged
first renders. The local E2E suite rechecks the upstream emissions.

This is an intentional extension to upstream behavior for
https://github.com/leehack/llamadart/issues/1118. Only failed renders that reject
the tool role take this retry. No existing fixture was changed.
