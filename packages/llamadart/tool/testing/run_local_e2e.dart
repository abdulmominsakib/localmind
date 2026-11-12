#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Result returned by [runLocalE2e].
class LocalE2eResult {
  const LocalE2eResult(this.exitCode, {this.stdout = '', this.stderr = ''});

  final int exitCode;
  final String stdout;
  final String stderr;
}

enum LocalE2eScenarioGroup {
  dartLocalOnly('Dart local-only'),
  flutterDevice('Flutter device'),
  webSmoke('Web smoke');

  const LocalE2eScenarioGroup(this.label);

  final String label;
}

class LocalE2eCommandStep {
  const LocalE2eCommandStep({
    required this.workingDirectory,
    required this.executable,
    required this.arguments,
    required this.description,
    this.environment = const {},
    this.background = false,
    this.waitForPort,
    this.foregroundStdoutEncoding = systemEncoding,
  });

  final String workingDirectory;
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final String description;
  final bool background;
  final int? waitForPort;

  /// Codec for foreground stdout; controlled Dart protocols can opt into
  /// strict [utf8]. The default retains the platform's output encoding, with
  /// replacement characters for malformed UTF-8 diagnostics.
  final Encoding foregroundStdoutEncoding;

  /// Renders this step as a copy-pasteable command for [shell].
  String toDisplayString({LocalE2eDisplayShell? shell}) {
    return switch (shell ?? LocalE2eDisplayShell.host) {
      LocalE2eDisplayShell.posix => _toPosixDisplayString(),
      LocalE2eDisplayShell.powerShell => _toPowerShellDisplayString(),
    };
  }

  String _toPosixDisplayString() {
    final envPrefix = environment.entries
        .map((entry) => '${entry.key}=${_shellQuote(entry.value)}')
        .join(' ');
    final command = [executable, ...arguments].map(_shellQuote).join(' ');
    final rendered = envPrefix.isEmpty ? command : '$envPrefix $command';
    final suffix = background ? ' &' : '';
    return 'cd ${_shellQuote(workingDirectory)} && $rendered$suffix';
  }

  String _toPowerShellDisplayString() {
    final statements = [
      'Set-Location -LiteralPath ${_powerShellQuote(workingDirectory)}',
      for (final entry in environment.entries)
        '\$env:${entry.key} = ${_powerShellQuote(entry.value)}',
    ];
    if (background) {
      final argumentList = arguments.isEmpty
          ? ''
          : ' -ArgumentList ${arguments.map(_powerShellQuote).join(',')}';
      statements.add(
        'Start-Process -NoNewWindow -FilePath '
        '${_powerShellQuote(executable)}$argumentList',
      );
    } else {
      final quotedExecutable = _powerShellQuote(executable);
      // A quoted string at command position is an expression in PowerShell,
      // so it needs the call operator to run.
      final invocation = quotedExecutable == executable
          ? executable
          : '& $quotedExecutable';
      statements.add(
        [invocation, ...arguments.map(_powerShellQuote)].join(' '),
      );
    }
    return statements.join('; ');
  }
}

/// Shell syntax used when `--dry-run` prints scenario commands.
enum LocalE2eDisplayShell {
  /// POSIX `sh` syntax for macOS and Linux.
  posix,

  /// PowerShell syntax for Windows.
  powerShell;

  /// The shell matching the platform running the tool.
  static LocalE2eDisplayShell get host =>
      Platform.isWindows ? powerShell : posix;
}

class _BackgroundProcess {
  const _BackgroundProcess({
    required this.process,
    required this.stdoutSubscription,
    required this.stderrSubscription,
  });

  final Process process;
  final StreamSubscription<String> stdoutSubscription;
  final StreamSubscription<String> stderrSubscription;
}

class LocalE2eRunContext {
  const LocalE2eRunContext({
    required this.projectRoot,
    required this.device,
    required this.port,
    required this.python,
    required this.modelPath,
    required this.tokenizerPath,
    required this.modelPreset,
    required this.draftModelPath,
    required this.mmprojPath,
    required this.imagePath,
    required this.audioPath,
    required this.headPath,
    required this.configPath,
    required this.modelUrl,
    required this.mmprojUrl,
    required this.backend,
    required this.backendProvided,
    required this.speculativeCases,
    required this.benchmarkGpuLayers,
    required this.benchmarkMaxTokens,
    required this.benchmarkRuns,
    required this.benchmarkWarmups,
    required this.draftTokenMaxList,
    required this.ngramSize,
    required this.browser,
    required this.ngramSizeM,
    required this.ngramTokenMax,
    required this.ngramCacheStaticPath,
    required this.ngramCacheDynamicPath,
    required this.ngramCacheBuildStaticPath,
    required this.ngramCacheBuildText,
    required this.expect,
    required this.expectProvided,
    required this.allowAnyResponse,
    required this.skipBuild,
    Map<String, String>? environment,
  }) : _environment = environment;

  final String projectRoot;
  final String device;
  final int port;
  final String python;
  final String? modelPath;
  final String? tokenizerPath;
  final String modelPreset;
  final String? draftModelPath;
  final String? mmprojPath;
  final String? imagePath;
  final String? audioPath;
  final String? headPath;
  final String? configPath;
  final String? modelUrl;
  final String? mmprojUrl;
  final String backend;
  final bool backendProvided;
  final String speculativeCases;
  final String benchmarkGpuLayers;
  final String benchmarkMaxTokens;
  final String benchmarkRuns;
  final String benchmarkWarmups;
  final String draftTokenMaxList;
  final String? ngramSize;
  final String? browser;
  final String? ngramSizeM;
  final String? ngramTokenMax;
  final String? ngramCacheStaticPath;
  final String? ngramCacheDynamicPath;
  final String? ngramCacheBuildStaticPath;
  final String? ngramCacheBuildText;
  final String expect;
  final bool expectProvided;
  final bool allowAnyResponse;
  final bool skipBuild;
  final Map<String, String>? _environment;

  /// The process environment scenarios read, or what a test injected.
  Map<String, String> get environment => _environment ?? Platform.environment;

  String get chatAppDir => '$projectRoot/example/chat_app';
  String get webBuildUrl =>
      'http://127.0.0.1:$port/example/chat_app/build/web/';
  String get defaultModelUrl =>
      'http://127.0.0.1:$port/example/llamadart_server/models/Qwen3.5-0.8B-Q4_K_M.gguf';
  String get defaultLiteRtLmWebModelUrl =>
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.litertlm?download=true';
  String get defaultGemma4WebGpuModelUrl =>
      'http://127.0.0.1:$port/example/llamadart_server/models/gemma-4-E2B-it-Q4_K_S.gguf';
  String get defaultQwen3AsrWebModelUrl =>
      'https://huggingface.co/ggml-org/Qwen3-ASR-0.6B-GGUF/resolve/928ab958557df9aa2ef1c93e0e83c7ad0933fae2/Qwen3-ASR-0.6B-Q8_0.gguf';
  String get defaultQwen3AsrWebMmprojUrl =>
      'https://huggingface.co/ggml-org/Qwen3-ASR-0.6B-GGUF/resolve/928ab958557df9aa2ef1c93e0e83c7ad0933fae2/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf';
  String get defaultQwen3TtsWebModelUrl =>
      'https://huggingface.co/ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF/resolve/ca27d74bc954b73dadab5b71ca265d87fc861a7c/Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf';
  String get defaultQwen3TtsWebMmprojUrl =>
      'https://huggingface.co/ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF/resolve/ca27d74bc954b73dadab5b71ca265d87fc861a7c/mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf';
}

class LocalE2eScenario {
  const LocalE2eScenario({
    required this.name,
    required this.group,
    required this.description,
    required this.requiresDevice,
    required this.stepsBuilder,
  });

  final String name;
  final LocalE2eScenarioGroup group;
  final String description;
  final bool requiresDevice;
  final List<LocalE2eCommandStep> Function(LocalE2eRunContext context)
  stepsBuilder;

  List<LocalE2eCommandStep> steps(LocalE2eRunContext context) {
    final steps = stepsBuilder(context);
    if (group != LocalE2eScenarioGroup.flutterDevice ||
        !requiresDevice ||
        context.device != 'macos') {
      return steps;
    }
    return [
      for (final step in steps)
        step.executable == 'flutter' ? _withoutAppNap(step, context) : step,
    ];
  }
}

const String _chatAppMacOsBundleId = 'com.example.llamaDartChatExample';

/// Runs [step] with App Nap disabled for the chat app: the test app is often
/// not foregrounded, and a napped app on a busy host can miss startup
/// deadlines (#1674).
LocalE2eCommandStep _withoutAppNap(
  LocalE2eCommandStep step,
  LocalE2eRunContext context,
) => LocalE2eCommandStep(
  workingDirectory: step.workingDirectory,
  executable: '${context.projectRoot}/tool/testing/without_app_nap.sh',
  arguments: [_chatAppMacOsBundleId, step.executable, ...step.arguments],
  environment: step.environment,
  description: step.description,
  background: step.background,
  waitForPort: step.waitForPort,
  foregroundStdoutEncoding: step.foregroundStdoutEncoding,
);

LocalE2eCommandStep _prepareValidationPackage(LocalE2eRunContext context) =>
    LocalE2eCommandStep(
      workingDirectory: '${context.projectRoot}/packages/llamadart_validation',
      executable: 'dart',
      arguments: const ['pub', 'get'],
      description: 'Prepare private suite',
    );

List<LocalE2eCommandStep> _webRealModelSmokeSteps(
  LocalE2eRunContext context,
  List<String> extraSmokeArguments,
) {
  return [
    _prepareChatAppWebBuild(context),
    LocalE2eCommandStep(
      workingDirectory: context.projectRoot,
      executable: context.python,
      arguments: [
        'tool/testing/serve_static_with_headers.py',
        '--directory',
        '.',
        '--port',
        '${context.port}',
      ],
      description: 'Serve repo root with COOP/COEP headers',
      background: true,
      waitForPort: context.port,
    ),
    LocalE2eCommandStep(
      workingDirectory: context.projectRoot,
      executable: context.python,
      arguments: [
        'tool/testing/playwright_chat_app_real_model_smoke.py',
        context.webBuildUrl,
        '--model-url',
        context.modelUrl ?? context.defaultModelUrl,
        '--expect',
        context.expect,
        if (context.allowAnyResponse) '--allow-any-response',
        ...extraSmokeArguments,
      ],
      description: 'Run Playwright real-model chat app smoke',
    ),
  ];
}

LocalE2eCommandStep _prepareChatAppWebBuild(LocalE2eRunContext context) =>
    LocalE2eCommandStep(
      workingDirectory: context.projectRoot,
      executable: 'bash',
      arguments: [
        context.skipBuild
            ? 'scripts/validate_chat_app_web_build.sh'
            : 'scripts/build_chat_app_web.sh',
      ],
      environment: context.skipBuild
          ? const {}
          : const {'CHAT_APP_BASE_HREF': '/example/chat_app/build/web/'},
      description: context.skipBuild
          ? 'Validate existing Flutter web chat app build'
          : 'Build and validate Flutter web chat app',
    );

/// The FLUX.1 Kontext component paths `image-reference-editing` reads.
const List<String> _referenceEditComponentVariables = [
  'LLAMADART_REFERENCE_EDIT_VAE',
  'LLAMADART_REFERENCE_EDIT_CLIP_L',
  'LLAMADART_REFERENCE_EDIT_T5XXL',
];

