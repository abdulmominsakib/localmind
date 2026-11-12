# Qwen3.5 0.8B template fixture

Exact `tokenizer.chat_template` extracted from `ggml-org/Qwen3.5-0.8B-GGUF`, revision `8fea620810c4afa23dd6443f999a48574c1611a3`, file `Qwen3.5-0.8B-Q4_0.gguf`.

- Model SHA256: `57d1997790d1744fba5b40a7317df71ea5e2acee28c47e78f0cce39c0703f8cf`.
- Template UTF-8 SHA256: `273d8e0e683b885071fb17e08d71e5f2a5ddfb5309756181681de4f5a1822d80`.
- Source: https://huggingface.co/ggml-org/Qwen3.5-0.8B-GGUF/tree/8fea620810c4afa23dd6443f999a48574c1611a3

Used by `test/integration/core/template/qwen35_tool_result_test.dart` to reproduce mapping-valued tool-result rejection and verify render-boundary JSON normalization. The template is unchanged; the fix belongs to Dart input serialization.
