#!/usr/bin/env dart

import 'dart:async';
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
  });

  final String workingDirectory;
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final String description;
  final bool background;
  final int? waitForPort;

  String toDisplayString() {
    final envPrefix = environment.entries
        .map((entry) => '${entry.key}=${_shellQuote(entry.value)}')
        .join(' ');
    final command = [executable, ...arguments].map(_shellQuote).join(' ');
    final rendered = envPrefix.isEmpty ? command : '$envPrefix $command';
    final suffix = background ? ' &' : '';
    return 'cd ${_shellQuote(workingDirectory)} && $rendered$suffix';
  }
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
    required this.draftModelPath,
    required this.mmprojPath,
    required this.imagePath,
    required this.modelUrl,
    required this.backend,
    required this.speculativeCases,
    required this.benchmarkGpuLayers,
    required this.benchmarkMaxTokens,
    required this.benchmarkRuns,
    required this.benchmarkWarmups,
    required this.draftTokenMaxList,
    required this.ngramSize,
    required this.ngramSizeM,
    required this.ngramTokenMax,
    required this.ngramCacheStaticPath,
    required this.ngramCacheDynamicPath,
    required this.ngramCacheBuildStaticPath,
    required this.ngramCacheBuildText,
    required this.expect,
    required this.allowAnyResponse,
    required this.skipBuild,
  });

  final String projectRoot;
  final String device;
  final int port;
  final String python;
  final String? modelPath;
  final String? draftModelPath;
  final String? mmprojPath;
  final String? imagePath;
  final String? modelUrl;
  final String backend;
  final String speculativeCases;
  final String benchmarkGpuLayers;
  final String benchmarkMaxTokens;
  final String benchmarkRuns;
  final String benchmarkWarmups;
  final String draftTokenMaxList;
  final String? ngramSize;
  final String? ngramSizeM;
  final String? ngramTokenMax;
  final String? ngramCacheStaticPath;
  final String? ngramCacheDynamicPath;
  final String? ngramCacheBuildStaticPath;
  final String? ngramCacheBuildText;
  final String expect;
  final bool allowAnyResponse;
  final bool skipBuild;

  String get chatAppDir => '$projectRoot/example/chat_app';
  String get chatAppWebDir => '$chatAppDir/web';
  String get webBuildUrl =>
      'http://127.0.0.1:$port/example/chat_app/build/web/';
  String get defaultModelUrl =>
      'http://127.0.0.1:$port/example/llamadart_server/models/Qwen3.5-0.8B-Q4_K_M.gguf';
  String get defaultLiteRtLmWebModelUrl =>
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.litertlm?download=true';
  String get defaultGemma4WebGpuModelUrl =>
      'http://127.0.0.1:$port/example/llamadart_server/models/gemma-4-E2B-it-Q4_K_S.gguf';
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

  List<LocalE2eCommandStep> steps(LocalE2eRunContext context) =>
      stepsBuilder(context);
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

List<LocalE2eScenario> buildLocalE2eScenarios({String? projectRoot}) {
  return [
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
            'test/e2e/template',
          ],
          description: 'Dart template E2E',
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
      name: 'gguf-chat-features-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description:
          'Run real GGUF chat, thinking-budget/suppression, and tool-call smoke.',
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
            description: 'GGUF chat feature smoke',
          ),
        ];
      },
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
      name: 'litert-lm-chat-features-smoke',
      group: LocalE2eScenarioGroup.dartLocalOnly,
      description: 'Run real LiteRT-LM chat, thinking, and tool-call smoke.',
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
      name: 'chat-app-web-real-model-smoke',
      group: LocalE2eScenarioGroup.webSmoke,
      description:
          'Build chat_app web and run the real-model Playwright smoke.',
      requiresDevice: false,
      stepsBuilder: (context) {
        final steps = <LocalE2eCommandStep>[_prepareChatAppWebBuild(context)];
        final smokeArguments = <String>[
          'tool/testing/playwright_chat_app_real_model_smoke.py',
          context.webBuildUrl,
          '--model-url',
          context.modelUrl ?? context.defaultModelUrl,
          '--expect',
          context.expect,
          if (context.allowAnyResponse) '--allow-any-response',
        ];
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
            description: 'Run Playwright real-model chat app smoke',
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
      description: 'Run the cheap WebGPU bridge bootstrap smoke.',
      requiresDevice: false,
      stepsBuilder: (context) => [
        LocalE2eCommandStep(
          workingDirectory: context.chatAppWebDir,
          executable: context.python,
          arguments: [
            '-m',
            'http.server',
            '${context.port}',
            '--bind',
            '127.0.0.1',
          ],
          description: 'Serve repo root for bridge smoke',
          background: true,
          waitForPort: context.port,
        ),
        LocalE2eCommandStep(
          workingDirectory: context.projectRoot,
          executable: context.python,
          arguments: [
            'tool/testing/playwright_bridge_smoke.py',
            'http://127.0.0.1:${context.port}',
          ],
          description: 'Run bridge smoke',
        ),
      ],
    ),
  ];
}