List<LocalE2eScenario> buildLocalE2eScenarios({String? projectRoot}) {
  return [
    LocalE2eScenario(
      name: 'native-default-consumer-aot',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Explicit macOS/Windows default-hook consumer and distributed AOT qualification; native v0.8.0-2 is pipeline-only.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'test/fixtures/native_default_consumer_qualification/qualify.py',
            '--core-root',
            context.projectRoot,
            '--expected-core-sha',
            context.environment['LLAMADART_DEFAULT_AOT_EXPECTED_SHA'] ??
                '<LLAMADART_DEFAULT_AOT_EXPECTED_SHA>',
            '--expected-native-tag',
            context.environment['LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG'] ??
                '<LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG>',
            '--model',
            context.environment['LLAMADART_DEFAULT_AOT_MODEL_PATH'] ??
                '<LLAMADART_DEFAULT_AOT_MODEL_PATH>',
            '--output',
            context.environment['LLAMADART_DEFAULT_AOT_OUTPUT_ROOT'] ??
                '<LLAMADART_DEFAULT_AOT_OUTPUT_ROOT>',
          ],
          environment: const {'PYTHONDONTWRITEBYTECODE': '1'},
          description:
              'Run the maintained real consumer/provider/AOT driver; expected tag verifies the source pin and never overrides it.',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'windows-native-override-registry',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Pinned Windows x64 CPU H/E/P registry matrix, declaration mutation and distributed AOT evidence.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            '-j',
            '1',
            '--run-skipped',
            '-t',
            'local-only',
            'test/integration/windows_ggml_registry_qualification_test.dart',
          ],
          description:
              'Run the Windows-only model-backed qualification; set LLAMADART_WINDOWS_QUALIFICATION to a fresh evidence root.',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'ci-selection',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'CI trigger selection and aggregate workflow wiring contracts.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: Platform.isWindows ? 'python' : 'python3',
          arguments: const [
            '-m',
            'unittest',
            'discover',
            '-s',
            'test/ci',
            '-p',
            'test_*.py',
          ],
          description:
              'Git change inventory, dependency selection and aggregate behavior',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            'test/unit/tooling/ci_workflow_selection_test.dart',
          ],
          description: 'Actual workflow target, event and aggregate wiring',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'android-perfetto-capability',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Build model-free Android trace probe and run evidence negatives; no cloud run.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: const [
            '-m',
            'unittest',
            'discover',
            '-s',
            'tool/testing/validation/android_perfetto',
            '-p',
            'test_*.py',
          ],
          description: 'Trace receipt, producer and CPU/idle control negatives',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: Platform.environment['GRADLE_BIN'] ?? 'gradle',
          arguments: const [
            '--offline',
            '--no-daemon',
            '-p',
            'tool/testing/validation/android_perfetto',
            'app:testDebugUnitTest',
            'app:assembleDebug',
            'app:assembleDebugAndroidTest',
          ],
          description: 'Cached SDK model-free app/test APK build',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'validation-harness',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Model-free validation runner, bundle and provider lifecycle checks.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        _prepareValidationPackage(context),
        LocalE2eCommandStep(
          workingDirectory:
              '${context.projectRoot}/packages/llamadart_validation',
          executable: 'dart',
          arguments: const ['test'],
          description: 'Shared suite regressions',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            'test/unit/tooling/validation_remote_test.dart',
            'test/unit/tooling/validation_image_profile_test.dart',
            'test/unit/tooling/validation_embedding_profile_test.dart',
            'test/unit/tooling/validation_npu_test.dart',
          ],
          description:
              'Provider safety, bundle identity, image grading and NPU input checks',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: Platform.isWindows ? 'python' : 'python3',
          arguments: const [
            '-m',
            'unittest',
            'discover',
            '-s',
            'tool/testing/validation',
            '-p',
            'test_npu_apk.py',
          ],
          description: 'Embedded NPU model/library integrity checks',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'root-template-e2e',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description: 'Run local-only upstream/template parity E2E tests.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/template/llama_cpp_chat_tests_e2e_test.dart',
          ],
          description: 'Upstream llama.cpp chat tests (builds the validator)',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'bash',
          arguments: const [
            'tool/testing/build_llama_cpp_runtime_gbnf_validator.sh',
          ],
          description: 'GBNF validator for the shipped llama.cpp runtime',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/template/specialized_tool_grammar_validation_e2e_test.dart',
          ],
          environment: {
            'LLAMA_CPP_GBNF_VALIDATOR':
                '${Platform.environment['LLAMA_CPP_RUNTIME_BUILD_DIR'] ?? '${context.projectRoot}/.dart_tool/llama_cpp_runtime_build'}'
                '/bin/test-gbnf-validator',
          },
          description: 'Compiled tool-grammar acceptance',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/template/lfm2_quoted_tool_delimiter_e2e_test.dart',
          ],
          description: 'LFM2 quoted delimiter with existing affected weights',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/template/lfm2_schema_qualification_e2e_test.dart',
          ],
          description: 'LFM2 schema parsing with existing affected weights',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'qwen35-multimodal-macos-repro',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run the macOS-only Qwen3.5 multimodal native repro harness.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/tooling/qwen35_multimodal_macos_repro_e2e_test.dart',
          ],
          description: 'Qwen3.5 multimodal macOS repro E2E',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'gguf-stop-sequences',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description: 'Verify public GGUF caller stop suppression and recovery.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            '--run-skipped',
            'test/e2e/backends/gguf_stop_sequences_e2e_test.dart',
          ],
          environment: {
            if (context.modelPath != null)
              'GGUF_STOP_MODEL': context.modelPath!,
            if (context.backendProvided) 'GGUF_STOP_BACKEND': context.backend,
          },
          description: 'GGUF public stop-sequence regression',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'tool-result-image-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify image tool results on a real vision GGUF: tool-turn photos '
          'reach the next model turn through native llama.cpp.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/backends/tool_result_media_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_TOOL_MEDIA_MODEL': context.modelPath!,
            'LLAMADART_TOOL_MEDIA_MMPROJ': context.mmprojPath!,
            if (context.backendProvided)
              'LLAMADART_TOOL_MEDIA_BACKEND': context.backend,
            'LLAMADART_TOOL_MEDIA_CHAT_TEMPLATE':
                ?context.environment['LLAMADART_TOOL_MEDIA_CHAT_TEMPLATE'],
          },
          description: 'Tool-result image E2E',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'native-prompt-cancel',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Cancel native GGUF generations during a ~1,600-token prompt and '
          'report cancel latency.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-p',
            'vm',
            '-j',
            '1',
            '-t',
            'local-only',
            'test/e2e/backends/prompt_cancel_e2e_test.dart',
          ],
          environment: {
            'PROMPT_CANCEL_MODEL': context.modelPath!,
            'PROMPT_CANCEL_BACKEND': context.backend,
          },
          description: 'Native prompt-evaluation cancel',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'native-exit-teardown',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Check macOS Metal exit teardown and Linux cooperative worker '
          'shutdown before C exit.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-p',
            'vm',
            '-j',
            '1',
            '-t',
            'local-only',
            'test/e2e/backends/llama_cpp_exit_teardown_e2e_test.dart',
          ],
          environment: {
            'EXIT_TEARDOWN_MODEL': context.modelPath!,
            if (Platform.isLinux) 'EXIT_TEARDOWN_BACKEND': context.backend,
          },
          description: 'Native exit teardown',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'gguf-chat-features-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run real GGUF chat, thinking-budget/suppression, tool-call, and optional image path/bytes smoke.',
      requiresDevice: false,
      stepsBuilder: (context) {
        final arguments = <String>['run', 'tool/gguf_chat_features_smoke.dart'];
        if (context.modelPath != null) {
          arguments.add(context.modelPath!);
          arguments.add(context.backend);
          if (context.mmprojPath != null) {
            arguments.add(context.mmprojPath!);
          }
          if (context.imagePath != null) {
            arguments.add(context.imagePath!);
          }
        }
        return [
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: 'dart',
            arguments: arguments,
            environment: const {
              'GGUF_AUDIO_PATH': '',
              'GGUF_AUDIO_EXPECTED_TEXT': '',
            },
            description: 'GGUF chat feature smoke',
          ),
        ];
      },
    ),
    LocalE2eScenario(
      name: 'gguf-audio-chat-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run exact-answer byte-backed audio chat through native llama.cpp.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: [
            'run',
            'tool/gguf_chat_features_smoke.dart',
            context.modelPath!,
            context.backend,
            context.mmprojPath!,
          ],
          environment: {
            'GGUF_AUDIO_PATH': context.audioPath!,
            'GGUF_AUDIO_EXPECTED_TEXT': context.expect,
          },
          description: 'GGUF exact-answer audio chat smoke',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'validation-voice-round-trip',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description: 'Locked file STT -> Gemma 4 CPU -> TTS WAV round trip.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        _prepareValidationPackage(context),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: [
            'run',
            'tool/testing/validation.dart',
            'voice',
            '--out',
            '${context.projectRoot}/.dart_tool/validation/runs/voice-${DateTime.now().microsecondsSinceEpoch}',
            if (context.modelPath != null) ...[
              '--chat-model',
              context.modelPath!,
            ],
          ],
          description:
              'Voice pipeline; physical microphone/playback remains separate.',
        ),
      ],
    ),
    for (final pack in ['stt', 'tts', 'litert-asr'])
      LocalE2eScenario(
        name: 'validation-speech-$pack',
        group: LocalE2eScenarioGroup.dartLocalOnly,
        description:
            'Locked GGUF $pack pack with lifecycle and speech metrics.',
        requiresDevice: false,
        stepsBuilder: (context) => [
          _prepareValidationPackage(context),
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: 'dart',
            arguments: [
              'run',
              'tool/testing/validation.dart',
              'speech',
              '--pack',
              pack,
              '--backend',
              'cpu',
              '--out',
              '${context.projectRoot}/.dart_tool/validation/runs/$pack-${DateTime.now().microsecondsSinceEpoch}',
              if (context.modelPath != null) ...['--model', context.modelPath!],
              if (pack == 'litert-asr' && context.tokenizerPath != null) ...[
                '--tokenizer',
                context.tokenizerPath!,
              ],
              if (pack != 'litert-asr' && context.mmprojPath != null) ...[
                '--projector',
                context.mmprojPath!,
              ],
            ],
            description:
                'Run $pack with verified model/projector inputs; no cloud resources.',
          ),
        ],
      ),
    LocalE2eScenario(
      name: 'speech-to-text-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run typed native Qwen3-ASR file/bytes transcription, cancellation and recovery against a known fixture.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/backends/speech_to_text_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_STT_MODEL_PATH': context.modelPath!,
            'LLAMADART_STT_MMPROJ_PATH': context.mmprojPath!,
            'LLAMADART_STT_AUDIO_PATH': context.audioPath!,
            if (context.expectProvided)
              'LLAMADART_STT_EXPECTED_TEXT': context.expect,
          },
          description: 'Typed speech-to-text real-model smoke',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-asr-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run the public dedicated LiteRT-LM speech engine against a known PCM16 fixture.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: [
            'run',
            'tool/litert_lm_asr_smoke.dart',
            context.modelPath!,
            context.tokenizerPath!,
            context.audioPath!,
            context.modelPreset,
            context.expect,
          ],
          description: 'Public LiteRT-LM speech engine real-model smoke',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-asr-preservation',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Preserve hash-bound Whisper Tiny CPU transcription, silence, cancellation and reuse through the public engine.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            '-j',
            '1',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/backends/litert_lm_asr_preservation_e2e_test.dart',
          ],
          environment: {
            'LITERT_LM_ASR_MODEL': context.modelPath!,
            'LITERT_LM_ASR_TOKENIZER': context.tokenizerPath!,
            'LITERT_LM_ASR_AUDIO': context.audioPath!,
          },
          description: 'Public CPU ASR preservation with fixed fixture hashes',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-v1-asr-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify exact v1 ASR inputs through the injected public speech probe and worker with an owned process deadline.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: [
            'run',
            'test/fixtures/litert_lm_v1_asr_qualification.dart',
            context.environment['LITERT_LM_V1_LIBRARY']!,
            context.environment['LITERT_LM_V1_LIBRARY_SHA256']!.toLowerCase(),
            context.modelPath!,
            context.environment['LITERT_LM_V1_MODEL_SHA256']!.toLowerCase(),
            context.tokenizerPath!,
            context.environment['LITERT_LM_V1_TOKENIZER_SHA256']!.toLowerCase(),
            context.audioPath!,
            context.environment['LITERT_LM_V1_AUDIO_SHA256']!.toLowerCase(),
            context.modelPreset,
            context.expect,
          ],
          description:
              'Bounded injected v1 CPU ASR stream/task/cancellation qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'text-to-speech-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run typed native Qwen3-TTS synthesis and write a playable WAV.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/backends/text_to_speech_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_TTS_MODEL_PATH': context.modelPath!,
            'LLAMADART_TTS_MMPROJ_PATH': context.mmprojPath!,
            'LLAMADART_TTS_OUTPUT_PATH':
                '${context.projectRoot}/build/text-to-speech-smoke.wav',
          },
          description: 'Typed text-to-speech real-model smoke',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'text-to-speech-models-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run typed native LFM3-Audio, Soprano, Chatterbox and Pocket TTS '
          'synthesis with voices, speaker references, languages, '
          'refusals, seed repeats and an ASR round trip, for each model whose '
          'LLAMADART_TTS_<MODEL>_MODEL_PATH and _MMPROJ_PATH are set.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            '-j',
            '1',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/backends/text_to_speech_models_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_TTS_OUTPUT_DIR':
                '${context.projectRoot}/build/text-to-speech-models',
          },
          description: 'Typed text-to-speech model family smoke',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'image-generation-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run experimental ImageGenerationEngine on SDXS through the opt-in '
          'stable_diffusion runtime, including CPU/automatic-device '
          'conditioning-cache parity, hits, eviction, cancellation/reuse and '
          'reload; SD-Turbo with and without VAE tiling when '
          'LLAMADART_SD_TURBO_MODEL is set, SDXL-Lightning when '
          'LLAMADART_SDXL_LIGHTNING_MODEL is set, and SDXS from its pinned '
          'Hugging Face file when LLAMADART_IMAGE_HF_CACHE '
          'names a model cache directory, and a split model from files in '
          'any order when LLAMADART_IMAGE_SPLIT_MODEL lists them.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: '${context.projectRoot}/example/basic_app',
          executable: 'dart',
          arguments: const [
            'test',
            '--configuration',
            'test/image_generation_smoke.yaml',
            '-t',
            'local-only',
            'test/image_generation_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_SDXS_MODEL': context.modelPath!,
            'LLAMADART_IMAGE_OUTPUT_DIR':
                '${context.projectRoot}/build/image-generation-smoke',
          },
          description: 'Image generation real-model smoke',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'image-container-formats',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Compare complete byte-equivalent SD-Turbo checkpoint containers '
          'through automatic/explicit public roles against direct-C CPU RGB; '
          '--model-path names the hashed local model-set manifest and '
          'LLAMADART_IMAGE_CONTAINER_REFERENCES names independent PPM files.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: '${context.projectRoot}/example/basic_app',
          executable: 'dart',
          arguments: const [
            'test',
            '--configuration',
            'test/image_generation_smoke.yaml',
            '-t',
            'local-only',
            'test/image_generation_e2e_test.dart',
            '--name',
            r'^checkpoint containers preserve CPU pixels$',
          ],
          environment: {
            'LLAMADART_IMAGE_CONTAINER_SET': context.modelPath!,
            'LLAMADART_IMAGE_OUTPUT_DIR':
                '${context.projectRoot}/build/image-container-formats',
          },
          description: 'Complete image checkpoint container parity on CPU',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'image-original-containers',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run the six hash-bound original SD24 native/public diagnostic cases '
          'with external TAESD, cache4 and diffusion flash attention; '
          '--model-path is the independently admitted local plan.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'packages/llamadart_validation/native/sd_original_mode/run.py',
            '--plan',
            context.modelPath!,
            '--out',
            '${context.projectRoot}/build/image-original-containers',
            '--execute',
          ],
          description:
              'Bounded original-mode diagnostic, not release qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'image-seamless-textures',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify the bounded SDXS 512-square circular texture recipe: '
          'CPU and actual Metal, X/Y seam quality, repeat PNGs, off-after-on, '
          'cancellation/reuse and optional exact native-reference pixels.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: '${context.projectRoot}/example/basic_app',
          executable: 'dart',
          arguments: const [
            'test',
            '--configuration',
            'test/image_generation_smoke.yaml',
            '-t',
            'local-only',
            'test/image_seamless_textures_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_SDXS_MODEL': context.modelPath!,
            'LLAMADART_IMAGE_OUTPUT_DIR':
                '${context.projectRoot}/build/image-seamless-textures',
          },
          description: 'SDXS circular axes and decoder quality qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'image-local-checkpoint-sets',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify the bounded complete SD-Turbo F16/F32 local index/directory recipe on macOS CPU, owned snapshots, aggregate accounting, cache reuse, source-removal lifetime, cancellation and reference parity.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'example/basic_app/test/fixtures/split_local_checkpoint.py',
            context.modelPath!,
            '${context.projectRoot}/build/local-image-set-fixture',
          ],
          description:
              'Build the owned, content-verified two-shard qualification fixture',
        ),
        LocalE2eCommandStep(
          workingDirectory: '${context.projectRoot}/example/basic_app',
          executable: 'dart',
          arguments: const [
            'test',
            '--configuration',
            'test/image_generation_smoke.yaml',
            '-t',
            'local-only',
            'test/local_image_set_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_LOCAL_SET_FIXTURES':
                '${context.projectRoot}/build/local-image-set-fixture',
            'LLAMADART_IMAGE_OUTPUT_DIR':
                '${context.projectRoot}/build/local-image-sets',
          },
          description:
              'Public complete-checkpoint directory/index qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'image-editing',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify SD-Turbo embedded full-VAE macOS CPU RGB inputs, binary masks, strength, direct-C parity, cancellation and reset.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: '${context.projectRoot}/example/basic_app',
          executable: 'dart',
          arguments: const [
            'test',
            '--configuration',
            'test/image_generation_smoke.yaml',
            '-t',
            'local-only',
            'test/image_editing_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_SD_TURBO_MODEL': context.modelPath!,
            'LLAMADART_IMAGE_OUTPUT_DIR':
                '${context.projectRoot}/build/image-editing',
          },
          description: 'Bounded image-editing CPU qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'image-controlnet',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify an SD 1.x checkpoint plus original-layout SD 1.x ControlNet '
          'on macOS CPU: control image and strength effects, strength-0 and '
          'reset equivalence, direct-C parity, cancellation and reload; '
          'LLAMADART_SD15_CONTROLNET names the ControlNet.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: '${context.projectRoot}/example/basic_app',
          executable: 'dart',
          arguments: const [
            'test',
            '--configuration',
            'test/image_generation_smoke.yaml',
            '-t',
            'local-only',
            'test/image_controlnet_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_SD15_MODEL': context.modelPath!,
            'LLAMADART_IMAGE_OUTPUT_DIR':
                '${context.projectRoot}/build/image-controlnet',
          },
          description: 'Bounded SD 1.x ControlNet CPU qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'image-hires-fix',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify the bounded two-pass hires fix with an SD 1.x or SD 2.x '
          'full-VAE checkpoint on macOS CPU or Metal: final size, direct-C '
          'parity, one-pass reset, composition, second-pass cancellation and '
          'reload; LLAMADART_HIRES_RECIPE (sd15, turbo) and '
          'LLAMADART_HIRES_DEVICE (cpu, gpu) pick the recipe and device.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: '${context.projectRoot}/example/basic_app',
          executable: 'dart',
          arguments: const [
            'test',
            '--configuration',
            'test/image_generation_smoke.yaml',
            '-t',
            'local-only',
            'test/image_hires_fix_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_HIRES_MODEL': context.modelPath!,
            'LLAMADART_HIRES_RECIPE':
                context.environment['LLAMADART_HIRES_RECIPE'] ?? 'sd15',
            'LLAMADART_HIRES_DEVICE':
                context.environment['LLAMADART_HIRES_DEVICE'] ?? 'cpu',
            'LLAMADART_IMAGE_OUTPUT_DIR':
                '${context.projectRoot}/build/image-hires-fix',
          },
          description: 'Bounded hires-fix qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'image-reference-editing',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify FLUX.1 Kontext [dev] reference image editing on macOS '
          'Metal: visible edit, preserved content, reference effect, direct-C '
          'parity, cancellation and reload; --model-path is the transformer '
          'and LLAMADART_REFERENCE_EDIT_VAE, _CLIP_L and _T5XXL its '
          'components.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: '${context.projectRoot}/example/basic_app',
          executable: 'dart',
          arguments: const [
            'test',
            '--configuration',
            'test/image_generation_smoke.yaml',
            '-t',
            'local-only',
            'test/image_reference_editing_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_REFERENCE_EDIT_DIFFUSION': context.modelPath!,
            for (final name in _referenceEditComponentVariables)
              name: context.environment[name]!,
            'LLAMADART_IMAGE_OUTPUT_DIR':
                '${context.projectRoot}/build/image-reference-editing',
          },
          description: 'FLUX.1 Kontext reference-editing qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'image-exit-teardown',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Check macOS Metal image exit teardown and Linux cooperative '
          'worker shutdown; compare image batch progress events.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: '${context.projectRoot}/example/basic_app',
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'test/image_exit_teardown_e2e_test.dart',
          ],
          environment: {
            'IMAGE_EXIT_MODEL': context.modelPath!,
            if (Platform.isLinux) 'IMAGE_EXIT_BACKEND': context.backend,
            if (Platform.isLinux) 'IMAGE_EXIT_CHAT_BACKEND': context.backend,
          },
          description: 'Image model exit teardown',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'decision-model-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run the Laya parity fixture through a real ModernBERT GGUF and '
          'decision head: exact token ids, raw logits and answers.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/backends/decision_engine_e2e_test.dart',
          ],
          environment: {
            'LLAMADART_DECISION_MODEL_PATH': context.modelPath!,
            'LLAMADART_DECISION_HEAD_PATH': context.headPath!,
            if (context.configPath != null)
              'LLAMADART_DECISION_CONFIG_PATH': context.configPath!,
            if (context.backendProvided)
              'LLAMADART_DECISION_BACKEND': context.backend,
          },
          description: 'Decision model real-model parity smoke',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'decision-model-web-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Run the Laya parity fixture on Web through LlamaBackend and the '
          'pinned WebGPU bridge: exact token ids, raw logits and answers.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'bash',
          arguments: const ['scripts/fetch_webgpu_bridge_assets.sh'],
          environment: {
            'WEBGPU_BRIDGE_OUT_DIR':
                '${context.projectRoot}/build/decision_web_e2e/bridge',
          },
          description: 'Fetch pinned WebGPU bridge assets for the test server',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'chrome-webgpu',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/backends/decision_engine_web_e2e_test.dart',
          ],
          description: 'Web decision model real-model parity smoke',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'web-lazy-grammar',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Check pinned-asset lazy grammar activation, custom roots and '
          'typed rejection/reuse in direct and worker CPU Wasm runtimes.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'bash',
          arguments: const ['scripts/fetch_webgpu_bridge_assets.sh'],
          environment: {
            'WEBGPU_BRIDGE_OUT_DIR':
                '${context.projectRoot}/build/web_lazy_grammar/bridge',
          },
          description: 'Fetch pinned WebGPU bridge assets for the test server',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'chrome-webgpu',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/webgpu/lazy_grammar_e2e_test.dart',
            'test/e2e/webgpu/prompt_penalty_grammar_e2e_test.dart',
          ],
          description: 'Web lazy grammar, prompt penalties and error recovery',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'web-speech-task-cancel',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Check real STT/TTS task cancellation isolation and engine reuse '
          'through the direct and worker paths of the pinned WebGPU bridge.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'bash',
          arguments: const ['scripts/fetch_webgpu_bridge_assets.sh'],
          environment: {
            'WEBGPU_BRIDGE_OUT_DIR':
                '${context.projectRoot}/build/web_speech_task_cancel/bridge',
          },
          description: 'Fetch pinned WebGPU bridge assets for the test server',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'chrome-webgpu',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/webgpu/speech_task_cancellation_e2e_test.dart',
          ],
          description: 'Web speech task cancellation isolation and reuse',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'llama-cpp-speculative-benchmark',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Benchmark real GGUF llama.cpp speculative decoding strategies.',
      requiresDevice: false,
      stepsBuilder: (context) {
        final arguments = <String>[
          'run',
          'tool/testing/llama_cpp_speculative_benchmark.dart',
          '--model',
          context.modelPath!,
          '--cases',
          context.speculativeCases,
          '--backend',
          context.backend,
          '--gpu-layers',
          context.benchmarkGpuLayers,
          '--max-tokens',
          context.benchmarkMaxTokens,
          '--runs',
          context.benchmarkRuns,
          '--draft-token-max',
          context.draftTokenMaxList,
          '--warmups',
          context.benchmarkWarmups,
        ];
        final draftModelPath = context.draftModelPath;
        if (draftModelPath != null) {
          arguments.addAll(['--draft-model', draftModelPath]);
        }
        final ngramSize = context.ngramSize;
        if (ngramSize != null) {
          arguments.addAll(['--ngram-size', ngramSize]);
        }
        final ngramSizeM = context.ngramSizeM;
        if (ngramSizeM != null) {
          arguments.addAll(['--ngram-size-m', ngramSizeM]);
        }
        final ngramTokenMax = context.ngramTokenMax;
        if (ngramTokenMax != null) {
          arguments.addAll(['--ngram-token-max', ngramTokenMax]);
        }
        final ngramCacheStaticPath = context.ngramCacheStaticPath;
        if (ngramCacheStaticPath != null) {
          arguments.addAll(['--ngram-cache-static-path', ngramCacheStaticPath]);
        }
        final ngramCacheDynamicPath = context.ngramCacheDynamicPath;
        if (ngramCacheDynamicPath != null) {
          arguments.addAll([
            '--ngram-cache-dynamic-path',
            ngramCacheDynamicPath,
          ]);
        }
        final ngramCacheBuildStaticPath = context.ngramCacheBuildStaticPath;
        if (ngramCacheBuildStaticPath != null) {
          arguments.addAll([
            '--ngram-cache-build-static-path',
            ngramCacheBuildStaticPath,
          ]);
        }
        final ngramCacheBuildText = context.ngramCacheBuildText;
        if (ngramCacheBuildText != null) {
          arguments.addAll(['--ngram-cache-build-text', ngramCacheBuildText]);
        }
        return [
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: 'dart',
            arguments: arguments,
            description: 'llama.cpp speculative benchmark',
          ),
        ];
      },
    ),
    LocalE2eScenario(
      name: 'gemma4-mtp-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Smoke-test Gemma 4 bundled MTP speculative decoding against a real '
          'GGUF model.',
      requiresDevice: false,
      stepsBuilder: (context) {
        return [
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: 'dart',
            arguments: <String>[
              'run',
              'tool/testing/gemma4_mtp_smoke.dart',
              context.modelPath!,
              context.draftModelPath ?? '-',
              context.benchmarkMaxTokens,
              context.draftTokenMaxList.split(',').first,
            ],
            description: 'Gemma 4 MTP smoke',
          ),
        ];
      },
    ),
    LocalE2eScenario(
      name: 'web-multimodal-embeddings',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify direct/worker Web media embeddings against local native reference vectors; no downloads. See doc/multimodal_embeddings_web.md.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'chrome',
            '--run-skipped',
            '--tags',
            'local-only',
            'test/e2e/backends/multimodal_embedding_web_e2e_test.dart',
          ],
          description:
              'Web media embedding reference qualification (local assets/weights required)',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'native-multimodal-embeddings',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify EmbeddingGemma-2 mixed image/audio/text vectors against the pinned native reference (environment supplies local weights and reference JSON).',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            '-j',
            '1',
            '--run-skipped',
            '--tags',
            'local-only',
            'test/e2e/backends/multimodal_embedding_native_e2e_test.dart',
          ],
          description:
              'Native CPU/Metal multimodal embedding qualification; no downloads',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'native-reranking',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify native reranking against pinned upstream full-class and server oracles with local Qwen3/Jina weights; see doc/native_reranking.md.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            '-j',
            '1',
            '--run-skipped',
            '--tags',
            'local-only',
            'test/e2e/backends/native_reranking_e2e_test.dart',
          ],
          description:
              'Native reranking CPU/Metal reference qualification; no downloads',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'text-embedding-retrieval',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Compare EmbeddingGemma-2 text helpers at 768/512/256/128 dimensions with the official float32 CPU reference; no downloads. See doc/embedding_text_helpers.md.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            '-j',
            '1',
            '--tags',
            'local-only',
            '--run-skipped',
            'test/e2e/backends/embeddinggemma2_retrieval_e2e_test.dart',
          ],
          description: 'Official EG2 text retrieval reference qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'native-embedding-benchmark',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Compare sequential embedding calls against embedBatch throughput on '
          'a real GGUF model.',
      requiresDevice: false,
      stepsBuilder: (context) {
        return [
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: 'dart',
            arguments: <String>[
              'run',
              'tool/testing/native_embedding_benchmark.dart',
              '--model',
              context.modelPath!,
              '--mode',
              'both',
              '--input-count',
              '8',
              '--max-seq',
              '8',
              '--runs',
              context.benchmarkRuns,
              '--warmup',
              context.benchmarkWarmups,
              '--gpu-layers',
              context.benchmarkGpuLayers,
            ],
            description: 'Native embedding sequential vs batch benchmark',
          ),
        ];
      },
    ),
    LocalE2eScenario(
      name: 'native-embedding-sweep',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Sweep max-seq values and emit a CSV embedding speedup report.',
      requiresDevice: false,
      stepsBuilder: (context) {
        return [
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: 'dart',
            arguments: <String>[
              'run',
              'tool/testing/native_embedding_sweep.dart',
              '--model',
              context.modelPath!,
              '--max-seq-values',
              '1,2,4,8',
              '--runs',
              context.benchmarkRuns,
              '--warmup',
              context.benchmarkWarmups,
              '--gpu-layers',
              context.benchmarkGpuLayers,
              '--csv-out',
              '${context.projectRoot}/build/embedding_speedup_sweep.csv',
            ],
            description: 'Native embedding max-seq sweep',
          ),
        ];
      },
    ),
    LocalE2eScenario(
      name: 'llama-cpp-chat-template-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run real GGUF llama.cpp direct backend chat-template smoke.',
      requiresDevice: false,
      stepsBuilder: (context) {
        final environment = <String, String>{};
        final modelPath = context.modelPath;
        if (modelPath != null) {
          environment['LLAMADART_LLAMA_CPP_TEMPLATE_MODEL_PATH'] = modelPath;
        }
        return [
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: 'dart',
            arguments: const [
              'test',
              '--run-skipped',
              '-t',
              'local-only',
              'test/e2e/backends/llama_cpp_chat_template_backend_e2e_test.dart',
            ],
            environment: environment,
            description: 'llama.cpp chat-template backend smoke',
          ),
        ];
      },
    ),
    LocalE2eScenario(
      name: 'litert-lm-web-text-history',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Compare ordered Web text history/system prompts with pinned JS and bypass controls using an existing local model.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'tool/testing/litert_text_history_web_e2e.py',
            '--model-path',
            context.modelPath!,
            '--backend',
            context.backend,
            if (context.browser case final browser?) ...['--browser', browser],
          ],
          description:
              'LiteRT Web text history, direct-runtime controls, reset and cancellation (local port 5198)',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-web-tool-calling',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Compare Web manual tool calls and tool results with pinned JS and a no-tools control using an existing local model.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'tool/testing/litert_text_history_web_e2e.py',
            '--model-path',
            context.modelPath!,
            '--backend',
            context.backend,
            '--suite',
            'tool-calling',
          ],
          description:
              'LiteRT Web manual tool calls, results, direct-runtime controls, cancellation and reset (local port 5198)',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-web-truncation',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Compare Web token-limit reports and automatic tool loops with the pinned JS runtime token counts using an existing local model.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'tool/testing/litert_text_history_web_e2e.py',
            '--model-path',
            context.modelPath!,
            '--backend',
            context.backend,
            '--suite',
            'truncation',
          ],
          description:
              'LiteRT Web maxTokens boundary, context fill and automatic tool loops against direct-runtime token counts (local port 5198)',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-multimodal-embedding',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify embedding-only LiteRT-LM text, image, audio, mixed inputs and batch order.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-p',
            'vm',
            '-j',
            '1',
            '-t',
            'local-only',
            'test/e2e/backends/multimodal_embedding_litert_e2e_test.dart',
          ],
          environment: {
            'LITERT_LM_EMBEDDING_MODEL': context.modelPath!,
            'LITERT_LM_EMBEDDING_BACKEND': context.backend,
          },
          description: 'LiteRT-LM multimodal embedding qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-utility-preservation',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify hash-pinned Qwen3 CPU public tokenizer, native benchmark metrics and client reuse; no downloads.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-p',
            'vm',
            '-j',
            '1',
            '-t',
            'local-only',
            'test/e2e/backends/litert_lm_utility_preservation_e2e_test.dart',
          ],
          environment: {'LITERT_LM_UTILITY_MODEL': context.modelPath!},
          description: 'Qwen3 CPU tokenizer and benchmark utility preservation',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-media-preservation',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify hash-pinned Qwen3.5 CPU image path/bytes, history, cancellation and reload; no downloads.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-p',
            'vm',
            '-j',
            '1',
            '-t',
            'local-only',
            'test/e2e/backends/litert_lm_media_preservation_e2e_test.dart',
          ],
          environment: {'LITERT_LM_VISION_MODEL': context.modelPath!},
          description: 'Qwen3.5 CPU generative image preservation',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-lifecycle',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Verify real LiteRT-LM reload, recovery, and timed-out cleanup in bounded child processes.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-p',
            'vm',
            '-j',
            '1',
            '-t',
            'local-only',
            'test/e2e/backends/litert_lm_lifecycle_e2e_test.dart',
          ],
          environment: {
            'LITERT_LM_MODEL': context.modelPath!,
            'LITERT_LM_BACKEND': context.backend,
          },
          description: 'LiteRT-LM lifecycle and process cleanup',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-v1-service',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify exact v1 library/model bytes through injected CPU service chat, native cancellation and reload.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-p',
            'vm',
            '-j',
            '1',
            '-t',
            'local-only',
            'test/e2e/backends/litert_lm_v1_service_e2e_test.dart',
          ],
          environment: {
            'LITERT_LM_V1_MODEL': context.modelPath!,
            'LITERT_LM_V1_SCHEMA_QUALIFICATION': '0',
            for (final name in const [
              'LITERT_LM_V1_LIBRARY',
              'LITERT_LM_V1_LIBRARY_SHA256',
              'LITERT_LM_V1_MODEL_SHA256',
            ])
              name: context.environment[name] ?? '',
            'LITERT_LM_V1_LOG_DIR':
                ?context.environment['LITERT_LM_V1_LOG_DIR'],
          },
          description: 'Bounded actual LiteRT v1 CPU service qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-v1-json-schema',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify internal v1 JSON Schema through the injected CPU service on the fixed published Qwen profile, with Unicode/types, thinking-disabled output, control/followup, cancellation and reload.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-p',
            'vm',
            '-j',
            '1',
            '-t',
            'local-only',
            'test/e2e/backends/litert_lm_v1_service_e2e_test.dart',
          ],
          environment: {
            'LITERT_LM_V1_MODEL': context.modelPath!,
            'LITERT_LM_V1_SCHEMA_QUALIFICATION': '1',
            for (final name in const [
              'LITERT_LM_V1_LIBRARY',
              'LITERT_LM_V1_LIBRARY_SHA256',
              'LITERT_LM_V1_MODEL_SHA256',
            ])
              name: context.environment[name] ?? '',
            'LITERT_LM_V1_LOG_DIR':
                ?context.environment['LITERT_LM_V1_LOG_DIR'],
          },
          description: 'Bounded actual LiteRT v1 CPU service qualification',
        ),
      ],
    ),
    for (final route in const ['direct', 'service', 'speech'])
      LocalE2eScenario(
        name: 'litert-lm-v1-public-$route',
        group: LocalE2eScenarioGroup.dartLocalOnly,
        description:
            'Qualify the uninjected public $route path against hash-bound runtime/model/config bytes; disabled v1 refuses.',
        requiresDevice: false,
        stepsBuilder: (context) => [
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: 'dart',
            arguments: [
              'run',
              'test/fixtures/litert_lm_v1_public_qualification.dart',
              route,
              context.environment['LITERT_LM_V1_LIBRARY']!,
              context.environment['LITERT_LM_V1_LIBRARY_SHA256']!.toLowerCase(),
              context.modelPath!,
              context.environment['LITERT_LM_V1_MODEL_SHA256']!.toLowerCase(),
              context.environment['LITERT_LM_V1_RUNTIME_MANIFEST']!,
              context.environment['LITERT_LM_V1_RUNTIME_MANIFEST_SHA256']!
                  .toLowerCase(),
              context.environment['LITERT_LM_V1_PUBLIC_CONFIG']!,
              context.environment['LITERT_LM_V1_PUBLIC_CONFIG_SHA256']!
                  .toLowerCase(),
            ],
            description:
                'Bounded public LiteRT v1 $route qualification without injected factories',
          ),
        ],
      ),
    LocalE2eScenario(
      name: 'litert-lm-v1-thinking-budget',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify exact Gemma CPU native thinking bounds, cancellation, no-budget isolation and reload with complete runtime payload identity.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '--run-skipped',
            '-p',
            'vm',
            '-j',
            '1',
            '-t',
            'local-only',
            'test/e2e/backends/litert_lm_v1_thinking_e2e_test.dart',
          ],
          environment: {
            'LITERT_LM_V1_MODEL': context.modelPath!,
            for (final name in const [
              'LITERT_LM_V1_LIBRARY',
              'LITERT_LM_V1_LIBRARY_SHA256',
              'LITERT_LM_V1_MODEL_SHA256',
              'LITERT_LM_V1_RUNTIME_MANIFEST',
              'LITERT_LM_V1_RUNTIME_MANIFEST_SHA256',
            ])
              name: context.environment[name] ?? '',
            'LITERT_LM_V1_LOG_DIR':
                ?context.environment['LITERT_LM_V1_LOG_DIR'],
          },
          description: 'Bounded actual v1 Gemma CPU thinking qualification',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'qwen3-litert-cpu-unicode',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Check known Qwen3 artifact split-token Unicode and CPU chat.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: [
            'run',
            'tool/litert_lm_chat_features_smoke.dart',
            context.modelPath!,
            'cpu',
          ],
          environment: const {
            'LITERT_LM_TOKENIZER_FIXTURE': 'qwen3-0.6b',
            'LITERT_LM_AUDIO_PATH': '',
            'LITERT_LM_AUDIO_EXPECTED_TEXT': '',
            'LITERT_LM_IMAGE_PATH': '',
          },
          description: 'Qwen3 exact Unicode decode and CPU chat campaign',
          foregroundStdoutEncoding: utf8,
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-json-schema',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Qualify native JSON Schema chat on a fixed Qwen3 or Gemma 4 model with --backend cpu or gpu.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'dart',
          arguments: const [
            'test',
            '-p',
            'vm',
            '-j',
            '1',
            '--run-skipped',
            '-t',
            'local-only',
            'test/e2e/backends/litert_lm_json_schema_e2e_test.dart',
          ],
          environment: {
            'LITERT_LM_MODEL': context.modelPath ?? '',
            'LITERT_LM_BACKEND': context.backend,
          },
          description: 'Native schema enforcement, contract and lifecycle',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'litert-lm-chat-features-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run real LiteRT-LM chat, thinking, tool-call, and optional media smoke.',
      requiresDevice: false,
      stepsBuilder: (context) {
        final arguments = <String>[
          'run',
          'tool/litert_lm_chat_features_smoke.dart',
        ];
        if (context.modelPath != null) {
          arguments.add(context.modelPath!);
          arguments.add(context.backend);
        }
        return [
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: 'dart',
            arguments: arguments,
            environment: {
              'LITERT_LM_AUDIO_PATH': context.audioPath ?? '',
              'LITERT_LM_AUDIO_EXPECTED_TEXT':
                  context.audioPath != null && context.expectProvided
                  ? context.expect
                  : '',
            },
            description: 'LiteRT-LM chat feature smoke',
          ),
        ];
      },
    ),
    LocalE2eScenario(
      name: 'webgpu-multimodal-regression',
      group: LocalE2eScenarioGroup.webSmoke,
      description: 'Run CPU and WebGPU Qwen multimodal regression gate.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'bash',
          arguments: const [
            'tool/testing/run_webgpu_multimodal_regression_gate.sh',
          ],
          environment: {
            'PLAYWRIGHT_GATE_PORT': '${context.port}',
            'PLAYWRIGHT_PYTHON': context.python,
            'LLAMADART_SKIP_WEB_BUILD': context.skipBuild ? '1' : '0',
          },
          description: 'WebGPU multimodal regression E2E',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-model-cache',
      group: LocalE2eScenarioGroup.flutterDevice,
      description: 'Run chat app model/mmproj download-cache-load E2E.',
      requiresDevice: true,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.chatAppDir,
          executable: 'flutter',
          arguments: [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'integration_test/model_cache_mmproj_e2e_test.dart',
            '-d',
            context.device,
          ],
          description: 'Flutter chat app model cache E2E',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-litert-reload-memory',
      group: LocalE2eScenarioGroup.flutterDevice,
      description:
          'Log per-step memory across LiteRT-LM engine create/delete loops '
          'and fail when deletes leave memory that accumulates.',
      requiresDevice: true,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.chatAppDir,
          executable: 'flutter',
          arguments: [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'integration_test/litert_lm_reload_memory_e2e_test.dart',
            '-d',
            context.device,
            if (context.modelPath != null)
              '--dart-define=LITERT_RELOAD_MODEL=${context.modelPath}',
          ],
          description: 'Flutter chat app LiteRT-LM reload memory E2E',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-litert-json-schema',
      group: LocalE2eScenarioGroup.flutterDevice,
      description:
          'Qualify native LiteRT-LM JSON Schema output on a device with a '
          'fixed Qwen3 or Gemma 4 model; --model-path is a path the app can '
          'read or an http(s) URL it downloads.',
      requiresDevice: true,
      stepsBuilder: (context) {
        final model = context.modelPath!;
        final remote = _isRemoteModel(model);
        return [
          LocalE2eCommandStep(
            workingDirectory: context.chatAppDir,
            executable: 'flutter',
            arguments: [
              'test',
              '--run-skipped',
              '-t',
              'local-only',
              'integration_test/litert_lm_json_schema_e2e_test.dart',
              '-d',
              context.device,
              '--dart-define=${remote ? 'LITERT_LM_MODEL_URL' : 'LITERT_LM_MODEL'}=$model',
              '--dart-define=LITERT_LM_BACKEND=${context.backend}',
            ],
            description: 'Flutter chat app native JSON Schema E2E',
          ),
        ];
      },
    ),
    LocalE2eScenario(
      name: 'chat-app-litert-read-only-bundle',
      group: LocalE2eScenarioGroup.flutterDevice,
      description:
          'Load a LiteRT-LM bundle from a mode-555 directory with no cache '
          'directory configured, named with and without .litertlm, and '
          'require that nothing is written there.',
      requiresDevice: true,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.chatAppDir,
          executable: 'flutter',
          arguments: [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'integration_test/litert_lm_read_only_bundle_e2e_test.dart',
            '-d',
            context.device,
            if (context.modelPath != null)
              '--dart-define=LITERT_READ_ONLY_MODEL=${context.modelPath}',
          ],
          description: 'Flutter chat app LiteRT-LM read-only bundle E2E',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-text-image-coexistence',
      group: LocalE2eScenarioGroup.flutterDevice,
      description:
          'Generate llama.cpp text, a stable_diffusion image, the same text '
          'and the same image again in one process, and require the reply '
          'and the image to be unchanged.',
      requiresDevice: true,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.chatAppDir,
          executable: 'flutter',
          arguments: [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'integration_test/text_image_coexistence_e2e_test.dart',
            '-d',
            context.device,
          ],
          description: 'Flutter chat app text and image coexistence E2E',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-image-settings-comparison',
      group: LocalE2eScenarioGroup.flutterDevice,
      description:
          'Time and measure the peak memory of SDXS and SD-Turbo (with and '
          'without TAESD) images with the automatic attention and VAE '
          'settings and with them turned off, in one process (#805).',
      requiresDevice: true,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.chatAppDir,
          executable: 'flutter',
          arguments: [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'integration_test/image_settings_comparison_e2e_test.dart',
            '-d',
            context.device,
          ],
          description: 'Flutter chat app image settings comparison',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-micro-batch-sweep',
      group: LocalE2eScenarioGroup.flutterDevice,
      description:
          'Answer history and tool prompts at the default and at explicit '
          'micro-batch sizes in one process, and record the Android Vulkan '
          'prompt cap decision with the Vulkan device facts.',
      requiresDevice: true,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.chatAppDir,
          executable: 'flutter',
          arguments: [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'integration_test/micro_batch_sweep_e2e_test.dart',
            '-d',
            context.device,
            if (context.modelPath != null)
              '--dart-define=MICRO_BATCH_SWEEP_MODEL=${context.modelPath}',
          ],
          description: 'Flutter chat app micro-batch sweep E2E',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-macos-quit',
      group: LocalE2eScenarioGroup.flutterDevice,
      description:
          'Quit the macOS chat app Runner through each AppKit path with '
          'models loaded on Metal and nothing disposed, and after a hot '
          'restart, and require exit status 0 and no crash report.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.chatAppDir,
          executable: 'flutter',
          arguments: const [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'test/macos_quit_e2e_test.dart',
          ],
          environment: {'MACOS_QUIT_CHAT_MODEL': context.modelPath!},
          description: 'Flutter macOS quit with models loaded',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-flutter-active-shutdown',
      group: LocalE2eScenarioGroup.flutterDevice,
      description:
          'Quit a real macOS or Linux Flutter engine during native load and '
          'generation; verify native call completion, host callbacks and C output.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.chatAppDir,
          executable: 'flutter',
          arguments: const [
            'test',
            '--run-skipped',
            '-t',
            'local-only',
            'test/flutter_shutdown_e2e_test.dart',
          ],
          environment: {'MACOS_QUIT_CHAT_MODEL': context.modelPath!},
          description: 'Flutter host shutdown during active native work',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-flutter-image-shutdown',
      group: LocalE2eScenarioGroup.flutterDevice,
      description:
          'Quit a real macOS or Linux Flutter engine during image load and '
          'sampling; await image startup/disposal, host callbacks and C output.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.chatAppDir,
          executable: 'flutter',
          arguments: const [
            'test',
            '--no-pub',
            '--run-skipped',
            '-t',
            'local-only',
            'test/flutter_image_shutdown_e2e_test.dart',
          ],
          environment: {'MACOS_QUIT_CHAT_MODEL': context.modelPath!},
          description: 'Flutter host shutdown during image load and sampling',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-web-production-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Test the exact production-root build with mock and real GGUF smokes.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: 'bash',
          arguments: [
            context.skipBuild
                ? 'scripts/validate_chat_app_web_build.sh'
                : 'scripts/build_chat_app_web.sh',
          ],
          environment: const {'CHAT_APP_BASE_HREF': '/'},
          description: 'Build or validate the production-root artifact',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'tool/testing/serve_static_with_headers.py',
            '--directory',
            'example/chat_app/build/web',
            '--port',
            '${context.port}',
            '--coep',
            'require-corp',
          ],
          description: 'Serve the unchanged production artifact at root',
          background: true,
          waitForPort: context.port,
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'tool/testing/serve_static_with_headers.py',
            '--directory',
            '.',
            '--port',
            '${context.port + 1}',
            '--cors-origin',
            'http://127.0.0.1:${context.port}',
          ],
          description:
              'Serve the tiny test model separately from deployable files',
          background: true,
          waitForPort: context.port + 1,
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'tool/testing/playwright_chat_app_mock_smoke.py',
            'http://127.0.0.1:${context.port}/?llamadart_mock_bridge=echo',
          ],
          description: 'Run deterministic mock smoke on the production layout',
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'tool/testing/playwright_chat_app_real_model_smoke.py',
            'http://127.0.0.1:${context.port}/',
            '--model-url',
            context.modelUrl ??
                'http://127.0.0.1:${context.port + 1}/.dart_tool/test_models/stories15M.gguf',
            '--allow-any-response',
            '--expect-penalty-prompt-tokens-probe',
            '--expect-penalty-prompt-tokens-option',
            'absent',
          ],
          description:
              'Run real worker/GGUF smoke on the same production artifact',
        ),
      ],
    ),
    LocalE2eScenario(
      name: 'chat-app-web-real-model-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Build chat_app web and run the real-model Playwright smoke; '
          'plain chat must run without a penaltyPromptTokens option and the '
          'probe must report it.',
      requiresDevice: false,
      stepsBuilder: (context) => _webRealModelSmokeSteps(context, const [
        '--expect-penalty-prompt-tokens-probe',
        '--expect-penalty-prompt-tokens-option',
        'absent',
      ]),
    ),
    LocalE2eScenario(
      name: 'chat-app-web-tool-penalty-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Build chat_app web and run a ToolChoice.auto chat on a '
          'tool-capable --model-url; the completion must carry a lazy '
          'grammar and omit penaltyPromptTokens.',
      requiresDevice: false,
      stepsBuilder: (context) => _webRealModelSmokeSteps(context, const [
        '--tools',
        '--expect-penalty-prompt-tokens-probe',
        '--expect-penalty-prompt-tokens-option',
        'absent',
        '--expect-lazy-grammar',
      ]),
    ),
    LocalE2eScenario(
      name: 'chat-app-web-speech-to-text-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Build chat_app web and transcribe a selected WAV, MP3 or FLAC with '
          'Qwen3-ASR; a WAV also drives the fake microphone.',
      requiresDevice: false,
      stepsBuilder: (context) {
        final steps = <LocalE2eCommandStep>[_prepareChatAppWebBuild(context)];
        steps.addAll([
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: context.python,
            arguments: [
              'tool/testing/serve_static_with_headers.py',
              '--directory',
              '.',
              '--port',
              '${context.port}',
            ],
            description: 'Serve repo root with COOP/COEP headers',
            background: true,
            waitForPort: context.port,
          ),
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: context.python,
            arguments: [
              'tool/testing/playwright_chat_app_real_model_smoke.py',
              context.webBuildUrl,
              '--model-url',
              context.modelUrl ?? context.defaultQwen3AsrWebModelUrl,
              '--mmproj-url',
              context.mmprojUrl ?? context.defaultQwen3AsrWebMmprojUrl,
              '--speech-audio-path',
              context.audioPath!,
              if (context.audioPath!.toLowerCase().endsWith('.wav')) ...[
                '--speech-microphone',
                '--microphone-allow-any-response',
              ],
              '--expect',
              context.expect,
              '--gpu-layers',
              '0',
              '--context-size',
              '4096',
              '--max-tokens',
              '512',
              '--load-timeout-ms',
              '${40 * 60 * 1000}',
              '--response-timeout-ms',
              '${10 * 60 * 1000}',
            ],
            description: 'Run Playwright Qwen3-ASR Web speech smoke',
          ),
        ]);
        return steps;
      },
    ),
    LocalE2eScenario(
      name: 'chat-app-web-text-to-speech-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Build chat_app web, synthesize Qwen3-TTS audio, autoplay it, and '
          'export a validated WAV.',
      requiresDevice: false,
      stepsBuilder: (context) {
        final steps = <LocalE2eCommandStep>[_prepareChatAppWebBuild(context)];
        steps.addAll([
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: context.python,
            arguments: [
              'tool/testing/serve_static_with_headers.py',
              '--directory',
              '.',
              '--port',
              '${context.port}',
            ],
            description: 'Serve repo root with COOP/COEP headers',
            background: true,
            waitForPort: context.port,
          ),
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: context.python,
            arguments: [
              'tool/testing/playwright_chat_app_text_to_speech_smoke.py',
              context.webBuildUrl,
              '--model-url',
              context.modelUrl ?? context.defaultQwen3TtsWebModelUrl,
              '--mmproj-url',
              context.mmprojUrl ?? context.defaultQwen3TtsWebMmprojUrl,
              if (context.audioPath != null) ...[
                '--speaker-audio-path',
                context.audioPath!,
              ],
            ],
            description: 'Run Playwright Qwen3-TTS Web speech smoke',
          ),
        ]);
        return steps;
      },
    ),
    LocalE2eScenario(
      name: 'chat-app-web-mock-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Build chat_app web and run the deterministic mock-bridge smoke.',
      requiresDevice: false,
      stepsBuilder: (context) {
        final steps = <LocalE2eCommandStep>[_prepareChatAppWebBuild(context)];
        final smokeArguments = <String>[
          'tool/testing/playwright_chat_app_mock_smoke.py',
          '${context.webBuildUrl}?llamadart_mock_bridge=echo',
        ];
        if (context.modelUrl != null) {
          smokeArguments.addAll(['--model-url', context.modelUrl!]);
        }
        steps.addAll([
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: context.python,
            arguments: [
              'tool/testing/serve_static_with_headers.py',
              '--directory',
              '.',
              '--port',
              '${context.port}',
            ],
            description: 'Serve repo root with COOP/COEP headers',
            background: true,
            waitForPort: context.port,
          ),
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: context.python,
            arguments: smokeArguments,
            description: 'Run Playwright mock-bridge chat app smoke',
          ),
        ]);
        return steps;
      },
    ),
    LocalE2eScenario(
      name: 'chat-app-web-litert-gemma4-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description: 'Build chat_app web and run Gemma 4 through LiteRT-LM JS.',
      requiresDevice: false,
      stepsBuilder: (context) {
        final steps = <LocalE2eCommandStep>[_prepareChatAppWebBuild(context)];
        steps.addAll([
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: context.python,
            arguments: [
              'tool/testing/serve_static_with_headers.py',
              '--directory',
              '.',
              '--port',
              '${context.port}',
            ],
            description: 'Serve repo root with COOP/COEP headers',
            background: true,
            waitForPort: context.port,
          ),
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: context.python,
            arguments: [
              'tool/testing/playwright_chat_app_real_model_smoke.py',
              context.webBuildUrl,
              '--model-url',
              context.modelUrl ?? context.defaultLiteRtLmWebModelUrl,
              '--prompt',
              'What is 2+2? Answer with only the number.',
              '--expect',
              context.expect,
              '--response-source',
              'litert',
              '--backend-index',
              '2',
              '--gpu-layers',
              '999',
              '--context-size',
              '8192',
              '--max-tokens',
              '16',
              '--penalty',
              '1.1',
              '--load-timeout-ms',
              '${40 * 60 * 1000}',
              '--response-timeout-ms',
              '${10 * 60 * 1000}',
              if (context.browser == 'safari') ...['--browser', 'safari'],
            ],
            description: 'Run Playwright Gemma 4 LiteRT-LM web smoke',
          ),
        ]);
        return steps;
      },
    ),
    LocalE2eScenario(
      name: 'chat-app-web-gemma4-webgpu-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Build chat_app web and run Gemma 4 E2B (text-only) through '
          'WebGPU/llama.cpp with the mem64 core.',
      requiresDevice: false,
      stepsBuilder: (context) {
        final steps = <LocalE2eCommandStep>[_prepareChatAppWebBuild(context)];
        steps.addAll([
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: context.python,
            arguments: [
              'tool/testing/serve_static_with_headers.py',
              '--directory',
              '.',
              '--port',
              '${context.port}',
            ],
            description: 'Serve repo root with COOP/COEP headers',
            background: true,
            waitForPort: context.port,
          ),
          LocalE2eCommandStep(
            workingDirectory: context.projectRoot,
            executable: context.python,
            arguments: [
              'tool/testing/playwright_chat_app_real_model_smoke.py',
              context.webBuildUrl,
              '--model-url',
              context.modelUrl ?? context.defaultGemma4WebGpuModelUrl,
              '--prompt',
              'What is 2+2? Answer with only the number.',
              '--expect',
              context.expect,
              // WebGPU/llama.cpp backend (LiteRT-LM is index 2).
              '--backend-index',
              '1',
              '--gpu-layers',
              '0',
              // Bounded context for the large model per AGENTS.md guidance.
              '--context-size',
              '2048',
              '--max-tokens',
              '16',
              // Force the mem64 core: Gemma 4 E2B exceeds the wasm32 ceiling.
              '--mem64',
              '--load-timeout-ms',
              '${40 * 60 * 1000}',
              '--response-timeout-ms',
              '${10 * 60 * 1000}',
            ],
            description: 'Run Playwright Gemma 4 WebGPU (mem64) web smoke',
          ),
        ]);
        return steps;
      },
    ),
    LocalE2eScenario(
      name: 'bridge-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description: 'Run the packaged WebGPU bridge bootstrap smoke.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        _prepareChatAppWebBuild(context),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'tool/testing/serve_static_with_headers.py',
            '--directory',
            '.',
            '--port',
            '${context.port}',
          ],
          description: 'Serve repo root with COOP/COEP headers',
          background: true,
          waitForPort: context.port,
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'tool/testing/playwright_bridge_smoke.py',
            context.webBuildUrl,
          ],
          description: 'Run packaged bridge smoke',
        ),
      ],
    ),
  ];
}

