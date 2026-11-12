# Vendored llama.cpp chat templates

Copied verbatim from `models/templates` in [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
at the ref pinned in `tool/testing/llama_cpp_templates.ref`. Only the templates
that `test/unit/core/template/handlers/firefunction_v2_handler_test.dart`,
`test/unit/core/template/handlers/gemma4_handler_test.dart`,
`test/unit/core/template/template_message_json_parity_test.dart`,
`test/unit/core/template/tool_result_user_turn_render_test.dart`,
`test/unit/core/template/command_r_render_failure_test.dart`,
`test/unit/core/template/enable_thinking_render_parity_test.dart`,
`test/unit/core/template/thinking_template_kwargs_parity_test.dart`,
`test/unit/core/template/forced_open_grammar_test.dart`,
`test/unit/core/template/cohere_control_markers_test.dart`,
`test/e2e/template/specialized_tool_grammar_validation_e2e_test.dart`,
`test/integration/core/engine/forced_open_thought_upstream_test.dart`,
`test/integration/core/engine/closed_thought_upstream_test.dart`,
`test/integration/core/engine/ling3_tool_call_upstream_test.dart`,
`test/integration/core/template/ling3_call_grammar_test.dart` and
`test/integration/core/engine/xml_parallel_tool_calls_upstream_test.dart` read live
here, so those tests run on a clean checkout with no network.

`inclusionai-ling-3.0-flash.jinja` is copied from llama.cpp `v0.9.0`
(`cd959bae9`), the native pin, because the ref above predates it; it is not in
the release tarball the detection test downloads.

`test/integration/core/template/llama_cpp_template_detection_integration_test.dart`
needs the full set and only reads it from `LLAMA_CPP_TEMPLATES_DIR`, defaulting to
`.dart_tool/llama_cpp/models/templates`. Nothing in the test provisions that
directory: CI downloads the release tarball at the pinned ref, and locally
`tool/testing/prepare_llama_cpp_source.sh` clones the source tree there.

To refresh, at a newer llama.cpp tag:

1. Update `tool/testing/llama_cpp_templates.ref`.
2. Re-run `tool/testing/prepare_llama_cpp_source.sh` and copy the files here.
3. Reconcile the expectation map and `unclassifiedTemplates` in the detection test.
