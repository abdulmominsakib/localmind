# Qwen3.5 schema parser reference

`qwen35_schema_upstream.json` records output from unchanged pinned llama.cpp
commit `b2e5e9b28b2484fbf94b543432ece638996a8b97`.

The unchanged `templates/Qwen3_5-0_8B.jinja` was extracted from
`ggml-org/Qwen3.5-0.8B-GGUF`, revision
`8fea620810c4afa23dd6443f999a48574c1611a3`, file `Qwen3.5-0.8B-Q4_0.gguf`.
Model SHA256: `57d1997790d1744fba5b40a7317df71ea5e2acee28c47e78f0cce39c0703f8cf`.
Template UTF-8 SHA256: `273d8e0e683b885071fb17e08d71e5f2a5ddfb5309756181681de4f5a1822d80`.
Source: https://huggingface.co/ggml-org/Qwen3.5-0.8B-GGUF/tree/8fea620810c4afa23dd6443f999a48574c1611a3

The model-free probe used `common_chat_templates_init`,
`common_chat_templates_apply`, and `common_chat_peg_parse` with the exact
Qwen3.5-0.8B template. Its messages and `inspect` schema match
`test/support/qwen_tool_schema_fixture.dart`, using pre-encoded JSON tool-result
text. Thinking was disabled; tool choice was auto. The raw emissions and
unmodified upstream results are stored together. Tool-call IDs are generated
locally and are not part of the parity assertion.

The declared string `code` remains `"123"`; the other values retain empty
object/array, integer, boolean and null types. An undeclared function produces
no upstream tool calls. Upstream drops that invalid output; Dart's established
rollback contract retains it as content. The comparison asserts callable-tool
parity rather than claiming identical invalid-content presentation.

These controls also failed against llamadart main
`6c01a69af5bd13b338763f5f63cf16e482aa9fd6`, before PR #529. They establish issue
#530 as a pre-existing Dart parser divergence, not an input-normalization
regression. `qwen_schema_tool_calling_test.dart` exercises the production engine
and compares the output parser with these pinned upstream emissions. The
local-only upstream E2E also compares prompt rendering directly with the pinned
`test-chat-template` executable.