/// Runs a foreground step without letting malformed diagnostics hide its exit
/// code. Explicit stdout codecs remain strict for controlled output protocols.
Future<ProcessResult> runLocalE2eForegroundStep(LocalE2eCommandStep step) {
  final diagnostics = Platform.isWindows
      ? systemEncoding
      : const Utf8Codec(allowMalformed: true);
  return Process.run(
    step.executable,
    step.arguments,
    workingDirectory: step.workingDirectory,
    environment: step.environment.isEmpty ? null : step.environment,
    runInShell: false,
    stdoutEncoding: step.foregroundStdoutEncoding == systemEncoding
        ? diagnostics
        : step.foregroundStdoutEncoding,
    stderrEncoding: diagnostics,
  );
}

Future<LocalE2eResult> runLocalE2e(
  List<String> args, {
  String? projectRoot,
  Map<String, String>? environment,
  Future<void> Function(int port)? portAvailabilityCheck,
  Future<void> Function(int port, Process owner)? portReadinessWait,
  Future<ProcessResult> Function(LocalE2eCommandStep step)? foregroundStepRun,
  LocalE2eDisplayShell? displayShell,
}) async {
  final parsed = _ParsedArgs.parse(args);
  if (parsed.help) {
    return LocalE2eResult(0, stdout: _usage());
  }

  final root = projectRoot ?? Directory.current.path;
  final scenarios = buildLocalE2eScenarios(projectRoot: root);
  if (parsed.list) {
    return LocalE2eResult(0, stdout: _formatScenarioList(scenarios));
  }

  final scenarioName = parsed.scenario;
  if (scenarioName == null || scenarioName.isEmpty) {
    return LocalE2eResult(
      64,
      stderr: 'Missing --scenario. Use --list to inspect scenarios.\n',
    );
  }

  final scenario = scenarios.cast<LocalE2eScenario?>().firstWhere(
    (candidate) => candidate?.name == scenarioName,
    orElse: () => null,
  );
  if (scenario == null) {
    return LocalE2eResult(
      64,
      stderr:
          'Unknown local E2E scenario: $scenarioName\nUse --list to inspect scenarios.\n',
    );
  }
  if (scenario.name == 'native-default-consumer-aot' && !parsed.dryRun) {
    final env = environment ?? Platform.environment;
    final sha = env['LLAMADART_DEFAULT_AOT_EXPECTED_SHA'] ?? '';
    final tag = env['LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG'];
    if (sha.length != 40 ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha) ||
        sha == '0000000000000000000000000000000000000000' ||
        !const {'v0.8.0-2', 'v0.8.0-3', 'v0.9.0'}.contains(tag) ||
        (env['LLAMADART_DEFAULT_AOT_MODEL_PATH'] ?? '').trim().isEmpty ||
        (env['LLAMADART_DEFAULT_AOT_OUTPUT_ROOT'] ?? '').trim().isEmpty) {
      return const LocalE2eResult(
        64,
        stderr:
            'native-default-consumer-aot requires '
            'LLAMADART_DEFAULT_AOT_EXPECTED_SHA (full lowercase commit), '
            'LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG (v0.8.0-2, v0.8.0-3 or v0.9.0), '
            'LLAMADART_DEFAULT_AOT_MODEL_PATH and '
            'LLAMADART_DEFAULT_AOT_OUTPUT_ROOT (fresh output). '
            'Expected tag is verification only; native2 is pipeline-only.\n',
      );
    }
  }
  if (parsed.browser case final browser?
      when !const [
            'litert-lm-web-text-history',
            'chat-app-web-litert-gemma4-smoke',
          ].contains(scenario.name) ||
          !const ['chrome', 'safari'].contains(browser)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--browser chrome or safari applies only to litert-lm-web-text-history '
          'and chat-app-web-litert-gemma4-smoke.\n',
    );
  }
  if (const [
        'litert-lm-web-text-history',
        'litert-lm-web-tool-calling',
        'litert-lm-web-truncation',
      ].contains(scenario.name) &&
      !const ['cpu', 'gpu'].contains(parsed.backend)) {
    return LocalE2eResult(
      64,
      stderr: '--backend cpu or gpu is required for ${scenario.name}.\n',
    );
  }
  if (parsed.mmprojPath != null && parsed.modelPath == null) {
    return LocalE2eResult(64, stderr: '--mmproj-path requires --model-path.\n');
  }
  if (parsed.imagePath != null && parsed.mmprojPath == null) {
    return LocalE2eResult(64, stderr: '--image-path requires --mmproj-path.\n');
  }
  if (parsed.configPath != null && parsed.headPath == null) {
    return LocalE2eResult(64, stderr: '--config-path requires --head-path.\n');
  }
  if (parsed.headPath != null && scenario.name != 'decision-model-smoke') {
    return LocalE2eResult(
      64,
      stderr: '--head-path is not supported by ${scenario.name}.\n',
    );
  }
  if (scenario.name == 'tool-result-image-smoke' &&
      (parsed.modelPath == null || parsed.mmprojPath == null)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path and --mmproj-path are required for '
          'tool-result-image-smoke.\n',
    );
  }
  if (scenario.name == 'decision-model-smoke' &&
      (parsed.modelPath == null || parsed.headPath == null)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path and --head-path are required for decision-model-smoke.\n',
    );
  }
  if ((scenario.name == 'litert-lm-json-schema' ||
          scenario.name == 'chat-app-litert-json-schema') &&
      parsed.modelPath == null) {
    return LocalE2eResult(
      64,
      stderr: '--model-path is required for ${scenario.name}.\n',
    );
  }
  // The URL is printed and compiled into the app, so it must carry no secret;
  // a URL that does not parse cannot be checked, so it is refused too.
  if (scenario.name == 'chat-app-litert-json-schema' &&
      _isRemoteModel(parsed.modelPath!)) {
    final modelUrl = Uri.tryParse(parsed.modelPath!);
    if (modelUrl == null ||
        modelUrl.userInfo.isNotEmpty ||
        modelUrl.hasQuery ||
        modelUrl.hasFragment) {
      return LocalE2eResult(
        64,
        stderr:
            '${scenario.name} accepts a model URL without credentials, query or '
            'fragment; serve the bundle from a plain URL.\n',
      );
    }
  }
  if ((scenario.name == 'litert-lm-json-schema' ||
          scenario.name == 'chat-app-litert-json-schema') &&
      (!parsed.backendProvided ||
          (parsed.backend != 'cpu' && parsed.backend != 'gpu'))) {
    return LocalE2eResult(
      64,
      stderr: '${scenario.name} requires --backend cpu or gpu.\n',
    );
  }
  if ((scenario.name == 'qwen3-litert-cpu-unicode' ||
          scenario.name == 'litert-lm-media-preservation' ||
          scenario.name == 'litert-lm-utility-preservation') &&
      parsed.backendProvided &&
      parsed.backend != 'cpu') {
    return LocalE2eResult(
      64,
      stderr: '${scenario.name} requires --backend cpu.\n',
    );
  }
  if (scenario.name == 'gguf-chat-features-smoke' && parsed.audioPath != null) {
    return const LocalE2eResult(
      64,
      stderr:
          '--audio-path uses the dedicated gguf-audio-chat-smoke scenario.\n',
    );
  }
  const audioPathScenarios = <String>{
    'gguf-audio-chat-smoke',
    'speech-to-text-smoke',
    'litert-lm-asr-smoke',
    'litert-lm-asr-preservation',
    'litert-lm-v1-asr-smoke',
    'litert-lm-chat-features-smoke',
    'chat-app-web-speech-to-text-smoke',
    'chat-app-web-text-to-speech-smoke',
  };
  if (parsed.audioPath != null && !audioPathScenarios.contains(scenario.name)) {
    return LocalE2eResult(
      64,
      stderr: '--audio-path is not supported by ${scenario.name}.\n',
    );
  }
  if (scenario.name == 'speech-to-text-smoke' &&
      (parsed.modelPath == null ||
          parsed.mmprojPath == null ||
          parsed.audioPath == null ||
          !parsed.expectProvided ||
          parsed.expect.trim().isEmpty)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path, --mmproj-path, --audio-path, and a nonempty --expect '
          'are required for speech-to-text-smoke.\n',
    );
  }
  if (scenario.name == 'chat-app-web-speech-to-text-smoke' &&
      (parsed.audioPath == null ||
          !parsed.expectProvided ||
          parsed.expect.trim().isEmpty)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--audio-path and a nonempty --expect are required for '
          'chat-app-web-speech-to-text-smoke.\n',
    );
  }
  if (scenario.name == 'litert-lm-asr-preservation' &&
      (parsed.modelPath == null ||
          parsed.tokenizerPath == null ||
          parsed.audioPath == null)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path, --tokenizer-path and --audio-path are required for '
          'litert-lm-asr-preservation.\n',
    );
  }
  if (scenario.name == 'litert-lm-asr-preservation' &&
      parsed.backendProvided &&
      parsed.backend != 'cpu') {
    return const LocalE2eResult(
      64,
      stderr: 'litert-lm-asr-preservation requires --backend cpu.\n',
    );
  }
  if ((scenario.name == 'litert-lm-asr-smoke' ||
          scenario.name == 'litert-lm-v1-asr-smoke') &&
      (parsed.modelPath == null ||
          parsed.tokenizerPath == null ||
          parsed.audioPath == null ||
          !parsed.expectProvided ||
          parsed.expect.trim().isEmpty)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path, --tokenizer-path, --audio-path, and a nonempty '
          '--expect are required for litert-lm-asr-smoke.\n',
    );
  }
  if (scenario.name == 'chat-app-web-tool-penalty-smoke' &&
      parsed.modelUrl == null) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-url <tool-capable.gguf> is required for '
          'chat-app-web-tool-penalty-smoke.\n',
    );
  }
  if ((scenario.name == 'image-generation-smoke' ||
          scenario.name == 'image-seamless-textures' ||
          scenario.name == 'image-editing') &&
      parsed.modelPath == null) {
    return LocalE2eResult(
      64,
      stderr:
          '--model-path <${scenario.name == 'image-editing' ? 'sd-turbo' : 'sdxs'}.gguf> is required for ${scenario.name}.\n',
    );
  }
  if (scenario.name == 'image-controlnet' &&
      (parsed.modelPath == null ||
          (environment ?? Platform.environment)['LLAMADART_SD15_CONTROLNET']
                  ?.trim()
                  .isNotEmpty !=
              true)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path <sd15-checkpoint> and LLAMADART_SD15_CONTROLNET are '
          'required for image-controlnet; see doc/image_controlnet.md.\n',
    );
  }
  if (scenario.name == 'image-reference-editing') {
    final env = environment ?? Platform.environment;
    if (parsed.modelPath == null ||
        _referenceEditComponentVariables.any(
          (name) => (env[name] ?? '').isEmpty,
        )) {
      return LocalE2eResult(
        64,
        stderr:
            '--model-path <flux1-kontext-dev transformer> and '
            '${_referenceEditComponentVariables.join(', ')} are required for '
            'image-reference-editing. See doc/image_reference_editing.md.\n',
      );
    }
  }
  if (scenario.name == 'image-hires-fix') {
    final env = environment ?? Platform.environment;
    if (parsed.modelPath == null ||
        !const {
          'sd15',
          'turbo',
        }.contains(env['LLAMADART_HIRES_RECIPE'] ?? 'sd15') ||
        !const {
          'cpu',
          'gpu',
        }.contains(env['LLAMADART_HIRES_DEVICE'] ?? 'cpu')) {
      return const LocalE2eResult(
        64,
        stderr:
            '--model-path <sd15-or-sd2-checkpoint> is required for '
            'image-hires-fix; LLAMADART_HIRES_RECIPE is sd15 or turbo and '
            'LLAMADART_HIRES_DEVICE cpu or gpu. See doc/image_hires_fix.md.\n',
      );
    }
  }
  if (scenario.name == 'image-original-containers' &&
      parsed.modelPath == null) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path <independently-admitted-plan.json> is required for '
          'image-original-containers; see doc/image_weight_formats.md.\n',
    );
  }
  if (scenario.name == 'image-container-formats' &&
      (parsed.modelPath == null ||
          (environment ??
                      Platform
                          .environment)['LLAMADART_IMAGE_CONTAINER_REFERENCES']
                  ?.trim()
                  .isNotEmpty !=
              true)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path <manifest.json> and '
          'LLAMADART_IMAGE_CONTAINER_REFERENCES are required for '
          'image-container-formats; see doc/image_weight_formats.md.\n',
    );
  }
  if (scenario.name == 'image-local-checkpoint-sets' &&
      parsed.modelPath == null) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path <complete-sd-turbo.safetensors> is required for image-local-checkpoint-sets.\n',
    );
  }
  if (scenario.name == 'text-to-speech-smoke' &&
      (parsed.modelPath == null || parsed.mmprojPath == null)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path and --mmproj-path are required for text-to-speech-smoke.\n',
    );
  }
  if (scenario.name == 'gguf-audio-chat-smoke' &&
      (parsed.modelPath == null ||
          parsed.mmprojPath == null ||
          parsed.audioPath == null ||
          !parsed.expectProvided ||
          parsed.expect.trim().isEmpty)) {
    return const LocalE2eResult(
      64,
      stderr:
          '--model-path, --mmproj-path, --audio-path, and a nonempty --expect '
          'are required for gguf-audio-chat-smoke.\n',
    );
  }
  if (scenario.name == 'gguf-audio-chat-smoke' && parsed.imagePath != null) {
    return const LocalE2eResult(
      64,
      stderr: '--image-path is not supported by gguf-audio-chat-smoke.\n',
    );
  }
  if (scenario.name == 'litert-lm-chat-features-smoke' &&
      parsed.audioPath != null &&
      (!parsed.expectProvided || parsed.expect.trim().isEmpty)) {
    return const LocalE2eResult(
      64,
      stderr:
          'A nonempty --expect is required when --audio-path is set for '
          'litert-lm-chat-features-smoke.\n',
    );
  }
  if ((scenario.name == 'llama-cpp-speculative-benchmark' ||
          scenario.name == 'llama-cpp-chat-template-smoke' ||
          scenario.name == 'litert-lm-lifecycle' ||
          scenario.name == 'litert-lm-media-preservation' ||
          scenario.name == 'litert-lm-utility-preservation' ||
          scenario.name == 'litert-lm-v1-thinking-budget' ||
          scenario.name == 'litert-lm-v1-service' ||
          scenario.name == 'litert-lm-v1-json-schema' ||
          scenario.name == 'litert-lm-json-schema' ||
          scenario.name == 'litert-lm-multimodal-embedding' ||
          scenario.name == 'litert-lm-web-text-history' ||
          scenario.name == 'litert-lm-web-tool-calling' ||
          scenario.name == 'litert-lm-web-truncation' ||
          scenario.name == 'litert-lm-chat-features-smoke' ||
          scenario.name == 'qwen3-litert-cpu-unicode' ||
          scenario.name == 'native-prompt-cancel' ||
          scenario.name == 'native-exit-teardown' ||
          scenario.name == 'image-exit-teardown' ||
          scenario.name == 'chat-app-macos-quit' ||
          scenario.name == 'chat-app-flutter-active-shutdown' ||
          scenario.name == 'chat-app-flutter-image-shutdown' ||
          scenario.name == 'gemma4-mtp-smoke' ||
          scenario.name == 'native-embedding-benchmark' ||
          scenario.name == 'native-embedding-sweep') &&
      parsed.modelPath == null) {
    return LocalE2eResult(
      64,
      stderr: '--model-path is required for ${scenario.name}.\n',
    );
  }

  if (scenario.name.startsWith('litert-lm-v1-public-')) {
    if (parsed.modelPath == null || parsed.backend != 'cpu') {
      return const LocalE2eResult(
        64,
        stderr:
            'Public v1 qualification requires --model-path and --backend cpu.\n',
      );
    }
    final env = environment ?? Platform.environment;
    for (final name in const [
      'LITERT_LM_V1_LIBRARY',
      'LITERT_LM_V1_LIBRARY_SHA256',
      'LITERT_LM_V1_MODEL_SHA256',
      'LITERT_LM_V1_RUNTIME_MANIFEST',
      'LITERT_LM_V1_RUNTIME_MANIFEST_SHA256',
      'LITERT_LM_V1_PUBLIC_CONFIG',
      'LITERT_LM_V1_PUBLIC_CONFIG_SHA256',
    ]) {
      final value = env[name]?.trim() ?? '';
      if (value.isEmpty ||
          (name.endsWith('SHA256') &&
              !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value))) {
        return LocalE2eResult(
          64,
          stderr: '$name is required for public v1 qualification.\n',
        );
      }
    }
  }

  if (scenario.name == 'litert-lm-v1-thinking-budget' ||
      scenario.name == 'litert-lm-v1-service' ||
      scenario.name == 'litert-lm-v1-json-schema' ||
      scenario.name == 'litert-lm-v1-asr-smoke') {
    if (parsed.backend != 'cpu') {
      return LocalE2eResult(
        64,
        stderr: '--backend cpu is required for ${scenario.name}.\n',
      );
    }
    final env = environment ?? Platform.environment;
    for (final name in [
      'LITERT_LM_V1_LIBRARY',
      'LITERT_LM_V1_LIBRARY_SHA256',
      'LITERT_LM_V1_MODEL_SHA256',
      if (scenario.name == 'litert-lm-v1-thinking-budget') ...[
        'LITERT_LM_V1_RUNTIME_MANIFEST',
        'LITERT_LM_V1_RUNTIME_MANIFEST_SHA256',
      ],
      if (scenario.name == 'litert-lm-v1-asr-smoke') ...[
        'LITERT_LM_V1_TOKENIZER_SHA256',
        'LITERT_LM_V1_AUDIO_SHA256',
      ],
    ]) {
      final value = env[name]?.trim() ?? '';
      if (value.isEmpty ||
          (name.endsWith('SHA256') &&
              !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value))) {
        return LocalE2eResult(
          64,
          stderr:
              '$name is required for ${scenario.name} (SHA256 inputs require 64 hexadecimal digits).\n',
        );
      }
    }
  }

  if (scenario.name == 'litert-lm-v1-json-schema' &&
      (environment ?? Platform.environment)['LITERT_LM_V1_MODEL_SHA256']
              ?.toLowerCase() !=
          'c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108') {
    return const LocalE2eResult(
      64,
      stderr:
          'litert-lm-v1-json-schema requires the fixed published Qwen CPU profile model SHA256.\n',
    );
  }

  if (scenario.name == 'litert-lm-v1-thinking-budget' &&
      (environment ?? Platform.environment)['LITERT_LM_V1_MODEL_SHA256']
              ?.toLowerCase() !=
          '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c') {
    return const LocalE2eResult(
      64,
      stderr: 'The fixed maintained Gemma thinking model SHA256 is required.\n',
    );
  }

  if (scenario.name == 'text-embedding-retrieval') {
    for (final name in const [
      'LLAMADART_EMBEDDINGGEMMA2_MODEL_PATH',
      'LLAMADART_EG2_RETRIEVAL_REFERENCE',
    ]) {
      if ((environment ?? Platform.environment)[name]?.trim().isNotEmpty !=
          true) {
        return LocalE2eResult(
          64,
          stderr:
              '$name is required for text-embedding-retrieval; see doc/embedding_text_helpers.md.\n',
        );
      }
    }
  }

  if (scenario.name == 'native-multimodal-embeddings') {
    for (final name in const [
      'LLAMADART_EMBEDDING_MODELS_DIR',
      'LLAMADART_EMBEDDING_REFERENCE_CPU',
      'LLAMADART_EMBEDDING_REFERENCE_METAL',
    ]) {
      if ((environment ?? Platform.environment)[name]?.trim().isNotEmpty !=
          true) {
        return LocalE2eResult(
          64,
          stderr:
              '$name is required for native-multimodal-embeddings; see doc/multimodal_embeddings_native.md.\n',
        );
      }
    }
  }

  if ((scenario.name == 'chat-app-flutter-active-shutdown' ||
          scenario.name == 'chat-app-flutter-image-shutdown') &&
      (environment ?? Platform.environment)['FLUTTER_SHUTDOWN_HEADERS']
              ?.trim()
              .isNotEmpty !=
          true) {
    return const LocalE2eResult(
      64,
      stderr:
          'FLUTTER_SHUTDOWN_HEADERS must name the exact runtime header bundle '
          'for the active Flutter shutdown scenarios.\n',
    );
  }

  final context = LocalE2eRunContext(
    projectRoot: root,
    device: parsed.device,
    port: parsed.port,
    python: parsed.pythonProvided ? parsed.python : _defaultPython(root),
    modelPath: parsed.modelPath,
    tokenizerPath: parsed.tokenizerPath,
    modelPreset: parsed.modelPreset,
    draftModelPath: parsed.draftModelPath,
    mmprojPath: parsed.mmprojPath,
    imagePath: parsed.imagePath,
    audioPath: parsed.audioPath,
    headPath: parsed.headPath,
    configPath: parsed.configPath,
    modelUrl: parsed.modelUrl,
    mmprojUrl: parsed.mmprojUrl,
    backend: parsed.backend,
    backendProvided: parsed.backendProvided,
    speculativeCases: parsed.speculativeCases,
    benchmarkGpuLayers: parsed.benchmarkGpuLayers,
    benchmarkMaxTokens: parsed.benchmarkMaxTokens,
    benchmarkRuns: parsed.benchmarkRuns,
    benchmarkWarmups: parsed.benchmarkWarmups,
    draftTokenMaxList: parsed.draftTokenMaxList,
    ngramSize: parsed.ngramSize,
    browser: parsed.browser,
    ngramSizeM: parsed.ngramSizeM,
    ngramTokenMax: parsed.ngramTokenMax,
    ngramCacheStaticPath: parsed.ngramCacheStaticPath,
    ngramCacheDynamicPath: parsed.ngramCacheDynamicPath,
    ngramCacheBuildStaticPath: parsed.ngramCacheBuildStaticPath,
    ngramCacheBuildText: parsed.ngramCacheBuildText,
    expect: parsed.expect,
    expectProvided: parsed.expectProvided,
    allowAnyResponse: parsed.allowAnyResponse,
    skipBuild: parsed.skipBuild,
    environment: environment,
  );
  final steps = scenario.steps(context);

  if (parsed.dryRun) {
    return LocalE2eResult(
      0,
      stdout: _formatDryRun(scenario, steps, displayShell),
    );
  }

  final buffer = StringBuffer()
    ..writeln('Running local E2E scenario: ${scenario.name}');
  final backgroundProcesses = <_BackgroundProcess>[];
  try {
    for (final step in steps) {
      buffer.writeln('[local-e2e] ${step.description}');
      if (step.background) {
        final port = step.waitForPort;
        if (port != null) {
          await (portAvailabilityCheck ?? _ensurePortAvailable)(port);
        }
        final process = await Process.start(
          step.executable,
          step.arguments,
          workingDirectory: step.workingDirectory,
          environment: step.environment.isEmpty ? null : step.environment,
          runInShell: false,
        );
        final stdoutSubscription = process.stdout
            .transform(systemEncoding.decoder)
            .listen(buffer.write);
        final stderrSubscription = process.stderr
            .transform(systemEncoding.decoder)
            .listen(buffer.write);
        backgroundProcesses.add(
          _BackgroundProcess(
            process: process,
            stdoutSubscription: stdoutSubscription,
            stderrSubscription: stderrSubscription,
          ),
        );
        if (port != null) {
          await (portReadinessWait ?? _waitForPort)(port, process);
        }
        continue;
      }

      final result = await (foregroundStepRun ?? runLocalE2eForegroundStep)(
        step,
      );
      buffer
        ..write(result.stdout)
        ..write(result.stderr);
      if (result.exitCode != 0) {
        return LocalE2eResult(result.exitCode, stdout: buffer.toString());
      }
    }
    return LocalE2eResult(0, stdout: buffer.toString());
  } on Object catch (error) {
    return LocalE2eResult(1, stdout: buffer.toString(), stderr: '$error\n');
  } finally {
    for (final background in backgroundProcesses.reversed) {
      background.process.kill();
      await background.process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          background.process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      await background.stdoutSubscription.cancel();
      await background.stderrSubscription.cancel();
    }
  }
}

