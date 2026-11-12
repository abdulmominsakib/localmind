# LocalMind dependency patch

Baseline: llamadart 0.19.7, upstream tag `v0.19.7`
(https://github.com/leehack/llamadart, native llama.cpp runtime `v0.9.0`,
which includes LFM3-series support: upstream llama.cpp landed LFM3 at
b11960 / llamadart-native v0.8.0). Original LICENSE retained.
Companion pinned in lockstep at llamadart_llama_cpp_flutter 0.19.7.

Local change: validate sampled vocabulary token IDs before native EOG checks,
token-to-piece conversion, and subsequent decoding. Invalid IDs become Dart
errors instead of being submitted to native embedding lookup. This guard only
applies to sampled text tokens, never multimodal embedding markers. Ported to
the 0.19.7 `llama_cpp_service.dart` sampling sites: the two decode-loop sample
calls and the two look-ahead EOG probe calls (the probe restructures preserve
the original short-circuit behaviour so no extra sample happens when
`limit == null`).

Regression: test/features/on_device/sampled_token_validation_test.dart.
No native binaries or generated bindings changed. This is defensive containment,
not proof of the reported ggml_compute_forward_get_rows abort's root cause; its
original model/projector and device reproduction remain necessary.

Do not patch the global pub cache. Remove the override only after equivalent upstream behavior is verified.
