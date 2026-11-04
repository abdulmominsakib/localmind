# LocalMind dependency patch

Baseline: llamadart 0.8.18, published pub.dev archive. Original LICENSE retained.
Companion remains pinned at llamadart_llama_cpp_flutter 0.0.12 (llama.cpp b10276).

Local change: validate sampled vocabulary token IDs before native EOG checks,
token-to-piece conversion, and subsequent decoding. Invalid IDs become Dart
errors instead of being submitted to native embedding lookup. This guard only
applies to sampled text tokens, never multimodal embedding markers.

Regression: test/features/on_device/sampled_token_validation_test.dart.
No native binaries or generated bindings changed. This is defensive containment,
not proof of the reported ggml_compute_forward_get_rows abort's root cause; its
original model/projector and device reproduction remain necessary.

Do not patch the global pub cache. Remove the override only after equivalent upstream behavior is verified.