Future<void> _ensurePortAvailable(int port) async {
  ServerSocket? socket;
  try {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  } on SocketException catch (error) {
    throw StateError(
      'Port $port is already in use; stop the existing server or choose a different --port. $error',
    );
  } finally {
    await socket?.close();
  }
}

Future<void> _waitForPort(int port, Process owner) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    final exitCode = await _pollExitCode(owner);
    if (exitCode != null) {
      throw StateError(
        'Background server exited before port $port became ready (exit code $exitCode).',
      );
    }
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      await socket.close();
      final lateExitCode = await _pollExitCode(owner);
      if (lateExitCode != null) {
        throw StateError(
          'Background server exited after opening port $port (exit code $lateExitCode).',
        );
      }
      return;
    } on Object catch (error) {
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  throw StateError(
    'Timed out waiting for local server on port $port: $lastError',
  );
}

Future<int?> _pollExitCode(Process process) async {
  try {
    return await process.exitCode.timeout(Duration.zero);
  } on TimeoutException {
    return null;
  }
}

String _defaultPython(String projectRoot) {
  final localPython = Platform.isWindows
      ? '$projectRoot/.dart_tool/playwright-python/Scripts/python.exe'
      : '$projectRoot/.dart_tool/playwright-python/bin/python';
  if (File(localPython).existsSync()) {
    return localPython;
  }
  return 'python3';
}

