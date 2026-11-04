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

  /// One of `essential`, `targeted`, `platform`, or `release`.
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
    id: 'static-format-analyze',
    tier: 'essential',
    mode: 'CI + local',
    covers: 'format, analyzer, web/native import boundaries',
    command:
        'dart format --output=none --set-exit-if-changed .; dart analyze; '
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
    covers: '>=70% line coverage for maintainable lib/ code',
    command:
        'dart test -p vm --coverage=coverage; '
        'dart pub global run coverage:format_coverage --lcov '
        '--in=coverage/test --out=coverage/lcov.info --report-on=lib '
        '--check-ignore; '
        'dart run tool/testing/check_lcov_threshold.dart coverage/lcov.info 70',
    useWhen: 'Before merge when lib/ behavior changes or coverage is in doubt.',
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
        'current README/website install snippets and companion README versions',
    command: 'dart run tool/testing/verify_release_docs_versions.dart',
    useWhen:
        'Release prep, companion package version bumps, or current install docs.',
  ),
  TestMatrixRow(
    id: 'examples-tests',
    tier: 'targeted',
    mode: 'local',
    covers: 'example package unit tests and Flutter app regressions',
    command:
        'Run tests in each touched example package, for example '
        '(cd example/chat_app && flutter test).',
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
    id: 'llama-cpp-speculative-benchmark',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real GGUF llama.cpp speculative decoding baseline, bundled MTP, '
        'n-gram, draft-model, and cache throughput/acceptance metrics',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'llama-cpp-speculative-benchmark --model-path <model.gguf> '
        '--backend cpu --speculative-cases baseline,ngram-simple,'
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
    id: 'gguf-chat-features-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real GGUF llama.cpp chat, thinking-budget/suppression, streaming '
        'tool calls, optional multimodal input',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'gguf-chat-features-smoke --model-path <model.gguf> --backend auto '
        '[--mmproj-path <mmproj.gguf> --image-path <image>]',
    useWhen:
        'Chat rendering, parser, tool calling, thinking, or GGUF feature work.',
  ),
  TestMatrixRow(
    id: 'llama-cpp-chat-template-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real GGUF llama.cpp direct backend chat-template rendering, custom '
        'template override, and unsupported multimodal template diagnostics',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'llama-cpp-chat-template-smoke --model-path <model.gguf>',
    useWhen:
        'llama.cpp backend applyChatTemplate, speculative benchmark prompt '
        'wrapping, or raw-vs-template parity changes.',
  ),
  TestMatrixRow(
    id: 'template-parity',
    tier: 'targeted',
    mode: 'local-only',
    covers: 'vendored llama.cpp chat-template detection/render/parse parity',
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
    id: 'litert-lm-chat-features-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers:
        'real .litertlm chat, thinking channel reassembly, streaming tool calls',
    command:
        'dart run tool/testing/run_local_e2e.dart --scenario '
        'litert-lm-chat-features-smoke --model-path <model.litertlm> '
        '--backend auto',
    useWhen:
        'LiteRT-LM chat templates, thinking, tool calling, or ChatSession work.',
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
    id: 'web-bridge-smoke',
    tier: 'targeted',
    mode: 'local-only',
    covers: 'WebGPU bridge bootstrap and fallback wiring',
    command: 'dart run tool/testing/run_local_e2e.dart --scenario bridge-smoke',
    useWhen: 'Bridge asset loading, web bootstrap, or web interop changes.',
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
        'chat-app-web-real-model-smoke --model-url <model-url> --expect 4',
    useWhen:
        'Web chat app, web model loading, or WebGPU bridge runtime changes.',
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
        'Windows x64 VM tests, hook bundle validation, LiteRT-LM native '
        'library smoke, and opportunistic LiteRT-LM CPU engine smoke',
    command:
        'CI jobs "Test Native (windows-latest)" and '
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
    covers: 'macOS x64 llama.cpp CPU/Metal and LiteRT-LM CPU/GPU runtime',
    command:
        'On Intel macOS: dart test -p vm -j 1 --exclude-tags local-only; '
        'dart run tool/gguf_chat_features_smoke.dart <model.gguf> metal; '
        'dart run tool/litert_lm_chat_features_smoke.dart '
        '<model.litertlm> gpu',
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
        'iOS arm64 simulator and x86_64 simulator bundle/framework staging paths',
    command:
        'Run example/chat_app on available iOS simulators; record simulator '
        'architecture, model, backend, and whether model load/generation passed.',
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
        'doc/android_runtime_smoke_test_plan.md.',
    useWhen:
        'Android runtime selection, CPU variants, release candidates, or '
        'native bundle changes affecting Android.',
  ),
  TestMatrixRow(
    id: 'release-companion-pub-gate',
    tier: 'release',
    mode: 'manual/release',
    covers:
        'Flutter Apple SPM companion package pub.dev availability before the '
        'post-merge core tag',
    command:
        'Before merging the release-prep PR, verify each referenced companion '
        'version with '
        'https://pub.dev/api/packages/<package>/versions/<version>. If a '
        'changed version is missing, keep the PR scoped to release prep; after '
        'merge, release_on_prep_merge.yml pushes the missing companion tag, '
        'waits for publish_companion_pubdev.yml, verifies pub.dev, and only '
        'then pushes the core release tag.',
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
      'Expected all, essential, targeted, platform, or release.',
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
  --tier <tier>          Filter by all, essential, targeted, platform, or release.
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