Future<LocalE2eResult> runLocalE2e(
  List<String> args, {
  String? projectRoot,
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
  if (parsed.mmprojPath != null && parsed.modelPath == null) {
    return LocalE2eResult(64, stderr: '--mmproj-path requires --model-path.\n');
  }
  if (parsed.imagePath != null && parsed.mmprojPath == null) {
    return LocalE2eResult(64, stderr: '--image-path requires --mmproj-path.\n');
  }
  if ((scenario.name == 'llama-cpp-speculative-benchmark' ||
          scenario.name == 'llama-cpp-chat-template-smoke' ||
          scenario.name == 'litert-lm-chat-features-smoke') &&
      parsed.modelPath == null) {
    return LocalE2eResult(
      64,
      stderr: '--model-path is required for ${scenario.name}.\n',
    );
  }

  final context = LocalE2eRunContext(
    projectRoot: root,
    device: parsed.device,
    port: parsed.port,
    python: parsed.pythonProvided ? parsed.python : _defaultPython(root),
    modelPath: parsed.modelPath,
    draftModelPath: parsed.draftModelPath,
    mmprojPath: parsed.mmprojPath,
    imagePath: parsed.imagePath,
    modelUrl: parsed.modelUrl,
    backend: parsed.backend,
    speculativeCases: parsed.speculativeCases,
    benchmarkGpuLayers: parsed.benchmarkGpuLayers,
    benchmarkMaxTokens: parsed.benchmarkMaxTokens,
    benchmarkRuns: parsed.benchmarkRuns,
    benchmarkWarmups: parsed.benchmarkWarmups,
    draftTokenMaxList: parsed.draftTokenMaxList,
    ngramSize: parsed.ngramSize,
    ngramSizeM: parsed.ngramSizeM,
    ngramTokenMax: parsed.ngramTokenMax,
    ngramCacheStaticPath: parsed.ngramCacheStaticPath,
    ngramCacheDynamicPath: parsed.ngramCacheDynamicPath,
    ngramCacheBuildStaticPath: parsed.ngramCacheBuildStaticPath,
    ngramCacheBuildText: parsed.ngramCacheBuildText,
    expect: parsed.expect,
    allowAnyResponse: parsed.allowAnyResponse,
    skipBuild: parsed.skipBuild,
  );
  final steps = scenario.steps(context);

  if (parsed.dryRun) {
    return LocalE2eResult(0, stdout: _formatDryRun(scenario, steps));
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
          await _ensurePortAvailable(port);
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
          await _waitForPort(port, process);
        }
        continue;
      }

      final result = await Process.run(
        step.executable,
        step.arguments,
        workingDirectory: step.workingDirectory,
        environment: step.environment.isEmpty ? null : step.environment,
        runInShell: false,
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
) {
  final buffer = StringBuffer()
    ..writeln('Scenario: ${scenario.name}')
    ..writeln('Group: ${scenario.group.label}')
    ..writeln('Description: ${scenario.description}')
    ..writeln('')
    ..writeln('Commands:');
  for (final step in steps) {
    buffer.writeln('- ${step.description}:');
    buffer.writeln('  ${step.toDisplayString()}');
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
  --draft-model-path <path>      Optional draft GGUF model path for llama.cpp speculative benchmark.
  --mmproj-path <path>           Optional multimodal projector path for GGUF chat smoke.
  --image-path <path>            Optional image path for GGUF chat smoke multimodal variant.
  --model-url <url>              Model URL for real-model web smoke.
  --backend <name>               Backend for local model scenarios (default: auto).
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
  --expect <text>                Expected response text for real-model web smoke.
  --allow-any-response           Accept any non-empty real-model Web response.
  --skip-build                   Reuse an existing Flutter web build where supported.
  -h, --help                     Show this help.
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

class _ParsedArgs {
  const _ParsedArgs({
    required this.list,
    required this.help,
    required this.dryRun,
    required this.device,
    required this.port,
    required this.python,
    required this.pythonProvided,
    required this.backend,
    required this.speculativeCases,
    required this.benchmarkGpuLayers,
    required this.benchmarkMaxTokens,
    required this.benchmarkRuns,
    required this.benchmarkWarmups,
    required this.draftTokenMaxList,
    required this.expect,
    required this.allowAnyResponse,
    required this.skipBuild,
    this.scenario,
    this.modelPath,
    this.draftModelPath,
    this.mmprojPath,
    this.imagePath,
    this.modelUrl,
    this.ngramSize,
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
  final String? draftModelPath;
  final String? mmprojPath;
  final String? imagePath;
  final String? modelUrl;
  final String backend;
  final String speculativeCases;
  final String benchmarkGpuLayers;
  final String benchmarkMaxTokens;
  final String benchmarkRuns;
  final String benchmarkWarmups;
  final String draftTokenMaxList;
  final String? ngramSize;
  final String? ngramSizeM;
  final String? ngramTokenMax;
  final String? ngramCacheStaticPath;
  final String? ngramCacheDynamicPath;
  final String? ngramCacheBuildStaticPath;
  final String? ngramCacheBuildText;
  final String expect;
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
    var speculativeCases =
        'baseline,ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,mixed-ngram';
    var benchmarkGpuLayers = '0';
    var benchmarkMaxTokens = '128';
    var benchmarkRuns = '3';
    var benchmarkWarmups = '1';
    var draftTokenMaxList = '1,2';
    var expect = '4';
    var allowAnyResponse = false;
    var skipBuild = false;
    String? scenario;
    String? modelPath;
    String? draftModelPath;
    String? mmprojPath;
    String? imagePath;
    String? modelUrl;
    String? ngramSize;
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
        case '--draft-model-path':
          draftModelPath = _readValue(args, ++index, arg);
        case '--mmproj-path':
          mmprojPath = _readValue(args, ++index, arg);
        case '--image-path':
          imagePath = _readValue(args, ++index, arg);
        case '--model-url':
          modelUrl = _readValue(args, ++index, arg);
        case '--backend':
          backend = _readValue(args, ++index, arg);
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
      draftModelPath: draftModelPath,
      mmprojPath: mmprojPath,
      imagePath: imagePath,
      modelUrl: modelUrl,
      backend: backend,
      speculativeCases: speculativeCases,
      benchmarkGpuLayers: benchmarkGpuLayers,
      benchmarkMaxTokens: benchmarkMaxTokens,
      benchmarkRuns: benchmarkRuns,
      benchmarkWarmups: benchmarkWarmups,
      draftTokenMaxList: draftTokenMaxList,
      ngramSize: ngramSize,
      ngramSizeM: ngramSizeM,
      ngramTokenMax: ngramTokenMax,
      ngramCacheStaticPath: ngramCacheStaticPath,
      ngramCacheDynamicPath: ngramCacheDynamicPath,
      ngramCacheBuildStaticPath: ngramCacheBuildStaticPath,
      ngramCacheBuildText: ngramCacheBuildText,
      expect: expect,
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