String _formatScenarioList(List<LocalE2eScenario> scenarios) {
  final buffer = StringBuffer()
    ..writeln('Local-only E2E scenarios:')
    ..writeln('');
  for (final group in LocalE2eScenarioGroup.values) {
    buffer.writeln('${group.label}:');
    for (final scenario in scenarios.where((item) => item.group == group)) {
      final deviceHint = scenario.requiresDevice ? ' --device <device>' : '';
      buffer.writeln('  ${scenario.name}$deviceHint');
      buffer.writeln('    ${scenario.description}');
    }
    buffer.writeln('');
  }
  buffer.writeln(
    'Run with: dart run tool/testing/run_local_e2e.dart --scenario <name> --dry-run',
  );
  return buffer.toString();
}

String _formatDryRun(
  LocalE2eScenario scenario,
  List<LocalE2eCommandStep> steps,
  LocalE2eDisplayShell? shell,
) {
  final buffer = StringBuffer()
    ..writeln('Scenario: ${scenario.name}')
    ..writeln('Group: ${scenario.group.label}')
    ..writeln('Description: ${scenario.description}')
    ..writeln('')
    ..writeln('Commands:');
  for (final step in steps) {
    buffer.writeln('- ${step.description}:');
    buffer.writeln('  ${step.toDisplayString(shell: shell)}');
  }
  return buffer.toString();
}

