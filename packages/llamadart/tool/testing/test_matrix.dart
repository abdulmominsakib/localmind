#!/usr/bin/env dart

import 'dart:io';

/// A test matrix row that contributors can cite in pull request evidence.
class TestMatrixRow {
  const TestMatrixRow({
    required this.id,
    required this.tier,
    required this.mode,
    required this.covers,
    required this.command,
    required this.useWhen,
  });

  /// Stable row identifier used in PR evidence.
  final String id;

  /// One of `essential`, `targeted`, `high-risk`, `platform`, or `release`.
  final String tier;

  /// Free-form descriptor for where the row normally runs.
  final String mode;

  /// Runtime, model, feature, or platform coverage represented by this row.
  final String covers;

  /// Command, workflow, or checklist entry point.
  final String command;

  /// Selection rule for contributors and agents.
  final String useWhen;
}

/// The canonical contributor-facing validation matrix.
const List<TestMatrixRow> testMatrixRows = <TestMatrixRow>[
  TestMatrixRow(
    id: 'genkit-contracts',
    tier: 'targeted',
    mode: 'CI + local; model-free',
    covers:
        'independent published/local-core resolution, minimum Dart and lower bounds, docs snippets and browser guards',
    command:
        'CI job genkit in .github/workflows/ci.yml; package commands in packages/genkit_llamadart/CONTRIBUTING.md',
    useWhen:
        'Genkit adapter, core API or integration quickstart changes. Browser guards do not qualify a full Genkit Web deployment.',
  ),
  TestMatrixRow(
    id: 'genkit-native-cpu',
    tier: 'platform',
    mode: 'local + tiny-model CI; CPU',
    covers:
        'adapter native capability guards, embeddings, cancellation, disposal and owner isolation',
    command:
        'From packages/genkit_llamadart: supply LLAMADART_INTEGRATION_MODEL_PATH and LLAMADART_INTEGRATION_EMBED_MODEL_PATH, then dart test -t real-model -j 1; optional-family fixtures are documented in CONTRIBUTING.md',
    useWhen:
        'Adapter runtime or core integration changes; reuse local fixtures and record skipped families explicitly.',
  ),
  TestMatrixRow(
    id: 'genkit-release',
    tier: 'release',
    mode: 'CI + local; no publication',
    covers:
        'core/adapter release isolation, two-file prep scope, tag/version guards, HTTP failure handling and standalone staging',
    command:
        'dart test -p vm test/unit/tooling/genkit_release_routing_test.dart test/unit/tooling/genkit_package_staging_test.dart',
    useWhen:
        'Independent adapter release routing or archives change; owner handoff checklist: website/docs/maintainers/genkit-package.md.',
  ),
  TestMatrixRow(
    id: 'model-store-contracts',
    tier: 'targeted',
    mode: 'CI + local; model-free',
    covers:
        'shared model store references, deletes, prune, metadata redaction, cross-process store lock and the browser refusal against checkout core',
    command:
        'CI job model-store in .github/workflows/ci.yml; from packages/llamadart_model_store: TMPDIR="\$(mktemp -d)" flutter test, then dart test -p chrome test/model_store_web_test.dart',
    useWhen:
        'llamadart_model_store, its guide, or core download manager changes. Foreground only: no device backgrounding or sleep evidence.',
  ),
  TestMatrixRow(
    id: 'ci-selection',
    tier: 'targeted',
    mode: 'CI + local; no models',
    covers:
        'dependency-aware job/target selection, complete Git inventory and truthful aggregation',
    command: 'dart run tool/testing/run_local_e2e.dart --scenario ci-selection',
    useWhen:
        'CI workflow or impact selection changes; see doc/ci_selection.md.',
  ),
  TestMatrixRow(
    id: 'android-perfetto-capability',
    tier: 'platform',
    mode: 'opt-in; model-free Android build and bounded physical-device probe',
    covers:
        'registered render-stage discovery, fresh trace transport and CPU/idle '
        'controls; never model GPU placement',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'android-perfetto-capability; bounded cloud procedure in '
        'doc/android_perfetto_capability.md',
    useWhen:
        'Android trace capability or evidence validation changes. Real trace '
        'processor regression and exact APK identity are required for cloud qualification.',
  ),
  TestMatrixRow(
    id: 'validation-harness',
    tier: 'targeted',
    mode: 'CI + local; model-free',
    covers:
        'private runner, planned model/backend coverage, result integrity, provider lifecycle, artifact and NPU input checks',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario validation-harness',
    useWhen:
        'Validation harness, report, bundle or cloud orchestration changes.',
  ),
  TestMatrixRow(
    id: 'validation-model-core',
    tier: 'platform',
    mode: 'opt-in; owned hardware or explicit remote run',
    covers:
        'public package load, tokenizer, inference, cancellation, reload, limits and TPS',
    command:
        'dart run tool/testing/validation.dart local --profile tiny-gguf-cpu',
    useWhen:
        'Real-model qualification; see doc/cross_platform_validation.md for bundles and cloud lifecycle.',
  ),
  TestMatrixRow(
    id: 'validation-speech',
    tier: 'platform',
    mode: 'opt-in; local model-backed',
    covers:
        'Locked Qwen3-ASR/Qwen3-TTS and dedicated LiteRT CPU ASR, cancellation, '
        'reload, typed guards, WER, audio timing, Qwen3-ASR edge fixtures, and '
        'cancel-latency and peak-memory bounds',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario validation-speech-stt; '
        'dart run tool/testing/run_local_e2e.dart --scenario validation-speech-tts; '
        'dart run tool/testing/run_local_e2e.dart --scenario validation-voice-round-trip',
    useWhen:
        'Speech model/backend validation; diagnostic results do not qualify GPU placement or listening quality.',
  ),
  TestMatrixRow(
    id: 'gguf-stop-sequences',
    tier: 'targeted',
    mode: 'local-only',
    covers: 'public GGUF caller stop suppression, batching, and recovery',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'gguf-stop-sequences --model-path <chat.gguf> --backend cpu',
    useWhen:
        'Native GGUF streaming or stop-sequence changes. Use a compliant '
        'Gemma 4 or Qwen3.5 chat model; pair with the deterministic ordinary/'
        'speculative test/integration/stop_sequences_test.dart suite.',
  ),
  TestMatrixRow(
    id: 'native-prompt-cancel',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'native GGUF cancel during a ~1,600-token prompt: cancelGeneration and '
        'generate/create subscription-cancel latency, no events after a '
        'subscription cancel, and a generation right after the cancel',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'native-prompt-cancel --model-path <chat.gguf> --backend cpu',
    useWhen:
        'Native llama.cpp prompt evaluation, generation cancel or engine '
        'stream-forwarding changes. Repeat with --backend metal on macOS.',
  ),
  TestMatrixRow(
    id: 'native-exit-teardown',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Linux cooperative load/generation/idle shutdown awaits disposal and '
        'the model-owning isolate exit before C exit; macOS Metal process '
        'ends with llama.cpp objects alive: C exit '
        'through FFI with a model idle, generating or loading and optionally '
        'with a projector or a decision head, an unhandled error while '
        'generating or loading, an isolate killed inside a load, and an '
        'isolate that ends without freeing; not a Flutter quit and not an '
        'exit during an unguarded call',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'native-exit-teardown --model-path <chat.gguf>',
    useWhen:
        'llama.cpp native pin, exit-teardown call sites, object creation or '
        'free paths, or isolate shutdown changes. Linux uses the requested '
        'backend; macOS needs a GPU that loads the model.',
  ),
  TestMatrixRow(
    id: 'static-format-analyze',
    tier: 'essential',
    mode: 'CI + local',
    covers: 'format, analyzer, web/native import boundaries',
    command:
        'dart run tool/prepare_workspace.dart && '
        'dart format --output=none --set-exit-if-changed . && dart analyze && '
        'dart run tool/testing/check_platform_boundaries.dart',
    useWhen: 'Every non-trivial PR.',
  ),
  TestMatrixRow(
    id: 'root-vm',
    tier: 'essential',
    mode: 'CI + local',
    covers: 'native-safe unit/integration coverage on the Dart VM',
    command: 'dart test -p vm -j 1 --exclude-tags local-only',
    useWhen: 'Every code PR unless the change is docs-only.',
  ),
  TestMatrixRow(
    id: 'root-chrome',
    tier: 'essential',
    mode: 'CI + local',
    covers: 'browser-compatible unit/integration coverage',
    command: 'dart test -p chrome --exclude-tags local-only',
    useWhen: 'Every shared, web, template, or public API change.',
  ),
  TestMatrixRow(
    id: 'coverage-lib',
    tier: 'essential',
    mode: 'CI + local',
    covers:
        '>=70% line coverage for maintainable lib/ code; CI enforces it '
        'after merge only',
    command:
        'dart test -p vm -j 1 --exclude-tags local-only --coverage=coverage; '
        'dart run tool/testing/format_lcov.dart --lcov '
        '--in=coverage/test --out=coverage/lcov.info --report-on=lib '
        '--check-ignore; '
        'dart run tool/testing/check_lcov_threshold.dart coverage/lcov.info 70',
    useWhen:
        'Before merge when lib/ behavior changes or coverage is in doubt; PR '
        'CI does not check it.',
  ),
  TestMatrixRow(
    id: 'high-risk-exact-head-independent-qa',
    tier: 'high-risk',
    mode: 'pre-mark-ready review',
    covers:
        'independent blocking-only review of exact head/current base, live '
        'threads, production call sites, adversarial negatives, and tests '
        'sensitive to production-branch deletion, bypass, or miswiring',
    command:
        'Complete the PR high-risk regression review block from a task '
        'independent of implementation; record exact head/base, affected-family '
        'evidence or precise N/A, zero known PR-caused P1 regressions, and zero '
        'unresolved threads.',
    useWhen:
        'Parser/grammar/streaming, backend/runtime routing, public capability '
        'probe, artifact consumer, release automation, or regression-policy '
        'changes. Required before mark-ready, not after merge.',
  ),
  TestMatrixRow(
    id: 'release-metadata-verification',
    tier: 'high-risk',
    mode: 'local exact-head release evidence',
    covers:
        'bounded core-patch metadata diff and unchanged release regression suite',
    command:
        'dart run tool/testing/verify_release_docs_versions.dart --release-prep && '
        'dart test -p vm -j 1 test/unit/tooling/verify_release_docs_companion_pins_test.dart',
    useWhen:
        'Only the evaluator-verified core-patch metadata release route; '
        'never a substitute for relevant causal tests on production or policy changes.',
  ),
  TestMatrixRow(
    id: 'structured-output-adversarial',
    tier: 'high-risk',
    mode: 'CI + local + primary upstream fixtures',
    covers:
        'applicable v2 impact axes: input rendering/history, compiled grammar acceptance/rejection, schema-directed scalar and '
        'container types including empty values, partial/final streaming and '
        'rollback, auto/required/none tool choice with thinking prefixes, and '
        'pinned/current upstream template/parser parity',
    command:
        'Select applicable tests using doc/high_risk_pre_merge_readiness.md; '
        'for mixed changes run ./tool/testing/run_template_parity_suites.sh '
        'plus issue-specific VM and Chrome production-path tests.',
    useWhen:
        'Chat-template parser, grammar, streaming, thinking, or tool-call '
        'changes. Exact affected-family evidence is preferred; when weights '
        'are unavailable, name each family and use primary upstream emissions '
        'plus durable fixtures. An unrelated model is pipeline-only.',
  ),
  TestMatrixRow(
    id: 'docs-site',
    tier: 'targeted',
    mode: 'CI + local',
    covers: 'website build, docs metadata, generated docs routes',
    command: './tool/docs/build_site.sh; ./tool/docs/validate_links.sh',
    useWhen: 'Docs, README, website, migration, or changelog changes.',
  ),
  TestMatrixRow(
    id: 'release-doc-version-consistency',
    tier: 'targeted',
    mode: 'CI + local',
    covers:
        'current README/website install snippets, companion README versions, '
        'and each companion SwiftPM pin against its own released CHANGELOG '
        'section',
    command:
        'dart run tool/testing/verify_release_docs_versions.dart '
        '(add --release-prep during release prep)',
    useWhen:
        'Release prep, companion package version bumps, or current install docs.',
  ),
  TestMatrixRow(
    id: 'webgpu-bridge-tag-consistency',
    tier: 'targeted',
    mode: 'CI + local',
    covers:
        'every site pinning the WebGPU bridge asset tag matches the fetch '
        'script default, and the bridge assets\' llama.cpp build matches the '
        'native pin unless a divergence is recorded',
    command:
        'dart run tool/testing/check_webgpu_bridge_tag.dart '
        '(add --verify-manifest to check the published release, tag commit '
        'and manifest)',
    useWhen:
        'Bridge asset tag bumps, native llama.cpp pin bumps, or edits to the '
        'docs that pin either.',
  ),
  TestMatrixRow(
    id: 'native-release-digests',
    tier: 'targeted',
    mode: 'CI + local (network)',
    covers:
        'every llama.cpp, stable_diffusion and LiteRT-LM archive digest pin '
        'matches what its pinned release publishes',
    command:
        'CI workflow "Native Release Digests", or dart run '
        'tool/testing/check_native_release_digests.dart',
    useWhen: 'Any edit to lib/src/hook/native_release_pins.dart.',
  ),
  TestMatrixRow(
    id: 'native-sync-python-suites',
    tier: 'targeted',
    mode: 'CI + local',
    covers:
        'native release pin policy, header archive, native header/binding '
        'sync and stable-diffusion binding sync Python suites that CI runs '
        'only in Analyze & Lint',
    command:
        'python3 tool/native/test_sync_native_release_pins.py && '
        'python3 tool/native/test_native_header_archive.py && '
        'python3 tool/native/test_sync_native_headers_and_bindings.py && '
        'python3 tool/native/test_sync_stable_diffusion_bindings.py '
        '(needs Python 3.10+; macOS system python3 3.9 fails transport '
        'tests with KeyError \'file\')',
    useWhen:
        'Any edit under tool/native/, lib/src/hook/native_release_pins.dart, '
        '.github/workflows/sync_native_bindings.yml, an Apple companion '
        'Package.swift, or a runtime pin constant (pubspec.yaml, LiteRT-LM '
        'runtime or prepare script).',
  ),
  TestMatrixRow(
    id: 'examples-tests',
    tier: 'targeted',
    mode: 'CI + local',
    covers: 'example package unit tests and Flutter app regressions',
    command:
        'CI jobs "Example Package Tests" and "Web Chat Contract", or run '
        'tests in each touched example package, for example '
        '(cd example/chat_app && flutter test test test_vm).',
    useWhen: 'Any example app, CLI, or server package change.',
  ),
  TestMatrixRow(
    id: 'native-hook-bundles',
    tier: 'targeted',
    mode: 'CI + local',
    covers: 'native-assets hook, bundle selection, runtime companions',
    command: 'dart test -p vm -j 1 test/unit/hook --exclude-tags local-only',
    useWhen:
        'hook/build.dart, native bundle config, runtime selection, or pins.',
  ),
  TestMatrixRow(
    id: 'native-prompt-reuse-parity',
    tier: 'targeted',
    mode: 'CI + local',
    covers: 'real GGUF native prompt reuse parity with deterministic prompts',
    command:
        'CI job "Native Prompt Reuse Parity", or dart run '
        'tool/testing/native_prompt_reuse_parity.dart --model <model.gguf> '
        '--prompt-file tool/testing/prompts/native_prompt_reuse_ci_prompts.txt '
        '--max-prompts 4 --runs 1 --max-tokens 64 --gpu-layers 0 '
        '--fail-on-mismatch',
    useWhen:
        'Native prompt reuse, context reuse, generation stability changes.',
  ),
  TestMatrixRow(
    id: 'native-default-consumer-aot',
    tier: 'platform',
    mode: 'manual local-only macOS and Windows',
    covers:
        'Ordinary default-hook consumer inference, actual provider identity and distributed AOT with exact core/native/model provenance',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario native-default-consumer-aot',
    useWhen:
        'Native pin or consumer/AOT qualification; explicit local/manual execution only. Expected tag must match source; native2 is pipeline-only, native3 needs independent acceptance.',
  ),
  TestMatrixRow(
    id: 'windows-native-override-registry',
    tier: 'platform',
    mode: 'manual local-only Windows x64 CPU',
    covers:
        '18 fresh H/E/P and alias model/context/unload cases, passive registry/IAT identity, maintained declaration mutation, whole-bundle AOT distribution',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario windows-native-override-registry',
    useWhen:
        'Windows native override or registry changes; pinned SDK/native/model inputs, complete immutable evidence archive and independent review required. GPU remains unqualified.',
  ),
  TestMatrixRow(
    id: 'native-inference-benchmark',
    tier: 'targeted',
    mode: 'local-only',
    covers: 'real GGUF native generate/create TTFT and throughput metrics',
    command:
        'dart run tool/testing/native_inference_benchmark.dart '
        '--model <model.gguf> --gpu-layers 0 --mode all --runs 3 '
        '--max-tokens 128',
    useWhen:
        'Generation latency, streaming, batching, prompt reuse, or performance changes.',
  ),
  TestMatrixRow(
    id: 'web-multimodal-embeddings',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Direct/worker Web text/image/audio/mixed vectors against local native references, normalization, order and adjacent text',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario web-multimodal-embeddings',
    useWhen:
        'Web embedding bridge changes; requires local assets v0.1.64+, EmbeddingGemma-2/projector and reference vectors per doc/multimodal_embeddings_web.md. Numerically unqualified until run.',
  ),
  TestMatrixRow(
    id: 'native-multimodal-embeddings',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'EmbeddingGemma-2 text/image/audio/interleaved vectors versus pinned upstream, raw/normalized outputs, adjacent-text parity, batch order, capacity, cancellation and reuse on CPU/Metal',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario native-multimodal-embeddings',
    useWhen:
        'Native multimodal embedding or mixed-batch changes; set local model/reference paths per doc/multimodal_embeddings_native.md. No downloads.',
  ),
  TestMatrixRow(
    id: 'native-reranking',
    tier: 'targeted',
    mode: 'local-only',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario native-reranking',
    covers:
        'Qwen3 named-template/multiclass and Jina fallback/single-score parity against pinned upstream; batching, overflow, cancellation and lifecycle',
    useWhen:
        'Native reranker APIs, classifier output or pair framing changes. Requires local weights and exact oracle paths per doc/native_reranking.md; no downloads.',
  ),
  TestMatrixRow(
    id: 'text-embedding-retrieval',
    tier: 'targeted',
    mode: 'local-only; pinned official EG2 weights and reference',
    covers:
        'text task/document/prepared helpers, title formatting, Matryoshka dimensions and real production retrieval against official float32 CPU vectors',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario text-embedding-retrieval',
    useWhen:
        'Embedding text profiles, task formatting or output dimensions change. Follow doc/embedding_text_helpers.md; no GPU, quantized or media qualification.',
  ),
  TestMatrixRow(
    id: 'native-embedding-benchmark',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real GGUF sequential embedding calls versus embedBatch throughput, '
        'including n_seq_max parallelism',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'native-embedding-benchmark --model-path <model.gguf> '
        '--benchmark-runs 3 --benchmark-warmups 1 --benchmark-gpu-layers 0',
    useWhen:
        'Embedding API, embedBatch, pooling, or embedding throughput changes. '
        'Not run in CI.',
  ),
  TestMatrixRow(
    id: 'native-embedding-sweep',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real GGUF embedding speedup across a max-seq sweep, emitted as a CSV '
        'report for plotting',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'native-embedding-sweep --model-path <model.gguf> --benchmark-runs 3 '
        '--benchmark-warmups 1 --benchmark-gpu-layers 0',
    useWhen:
        'Choosing or defending a default maxParallelSequences, or when an '
        'embedding batching change needs a speedup curve rather than a single '
        'data point. Writes build/embedding_speedup_sweep.csv. Not run in CI.',
  ),
  TestMatrixRow(
    id: 'llama-cpp-speculative-benchmark',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real GGUF llama.cpp speculative decoding baseline, n-gram, external '
        'draft-model including DSpark, and cache throughput/acceptance metrics',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'llama-cpp-speculative-benchmark --model-path <model.gguf> '
        '--draft-model-path <draft.gguf> --backend cpu '
        '--speculative-cases baseline,draft-dspark,ngram-simple,'
        'ngram-map-k,ngram-map-k4v,ngram-mod,ngram-cache,mixed-ngram '
        '--benchmark-gpu-layers 0 --benchmark-max-tokens 128 '
        '--benchmark-runs 3 --draft-token-max 1,2 '
        '--ngram-size-m 8,16 --benchmark-warmups 1 '
        '--ngram-cache-build-static-path '
        '/tmp/llamadart-ngram-cache.bin',
    useWhen:
        'llama.cpp speculative decoding strategy, wrapper, rollback, or '
        'performance changes. External draft-model strategies require '
        '--draft-model-path in the local E2E scenario; bundled MTP omits it '
        'and enables ModelParams.loadMtp; ngram-cache can use '
        'an existing cache path or --ngram-cache-build-static-path.',
  ),
  TestMatrixRow(
    id: 'gemma4-mtp-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Gemma 4 bundled MTP speculative decoding correctness against a real '
        'GGUF model on a Metal-preferred native backend',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario gemma4-mtp-smoke '
        '--model-path <gemma4.gguf> [--draft-model-path <draft.gguf>] '
        '--benchmark-max-tokens 32 --draft-token-max 1',
    useWhen:
        'Gemma 4 MTP work, or a quick correctness check that bundled MTP still '
        'generates coherent output before running the fuller '
        'llama-cpp-mtp-benchmark row. Not run in CI.',
  ),
  TestMatrixRow(
    id: 'gguf-chat-features-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real GGUF llama.cpp chat, thinking-budget/suppression, streaming '
        'tool calls, and optional image input',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'gguf-chat-features-smoke --model-path <model.gguf> --backend auto '
        '--mmproj-path <mmproj.gguf> --image-path <image>',
    useWhen:
        'Chat rendering, parser, tool calling, thinking, or llama.cpp image '
        'input work.',
  ),
  TestMatrixRow(
    id: 'tool-result-image-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'native llama.cpp image tool results on a Hermes-format vision model: '
        'tool-turn photos read back by the model, and a handler '
        'LlamaToolOutput image reaching the next sendWithTools round',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'tool-result-image-smoke --model-path <qwen3-vl.gguf> '
        '--mmproj-path <mmproj.gguf> --backend cpu',
    useWhen:
        'LlamaToolResultContent.content, LlamaToolOutput or tool-result '
        'media routing work. Use Qwen3-VL; for a closest-family model set '
        'LLAMADART_TOOL_MEDIA_CHAT_TEMPLATE to '
        'test/fixtures/templates/Qwen3-VL-2B-Instruct.jinja.',
  ),
  TestMatrixRow(
    id: 'gguf-audio-chat-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'experimental native llama.cpp byte-backed audio question answering '
        'with an exact expected answer and path-free fixture identity',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'gguf-audio-chat-smoke --model-path <model.gguf> --backend auto '
        '--mmproj-path <mmproj.gguf> --audio-path <question.wav> '
        '--expect <expected-answer>',
    useWhen:
        'llama.cpp audio input or Ask-with-voice work. This engine-level row '
        'does not establish microphone UI or mobile-platform validation.',
  ),
  TestMatrixRow(
    id: 'speech-to-text-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real native Qwen3-ASR file/encoded-bytes parity, bounded prompt tokens, '
        'exact known-fixture text, malformed-byte rejection, cancellation and recovery',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'speech-to-text-smoke --model-path <model.gguf> '
        '--mmproj-path <mmproj.gguf> '
        '--audio-path <fixture.wav|.mp3|.flac> '
        '--expect "<expected transcript>"',
    useWhen:
        'Speech API, native audio routing, transcript normalization, or chat-app transcription changes.',
  ),
  TestMatrixRow(
    id: 'litert-lm-asr-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'public dedicated LiteRT-LM SpeechToTextEngine discovery, worker-isolated '
        'bounded PCM streaming, partial events, finalization, and expected '
        'real-model transcript',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'litert-lm-asr-smoke --model-path <model.tflite> '
        '--tokenizer-path <tokenizer.json> --audio-path <fixture.wav> '
        '--model-preset moonshine-tiny --expect "<expected transcript>"',
    useWhen:
        'LiteRT-LM ASR bridge, public speech API, native pins, or streaming '
        'speech work. This CPU-only engine row does not establish microphone UI.',
  ),
  TestMatrixRow(
    id: 'litert-lm-asr-preservation',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'hash-bound public Whisper Tiny CPU transcript/partials, empty silence, '
        'stream/task cancellation, same-engine reuse and fresh reload',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'litert-lm-asr-preservation --model-path <whisper-tiny.tflite> '
        '--tokenizer-path <tokenizer.json> --audio-path <jfk.wav> --backend cpu',
    useWhen:
        'Dedicated LiteRT-LM ASR preservation after runtime or speech changes. '
        'CPU subset only; no GPU, microphone, latency or device qualification.',
  ),
  TestMatrixRow(
    id: 'text-to-speech-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real native Qwen3-TTS capability discovery, progress, complete 24 kHz '
        'PCM output, cancellation boundary, and playable WAV encoding',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'text-to-speech-smoke --model-path <model.gguf> '
        '--mmproj-path <mmproj.gguf>',
    useWhen:
        'Text-to-speech API, native audio generation, Qwen3-TTS projector, or '
        'chat-app synthesis changes.',
  ),
  TestMatrixRow(
    id: 'text-to-speech-models-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real native LFM3-Audio, Soprano, Chatterbox Turbo/Multilingual and '
        'Pocket TTS capabilities, listed voices, default-voice identity, '
        'speaker cloning, Multilingual language and guidance-sequence '
        'refusal, voice/language/speaker-reference refusals, seed repeat '
        'after a cancel, and a Qwen3-ASR round trip of the synthesized speech',
    command:
        'LLAMADART_TTS_LFM3_MODEL_PATH=<model.gguf> '
        'LLAMADART_TTS_LFM3_MMPROJ_PATH=<mmproj.gguf> '
        'LLAMADART_STT_MODEL_PATH=<asr.gguf> '
        'LLAMADART_STT_MMPROJ_PATH=<asr-mmproj.gguf> '
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'text-to-speech-models-smoke',
    useWhen:
        'Text-to-speech model-type opt-in, voices, any adapter other than '
        'Qwen3-TTS, or llama.cpp pin changes. Set the other models\' '
        'variables (doc/testing_matrix.md) too.',
  ),
  TestMatrixRow(
    id: 'image-generation-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real opt-in stable_diffusion runtime bundled by the example hook, '
        'a runtime probe that leaves the calling isolate responsive, a first '
        'image after warmUp about as fast as a warm one, '
        'SDXS load and 256x256 one-step generation with labelled progress, '
        'same-seed determinism; disabled/default/one-entry conditioning-cache '
        'pixel parity, native hits, prompt changes, eviction, cancel/reuse '
        'and dispose/reload on CPU and the automatic device for SDXS and '
        'SD-Turbo; pre-start and mid-run cancellation, the '
        'one-generation guard, dispose during generation, and PNG output; '
        'the runtime\'s reason in the error of a truncated file, a missing '
        'file and a file in the wrong role, without paths; runtime messages '
        'through the log handler by level and none at the default levels; on '
        'macOS the runtime\'s GPU memory total against the Metal working set '
        'the memory check reads; '
        'SD-Turbo with TAESD, and its full VAE decoded untiled and with '
        'VAE tiling on the default device and the CPU, when '
        'LLAMADART_SD_TURBO_MODEL is set, '
        'SDXL-Lightning warm-up and 1024x1024 generation (with TAESDXL when '
        'LLAMADART_TAESDXL is set) when LLAMADART_SDXL_LIGHTNING_MODEL is '
        'set, and the SDXS from its pinned Hugging Face file through the '
        'model cache when LLAMADART_IMAGE_HF_CACHE is set, and header-based role '
        'detection of a split model when LLAMADART_IMAGE_SPLIT_MODEL lists '
        'its files',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'image-generation-smoke --model-path <sdxs.gguf>',
    useWhen:
        'Image generation API, stable_diffusion runtime pins, bindings, '
        'probe or hook changes.',
  ),
  TestMatrixRow(
    id: 'image-container-formats',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Complete byte-equivalent SD-Turbo F16 GGUF/Safetensors and restricted '
        'PyTorch ZIP/nested ZIP/legacy containers, '
        'automatic and explicit public checkpoint roles, per-input hashes, '
        'CPU generation/disposal and exact independent direct-C RGB parity; '
        'not arbitrary checkpoint, architecture, PyTorch object or GPU support',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'image-container-formats --model-path <manifest.json>',
    useWhen:
        'Image checkpoint format classification, explicit role transport '
        'or restricted native container reader changes.',
  ),
  TestMatrixRow(
    id: 'image-original-containers',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Original SD24 Safetensors/flat/nested CPU4 external-TAESD native/public '
        'RGB parity with cache4 and diffusion flash; PR41 diagnostic only',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'image-original-containers --model-path <admitted-plan.json>',
    useWhen:
        'After independent source/artifact/plan admission for the original '
        'ZIP load-time investigation; never an ordinary CI/model download gate.',
  ),
  TestMatrixRow(
    id: 'image-seamless-textures',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'SDXS embedded tiny decoder 512-square circular X/Y quality on CPU '
        'and actual Metal, exact native settings parity when references are '
        'provided, repeat-tile PNGs, off-after-on and cancellation/reuse; '
        'no generic VAE-tiling or other-family qualification',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'image-seamless-textures --model-path <sdxs.gguf>',
    useWhen:
        'SeamlessImageGenerationRequest, circular ABI wiring or decoder routing changes.',
  ),
  TestMatrixRow(
    id: 'image-local-checkpoint-sets',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Bounded complete SD-Turbo F16/F32 Safetensors index/directory CPU recipe; immutable per-file identities, owned snapshots, aggregate bytes, source-removal lifetime, cache reuse, cancellation cleanup and native-reference parity; no Diffusers or editing/tiling/seamless qualification',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario image-local-checkpoint-sets --model-path <complete-sd-turbo.safetensors>',
    useWhen:
        'Local image-set resolution, cache/snapshot lifetime, model-set factory, aggregate accounting or checkpoint-set native mapping changes.',
  ),
  TestMatrixRow(
    id: 'image-editing',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'SD-Turbo embedded full-VAE macOS CPU RGB/mask ownership and polarity, strength, direct-C reference parity, cancellation/reuse, ordinary defaults reset and reload; other recipes unmeasured or refused',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario image-editing --model-path <sd-turbo.gguf>',
    useWhen:
        'ImageEditingRequest, image-editing capability, worker transport or init/mask/strength native mapping changes.',
  ),
  TestMatrixRow(
    id: 'image-controlnet',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'SD 1.x checkpoint plus original-layout SD 1.x ControlNet on macOS CPU: control image and strength effects, strength-0 and ordinary reset equivalence, direct-C reference parity, cancellation/reuse and reload; other families, layouts and devices refused',
    command:
        'LLAMADART_SD15_CONTROLNET=<controlnet.safetensors> dart run tool/testing/run_local_e2e.dart --scenario image-controlnet --model-path <sd15.safetensors>',
    useWhen:
        'ControlNetImageGenerationRequest, ImageModelRole.controlNet admission, supportsControlNet, worker ControlNet probe/failure detection or control_net_path/control_image/control_strength native mapping changes.',
  ),
  TestMatrixRow(
    id: 'image-hires-fix',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Two-pass latent hires fix with an SD 1.x or SD 2.x full-VAE checkpoint on macOS CPU or Metal: final size, direct-C reference parity, one-pass reset, composition kept, second-pass cancellation/reuse and reload; other families, decoders, hosts and devices refused',
    command:
        'LLAMADART_HIRES_RECIPE=<sd15|turbo> LLAMADART_HIRES_DEVICE=<cpu|gpu> dart run tool/testing/run_local_e2e.dart --scenario image-hires-fix --model-path <checkpoint>',
    useWhen:
        'HiresFixImageGenerationRequest, ImageHiresFix limits, supportsHiresFix, two-pass progress or sd_hires_params_t native mapping changes.',
  ),
  TestMatrixRow(
    id: 'image-reference-editing',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'FLUX.1 Kontext [dev] reference image editing on macOS Metal: a visible requested edit with preserved content, a reference effect against ordinary text-to-image, direct-C reference parity, cancellation/reuse, ordinary reset and reload; other families, components, hosts, devices and reference counts refused',
    command:
        'LLAMADART_REFERENCE_EDIT_VAE=<ae> LLAMADART_REFERENCE_EDIT_CLIP_L=<clip_l> LLAMADART_REFERENCE_EDIT_T5XXL=<t5xxl> dart run tool/testing/run_local_e2e.dart --scenario image-reference-editing --model-path <flux1-kontext-dev>',
    useWhen:
        'ReferenceImageEditingRequest, ImageReferenceEditingRecipe, supportsReferenceImageEditing, FLUX.1 Kontext header admission or ref_images/ref_image_args native mapping changes.',
  ),
  TestMatrixRow(
    id: 'image-exit-teardown',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Linux cooperative load/generation/idle and both-runtime shutdown '
        'awaits disposal and isolate exit before C exit; macOS Metal '
        'process ends with an image model alive: C exit through '
        'FFI with the model idle, generating, loading, disposed and '
        'optionally with a llama.cpp model loaded too, an unhandled error '
        'while generating or loading, and an isolate killed inside a load; '
        'the idle, generating and loading exits again with the runtime log '
        'forwarded at debug level; nothing on stderr at the default log '
        'levels; the exports the required and the optional sd_dart_ calls '
        'resolve to; and the progress events of batches of two and three '
        'images; not a Flutter quit',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'image-exit-teardown --model-path <sdxs.gguf>',
    useWhen:
        'stable_diffusion runtime pin, image worker call sites, progress '
        'polling, or isolate shutdown changes. Linux uses the requested '
        'backend; macOS needs a GPU that loads the model.',
  ),
  TestMatrixRow(
    id: 'decision-model-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real native ModernBERT GGUF plus Laya decision head: exact fixture '
        'token ids and markers from the engine tokenizer, raw marker and '
        'action logits and DecisionEngine answers within the tolerances of '
        'doc/testing_matrix.md against the Laya 0.3.5 reference, CPU head '
        'placement without offloaded layers, and a clean exit after engine '
        'dispose with a head loaded',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'decision-model-smoke --model-path <laya.gguf> '
        '--head-path <laya-head.safetensors> '
        '[--config-path <rl_agent_config.json>] [--backend metal]',
    useWhen:
        'Decision engine, decision sequence or decoder, native decision head, '
        'safetensors reader, or llama.cpp encoder changes.',
  ),
  TestMatrixRow(
    id: 'decision-model-web-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'LlamaEngine(LlamaBackend()) through WebAutoBackend and '
        'WebGpuLlamaBackend in the pinned bridge worker, in Chrome with '
        'WebGPU: the Laya Q8_0 encoder and head from Hugging Face, exact '
        'fixture token ids and markers, raw logits and DecisionEngine answers '
        'within the decision-model-smoke tolerances, and model and head on '
        'WebGPU',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'decision-model-web-smoke',
    useWhen:
        'Web decision head (webgpu_decision.dart), WebAutoBackend decision '
        'routing, decision engine, or WebGPU bridge pin changes.',
  ),
  TestMatrixRow(
    id: 'web-lazy-grammar',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'lazy word/pattern/pattern-full/token activation after visible text, '
        'custom roots, grammar prompt penalties and typed rejection/reuse through '
        'pinned assets in direct and worker CPU Wasm runtimes; prompt penalties '
        'cover wasm32 and memory64; no tool accuracy or GPU claim',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario web-lazy-grammar',
    useWhen:
        'Web grammar capability, trigger transport or bridge pin changes. '
        'Stage build/web_lazy_grammar/config.json as doc/testing_matrix.md describes.',
  ),
  TestMatrixRow(
    id: 'web-speech-task-cancel',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real Qwen3-ASR and Qwen3-TTS task cancellation through the pinned '
        'bridge direct and worker paths: another request remains intact, '
        'cancelled tasks emit no final event, and the engine remains reusable; '
        'CPU placement by default; TTS batch 512/micro-batch 256 with bounded '
        'one/eight-frame controls; WebGPU qualification only with positive '
        'gpuLayers and verified WebGPU execution',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'web-speech-task-cancel',
    useWhen:
        'Speech task cancellation, WebGPU request ownership, direct/worker '
        'dispatch, or bridge pin changes. Stage the real input config in '
        'build/web_speech_task_cancel/config.json; see doc/testing_matrix.md.',
  ),
  TestMatrixRow(
    id: 'web-text-to-speech-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'published WebGPU bridge, public typed TTS API, Qwen3-TTS catalog, '
        'optional byte-backed speaker reference, progress, complete 24 kHz '
        'PCM, chat-app autoplay, and downloaded WAV validation',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-web-text-to-speech-smoke '
        '[--audio-path <speaker-reference.wav>]',
    useWhen:
        'Web bridge pins, Qwen3-TTS Web, typed speech synthesis, browser '
        'playback, or WAV export changes.',
  ),
  TestMatrixRow(
    id: 'chat-app-microphone-transcription-smoke',
    tier: 'targeted',
    mode: 'manual/device',
    covers:
        'microphone permission, nonempty finalized WAV capture, whole-file '
        'transcription, discard/background cancellation, and temporary-file '
        'cleanup',
    command:
        'Run example/chat_app on a microphone-equipped native device with the '
        'Qwen3-ASR model/projector, record known speech, use Stop & transcribe, '
        'then repeat with Discard and an app-background transition. Record '
        'platform/device, permission result, transcript, and cleanup evidence.',
    useWhen:
        'Chat-app microphone capture, recording permissions, lifecycle, or '
        'temporary-audio handling changes.',
  ),
  TestMatrixRow(
    id: 'physical-ios-speech-e2e',
    tier: 'targeted',
    mode: 'manual/device',
    covers:
        'physical iOS real microphone WAV capture, llama.cpp Qwen3-ASR with '
        'cancellation and reload, LiteRT-LM streaming ASR with partials and '
        'cancellation, llama.cpp Qwen3-TTS with 24 kHz WAV export, non-audible '
        'ASR round-trip intelligibility, and LiteRT-LM TTS unsupported '
        'classification across immutable local artifacts with no audio playback',
    command:
        r'cd example/chat_app && flutter drive --no-pub '
        r'--publish-port --no-start-paused '
        r'--device-vmservice-port="$IOS_SPEECH_DEVICE_VM_PORT" '
        r'--host-vmservice-port="$IOS_SPEECH_HOST_VM_PORT" '
        r'--driver=test_driver/integration_test.dart '
        r'--target=integration_test/physical_ios_speech_e2e_test.dart '
        r'--timeout=21600 -d "$PHYSICAL_IOS_DEVICE_ID" '
        r'--dart-define=IOS_SPEECH_QWEN3_ASR_MODEL_PATH="$IOS_SPEECH_QWEN3_ASR_MODEL_PATH" '
        r'--dart-define=IOS_SPEECH_QWEN3_ASR_MODEL_SHA256="$IOS_SPEECH_QWEN3_ASR_MODEL_SHA256" '
        r'--dart-define=IOS_SPEECH_QWEN3_ASR_MMPROJ_PATH="$IOS_SPEECH_QWEN3_ASR_MMPROJ_PATH" '
        r'--dart-define=IOS_SPEECH_QWEN3_ASR_MMPROJ_SHA256="$IOS_SPEECH_QWEN3_ASR_MMPROJ_SHA256" '
        r'--dart-define=IOS_SPEECH_ASR_AUDIO_PATH="$IOS_SPEECH_ASR_AUDIO_PATH" '
        r'--dart-define=IOS_SPEECH_ASR_AUDIO_SHA256="$IOS_SPEECH_ASR_AUDIO_SHA256" '
        r'--dart-define=IOS_SPEECH_ASR_EXPECTED_TRANSCRIPT="$IOS_SPEECH_ASR_EXPECTED_TRANSCRIPT" '
        r'--dart-define=IOS_SPEECH_MIC_DURATION_SECONDS="$IOS_SPEECH_MIC_DURATION_SECONDS" '
        r'--dart-define=IOS_SPEECH_MIC_EXPECTED_TRANSCRIPT="$IOS_SPEECH_MIC_EXPECTED_TRANSCRIPT" '
        r'--dart-define=IOS_SPEECH_LITERT_ASR_MODEL_PATH="$IOS_SPEECH_LITERT_ASR_MODEL_PATH" '
        r'--dart-define=IOS_SPEECH_LITERT_ASR_MODEL_SHA256="$IOS_SPEECH_LITERT_ASR_MODEL_SHA256" '
        r'--dart-define=IOS_SPEECH_LITERT_ASR_TOKENIZER_PATH="$IOS_SPEECH_LITERT_ASR_TOKENIZER_PATH" '
        r'--dart-define=IOS_SPEECH_LITERT_ASR_TOKENIZER_SHA256="$IOS_SPEECH_LITERT_ASR_TOKENIZER_SHA256" '
        r'--dart-define=IOS_SPEECH_LITERT_ASR_PRESET="$IOS_SPEECH_LITERT_ASR_PRESET" '
        r'--dart-define=IOS_SPEECH_LITERT_ASR_AUDIO_PATH="$IOS_SPEECH_LITERT_ASR_AUDIO_PATH" '
        r'--dart-define=IOS_SPEECH_LITERT_ASR_AUDIO_SHA256="$IOS_SPEECH_LITERT_ASR_AUDIO_SHA256" '
        r'--dart-define=IOS_SPEECH_LITERT_ASR_EXPECTED_TRANSCRIPT="$IOS_SPEECH_LITERT_ASR_EXPECTED_TRANSCRIPT" '
        r'--dart-define=IOS_SPEECH_QWEN3_TTS_MODEL_PATH="$IOS_SPEECH_QWEN3_TTS_MODEL_PATH" '
        r'--dart-define=IOS_SPEECH_QWEN3_TTS_MODEL_SHA256="$IOS_SPEECH_QWEN3_TTS_MODEL_SHA256" '
        r'--dart-define=IOS_SPEECH_QWEN3_TTS_MMPROJ_PATH="$IOS_SPEECH_QWEN3_TTS_MMPROJ_PATH" '
        r'--dart-define=IOS_SPEECH_QWEN3_TTS_MMPROJ_SHA256="$IOS_SPEECH_QWEN3_TTS_MMPROJ_SHA256" '
        r'--dart-define=IOS_SPEECH_TTS_TEXT="$IOS_SPEECH_TTS_TEXT" '
        r'--dart-define=IOS_SPEECH_TTS_OUTPUT_PATH="$IOS_SPEECH_TTS_OUTPUT_PATH" '
        r'--dart-define=IOS_SPEECH_TTS_EXPECTED_TRANSCRIPT="$IOS_SPEECH_TTS_EXPECTED_TRANSCRIPT" '
        r'--dart-define=IOS_SPEECH_LITERT_LM_MODEL_PATH="$IOS_SPEECH_LITERT_LM_MODEL_PATH" '
        r'--dart-define=IOS_SPEECH_LITERT_LM_MODEL_SHA256="$IOS_SPEECH_LITERT_LM_MODEL_SHA256"',
    useWhen:
        'Physical iOS speech validation across Qwen3-ASR, LiteRT-LM streaming '
        'ASR, Qwen3-TTS, microphone capture, and typed speech API contracts. '
        'Each _PATH define takes a safe absolute device path or an '
        '@appcache/ relative reference; prefer @appcache/ because installing '
        'rotates the app data-container UUID and invalidates absolute '
        'pre-install container paths.',
  ),
  TestMatrixRow(
    id: 'chat-app-live-speech-smoke',
    tier: 'targeted',
    mode: 'manual/device',
    covers:
        'selectable live-ASR sidecar download integrity/progress/cancellation, '
        'PCM16 microphone streaming, confirmed/pending updates, editable '
        'draft finalization, bounded session lifecycle, and cancellation',
    command:
        'Run example/chat_app on a microphone-equipped Android, iOS, macOS, '
        'or Windows device with a native chat model loaded. Install Moonshine, '
        'verify determinate progress, dictate for at least two five-second '
        'windows, verify confirmed/pending text, choose Use text, edit the '
        'draft, and send it. Repeat with Parakeet TDT where device storage/RAM '
        'permit, then test download cancellation and an app-background '
        'transition. Record device, runtime version, selected model, exact '
        'asset hashes, transcript, update/finalization latency, peak memory, '
        'and cleanup.',
    useWhen:
        'LiteRT-LM live ASR, worker isolation, PCM streaming, sidecar model '
        'downloads, chat composer dictation, or microphone lifecycle changes.',
  ),
  TestMatrixRow(
    id: 'chat-app-image-generation-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'chat-app image screen on a device with the bundled stable_diffusion '
        'runtime: a runtime probe that leaves the UI isolate responsive, SDXS '
        'download through the screen when not '
        'installed, seeded 512x512 generation with the used seed shown, and '
        'verified PNG plus screen-capture receipt in app external files on '
        'Android, or the app temporary directory elsewhere',
    command:
        'cd example/chat_app && flutter test --run-skipped -t local-only '
        'integration_test/image_generation_e2e_test.dart -d <device>',
    useWhen:
        'Chat-app image screen, image model catalog or download, or device '
        'QA of the stable_diffusion runtime on Android, iOS, macOS, Linux or '
        'Windows (#779). Record device, backend, timing and memory.',
  ),
  TestMatrixRow(
    id: 'firebase-image-generation-e2e',
    tier: 'platform',
    mode: 'opt-in; explicit Firebase Test Lab run with budget evidence',
    covers:
        'the chat-app image test on one physical Firebase device through the '
        'maintained validation flow: exact clean source commit compiled in, '
        'Android evidence pull or iOS XCTest attachments, and grading by the '
        'maintained image verifier (commit, clean source, backend, runtime '
        'tag, model lock, seed, dimensions, PNG structure)',
    command:
        'dart run tool/testing/validation.dart build --target android '
        '--profile image-sdxs-cpu --out <bundle>, then plan --target '
        'firebase-android, run and collect; image-sdxs-metal with ios and '
        'firebase-ios',
    useWhen:
        'Physical-device image evidence for a release or a change to the '
        'image screen, the stable_diffusion runtime or image validation '
        'tooling; see doc/cross_platform_validation.md.',
  ),
  TestMatrixRow(
    id: 'chat-app-voice-question-smoke',
    tier: 'targeted',
    mode: 'manual/device',
    covers:
        'native Gemma 4 E2B LiteRT-LM direct-media and experimental llama.cpp '
        'GGUF + projector microphone input, the 30-second cap, '
        'answer-not-transcript behavior, conversation reuse, and '
        'temporary-WAV cleanup',
    command:
        'Run example/chat_app on a microphone-equipped native device with the '
        'Gemma 4 E2B LiteRT-LM preset, then repeat with the pinned E2B GGUF + '
        'audio-capable projector. Record a known spoken instruction, use Stop '
        '& ask, verify the assistant answers it rather than automatically '
        'transcribing it, then send a text follow-up and regenerate the answer '
        'to verify audio context reuse. Repeat with the automatic 30-second '
        'limit and Discard, and confirm temporary-WAV cleanup. Record the '
        'platform/device, exact model and projector artifact hashes, backend, '
        'permission result, answer, cold/warm latency, memory, and cleanup '
        'evidence. The current packaged microphone evidence is LiteRT-LM on '
        'macOS; llama.cpp only has an engine-level Metal smoke. Do not '
        'generalize either result to Android, iOS, or Windows without '
        'device-level evidence.',
    useWhen:
        'Chat-app Ask with voice, native LiteRT-LM or llama.cpp audio input, '
        'microphone lifecycle, or byte-backed audio-history behavior changes.',
  ),
  TestMatrixRow(
    id: 'llama-cpp-chat-template-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real GGUF llama.cpp direct backend chat-template rendering, custom '
        'template override, LlamaEngine ModelParams.chatTemplate rendering, '
        'generation and tool-call parsing, and unsupported multimodal '
        'template diagnostics',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'llama-cpp-chat-template-smoke --model-path <model.gguf>',
    useWhen:
        'llama.cpp backend applyChatTemplate, ModelParams.chatTemplate, '
        'speculative benchmark prompt wrapping, or raw-vs-template parity '
        'changes.',
  ),
  TestMatrixRow(
    id: 'template-parity',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'vendored llama.cpp chat-template detection/render/parse parity and '
        'compiled structured-output GBNF schema and collision acceptance/rejection',
    command: 'tool/testing/run_template_parity_suites.sh',
    useWhen: 'Template engine, handlers, grammar, or parser changes.',
  ),
  TestMatrixRow(
    id: 'litert-lm-engine-smoke',
    tier: 'targeted',
    mode: 'CI + local',
    covers:
        'LiteRT-LM native library load in CI, plus real .litertlm '
        'load/generate path when the smoke model is available',
    command:
        'CI workflow "LiteRT-LM Smoke", or dart run '
        'tool/litert_lm_engine_smoke.dart <model.litertlm> cpu '
        '"What is 2+2? Answer only with the number." 16 1024',
    useWhen: 'LiteRT-LM backend, hook companion libraries, or runtime pins.',
  ),
  TestMatrixRow(
    id: 'litert-lm-multimodal-embedding',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'LiteRT-LM embedding-only load, text/image/audio/interleaved, normalization, batch order, limits and cancellation',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario litert-lm-multimodal-embedding --model-path <model.litertlm> --backend cpu',
    useWhen:
        'LiteRT-LM embeddings or embedding-engine loading. Chrome/reference procedure: doc/multimodal_embeddings_litert.md.',
  ),
  TestMatrixRow(
    id: 'litert-lm-utility-preservation',
    tier: 'targeted',
    mode: 'local-only; Qwen3 CPU only',
    covers:
        'Hash-pinned public runtime-client tokenizer, Unicode round trips, special-token prefix, native run metrics and reuse',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario litert-lm-utility-preservation --model-path <Qwen3-0.6B.litertlm> --backend cpu',
    useWhen:
        'LiteRT-LM runtime-client tokenizer, run loop or metrics changes. CPU and canonical minLogLevel 3 only; fixture and procedure: doc/testing_matrix.md.',
  ),
  TestMatrixRow(
    id: 'litert-lm-media-preservation',
    tier: 'targeted',
    mode: 'local-only; Qwen3.5 VL CPU only',
    covers:
        'Hash-pinned Qwen3.5 generative image path/bytes parity, vision probe, image history, cancellation reuse and dispose/reload',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario litert-lm-media-preservation --model-path <Qwen3.5-0.8B-VL_int8.litertlm> --backend cpu',
    useWhen:
        'LiteRT-LM image wiring, conversation history or lifecycle changes. No audio, thinking, GPU or general perceptual-quality qualification; fixture identity and procedure: doc/testing_matrix.md.',
  ),
  TestMatrixRow(
    id: 'litert-lm-lifecycle',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Real-model unload/reload, missing-model recovery, and timed-out native initialization cleanup with outer process deadlines',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario litert-lm-lifecycle --model-path <model.litertlm> --backend cpu',
    useWhen:
        'LiteRT-LM worker lifecycle, request settlement, or native teardown changes. Repeat with the affected requested backend; placement remains unverified.',
  ),
  TestMatrixRow(
    id: 'litert-lm-v1-asr-smoke',
    tier: 'targeted',
    mode: 'local-only; explicit unselected v1 speech client, CPU only',
    covers:
        'Exact library/model/tokenizer/audio hashes, actual injected speech support probe and worker, streaming updates, transcribeOnce and cancellation with bounded child exit and captured native stderr',
    command:
        'LITERT_LM_V1_LIBRARY=<lib> LITERT_LM_V1_LIBRARY_SHA256=<sha256> LITERT_LM_V1_MODEL_SHA256=<sha256> LITERT_LM_V1_TOKENIZER_SHA256=<sha256> LITERT_LM_V1_AUDIO_SHA256=<sha256> dart run tool/testing/run_local_e2e.dart --scenario litert-lm-v1-asr-smoke --model-path <speech-model> --tokenizer-path <tokenizer> --audio-path <wav> --model-preset moonshine-tiny --expect <known-transcript> --backend cpu',
    useWhen:
        'Qualifying C API1 ASR consumer dispatch against a prepared owner artifact. Run --dry-run first and schedule one model job at a time. Default factory and pins remain unchanged.',
  ),
  TestMatrixRow(
    id: 'litert-lm-v1-service',
    tier: 'targeted',
    mode: 'local-only; explicit unselected v1 client, CPU only',
    covers:
        'Exact library/model SHA256, actual injected service arithmetic chat, native cancellation cause, settled reload/reuse and bounded process exit with captured native stderr',
    command:
        'LITERT_LM_V1_LIBRARY=<lib> LITERT_LM_V1_LIBRARY_SHA256=<sha256> LITERT_LM_V1_MODEL_SHA256=<sha256> dart run tool/testing/run_local_e2e.dart --scenario litert-lm-v1-service --model-path <Qwen3-0.6B.litertlm> --backend cpu',
    useWhen:
        'Qualifying the internal C API 1 client/service path against a prepared owner artifact. Run --dry-run first; root owns model serialization. No public factory/pin enablement, GPU, ASR, media, LoRA, schema or embedding qualification is implied.',
  ),
  TestMatrixRow(
    id: 'litert-lm-v1-public-direct',
    tier: 'high-risk',
    mode:
        'local-only; public defaults, CPU; requires admitted production selection',
    covers:
        'Exact full runtime manifest/model/config hashes, public direct dispatch without runtime factory or speech driver overrides, raw observations before oracles, owned deadline and lifecycle',
    command:
        'LITERT_LM_V1_LIBRARY=<lib> LITERT_LM_V1_LIBRARY_SHA256=<sha256> LITERT_LM_V1_MODEL_SHA256=<sha256> LITERT_LM_V1_RUNTIME_MANIFEST=<json> LITERT_LM_V1_RUNTIME_MANIFEST_SHA256=<sha256> LITERT_LM_V1_PUBLIC_CONFIG=<profile-or-speech-json> LITERT_LM_V1_PUBLIC_CONFIG_SHA256=<sha256> dart run tool/testing/run_local_e2e.dart --scenario litert-lm-v1-public-direct --model-path <model> --backend cpu',
    useWhen:
        'Final public C API1 adoption. Run --dry-run first, then schedule only with exact artifact/model admission. Flag-off refusal and staged status9 fixture controls are model-free evidence, not successful v1, GPU or physical-device qualification.',
  ),
  TestMatrixRow(
    id: 'litert-lm-v1-public-service',
    tier: 'high-risk',
    mode:
        'local-only; public defaults, CPU; requires admitted production selection',
    covers:
        'Exact full runtime manifest/model/config hashes, public service dispatch without runtime factory or speech driver overrides, raw observations before oracles, owned deadline and lifecycle',
    command:
        'LITERT_LM_V1_LIBRARY=<lib> LITERT_LM_V1_LIBRARY_SHA256=<sha256> LITERT_LM_V1_MODEL_SHA256=<sha256> LITERT_LM_V1_RUNTIME_MANIFEST=<json> LITERT_LM_V1_RUNTIME_MANIFEST_SHA256=<sha256> LITERT_LM_V1_PUBLIC_CONFIG=<profile-or-speech-json> LITERT_LM_V1_PUBLIC_CONFIG_SHA256=<sha256> dart run tool/testing/run_local_e2e.dart --scenario litert-lm-v1-public-service --model-path <model> --backend cpu',
    useWhen:
        'Final public C API1 adoption. Run --dry-run first, then schedule only with exact artifact/model admission. Flag-off refusal and staged status9 fixture controls are model-free evidence, not successful v1, GPU or physical-device qualification.',
  ),
  TestMatrixRow(
    id: 'litert-lm-v1-public-speech',
    tier: 'high-risk',
    mode:
        'local-only; public defaults, CPU; requires admitted production selection',
    covers:
        'Exact full runtime manifest/model/config hashes, public speech dispatch without runtime factory or speech driver overrides, raw observations before oracles, owned deadline and lifecycle',
    command:
        'LITERT_LM_V1_LIBRARY=<lib> LITERT_LM_V1_LIBRARY_SHA256=<sha256> LITERT_LM_V1_MODEL_SHA256=<sha256> LITERT_LM_V1_RUNTIME_MANIFEST=<json> LITERT_LM_V1_RUNTIME_MANIFEST_SHA256=<sha256> LITERT_LM_V1_PUBLIC_CONFIG=<profile-or-speech-json> LITERT_LM_V1_PUBLIC_CONFIG_SHA256=<sha256> dart run tool/testing/run_local_e2e.dart --scenario litert-lm-v1-public-speech --model-path <model> --backend cpu',
    useWhen:
        'Final public C API1 adoption. Run --dry-run first, then schedule only with exact artifact/model admission. Flag-off refusal and staged status9 fixture controls are model-free evidence, not successful v1, GPU or physical-device qualification.',
  ),
  TestMatrixRow(
    id: 'litert-lm-v1-json-schema',
    tier: 'targeted',
    mode: 'local-only; internal v1, macOS arm64 CPU only',
    covers:
        'Fixed published Qwen profile identity; conflicting unconstrained control, constrained Unicode/types with thinking disabled, ordinary followup, native cancellation, schema reuse and engine reload with hash-bound bounded child receipts',
    command:
        'LITERT_LM_V1_LIBRARY=<lib> LITERT_LM_V1_LIBRARY_SHA256=<sha256> LITERT_LM_V1_MODEL_SHA256=c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108 dart run tool/testing/run_local_e2e.dart --scenario litert-lm-v1-json-schema --model-path <published-Qwen3-0.6B.litertlm> --backend cpu',
    useWhen:
        'Qualifying internal C API1 schema source against an exact prepared owner artifact. Run --dry-run first; schedule one model job at a time. The public factory and pins remain unchanged; grammar enforcement is separate from model accuracy.',
  ),
  TestMatrixRow(
    id: 'litert-lm-v1-thinking-budget',
    tier: 'targeted',
    mode: 'local-only; injected v1 client, macOS arm64 CPU only',
    covers:
        'Fixed Gemma first-channel proof, bounded/unbounded native reasoning, token metrics/finish, cancel/reuse/reload, complete runtime payload hashes/loaded paths and bounded child cleanup',
    command:
        'LITERT_LM_V1_LIBRARY=<lib> LITERT_LM_V1_LIBRARY_SHA256=<sha256> LITERT_LM_V1_MODEL_SHA256=181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c LITERT_LM_V1_RUNTIME_MANIFEST=<json> LITERT_LM_V1_RUNTIME_MANIFEST_SHA256=<sha256> dart run tool/testing/run_local_e2e.dart --scenario litert-lm-v1-thinking-budget --model-path <gemma-4-E2B-it.litertlm> --backend cpu',
    useWhen:
        'Qualifying actual C API1 thinking-budget enforcement after source admission. Run --dry-run first; the model-job owner admits exact identities and serializes execution. No public activation or other backend/model qualification.',
  ),
  TestMatrixRow(
    id: 'qwen3-litert-cpu-unicode',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Known Qwen3-0.6B artifact exact split-token emoji decode, Unicode '
        'and literal byte-level text round trips, followed by CPU chat features',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'qwen3-litert-cpu-unicode --model-path <Qwen3-0.6B.litertlm> --backend cpu',
    useWhen:
        'Changing the Qwen3 LiteRT-LM CPU smoke artifact or tokenizer fidelity. '
        'The original artifact is an expected failing negative control. '
        'No GPU, device, or Web qualification.',
  ),
  TestMatrixRow(
    id: 'litert-lm-web-text-history',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Ordered system/user/assistant Web text history, matching pinned JS reference, no-history/no-system bypass controls, reset and cancellation/reuse',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario litert-lm-web-text-history --model-path <existing-model.litertlm> --backend cpu',
    useWhen:
        'LiteRT-LM Web conversation serialization, runtime capability probe, ChatSession history or system prompts. Repeat with the affected model/backend; no other browser/backend or tool/media/template support is implied.',
  ),
  TestMatrixRow(
    id: 'litert-lm-web-tool-calling',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Web manual tool calls from the runtime tool_calls, tool results used in the answer, matching pinned JS reference, no-tools control, cancellation/reuse and reset',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario litert-lm-web-tool-calling --model-path <existing-model.litertlm> --backend cpu',
    useWhen:
        'LiteRT-LM Web tool declarations, tool-call/result serialization, the preface.tools probe or tool-call parsing. Repeat with the affected model/backend; litert-lm-web-truncation covers automatic tool loops.',
  ),
  TestMatrixRow(
    id: 'litert-lm-web-truncation',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Web finish reason length at and below the maxTokens boundary and for a filled context, including a requested context above a fixed KV cache, matching pinned JS runtime token counts; stop above the boundary; automatic tool loop completed and truncated without running the tool',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario litert-lm-web-truncation --model-path <existing-model.litertlm> --backend cpu',
    useWhen:
        'LiteRT-LM Web generation-limit reporting, the token-count load probe, automatic tool loops or a @litert-lm/core pin change. Repeat with the affected model/backend.',
  ),
  TestMatrixRow(
    id: 'litert-lm-json-schema',
    tier: 'high-risk',
    mode: 'local-only; native host CPU or GPU',
    covers:
        'Adversarial native JSON Schema enforcement, separate GBNF capability, nested/array/ref/pattern/Unicode contract, typed contract refusal, Gemma 4 thinking or Qwen3 thinking refusal, per-request reset, history/system, cancellation and a length cutoff inside a constrained string',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario litert-lm-json-schema --model-path <Qwen3-0.6B-or-gemma-4-E2B-it.litertlm> --backend cpu',
    useWhen:
        'Changing native schema constraints, the schema contract, provider admission or request transport. Run once per fixed model (Qwen3-0.6B, Gemma 4 E2B) and per qualified backend (cpu, gpu); no Web qualification.',
  ),
  TestMatrixRow(
    id: 'litert-lm-chat-features-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real .litertlm chat, stop and maxTokens length finish reasons, an '
        'automatic tool loop cut off at maxTokens, thinking channel '
        'reassembly (reported not_applicable with a reason when the bundle '
        'template always closes the think block, as for the Qwen3.5 int8 '
        'bundles), streaming tool calls, and optional byte-backed audio '
        'question answering with an exact expected answer',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'litert-lm-chat-features-smoke --model-path <model.litertlm> '
        '--backend auto --audio-path <audio.wav> '
        '--expect <expected-answer>',
    useWhen:
        'LiteRT-LM chat templates, finish reasons, thinking, tool calling, '
        'audio input, or ChatSession work. Omit --audio-path and --expect for the base '
        'chat-only smoke.',
  ),
  TestMatrixRow(
    id: 'chat-app-device-cache',
    tier: 'targeted',
    mode: 'local-only',
    covers: 'Flutter device model/mmproj download-cache-load flow',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-model-cache --device <macos|ios|android>',
    useWhen:
        'Chat app model lifecycle, cache, projector, or device UI changes.',
  ),
  TestMatrixRow(
    id: 'chat-app-litert-json-schema',
    tier: 'high-risk',
    mode: 'local-only; device',
    covers:
        'Native JSON Schema enforcement on a device: adversarial control, '
        'nested/array/ref/anyOf/pattern contract, typed contract refusal, '
        'Gemma 4 thinking or Qwen3 thinking refusal and a length cutoff '
        'inside a constrained string',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-litert-json-schema --device <android|ios|macos> '
        '--model-path <device-path-or-http-url> --backend cpu',
    useWhen:
        'Qualifying native schema output on Android or iOS, or changing the '
        'platform gate. Run per fixed model (Qwen3-0.6B, Gemma 4 E2B) and '
        'per backend (cpu, gpu).',
  ),
  TestMatrixRow(
    id: 'chat-app-litert-reload-memory',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'LiteRT-LM engine create/generate/delete loops on CPU and GPU with '
        'per-step process memory, including dumpsys graphics memory under '
        'Android instrumentation',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-litert-reload-memory --device <macos|android>',
    useWhen:
        'LiteRT-LM runtime pin, engine lifecycle or Android GPU memory '
        'changes. Downloads the locked model unless --model-path names a '
        'copy on the target device. Graphics memory needs the Test Lab '
        'arguments in example/chat_app/README.md.',
  ),
  TestMatrixRow(
    id: 'chat-app-litert-read-only-bundle',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'LiteRT-LM bundle in a mode-555 directory on a device with no cache '
        'directory configured: named with and without .litertlm it must '
        'generate on CPU and GPU, and nothing may be written to the '
        'directory or beside the original model file',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-litert-read-only-bundle --device <macos|ios|android>',
    useWhen:
        'LiteRT-LM runtime pin, cache directory defaults, the read-only '
        'directory probe or the .litertlm link for bundles named without '
        'that extension change. Downloads '
        'the locked model unless --model-path names a copy on the target '
        'device. macOS and Android default to a temp cache directory, so '
        'of the POSIX targets only iOS and Linux run uncached through the '
        'public API; '
        'the Test Lab build is in example/chat_app/README.md.',
  ),
  TestMatrixRow(
    id: 'chat-app-text-image-coexistence',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'llama.cpp text generation and stable_diffusion image generation in '
        'one process on a device: a greedy seeded chat reply before the '
        'image runtime is used must be repeated exactly with the image '
        'engine loaded, and a seeded 512x512 SDXS image must be repeated '
        'byte for byte with the text engine still loaded; resident memory '
        'is logged per step',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-text-image-coexistence --device <macos|android|ios>',
    useWhen:
        'llama.cpp or stable_diffusion runtime pin, native bundle packaging, '
        'or image engine load and memory check changes (#779). Downloads '
        'the locked chat-gguf-cpu model and SDXS (1.2 GB together); the '
        'Test Lab build is in example/chat_app/README.md.',
  ),
  TestMatrixRow(
    id: 'chat-app-image-settings-comparison',
    tier: 'targeted',
    mode: 'local-only; Firebase through the image-settings-* profiles',
    covers:
        'the automatic image attention and VAE settings against '
        'flashAttention: false and vaeDirectConvolution: false (and the '
        'VAE setting alone for the full SD-Turbo VAE) for SDXS and SD-Turbo '
        'with and without TAESD, in one process at seed 42 and 512x512: warm '
        'time '
        'per image, sampling and decode split, per-load peak memory, '
        'backend and image hash per arm, with a verified receipt',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-image-settings-comparison --device <macos|android|ios>; '
        'on Firebase build --profile image-settings-cpu and '
        'image-settings-cpu-vae (android), or image-settings-metal, '
        'image-settings-metal-taesd and image-settings-metal-vae (ios), then '
        'plan, run and collect',
    useWhen:
        'Changing the automatic flashAttention or vaeDirectConvolution '
        'defaults, the stable_diffusion runtime pin, or re-measuring them on '
        'a device (#805). Downloads SDXS, SD-Turbo and TAESD (2.7 GB); see '
        'doc/cross_platform_validation.md.',
  ),
  TestMatrixRow(
    id: 'chat-app-micro-batch-sweep',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'llama.cpp history, long-history and grammar-constrained tool '
        'prompts at the default micro-batch and at explicit sizes in one '
        'process on a device, with a flushed verdict per attempt, the '
        'Android Vulkan prompt cap state (capped, not capped, or capped '
        'without a Vulkan device), the Vulkan device name, API version and '
        'subgroup size, and a typed load refusal recorded; the default size '
        'must answer correctly, explicit sizes are controls',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-micro-batch-sweep --device <macos|android>',
    useWhen:
        'llama.cpp native pin, Android Vulkan prompt cap, Vulkan device '
        'facts or the Vulkan 1.2 load refusal changes. Downloads the locked '
        'chat-gguf-vulkan model unless --model-path names a copy on the '
        'target device. Only an Android Vulkan device exercises the cap; '
        'the Test Lab arguments are in example/chat_app/README.md.',
  ),
  TestMatrixRow(
    id: 'chat-app-macos-quit',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'Flutter macOS quit of debug and release builds with a llama.cpp '
        'model and optionally an image model and a decision head loaded on '
        'Metal and nothing disposed: Quit Apple event, the Quit menu action, '
        'last-window close and exitApplication (required and cancelable), '
        'plus a hot restart then quit; exit status 0 and no crash report, '
        'with a model nothing frees aborting each path; not the Cmd-Q '
        'keystroke and not a quit during a load or a generation',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-macos-quit --model-path <chat.gguf>',
    useWhen:
        'Isolate shutdown releases, llama.cpp or stable_diffusion exit '
        'teardown, a Flutter pin bump, or app-exit guidance changes. Needs '
        'a Mac whose GPU loads the model.',
  ),
  TestMatrixRow(
    id: 'chat-app-flutter-active-shutdown',
    tier: 'platform',
    mode: 'local-only',
    covers:
        'Flutter native-call shutdown plus awaiting high-level startup/disposal, '
        'native call completion, ordinary C host callbacks and buffered output',
    command:
        'FLUTTER_SHUTDOWN_HEADERS=<extracted-native-headers> dart run '
        'tool/testing/run_local_e2e.dart --scenario '
        'chat-app-flutter-active-shutdown --model-path <chat.gguf>',
    useWhen:
        'Host shutdown, native worker lifecycle, exit teardown or Flutter pin changes.',
  ),
  TestMatrixRow(
    id: 'chat-app-flutter-image-shutdown',
    tier: 'platform',
    mode: 'local-only',
    covers:
        'Actual Flutter engine shutdown after pending image loading or active sampling, '
        'native call completion, ordinary C host callbacks and buffered output',
    command:
        'FLUTTER_SHUTDOWN_HEADERS=<extracted-native-headers> dart run '
        'tool/testing/run_local_e2e.dart --scenario '
        'chat-app-flutter-image-shutdown --model-path <image.gguf>',
    useWhen:
        'Image worker shutdown, stable-diffusion runtime or Flutter host changes.',
  ),
  TestMatrixRow(
    id: 'web-bridge-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers: 'WebGPU bridge bootstrap and fallback wiring',
    command: 'dart run tool/testing/run_local_e2e.dart --scenario bridge-smoke',
    useWhen: 'Bridge asset loading, web bootstrap, or web interop changes.',
  ),
  TestMatrixRow(
    id: 'web-production-artifact-smoke',
    tier: 'targeted',
    mode: 'CI + local',
    covers:
        'one production-root build tested by mock and real worker/GGUF smokes',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario chat-app-web-production-smoke',
    useWhen:
        'Web build, CI artifact promotion or static deployment changes. Requires the cached stories15M model or --model-url.',
  ),
  TestMatrixRow(
    id: 'web-mock-chat-smoke',
    tier: 'targeted',
    mode: 'CI + local',
    covers: 'built Flutter web chat app with deterministic mock bridge',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-web-mock-smoke',
    useWhen:
        'Web chat app UI, prompt wiring, settings, or bridge integration changes.',
  ),
  TestMatrixRow(
    id: 'web-real-model-smoke',
    tier: 'targeted',
    mode: 'CI + local',
    covers:
        'built Flutter web chat app with real worker/WASM and GGUF model URL',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-web-real-model-smoke --model-url <model-url> '
        '--allow-any-response',
    useWhen:
        'Web chat app, web model loading, or WebGPU bridge runtime changes.',
  ),
  TestMatrixRow(
    id: 'web-tool-penalty-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'built Flutter web chat app tool chat on a tool-capable GGUF: '
        'ToolChoice.auto sends a lazy grammar and no penaltyPromptTokens option',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-web-tool-penalty-smoke --model-url <tool-capable-gguf-url> '
        '--allow-any-response',
    useWhen:
        'Web penalty, tool-call grammar, or bridge completion option changes.',
  ),
  TestMatrixRow(
    id: 'web-speech-to-text-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'published WebGPU bridge, public typed STT API, Qwen3-ASR catalog, '
        'exact browser-selected WAV, MP3 or FLAC transcription, non-empty '
        'fake-device microphone transcription for a WAV, and rendered '
        'transcripts',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-web-speech-to-text-smoke '
        '--audio-path <speech.wav|.mp3|.flac> '
        '--expect <exact-transcript>',
    useWhen:
        'Web bridge pins, prompt speech capability gating, Qwen3-ASR Web, '
        'or browser transcription UI changes.',
  ),
  TestMatrixRow(
    id: 'webgpu-multimodal-regression',
    tier: 'targeted',
    mode: 'local-only',
    covers: 'CPU and WebGPU Qwen multimodal regression path',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'webgpu-multimodal-regression',
    useWhen: 'Multimodal, WebGPU prompt formatting, or image staging changes.',
  ),
  TestMatrixRow(
    id: 'gemma4-webgpu-mem64',
    tier: 'targeted',
    mode: 'local-only',
    covers: 'Gemma 4 E2B GGUF through web llama.cpp mem64 core',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-web-gemma4-webgpu-smoke',
    useWhen: 'Large WebGPU models, mem64 selection, or Gemma 4 web GGUF work.',
  ),
  TestMatrixRow(
    id: 'gemma4-litert-web',
    tier: 'targeted',
    mode: 'local-only',
    covers: 'Gemma 4 web .litertlm through LiteRT-LM JS backend',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'chat-app-web-litert-gemma4-smoke',
    useWhen: 'LiteRT-LM web backend, web chat app, or Gemma 4 web bundle work.',
  ),
  TestMatrixRow(
    id: 'linux-x64-ci-runtime',
    tier: 'platform',
    mode: 'CI + local',
    covers:
        'Linux x64 root VM tests, real GGUF prompt reuse, LiteRT-LM native '
        'library smoke, and opportunistic LiteRT-LM CPU engine smoke',
    command:
        'CI jobs "Test Linux & Web (with Coverage)", '
        '"Native Prompt Reuse Parity", and '
        '"LiteRT-LM Smoke / Native smoke (ubuntu-latest)".',
    useWhen: 'Any native runtime or release change affecting Linux x64.',
  ),
  TestMatrixRow(
    id: 'linux-arm64-runtime-smoke',
    tier: 'platform',
    mode: 'local/self-hosted',
    covers: 'Linux arm64 native hook bundle plus llama.cpp/LiteRT-LM runtime',
    command:
        'On a Linux arm64 host: dart test -p vm -j 1 --exclude-tags '
        'local-only; dart run tool/gguf_chat_features_smoke.dart '
        '<model.gguf> cpu; dart run tool/litert_lm_engine_smoke.dart '
        '<model.litertlm> cpu',
    useWhen: 'Linux arm64 bundle, release, or runtime changes.',
  ),
  TestMatrixRow(
    id: 'windows-x64-ci-runtime',
    tier: 'platform',
    mode: 'CI + local',
    covers:
        'Windows x64 host VM tests, hook bundle validation, LiteRT-LM native '
        'library smoke, and opportunistic LiteRT-LM CPU engine smoke',
    command:
        'CI jobs "Test Native (windows-tooling, <shard>/<shards>)", '
        '"Test Native (windows-runtime, <shard>/<shards>)" and '
        '"LiteRT-LM Smoke / Native smoke (windows-latest)".',
    useWhen: 'Any native runtime or release change affecting Windows x64.',
  ),
  TestMatrixRow(
    id: 'windows-arm64-hook-coverage',
    tier: 'platform',
    mode: 'hook-only + manual/runtime',
    covers:
        'Windows arm64 bundle selection; runtime smoke requires Windows arm64 hardware',
    command:
        'dart test -p vm -j 1 test/unit/hook --exclude-tags local-only; '
        'for runtime proof, run the GGUF local smoke on Windows arm64 hardware.',
    useWhen: 'Windows arm64 bundle, hook, or release changes.',
  ),
  TestMatrixRow(
    id: 'macos-arm64-runtime-smoke',
    tier: 'platform',
    mode: 'local/device',
    covers: 'macOS arm64 llama.cpp CPU/Metal and LiteRT-LM CPU/GPU runtime',
    command:
        'On Apple Silicon: dart test -p vm -j 1 --exclude-tags local-only; '
        'dart run tool/gguf_chat_features_smoke.dart <model.gguf> metal; '
        'dart run tool/litert_lm_chat_features_smoke.dart '
        '<model.litertlm> gpu',
    useWhen: 'Apple Metal, macOS runtime, LiteRT-LM GPU, or release changes.',
  ),
  TestMatrixRow(
    id: 'macos-x64-runtime-smoke',
    tier: 'platform',
    mode: 'local/device',
    covers:
        'macOS x64 llama.cpp CPU/Metal runtime; LiteRT-LM has no x64 runtime '
        'and must throw LlamaUnsupportedException',
    command:
        'On Intel macOS or under Rosetta: dart test -p vm -j 1 '
        '--exclude-tags local-only; '
        'dart run tool/gguf_chat_features_smoke.dart <model.gguf> metal; '
        'launch a universal Flutter macOS build with arch -x86_64 and select '
        'LiteRT-LM',
    useWhen: 'macOS x64 native runtime, bundle, or release changes.',
  ),
  TestMatrixRow(
    id: 'ios-arm64-device-smoke',
    tier: 'platform',
    mode: 'manual/device',
    covers: 'iOS arm64 device bundle, app launch, model load, first tokens',
    command:
        'Run example/chat_app on an iOS device, load a known small model, '
        'generate a short deterministic response, and record device/iOS/model.',
    useWhen: 'iOS runtime, bundle, framework staging, or release changes.',
  ),
  TestMatrixRow(
    id: 'ios-simulator-smoke',
    tier: 'platform',
    mode: 'manual/simulator',
    covers:
        'iOS arm64 and x86_64 simulator bundle/framework staging; LiteRT-LM '
        'is arm64-only',
    command:
        'Run example/chat_app on available iOS simulators; record the '
        'architecture, model, backend, and whether model load/generation '
        'passed. LiteRT-LM runs only on arm64 Simulator.',
    useWhen: 'iOS simulator hook, framework staging, or release changes.',
  ),
  TestMatrixRow(
    id: 'android-arm64-device-smoke',
    tier: 'platform',
    mode: 'manual/device',
    covers:
        'Android arm64 app build/install/launch, CPU profiles, crash signatures; '
        'pair with manual model load/generation evidence when runtime behavior '
        'is at risk',
    command:
        './scripts/android_runtime_smoke.sh --project-dir example/chat_app '
        '--app-id com.example.llamadart_chat_example',
    useWhen:
        'Android arm64 runtime selection, CPU variants, native bundle changes, '
        'or release candidates.',
  ),
  TestMatrixRow(
    id: 'android-x64-emulator-smoke',
    tier: 'platform',
    mode: 'manual/emulator',
    covers: 'Android x64 emulator bundle, app launch, model load/generate',
    command:
        'Run example/chat_app on an Android x64 emulator and record emulator '
        'image, model, backend, and generation result.',
    useWhen: 'Android x64 bundle, hook, or emulator-targeted changes.',
  ),
  TestMatrixRow(
    id: 'web-chrome-runtime-smoke',
    tier: 'platform',
    mode: 'CI + local',
    covers: 'Chrome browser-safe tests plus local WebGPU/LiteRT-LM web smokes',
    command:
        'dart test -p chrome --exclude-tags local-only; choose relevant web '
        'rows: web-bridge-smoke, web-mock-chat-smoke, web-real-model-smoke, '
        'gemma4-webgpu-mem64, or gemma4-litert-web.',
    useWhen: 'Web backend, browser interop, WebGPU, or LiteRT-LM web changes.',
  ),
  TestMatrixRow(
    id: 'android-release-device-pool',
    tier: 'release',
    mode: 'manual/device',
    covers:
        'Android old/modern arm64 app launch, manual runtime load/generate, '
        'CPU profiles, crash signatures',
    command:
        'Run android-arm64-device-smoke on old and modern arm64 devices with '
        'the cpu_profile full and compact configurations; see '
        'https://github.com/leehack/llamadart/blob/main/doc/android_runtime_smoke_test_plan.md',
    useWhen:
        'Android runtime selection, CPU variants, release candidates, or '
        'native bundle changes affecting Android.',
  ),
  TestMatrixRow(
    id: 'release-companion-pub-gate',
    tier: 'release',
    mode: 'manual/release',
    covers:
        'Flutter Apple SPM companion package pub.dev availability and core '
        'constraints around the post-merge core tag',
    command:
        'Before merging the release-prep PR, verify each referenced companion '
        'version with '
        'https://pub.dev/api/packages/<package>/versions/<version>. If a '
        'changed version is missing, keep the PR scoped to release prep; after '
        'merge, release_on_prep_merge.yml pushes the core release tag, waits '
        'for it on pub.dev, then pushes the missing companion tag, waits for '
        'publish_companion_pubdev.yml, and verifies pub.dev.',
    useWhen:
        'Any release that changes companion packages or documents companion '
        'package versions.',
  ),
  TestMatrixRow(
    id: 'release-representative-smokes',
    tier: 'release',
    mode: 'manual/local',
    covers: 'representative examples before publishing a package release',
    command: 'Follow website/docs/maintainers/release-workflow.md.',
    useWhen: 'Before publishing a release.',
  ),
];

