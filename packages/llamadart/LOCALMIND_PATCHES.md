# LocalMind dependency patch

Baseline: llamadart 0.20.8, published pub.dev archive (native llama.cpp
`leehack/llamadart-native@v1.0.0-4`). Original LICENSE retained. The
companion is pinned in lockstep at llamadart_llama_cpp_flutter 0.20.8.

Upgraded from 0.8.18 (llama.cpp b10276) so models that need llama.cpp
v0.8.0 or later load, such as LiquidAI LFM3 (`general.architecture = lfm3`,
issue #153).

Not vendored: `test/`, `example/`, `skills/`, `docker/`, `tool/`, `codecov.yml`.

Local change: validate sampled vocabulary token IDs before native EOG checks,
token-to-piece conversion, and subsequent decoding
(`lib/src/backends/llama_cpp/sampled_token_validation.dart`, called from the
two generation loops and the speculative pending-token path in
`llama_cpp_service.dart`). Invalid IDs become Dart errors instead of being
submitted to native embedding lookup. This guard only applies to sampled text
tokens, never multimodal embedding markers.

Regression: test/features/on_device/sampled_token_validation_test.dart.
No native binaries or generated bindings changed. This is defensive containment,
not proof of the reported ggml_compute_forward_get_rows abort's root cause; its
original model/projector and device reproduction remain necessary.

Do not patch the global pub cache. Remove the override only after equivalent upstream behavior is verified.