String _usage() {
  return '''Usage: dart run tool/testing/run_local_e2e.dart [options]

Options:
  --list                         List available local-only scenarios.
  --scenario <name>              Scenario to run or dry-run.
  --dry-run                      Print commands without executing them.
  --device <device>              Flutter device id for device scenarios (default: macos).
  --port <port>                  Local web server port (default: 7358).
  --python <path>                Python executable for helper scripts (default: repo Playwright venv, then python3).
  --model-path <path>            Local model path for Dart local-only model scenarios.
  --tokenizer-path <path>        Local tokenizer JSON path for dedicated ASR scenarios.
  --model-preset <name>          Dedicated ASR preset (default: moonshine-tiny).
  --draft-model-path <path>      Optional draft GGUF model path for llama.cpp speculative benchmark.
  --mmproj-path <path>           Optional multimodal projector path for GGUF chat smoke.
  --image-path <path>            Optional image path for GGUF chat smoke multimodal variant.
  --audio-path <path>            Complete audio fixture for speech-to-text or native audio-chat smoke.
  --head-path <path>             Decision head safetensors for decision-model-smoke.
  --config-path <path>           Optional decision head config JSON for head files without laya.config metadata.
  --model-url <url>              Model URL for real-model web smoke.
  --mmproj-url <url>             Projector URL for real-model web smoke.
  --backend <name>               Backend for local model scenarios (default: auto; decision-model-smoke: cpu).
  --browser <name>               LiteRT-LM Web history and Gemma 4 smoke browser: chrome (default) or safari (safaridriver).
  --speculative-cases <list>     Benchmark cases for llama.cpp speculative benchmark.
  --benchmark-gpu-layers <n>     GPU layers for benchmark scenarios (default: 0).
  --benchmark-max-tokens <n>     Max tokens for benchmark scenarios (default: 128).
  --benchmark-runs <n>           Measured runs for benchmark scenarios (default: 3).
  --benchmark-warmups <n>        Warmup runs for benchmark scenarios (default: 1).
  --draft-token-max <list>       Draft-token sweep for speculative benchmark (default: 1,2).
  --ngram-size <n>               Optional n-gram size for speculative benchmark.
  --ngram-size-m <list>          Effective draft length sweep for ngram-simple/map benchmark cases.
  --ngram-token-max <n>          Optional ngram-mod token cap for speculative benchmark.
  --ngram-cache-static-path <p>  Optional ngram-cache static path for speculative benchmark.
  --ngram-cache-dynamic-path <p> Optional ngram-cache dynamic path for speculative benchmark.
  --ngram-cache-build-static-path <p>
                                 Build a static ngram-cache file before speculative benchmark.
  --ngram-cache-build-text <txt> Optional source text for generated ngram-cache static file
                                 (defaults to the resolved benchmark prompt).
  --expect <text>                Exact expected transcript/answer, or expected real-model Web response.
  --allow-any-response           Accept any non-empty real-model Web response.
  --skip-build                   Reuse an existing Flutter web build where supported.
  -h, --help                     Show this help.

Direct environment for test/e2e/backends/prompt_cancel_e2e_test.dart:
  PROMPT_CANCEL_THREADS          CPU threads for the model (default: 4).

Direct environment for test/e2e/backends/llama_cpp_exit_teardown_e2e_test.dart:
  EXIT_TEARDOWN_RUNS             Runs of each exit scenario (default: 3).
  EXIT_TEARDOWN_MMPROJ           The model's projector; unset skips quit-projector and
                                 quit-disposing.
  EXIT_TEARDOWN_DECISION_MODEL   Encoder GGUF; unset, or without the head, skips
                                 quit-decision.
  EXIT_TEARDOWN_DECISION_HEAD    Decision head safetensors for that encoder.

Direct environment for example/basic_app/test/image_exit_teardown_e2e_test.dart:
  IMAGE_EXIT_RUNS                Runs of each exit scenario (default: 3).
  IMAGE_EXIT_GGUF                GGUF chat model; unset skips quit-both-loaded.

Direct environment for example/chat_app/test/macos_quit_e2e_test.dart:
  MACOS_QUIT_IMAGE_MODEL         Image checkpoint to load too; unset loads the chat
                                 model only.
  MACOS_QUIT_RUNS                Runs of each clean quit (default: 3).
  MACOS_QUIT_BUILD_MODES         Builds to quit (default: debug,release).

Direct environment for example/chat_app/test/flutter_shutdown_e2e_test.dart:
  FLUTTER_SHUTDOWN_HEADERS       Extracted header bundle matching the runtime.
  MACOS_QUIT_RUNS                Runs of each active quit (default: 3).
  MACOS_QUIT_BUILD_MODES         Builds to quit (default: debug,release).

Direct environment for tool/litert_lm_chat_features_smoke.dart:
  LITERT_LM_TOKENIZER_FIXTURE    qwen3-0.6b checks only the known Qwen artifacts.
  LITERT_LM_IMAGE_PATH           Optional local image fixture.
  LITERT_LM_AUDIO_PATH           Optional local encoded audio fixture.
  LITERT_LM_AUDIO_EXPECTED_TEXT  Required exact expected answer when audio is set.

Direct environment for tool/litert_lm_asr_smoke.dart:
  LLAMADART_LITERT_LM_LIBRARY_PATH
                                 Optional explicit bridge-enabled runtime library.

Direct environment for tool/gguf_chat_features_smoke.dart:
  GGUF_AUDIO_PATH                Optional local encoded WAV fixture.
  GGUF_AUDIO_EXPECTED_TEXT       Required exact expected answer when audio is set.

Direct environment for test/e2e/backends/decision_engine_e2e_test.dart:
  LLAMADART_DECISION_LOGIT_TOLERANCE
                                 Largest raw marker-logit difference (default: 0.25).
  LLAMADART_DECISION_PROB_TOLERANCE
                                 Largest probability, confidence and noul difference
                                 (default: 0.05); scores get twice this, and a choice
                                 may differ when Laya's top-2 gap is within it.
  LLAMADART_DECISION_ACT_LOGIT_TOLERANCE
                                 Largest raw action-logit difference relative to the
                                 row's largest reference action logit (default: 0.05).
''';
}