String formatTestMatrix({String tier = 'all'}) {
  final rows = _filterRows(tier);
  final buffer = StringBuffer()
    ..writeln('| ID | Tier | Mode | Covers | Use when | Command |')
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  for (final row in rows) {
    buffer.writeln(
      '| ${_cell(row.id)} | ${_cell(row.tier)} | ${_cell(row.mode)} | '
      '${_cell(row.covers)} | ${_cell(row.useWhen)} | '
      '`${_cell(row.command)}` |',
    );
  }
  return buffer.toString();
}

String formatPrEvidenceTemplate({String tier = 'all'}) {
  final rows = _filterRows(tier);
  final buffer = StringBuffer()
    ..writeln(
      '| Matrix row | Scope covered | Platform / model / backend | Result | Evidence / notes |',
    )
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final row in rows) {
    buffer.writeln(
      '| `${_cell(row.id)}` | ${_cell(row.covers)} |  | PASS / FAIL / N/A |  |',
    );
  }
  return buffer.toString();
}

List<TestMatrixRow> _filterRows(String tier) {
  final normalized = tier.trim().toLowerCase();
  if (normalized == 'all') {
    return testMatrixRows;
  }
  final rows = testMatrixRows
      .where((row) => row.tier == normalized)
      .toList(growable: false);
  if (rows.isEmpty) {
    throw ArgumentError.value(
      tier,
      'tier',
      'Expected all, essential, targeted, high-risk, platform, or release.',
    );
  }
  return rows;
}

String _cell(String value) => value.replaceAll('|', r'\|');

String _usage() {
  return '''Usage: dart run tool/testing/test_matrix.dart [options]

Options:
  --list                 Print the canonical test matrix (default).
  --pr-template          Print a PR evidence table.
  --tier <tier>          Filter by all, essential, targeted, high-risk, platform, or release.
  -h, --help             Show this help.
''';
}

void main(List<String> args) {
  var list = true;
  var prTemplate = false;
  var tier = 'all';

  try {
    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      switch (arg) {
        case '--list':
          list = true;
          prTemplate = false;
        case '--pr-template':
          prTemplate = true;
          list = false;
        case '--tier':
          index++;
          if (index >= args.length) {
            throw ArgumentError('Missing value for --tier');
          }
          tier = args[index];
        case '--help' || '-h':
          stdout.write(_usage());
          return;
        default:
          throw ArgumentError('Unknown option: $arg');
      }
    }

    if (prTemplate) {
      stdout.write(formatPrEvidenceTemplate(tier: tier));
    } else if (list) {
      stdout.write(formatTestMatrix(tier: tier));
    }
  } on Object catch (error) {
    stderr.writeln(error);
    stderr.write(_usage());
    exitCode = 64;
  }
}