String _shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  final safe = RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$');
  if (safe.hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}

String _powerShellQuote(String value) {
  // Excludes `,` and `@`, which PowerShell parses as array and splat syntax.
  final safe = RegExp(r'^[A-Za-z0-9_%+=:./\\-]+$');
  if (value.isNotEmpty && safe.hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "''")}'";
}

class _ParsedArgs {
  const _ParsedArgs({
    required this.list,
    required this.help,
    required this.dryRun,
    required this.device,
    required this.port,
    required this.python,
    required this.pythonProvided,
    required this.modelPreset,
    required this.backend,
    required this.backendProvided,
    required this.speculativeCases,
    required this.benchmarkGpuLayers,
    required this.benchmarkMaxTokens,
    required this.benchmarkRuns,
    required this.benchmarkWarmups,
    required this.draftTokenMaxList,
    required this.expect,
    required this.expectProvided,
    required this.allowAnyResponse,
    required this.skipBuild,
    this.scenario,
    this.modelPath,
    this.tokenizerPath,
    this.draftModelPath,
    this.mmprojPath,
    this.imagePath,
    this.audioPath,
    this.headPath,
    this.configPath,
    this.modelUrl,
    this.mmprojUrl,
    this.ngramSize,
    this.browser,
    this.ngramSizeM,
    this.ngramTokenMax,
    this.ngramCacheStaticPath,
    this.ngramCacheDynamicPath,
    this.ngramCacheBuildStaticPath,
    this.ngramCacheBuildText,
  });

  final bool list;
  final bool help;
  final bool dryRun;
  final String? scenario;
  final String device;
  final int port;
  final String python;
  final bool pythonProvided;
  final String? modelPath;
  final String? tokenizerPath;
  final String modelPreset;
  final String? draftModelPath;
  final String? mmprojPath;
  final String? imagePath;
  final String? audioPath;
  final String? headPath;
  final String? configPath;
  final String? modelUrl;
  final String? mmprojUrl;
  final String backend;
  final bool backendProvided;
  final String speculativeCases;
  final String benchmarkGpuLayers;
  final String benchmarkMaxTokens;
  final String benchmarkRuns;
  final String benchmarkWarmups;
  final String draftTokenMaxList;
  final String? ngramSize;
  final String? browser;
  final String? ngramSizeM;
  final String? ngramTokenMax;
  final String? ngramCacheStaticPath;
  final String? ngramCacheDynamicPath;
  final String? ngramCacheBuildStaticPath;
  final String? ngramCacheBuildText;
  final String expect;
  final bool expectProvided;
  final bool allowAnyResponse;
  final bool skipBuild;

  factory _ParsedArgs.parse(List<String> args) {
    var list = false;
    var help = false;
    var dryRun = false;
    var device = 'macos';
    var port = 7358;
    var python = 'python3';
    var pythonProvided = false;
    var backend = 'auto';
    var backendProvided = false;
    var speculativeCases =
        'baseline,ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,mixed-ngram';
    var benchmarkGpuLayers = '0';
    var benchmarkMaxTokens = '128';
    var benchmarkRuns = '3';
    var benchmarkWarmups = '1';
    var draftTokenMaxList = '1,2';
    var expect = '4';
    var expectProvided = false;
    var allowAnyResponse = false;
    var skipBuild = false;
    var modelPreset = 'moonshine-tiny';
    String? scenario;
    String? modelPath;
    String? tokenizerPath;
    String? draftModelPath;
    String? mmprojPath;
    String? imagePath;
    String? audioPath;
    String? headPath;
    String? configPath;
    String? modelUrl;
    String? mmprojUrl;
    String? ngramSize;
    String? browser;
    String? ngramSizeM;
    String? ngramTokenMax;
    String? ngramCacheStaticPath;
    String? ngramCacheDynamicPath;
    String? ngramCacheBuildStaticPath;
    String? ngramCacheBuildText;

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      switch (arg) {
        case '--list':
          list = true;
        case '--help' || '-h':
          help = true;
        case '--dry-run':
          dryRun = true;
        case '--skip-build':
          skipBuild = true;
        case '--allow-any-response':
          allowAnyResponse = true;
        case '--scenario':
          scenario = _readValue(args, ++index, arg);
        case '--device':
          device = _readValue(args, ++index, arg);
        case '--port':
          port = int.parse(_readValue(args, ++index, arg));
        case '--python':
          python = _readValue(args, ++index, arg);
          pythonProvided = true;
        case '--model-path':
          modelPath = _readValue(args, ++index, arg);
        case '--tokenizer-path':
          tokenizerPath = _readValue(args, ++index, arg);
        case '--model-preset':
          modelPreset = _readValue(args, ++index, arg);
        case '--draft-model-path':
          draftModelPath = _readValue(args, ++index, arg);
        case '--mmproj-path':
          mmprojPath = _readValue(args, ++index, arg);
        case '--image-path':
          imagePath = _readValue(args, ++index, arg);
        case '--audio-path':
          audioPath = _readValue(args, ++index, arg);
        case '--head-path':
          headPath = _readValue(args, ++index, arg);
        case '--config-path':
          configPath = _readValue(args, ++index, arg);
        case '--model-url':
          modelUrl = _readValue(args, ++index, arg);
        case '--mmproj-url':
          mmprojUrl = _readValue(args, ++index, arg);
        case '--backend':
          backend = _readValue(args, ++index, arg);
          backendProvided = true;
        case '--speculative-cases':
          speculativeCases = _readValue(args, ++index, arg);
        case '--benchmark-gpu-layers':
          benchmarkGpuLayers = _readValue(args, ++index, arg);
        case '--benchmark-max-tokens':
          benchmarkMaxTokens = _readValue(args, ++index, arg);
        case '--benchmark-runs':
          benchmarkRuns = _readValue(args, ++index, arg);
        case '--benchmark-warmups':
          benchmarkWarmups = _readValue(args, ++index, arg);
        case '--draft-token-max':
          draftTokenMaxList = _readValue(args, ++index, arg);
        case '--ngram-size':
          ngramSize = _readValue(args, ++index, arg);
        case '--browser':
          browser = _readValue(args, ++index, arg);
        case '--ngram-size-m':
          ngramSizeM = _readValue(args, ++index, arg);
        case '--ngram-token-max':
          ngramTokenMax = _readValue(args, ++index, arg);
        case '--ngram-cache-static-path':
          ngramCacheStaticPath = _readValue(args, ++index, arg);
        case '--ngram-cache-dynamic-path':
          ngramCacheDynamicPath = _readValue(args, ++index, arg);
        case '--ngram-cache-build-static-path':
          ngramCacheBuildStaticPath = _readValue(args, ++index, arg);
        case '--ngram-cache-build-text':
          ngramCacheBuildText = _readValue(args, ++index, arg);
        case '--expect':
          expect = _readValue(args, ++index, arg);
          expectProvided = true;
        default:
          throw ArgumentError('Unknown option: $arg');
      }
    }

    return _ParsedArgs(
      list: list,
      help: help,
      dryRun: dryRun,
      scenario: scenario,
      device: device,
      port: port,
      python: python,
      pythonProvided: pythonProvided,
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      modelPreset: modelPreset,
      draftModelPath: draftModelPath,
      mmprojPath: mmprojPath,
      imagePath: imagePath,
      audioPath: audioPath,
      headPath: headPath,
      configPath: configPath,
      modelUrl: modelUrl,
      mmprojUrl: mmprojUrl,
      backend: backend,
      backendProvided: backendProvided,
      speculativeCases: speculativeCases,
      benchmarkGpuLayers: benchmarkGpuLayers,
      benchmarkMaxTokens: benchmarkMaxTokens,
      benchmarkRuns: benchmarkRuns,
      benchmarkWarmups: benchmarkWarmups,
      draftTokenMaxList: draftTokenMaxList,
      ngramSize: ngramSize,
      browser: browser,
      ngramSizeM: ngramSizeM,
      ngramTokenMax: ngramTokenMax,
      ngramCacheStaticPath: ngramCacheStaticPath,
      ngramCacheDynamicPath: ngramCacheDynamicPath,
      ngramCacheBuildStaticPath: ngramCacheBuildStaticPath,
      ngramCacheBuildText: ngramCacheBuildText,
      expect: expect,
      expectProvided: expectProvided,
      allowAnyResponse: allowAnyResponse,
      skipBuild: skipBuild,
    );
  }

  static String _readValue(List<String> args, int index, String option) {
    if (index >= args.length) {
      throw ArgumentError('Missing value for $option');
    }
    return args[index];
  }
}

Future<void> main(List<String> args) async {
  LocalE2eResult result;
  try {
    result = await runLocalE2e(args);
  } on FormatException catch (error) {
    result = LocalE2eResult(64, stderr: '${error.message}\n');
  } on ArgumentError catch (error) {
    result = LocalE2eResult(64, stderr: '$error\n');
  }

  if (result.stdout.isNotEmpty) {
    stdout.write(result.stdout);
  }
  if (result.stderr.isNotEmpty) {
    stderr.write(result.stderr);
  }
  await stdout.flush();
  await stderr.flush();
  exit(result.exitCode);
}

bool _isRemoteModel(String model) =>
    RegExp(r'^https?://', caseSensitive: false).hasMatch(model);
