@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../../tool/audio_chat_smoke_support.dart';
import '../../../tool/testing/run_local_e2e.dart';

void main() {
  group('default native consumer AOT scenario', () {
    const identity = {
      'LLAMADART_DEFAULT_AOT_EXPECTED_SHA':
          '1111111111111111111111111111111111111111',
      'LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG': 'v0.8.0-2',
      'LLAMADART_DEFAULT_AOT_MODEL_PATH': '/local/Qwen fixture.gguf',
      'LLAMADART_DEFAULT_AOT_OUTPUT_ROOT': '/local/fresh evidence',
    };
    test(
      'list and outer dry-run never execute the qualification driver',
      () async {
        Future<ProcessResult> forbidden(LocalE2eCommandStep step) async {
          fail('list/dry-run must not launch ${step.executable}');
        }

        final listed = await runLocalE2e(
          ['--list'],
          projectRoot: '/repo',
          environment: {},
          foregroundStepRun: forbidden,
        );
        expect(listed.stdout, contains('native-default-consumer-aot'));
        final inspected = await runLocalE2e(
          ['--scenario', 'native-default-consumer-aot', '--dry-run'],
          projectRoot: '/repo',
          environment: {},
          foregroundStepRun: forbidden,
        );
        expect(inspected.exitCode, 0);
        expect(
          inspected.stdout,
          contains('native_default_consumer_qualification/qualify.py'),
        );
        for (final variable in identity.keys) {
          expect(inspected.stdout, contains('<$variable>'));
        }
      },
    );
    test(
      'execution requires independent identity and passes opaque paths as argv',
      () async {
        var launches = 0;
        Future<ProcessResult> inspect(LocalE2eCommandStep step) async {
          launches++;
          expect(step.workingDirectory, '/repo');
          expect(step.background, isFalse);
          expect(step.environment, {'PYTHONDONTWRITEBYTECODE': '1'});
          expect(step.arguments, [
            'test/fixtures/native_default_consumer_qualification/qualify.py',
            '--core-root',
            '/repo',
            '--expected-core-sha',
            identity['LLAMADART_DEFAULT_AOT_EXPECTED_SHA'],
            '--expected-native-tag',
            'v0.8.0-2',
            '--model',
            '/local/Qwen fixture.gguf',
            '--output',
            '/local/fresh evidence',
          ]);
          return ProcessResult(1, 7, '', 'synthetic qualification failure');
        }

        for (final missing in identity.keys) {
          final result = await runLocalE2e(
            ['--scenario', 'native-default-consumer-aot'],
            projectRoot: '/repo',
            environment: {...identity}..remove(missing),
            foregroundStepRun: inspect,
          );
          expect(result.exitCode, 64);
        }
        for (final malformed in [
          'BAD',
          '0000000000000000000000000000000000000000',
        ]) {
          final result = await runLocalE2e(
            ['--scenario', 'native-default-consumer-aot'],
            projectRoot: '/repo',
            environment: {
              ...identity,
              'LLAMADART_DEFAULT_AOT_EXPECTED_SHA': malformed,
            },
            foregroundStepRun: inspect,
          );
          expect(result.exitCode, 64);
        }
        final wrongTag = await runLocalE2e(
          ['--scenario', 'native-default-consumer-aot'],
          projectRoot: '/repo',
          environment: {
            ...identity,
            'LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG': 'v0.8.0-1',
          },
          foregroundStepRun: inspect,
        );
        expect(wrongTag.exitCode, 64);
        expect(launches, 0);
        final actual = await runLocalE2e(
          ['--scenario', 'native-default-consumer-aot'],
          projectRoot: '/repo',
          environment: identity,
          foregroundStepRun: inspect,
        );
        expect(actual.exitCode, 7);
        expect(launches, 1);
      },
    );
  });
  group('foreground output decoding', () {
    late Directory directory;
    late File child;
    late File nativeDiagnostic;
    const nativePrefix =
        'llama_model_loader: - kv  19:                      '
        'tokenizer.ggml.merges arr[str,63683]   = '
        '["Ċ Ċ", "Ċ ĊĊ", "ĊĊ Ċ", "Ċ ';

    setUp(() {
      directory = Directory.systemTemp.createTempSync('local-e2e-output-');
      // Native v0.8.0 cuts this metadata preview inside the final Ċ.
      nativeDiagnostic = File('${directory.path}/native-diagnostic.bin')
        ..writeAsBytesSync([
          ...utf8.encode(nativePrefix),
          0xc4,
          ...ascii.encode('...\n'),
        ]);
      child = File('${directory.path}/output.dart')
        ..writeAsStringSync(r'''
import 'dart:io';
Future<void> main(List<String> args) async {
  final output = args[0] == 'stdout' ? stdout : stderr;
  final bytes = switch (args[1]) {
    'malformed' => [0xe2, 0x21],
    'truncated' => [0xe2, 0x82],
    'native-metadata' => File(args[3]).readAsBytesSync(),
    'unicode' => [0xe2, 0x82, 0xac, 0xf0, 0x9f, 0x8c, 0xb2],
    _ => systemEncoding.encode('native café'),
  };
  output.add(bytes.sublist(0, 1));
  await output.flush();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  output.add(bytes.sublist(1));
  await output.flush();
  exit(int.parse(args[2]));
}
''');
    });

    tearDown(() => directory.deleteSync(recursive: true));

    LocalE2eCommandStep step(
      String stream,
      String mode,
      int exitCode, {
      Encoding stdoutEncoding = systemEncoding,
    }) => LocalE2eCommandStep(
      workingDirectory: directory.path,
      executable: Platform.resolvedExecutable,
      arguments: [child.path, stream, mode, '$exitCode', nativeDiagnostic.path],
      description: 'Child output fixture',
      foregroundStdoutEncoding: stdoutEncoding,
    );

    for (final stream in ['stdout', 'stderr']) {
      for (final mode in ['malformed', 'truncated', 'native-metadata']) {
        for (final exitCode in [0, 7]) {
          test('$mode $stream diagnostics preserve exit $exitCode', () async {
            final result = await runLocalE2e(
              ['--scenario', 'gguf-stop-sequences'],
              projectRoot: directory.path,
              foregroundStepRun: (_) =>
                  runLocalE2eForegroundStep(step(stream, mode, exitCode)),
            );
            expect(result.exitCode, exitCode);
            final expected = switch (mode) {
              'native-metadata' =>
                Platform.isWindows
                    ? systemEncoding.decode(nativeDiagnostic.readAsBytesSync())
                    : '$nativePrefix\uFFFD...\n',
              _ =>
                Platform.isWindows
                    ? systemEncoding.decode([
                        0xe2,
                        mode == 'malformed' ? 0x21 : 0x82,
                      ])
                    : mode == 'malformed'
                    ? '\uFFFD!'
                    : '\uFFFD',
            };
            expect(result.stdout, contains(expected));
            expect(result.stderr, isEmpty);
          });
        }
      }

      test('$stream retains the platform encoding', () async {
        final result = await runLocalE2eForegroundStep(
          step(stream, 'system', 0),
        );
        expect(result.exitCode, 0);
        expect(
          stream == 'stdout' ? result.stdout : result.stderr,
          systemEncoding.decode(systemEncoding.encode('native café')),
        );
      });

      test(
        'split UTF-8 $stream stays intact',
        () async {
          final result = await runLocalE2eForegroundStep(
            step(stream, 'unicode', 0, stdoutEncoding: utf8),
          );
          expect(result.exitCode, 0);
          expect(stream == 'stdout' ? result.stdout : result.stderr, '€🌲');
        },
        skip: stream == 'stderr' && Platform.isWindows
            ? 'Windows diagnostics use the system code page tested above.'
            : false,
      );
    }

    test('explicit UTF-8 stdout rejects a malformed protocol', () async {
      final result = await runLocalE2e(
        ['--scenario', 'qwen3-litert-cpu-unicode', '--model-path', '/fixture'],
        projectRoot: directory.path,
        foregroundStepRun: (command) {
          expect(command.foregroundStdoutEncoding, same(utf8));
          return runLocalE2eForegroundStep(
            step(
              'stdout',
              'malformed',
              0,
              stdoutEncoding: command.foregroundStdoutEncoding,
            ),
          );
        },
      );
      expect(result.exitCode, 1);
      expect(result.stderr, contains('FormatException'));
    });

    test('explicit UTF-8 stdout still tolerates stderr diagnostics', () async {
      final result = await runLocalE2eForegroundStep(
        step('stderr', 'malformed', 0, stdoutEncoding: utf8),
      );
      expect(result.exitCode, 0);
      expect(result.stdout, isEmpty);
      expect(result.stderr, isNotEmpty);
    });

    test('an explicit stdout codec is retained', () async {
      final result = await runLocalE2eForegroundStep(
        step('stdout', 'malformed', 0, stdoutEncoding: latin1),
      );
      expect(result.exitCode, 0);
      expect(result.stdout, 'â!');
    });

    test(
      'the CLI uses diagnostic decoding and strict protocol decoding',
      () async {
        final runner = File(
          'tool/testing/run_local_e2e.dart',
        ).copySync('${directory.path}/runner.dart');
        final shim = File('${directory.path}/dart');
        String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
        for (final stream in ['stdout', 'stderr']) {
          for (final exitCode in [0, 7]) {
            shim.writeAsStringSync(
              '#!/bin/sh\nexec ${quote(Platform.resolvedExecutable)} '
              '${quote(child.path)} $stream malformed $exitCode\n',
            );
            expect((await Process.run('chmod', ['+x', shim.path])).exitCode, 0);
            final result = await Process.run(
              Platform.resolvedExecutable,
              [runner.path, '--scenario', 'gguf-stop-sequences'],
              workingDirectory: directory.path,
              environment: {
                'PATH': '${directory.path}:${Platform.environment['PATH']}',
              },
            );
            expect(result.exitCode, exitCode);
            expect(result.stdout, contains('\uFFFD!'));
            expect(result.stderr, isEmpty);
          }
        }
        shim.writeAsStringSync(
          '#!/bin/sh\nexec ${quote(Platform.resolvedExecutable)} '
          '${quote(child.path)} stdout malformed 0\n',
        );
        final protocol = await Process.run(
          Platform.resolvedExecutable,
          [
            runner.path,
            '--scenario',
            'qwen3-litert-cpu-unicode',
            '--model-path',
            '/fixture',
          ],
          workingDirectory: directory.path,
          environment: {
            'PATH': '${directory.path}:${Platform.environment['PATH']}',
          },
        );
        expect(protocol.exitCode, 1);
        expect(protocol.stderr, contains('FormatException'));
      },
      skip: Platform.isWindows ? 'Uses a POSIX executable shim.' : false,
    );

    test('process launch errors remain failures', () async {
      final missing = LocalE2eCommandStep(
        workingDirectory: directory.path,
        executable: '${directory.path}/missing-executable',
        arguments: const [],
        description: 'Missing executable',
      );
      await expectLater(
        runLocalE2eForegroundStep(missing),
        throwsA(isA<ProcessException>()),
      );
      final result = await runLocalE2e(
        ['--scenario', 'gguf-stop-sequences'],
        projectRoot: directory.path,
        foregroundStepRun: (_) => runLocalE2eForegroundStep(missing),
      );
      expect(result.exitCode, 1);
      expect(result.stderr, contains('ProcessException'));
    });
  });

  test(
    'native JSON Schema scenario consumes the maintained test, local model and backend',
    () async {
      const scenario = 'litert-lm-json-schema';
      const model = '/local/corrected-Qwen3.litertlm';
      const target = 'test/e2e/backends/litert_lm_json_schema_e2e_test.dart';
      final listed = await runLocalE2e(['--list'], projectRoot: '/repo');
      expect(listed.exitCode, 0);
      expect(listed.stdout, contains(scenario));
      final steps = <LocalE2eCommandStep>[];
      Future<ProcessResult> capture(LocalE2eCommandStep step) async {
        steps.add(step);
        return ProcessResult(0, 0, '', '');
      }

      for (final invalid in [
        ['--scenario', scenario],
        ['--scenario', scenario, '--model-path', model],
        for (final backend in ['auto', 'npu'])
          ['--scenario', scenario, '--model-path', model, '--backend', backend],
      ]) {
        final result = await runLocalE2e(
          invalid,
          projectRoot: '/repo',
          foregroundStepRun: capture,
        );
        expect(result.exitCode, 64);
        expect(
          steps,
          isEmpty,
          reason: 'rejected requests must not dispatch a child',
        );
      }
      final args = [
        '--scenario',
        scenario,
        '--model-path',
        model,
        '--backend',
        'cpu',
      ];
      final dry = await runLocalE2e(
        [...args, '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(dry.exitCode, 0);
      expect(dry.stdout, contains('LITERT_LM_MODEL=$model'));
      expect(
        dry.stdout,
        contains('dart test -p vm -j 1 --run-skipped -t local-only $target'),
      );
      final dispatched = await runLocalE2e(
        args,
        projectRoot: '/repo',
        foregroundStepRun: capture,
      );
      expect(dispatched.exitCode, 0);
      final step = steps.single;
      expect(step.executable, 'dart');
      expect(step.workingDirectory, '/repo');
      expect(step.arguments, [
        'test',
        '-p',
        'vm',
        '-j',
        '1',
        '--run-skipped',
        '-t',
        'local-only',
        target,
      ]);
      expect(step.environment, {
        'LITERT_LM_MODEL': model,
        'LITERT_LM_BACKEND': 'cpu',
      });
      steps.clear();
      final gpu = await runLocalE2e(
        [...args.take(4), '--backend', 'gpu'],
        projectRoot: '/repo',
        foregroundStepRun: capture,
      );
      expect(gpu.exitCode, 0);
      expect(steps.single.environment['LITERT_LM_BACKEND'], 'gpu');
      expect(step.background, isFalse);
      expect(File(target).existsSync(), isTrue);
    },
  );

  test(
    'LiteRT Web history requires an explicit backend and local model',
    () async {
      for (final args in [
        ['--scenario', 'litert-lm-web-text-history', '--dry-run'],
        [
          '--scenario',
          'litert-lm-web-text-history',
          '--model-path',
          'model.litertlm',
          '--dry-run',
        ],
        [
          '--scenario',
          'litert-lm-web-text-history',
          '--model-path',
          'model.litertlm',
          '--backend',
          'npu',
          '--dry-run',
        ],
        [
          '--scenario',
          'litert-lm-web-text-history',
          '--backend',
          'cpu',
          '--dry-run',
        ],
      ]) {
        expect((await runLocalE2e(args, projectRoot: '/repo')).exitCode, 64);
      }
      for (final backend in ['cpu', 'gpu']) {
        final result = await runLocalE2e(
          [
            '--scenario',
            'litert-lm-web-text-history',
            '--model-path',
            'models/existing.litertlm',
            '--backend',
            backend,
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains(
            'python3 tool/testing/litert_text_history_web_e2e.py --model-path models/existing.litertlm --backend $backend',
          ),
        );
        expect(result.stdout, isNot(contains('build web')));
        expect(result.stdout, isNot(contains('download')));
      }
    },
  );

  test('LiteRT Web tool calling requires a backend and local model and runs the '
      'tool-calling suite', () async {
    for (final args in [
      ['--scenario', 'litert-lm-web-tool-calling', '--dry-run'],
      [
        '--scenario',
        'litert-lm-web-tool-calling',
        '--model-path',
        'model.litertlm',
        '--dry-run',
      ],
      [
        '--scenario',
        'litert-lm-web-tool-calling',
        '--backend',
        'cpu',
        '--dry-run',
      ],
    ]) {
      expect((await runLocalE2e(args, projectRoot: '/repo')).exitCode, 64);
    }
    final result = await runLocalE2e(
      [
        '--scenario',
        'litert-lm-web-tool-calling',
        '--model-path',
        'models/existing.litertlm',
        '--backend',
        'cpu',
        '--dry-run',
      ],
      projectRoot: '/repo',
      displayShell: LocalE2eDisplayShell.posix,
    );
    expect(result.exitCode, 0);
    expect(
      result.stdout,
      contains(
        'python3 tool/testing/litert_text_history_web_e2e.py --model-path models/existing.litertlm --backend cpu --suite tool-calling',
      ),
    );
    expect(result.stdout, isNot(contains('download')));
  });

  test('LiteRT Web truncation requires a backend and local model and runs the '
      'truncation suite', () async {
    for (final args in [
      ['--scenario', 'litert-lm-web-truncation', '--dry-run'],
      [
        '--scenario',
        'litert-lm-web-truncation',
        '--model-path',
        'model.litertlm',
        '--dry-run',
      ],
      [
        '--scenario',
        'litert-lm-web-truncation',
        '--backend',
        'cpu',
        '--dry-run',
      ],
    ]) {
      expect((await runLocalE2e(args, projectRoot: '/repo')).exitCode, 64);
    }
    final result = await runLocalE2e(
      [
        '--scenario',
        'litert-lm-web-truncation',
        '--model-path',
        'models/existing.litertlm',
        '--backend',
        'cpu',
        '--dry-run',
      ],
      projectRoot: '/repo',
      displayShell: LocalE2eDisplayShell.posix,
    );
    expect(result.exitCode, 0);
    expect(
      result.stdout,
      contains(
        'python3 tool/testing/litert_text_history_web_e2e.py --model-path models/existing.litertlm --backend cpu --suite truncation',
      ),
    );
    expect(result.stdout, isNot(contains('download')));
  });

  test(
    'LiteRT Web scenarios leave the browser to the Chrome default',
    () async {
      final chatApp = await runLocalE2e(
        [
          '--scenario',
          'chat-app-web-litert-gemma4-smoke',
          '--skip-build',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(chatApp.exitCode, 0);
      expect(chatApp.stdout, contains('--response-timeout-ms 600000'));
      expect(chatApp.stdout, isNot(contains('--browser')));
      final history = await runLocalE2e(
        [
          '--scenario',
          'litert-lm-web-text-history',
          '--model-path',
          'models/existing.litertlm',
          '--backend',
          'gpu',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(history.exitCode, 0);
      expect(history.stdout, contains('litert_text_history_web_e2e.py'));
      expect(history.stdout, isNot(contains('--browser')));
    },
  );

  test('LiteRT Web scenarios forward only a supported --browser', () async {
    const history = [
      '--scenario',
      'litert-lm-web-text-history',
      '--model-path',
      'models/existing.litertlm',
      '--backend',
      'gpu',
      '--dry-run',
    ];
    final safari = await runLocalE2e(
      [...history, '--browser', 'safari'],
      projectRoot: '/repo',
      displayShell: LocalE2eDisplayShell.posix,
    );
    expect(safari.exitCode, 0);
    expect(
      safari.stdout,
      contains(
        'litert_text_history_web_e2e.py --model-path models/existing.litertlm --backend gpu --browser safari',
      ),
    );
    final chatApp = await runLocalE2e(
      [
        '--scenario',
        'chat-app-web-litert-gemma4-smoke',
        '--skip-build',
        '--browser',
        'safari',
        '--dry-run',
      ],
      projectRoot: '/repo',
      displayShell: LocalE2eDisplayShell.posix,
    );
    expect(chatApp.exitCode, 0);
    expect(
      chatApp.stdout,
      contains('--response-timeout-ms 600000 --browser safari'),
    );
    for (final args in [
      [...history, '--browser', 'firefox'],
      ['--scenario', 'chat-app-web-mock-smoke', '--browser', 'safari'],
    ]) {
      final result = await runLocalE2e(args, projectRoot: '/repo');
      expect(result.exitCode, 64);
      expect(result.stderr, contains('--browser chrome or safari'));
    }
  });

  test(
    'Qwen scenario preserves UTF-8 stdout from the real child process',
    () async {
      final project = await Directory.systemTemp.createTemp(
        'qwen-utf8-runner-',
      );
      addTearDown(() => project.delete(recursive: true));
      await File('${project.path}/pubspec.yaml').writeAsString(
        'name: qwen_stdout_fixture\nenvironment:\n  sdk: ^3.10.7\n',
      );
      final tool = await Directory('${project.path}/tool').create();
      await File(
        '${tool.path}/litert_lm_chat_features_smoke.dart',
      ).writeAsString(
        "import 'dart:convert';\n"
        "import 'dart:io';\n"
        'void main() {\n'
        "  stdout.add(utf8.encode(jsonEncode({'decoded': 'Hello! 😊', "
        "'literal': 'ĠðŁĺĬ', 'mixed': 'café 한글 日本語'})));\n"
        '}\n',
      );
      final result = await runLocalE2e([
        '--scenario',
        'qwen3-litert-cpu-unicode',
        '--model-path',
        'fixture.litertlm',
      ], projectRoot: project.path);
      expect(result.exitCode, 0, reason: result.stderr);
      final start = result.stdout.indexOf('{"decoded":');
      expect(start, greaterThanOrEqualTo(0), reason: result.stdout);
      expect(jsonDecode(result.stdout.substring(start)), {
        'decoded': 'Hello! 😊',
        'literal': 'ĠðŁĺĬ',
        'mixed': 'café 한글 日本語',
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'text retrieval scenario requires both artifacts and opts into local tests',
    () async {
      const environment = {
        'LLAMADART_EMBEDDINGGEMMA2_MODEL_PATH': '/local/model.gguf',
        'LLAMADART_EG2_RETRIEVAL_REFERENCE': '/local/reference.json',
      };
      for (final missing in environment.keys) {
        final result = await runLocalE2e(
          ['--scenario', 'text-embedding-retrieval', '--dry-run'],
          projectRoot: '/repo',
          environment: {...environment}..remove(missing),
        );
        expect(result.exitCode, 64);
        expect(result.stderr, contains(missing));
      }
      final result = await runLocalE2e(
        ['--scenario', 'text-embedding-retrieval', '--dry-run'],
        projectRoot: '/repo',
        environment: environment,
      );
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains('embeddinggemma2_retrieval_e2e_test.dart'),
      );
      expect(result.stdout, contains('--run-skipped'));
      expect(result.stdout, contains('--tags local-only'));
    },
  );

  test(
    'native multimodal embedding qualification requires local weights and references',
    () async {
      const environment = {
        'LLAMADART_EMBEDDING_MODELS_DIR': '/local/models',
        'LLAMADART_EMBEDDING_REFERENCE_CPU': '/local/cpu.json',
        'LLAMADART_EMBEDDING_REFERENCE_METAL': '/local/metal.json',
      };
      for (final missing in environment.keys) {
        final result = await runLocalE2e(
          ['--scenario', 'native-multimodal-embeddings', '--dry-run'],
          projectRoot: '/repo',
          environment: {...environment}..remove(missing),
        );
        expect(result.exitCode, 64);
        expect(result.stderr, contains(missing));
      }
      final result = await runLocalE2e(
        ['--scenario', 'native-multimodal-embeddings', '--dry-run'],
        projectRoot: '/repo',
        environment: environment,
      );
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains('multimodal_embedding_native_e2e_test.dart'),
      );
      expect(result.stdout, contains('--tags local-only'));
    },
  );

  test(
    'Qwen Unicode scenario wires the exact fixture and forces CPU',
    () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'qwen3-litert-cpu-unicode',
          '--model-path',
          'models/Qwen3-0.6B.litertlm',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(result.exitCode, 0);
      expect(result.stdout, contains('LITERT_LM_TOKENIZER_FIXTURE=qwen3-0.6b'));
      expect(
        result.stdout,
        contains(
          'tool/litert_lm_chat_features_smoke.dart '
          'models/Qwen3-0.6B.litertlm cpu',
        ),
      );
      for (final args in [
        ['--scenario', 'qwen3-litert-cpu-unicode', '--dry-run'],
        [
          '--scenario',
          'qwen3-litert-cpu-unicode',
          '--model-path',
          'model',
          '--backend',
          'gpu',
          '--dry-run',
        ],
      ]) {
        final invalid = await runLocalE2e(args, projectRoot: '/repo');
        expect(invalid.exitCode, 64);
      }
    },
  );

  for (final route in ['direct', 'service', 'speech']) {
    test(
      'public v1 $route requires identities and reaches its uninjected qualifier',
      () async {
        final args = [
          '--scenario',
          'litert-lm-v1-public-$route',
          '--model-path',
          '/model',
          '--backend',
          'cpu',
          '--dry-run',
        ];
        final identity = {
          'LITERT_LM_V1_LIBRARY': '/candidate/libLiteRtLm.dylib',
          'LITERT_LM_V1_RUNTIME_MANIFEST': '/candidate/runtime.json',
          'LITERT_LM_V1_PUBLIC_CONFIG': '/candidate/config.json',
          for (final name in [
            'LIBRARY',
            'MODEL',
            'RUNTIME_MANIFEST',
            'PUBLIC_CONFIG',
          ])
            'LITERT_LM_V1_${name}_SHA256': 'a' * 64,
        };
        final valid = await runLocalE2e(
          args,
          projectRoot: '/repo',
          environment: identity,
        );
        expect(valid.exitCode, 0, reason: valid.stderr);
        expect(
          valid.stdout,
          contains(
            'test/fixtures/litert_lm_v1_public_qualification.dart $route',
          ),
        );
        expect(valid.stdout, contains('/candidate/runtime.json'));
        expect(valid.stdout, isNot(contains('--expect-disabled')));
        for (final name in identity.keys) {
          final missing = await runLocalE2e(
            args,
            projectRoot: '/repo',
            environment: {...identity}..remove(name),
          );
          expect(missing.exitCode, 64, reason: name);
          expect(missing.stderr, contains(name));
        }
        final missingModel = await runLocalE2e(
          [
            '--scenario',
            'litert-lm-v1-public-$route',
            '--backend',
            'cpu',
            '--dry-run',
          ],
          projectRoot: '/repo',
          environment: identity,
        );
        expect(missingModel.exitCode, 64);
        final gpu = await runLocalE2e(
          [for (final arg in args) arg == 'cpu' ? 'gpu' : arg],
          projectRoot: '/repo',
          environment: identity,
        );
        expect(gpu.exitCode, 64);
      },
    );
  }

  group('run_local_e2e', () {
    test(
      'v1 ASR requires full inputs and digests and wires bounded wrapper',
      () async {
        const args = [
          '--scenario',
          'litert-lm-v1-asr-smoke',
          '--model-path',
          '/speech',
          '--tokenizer-path',
          '/tokenizer',
          '--audio-path',
          '/audio.wav',
          '--model-preset',
          'moonshine-tiny',
          '--expect',
          'country',
          '--backend',
          'cpu',
          '--dry-run',
        ];
        final identity = {
          'LITERT_LM_V1_LIBRARY': '/candidate/libLiteRtLm.dylib',
          for (final name in ['LIBRARY', 'MODEL', 'TOKENIZER', 'AUDIO'])
            'LITERT_LM_V1_${name}_SHA256': 'a' * 64,
        };
        final valid = await runLocalE2e(
          args,
          projectRoot: '/repo',
          environment: identity,
        );
        expect(valid.exitCode, 0);
        expect(
          valid.stdout,
          contains('test/fixtures/litert_lm_v1_asr_qualification.dart'),
        );
        expect(valid.stdout, contains('/tokenizer'));
        for (final name in [
          'LITERT_LM_V1_TOKENIZER_SHA256',
          'LITERT_LM_V1_AUDIO_SHA256',
        ]) {
          final invalid = await runLocalE2e(
            args,
            projectRoot: '/repo',
            environment: {...identity, name: 'bad'},
          );
          expect(invalid.exitCode, 64);
          expect(invalid.stderr, contains(name));
        }
        final gpu = await runLocalE2e(
          [for (final value in args) value == 'cpu' ? 'gpu' : value],
          projectRoot: '/repo',
          environment: identity,
        );
        expect(gpu.exitCode, 64);
        expect(
          gpu.stderr,
          contains('--backend cpu is required for litert-lm-v1-asr-smoke'),
        );
        final missing = await runLocalE2e(
          const ['--scenario', 'litert-lm-v1-asr-smoke', '--dry-run'],
          projectRoot: '/repo',
          environment: identity,
        );
        expect(missing.exitCode, 64);
      },
    );
    test(
      'v1 service qualification requires model, CPU and exact input digests',
      () async {
        final identity = <String, String>{
          'LITERT_LM_V1_LIBRARY': '/candidate/libLiteRtLm.dylib',
          'LITERT_LM_V1_LIBRARY_SHA256': 'a' * 64,
          'LITERT_LM_V1_MODEL_SHA256': 'b' * 64,
        };
        final missingModel = await runLocalE2e(
          const [
            '--scenario',
            'litert-lm-v1-service',
            '--backend',
            'cpu',
            '--dry-run',
          ],
          projectRoot: '/repo',
          environment: identity,
        );
        expect(missingModel.exitCode, 64);
        expect(missingModel.stderr, contains('--model-path is required'));
        final gpu = await runLocalE2e(
          const [
            '--scenario',
            'litert-lm-v1-service',
            '--model-path',
            '/Qwen3-0.6B.litertlm',
            '--backend',
            'gpu',
            '--dry-run',
          ],
          projectRoot: '/repo',
          environment: identity,
        );
        expect(gpu.exitCode, 64);
        expect(gpu.stderr, contains('--backend cpu'));
        for (final name in identity.keys) {
          final missing = await runLocalE2e(
            const [
              '--scenario',
              'litert-lm-v1-service',
              '--model-path',
              '/Qwen3-0.6B.litertlm',
              '--backend',
              'cpu',
              '--dry-run',
            ],
            projectRoot: '/repo',
            environment: {...identity}..remove(name),
          );
          expect(missing.exitCode, 64);
          expect(missing.stderr, contains(name));
        }
        final malformed = await runLocalE2e(
          const [
            '--scenario',
            'litert-lm-v1-service',
            '--model-path',
            '/Qwen3-0.6B.litertlm',
            '--backend',
            'cpu',
            '--dry-run',
          ],
          projectRoot: '/repo',
          environment: {...identity, 'LITERT_LM_V1_MODEL_SHA256': '555579'},
        );
        expect(malformed.exitCode, 64);
        expect(malformed.stderr, contains('64 hexadecimal digits'));
      },
    );

    test(
      'v1 service dry-run wires the bounded local-only exact-byte harness',
      () async {
        final result = await runLocalE2e(
          const [
            '--scenario',
            'litert-lm-v1-service',
            '--model-path',
            '/Qwen3-0.6B.litertlm',
            '--backend',
            'cpu',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
          environment: {
            'LITERT_LM_V1_LIBRARY': '/candidate/libLiteRtLm.dylib',
            'LITERT_LM_V1_LIBRARY_SHA256': 'a' * 64,
            'LITERT_LM_V1_MODEL_SHA256': 'b' * 64,
            'LITERT_LM_V1_LOG_DIR': '/evidence',
          },
        );
        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains('LITERT_LM_V1_MODEL=/Qwen3-0.6B.litertlm'),
        );
        expect(
          result.stdout,
          contains('LITERT_LM_V1_LIBRARY=/candidate/libLiteRtLm.dylib'),
        );
        expect(result.stdout, contains('LITERT_LM_V1_LOG_DIR=/evidence'));
        expect(result.stdout, contains('--run-skipped'));
        expect(
          result.stdout,
          contains('test/e2e/backends/litert_lm_v1_service_e2e_test.dart'),
        );
      },
    );

    test(
      'thinking qualifier enforces fixed model, CPU and complete payload identity',
      () async {
        final identity = {
          'LITERT_LM_V1_LIBRARY': '/candidate/libLiteRtLm.dylib',
          'LITERT_LM_V1_LIBRARY_SHA256': 'a' * 64,
          'LITERT_LM_V1_MODEL_SHA256':
              '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
          'LITERT_LM_V1_RUNTIME_MANIFEST': '/candidate/payloads.json',
          'LITERT_LM_V1_RUNTIME_MANIFEST_SHA256': 'c' * 64,
        };
        const arguments = [
          '--scenario',
          'litert-lm-v1-thinking-budget',
          '--model-path',
          '/Gemma.litertlm',
          '--backend',
          'cpu',
          '--dry-run',
        ];
        for (final name in identity.keys) {
          final result = await runLocalE2e(
            arguments,
            projectRoot: '/repo',
            environment: {...identity}..remove(name),
          );
          expect(result.exitCode, 64);
          expect(result.stderr, contains(name));
        }
        final wrongModel = await runLocalE2e(
          arguments,
          projectRoot: '/repo',
          environment: {...identity, 'LITERT_LM_V1_MODEL_SHA256': 'b' * 64},
        );
        expect(wrongModel.exitCode, 64);
        expect(wrongModel.stderr, contains('fixed maintained Gemma'));
        final malformedManifest = await runLocalE2e(
          arguments,
          projectRoot: '/repo',
          environment: {
            ...identity,
            'LITERT_LM_V1_RUNTIME_MANIFEST_SHA256': 'bad',
          },
        );
        expect(malformedManifest.exitCode, 64);
        final gpu = await runLocalE2e(
          arguments.map((arg) => arg == 'cpu' ? 'gpu' : arg).toList(),
          projectRoot: '/repo',
          environment: identity,
        );
        expect(gpu.exitCode, 64);
        final missingModel = await runLocalE2e(
          const [
            '--scenario',
            'litert-lm-v1-thinking-budget',
            '--backend',
            'cpu',
            '--dry-run',
          ],
          projectRoot: '/repo',
          environment: identity,
        );
        expect(missingModel.exitCode, 64);
        final valid = await runLocalE2e(
          arguments,
          projectRoot: '/repo',
          environment: {...identity, 'LITERT_LM_V1_LOG_DIR': '/evidence'},
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(valid.exitCode, 0);
        expect(
          valid.stdout,
          contains('test/e2e/backends/litert_lm_v1_thinking_e2e_test.dart'),
        );
        expect(
          valid.stdout,
          contains('LITERT_LM_V1_RUNTIME_MANIFEST=/candidate/payloads.json'),
        );
        expect(
          valid.stdout,
          contains('LITERT_LM_V1_RUNTIME_MANIFEST_SHA256=${'c' * 64}'),
        );
        expect(valid.stdout, contains('LITERT_LM_V1_LOG_DIR=/evidence'));
      },
    );

    test('documents shared runner options and defaults', () async {
      final result = await runLocalE2e(const ['--help'], projectRoot: '/repo');

      expect(result.exitCode, 0);
      expect(result.stdout, contains('--ngram-cache-build-text <txt>'));
      expect(result.stdout, contains('--ngram-token-max <n>'));
      expect(result.stdout, contains('--allow-any-response'));
      expect(result.stdout, contains('--mmproj-url <url>'));
      expect(result.stdout, contains('GGUF_AUDIO_EXPECTED_TEXT'));
      expect(result.stdout, contains('LLAMADART_LITERT_LM_LIBRARY_PATH'));
      expect(result.stdout, contains('--head-path <path>'));
      expect(result.stdout, contains('--config-path <path>'));
      expect(result.stdout, contains('LLAMADART_DECISION_LOGIT_TOLERANCE'));
      expect(result.stdout, contains('LLAMADART_DECISION_PROB_TOLERANCE'));
      expect(result.stdout, contains('LLAMADART_DECISION_ACT_LOGIT_TOLERANCE'));
      expect(
        result.stdout,
        contains('defaults to the resolved benchmark prompt'),
      );
    });

    group('dry-run display shell', () {
      const foreground = LocalE2eCommandStep(
        workingDirectory: "C:\\work\\it's repo",
        executable: 'dart',
        arguments: ['test', '--name', 'a b', 'x,y', '@file', ''],
        environment: {'MODEL_PATH': r'C:\models\m.gguf', 'NOTE': "it's"},
        description: 'Foreground step',
      );
      const background = LocalE2eCommandStep(
        workingDirectory: '/repo',
        executable: 'python3',
        arguments: ['serve.py', '--port', '7358'],
        description: 'Background step',
        background: true,
      );

      test('renders POSIX syntax for posix shells', () {
        expect(
          foreground.toDisplayString(shell: LocalE2eDisplayShell.posix),
          "cd 'C:\\work\\it'\\''s repo' && "
          "MODEL_PATH='C:\\models\\m.gguf' NOTE='it'\\''s' "
          "dart test --name 'a b' x,y @file ''",
        );
        expect(
          background.toDisplayString(shell: LocalE2eDisplayShell.posix),
          'cd /repo && python3 serve.py --port 7358 &',
        );
      });

      test('renders PowerShell syntax for Windows', () {
        expect(
          foreground.toDisplayString(shell: LocalE2eDisplayShell.powerShell),
          "Set-Location -LiteralPath 'C:\\work\\it''s repo'; "
          r"$env:MODEL_PATH = C:\models\m.gguf; "
          r"$env:NOTE = 'it''s'; "
          "dart test --name 'a b' 'x,y' '@file' ''",
        );
        expect(
          background.toDisplayString(shell: LocalE2eDisplayShell.powerShell),
          'Set-Location -LiteralPath /repo; '
          'Start-Process -NoNewWindow -FilePath python3 '
          '-ArgumentList serve.py,--port,7358',
        );
      });

      test('uses the call operator for a quoted PowerShell executable', () {
        const step = LocalE2eCommandStep(
          workingDirectory: '/repo',
          executable: r'C:\Program Files\Python\python.exe',
          arguments: ['-V'],
          description: 'Quoted executable',
        );

        expect(
          step.toDisplayString(shell: LocalE2eDisplayShell.powerShell),
          "Set-Location -LiteralPath /repo; "
          "& 'C:\\Program Files\\Python\\python.exe' -V",
        );
      });

      test('defaults to the host platform shell', () {
        expect(
          LocalE2eDisplayShell.host,
          Platform.isWindows
              ? LocalE2eDisplayShell.powerShell
              : LocalE2eDisplayShell.posix,
        );
        expect(
          background.toDisplayString(),
          background.toDisplayString(shell: LocalE2eDisplayShell.host),
        );
      });

      test('--dry-run prints the injected shell syntax', () async {
        Future<String> dryRun(LocalE2eDisplayShell shell) async {
          final result = await runLocalE2e(
            const ['--scenario', 'root-template-e2e', '--dry-run'],
            projectRoot: '/repo',
            displayShell: shell,
          );
          expect(result.exitCode, 0);
          return result.stdout;
        }

        final posix = await dryRun(LocalE2eDisplayShell.posix);
        expect(posix, contains('  cd /repo && LLAMA_CPP_GBNF_VALIDATOR='));
        expect(posix, isNot(contains('Set-Location')));

        final powerShell = await dryRun(LocalE2eDisplayShell.powerShell);
        expect(
          powerShell,
          contains(
            r'  Set-Location -LiteralPath /repo; $env:LLAMA_CPP_GBNF_VALIDATOR = ',
          ),
        );
        expect(powerShell, isNot(contains(' && ')));
        expect(powerShell, isNot(contains('  cd ')));
      });
    });

    test('lists local-only Dart, Flutter, and Web smoke scenarios', () async {
      final result = await runLocalE2e(const ['--list'], projectRoot: '/repo');

      expect(result.exitCode, 0);
      expect(result.stdout, contains('root-template-e2e'));
      expect(result.stdout, contains('qwen35-multimodal-macos-repro'));
      expect(result.stdout, contains('gguf-chat-features-smoke'));
      expect(result.stdout, contains('gguf-audio-chat-smoke'));
      expect(result.stdout, contains('speech-to-text-smoke'));
      expect(result.stdout, contains('litert-lm-asr-smoke'));
      expect(result.stdout, contains('decision-model-smoke'));
      expect(result.stdout, contains('decision-model-web-smoke'));
      expect(result.stdout, contains('web-speech-task-cancel'));
      expect(result.stdout, contains('llama-cpp-speculative-benchmark'));
      expect(result.stdout, contains('llama-cpp-chat-template-smoke'));
      expect(result.stdout, contains('litert-lm-chat-features-smoke'));
      expect(result.stdout, contains('webgpu-multimodal-regression'));
      expect(result.stdout, contains('chat-app-model-cache'));
      expect(result.stdout, contains('chat-app-web-real-model-smoke'));
      expect(result.stdout, contains('chat-app-web-tool-penalty-smoke'));
      expect(result.stdout, contains('chat-app-web-speech-to-text-smoke'));
      expect(result.stdout, contains('chat-app-web-text-to-speech-smoke'));
      expect(result.stdout, contains('chat-app-web-mock-smoke'));
      expect(result.stdout, contains('chat-app-web-litert-gemma4-smoke'));
      expect(result.stdout, contains('bridge-smoke'));
      expect(result.stdout, contains('Dart local-only'));
      expect(result.stdout, contains('Flutter device'));
      expect(result.stdout, contains('Web smoke'));
    });

    test(
      'Android Perfetto plan checks evidence before an offline model-free build',
      () async {
        final result = await runLocalE2e(
          const ['--scenario', 'android-perfetto-capability', '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        final commands = result.stdout
            .split('\n')
            .where((line) => line.startsWith('  cd '))
            .toList();
        expect(commands, hasLength(2));
        expect(commands.first, contains('python3 -m unittest discover'));
        expect(
          commands.first,
          contains('tool/testing/validation/android_perfetto'),
        );
        expect(commands.last, contains('--offline --no-daemon'));
        expect(commands.last, contains('app:testDebugUnitTest'));
        expect(commands.last, contains('app:assembleDebugAndroidTest'));
        expect(result.stdout, isNot(contains('gcloud firebase')));
        expect(result.stdout, isNot(contains('--model-path is required')));
        expect(result.stdout, isNot(contains('--device is required')));
      },
    );

    test('builds the GBNF validator before the grammar test uses it', () async {
      final result = await runLocalE2e(
        const ['--scenario', 'root-template-e2e', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      final buildDir =
          Platform.environment['LLAMA_CPP_RUNTIME_BUILD_DIR'] ??
          '/repo/.dart_tool/llama_cpp_runtime_build';

      expect(result.exitCode, 0);
      final chatTests = result.stdout.indexOf(
        'dart test --run-skipped -t local-only '
        'test/e2e/template/llama_cpp_chat_tests_e2e_test.dart',
      );
      final validatorBuild = result.stdout.indexOf(
        'bash tool/testing/build_llama_cpp_runtime_gbnf_validator.sh',
      );
      final grammarTests = result.stdout.indexOf(
        'LLAMA_CPP_GBNF_VALIDATOR=$buildDir/bin/test-gbnf-validator '
        'dart test --run-skipped -t local-only '
        'test/e2e/template/specialized_tool_grammar_validation_e2e_test.dart',
      );
      expect(chatTests, isNonNegative);
      expect(validatorBuild, greaterThan(chatTests));
      expect(grammarTests, greaterThan(validatorBuild));
      final templateTests = Directory('test/e2e/template')
          .listSync()
          .whereType<File>()
          .map((file) => file.path.replaceAll(r'\', '/'))
          .where((path) => path.endsWith('_test.dart'));
      expect(templateTests, isNotEmpty);
      for (final path in templateTests) {
        expect(result.stdout, contains(path));
      }
    });

    test('wires CPU runtime utility qualification without downloads', () async {
      final missing = await runLocalE2e(
        const ['--scenario', 'litert-lm-utility-preservation', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(missing.exitCode, 64);
      expect(missing.stderr, contains('--model-path is required'));
      final result = await runLocalE2e(
        const [
          '--scenario',
          'litert-lm-utility-preservation',
          '--model-path',
          '/model.litertlm',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains('LITERT_LM_UTILITY_MODEL=/model.litertlm'),
      );
      expect(
        result.stdout,
        contains(
          'dart test --run-skipped -p vm -j 1 -t local-only '
          'test/e2e/backends/litert_lm_utility_preservation_e2e_test.dart',
        ),
      );
      expect(result.stdout, isNot(contains('curl')));
      expect(result.stdout, isNot(contains('wget')));
      final gpu = await runLocalE2e(
        const [
          '--scenario',
          'litert-lm-utility-preservation',
          '--model-path',
          '/model.litertlm',
          '--backend',
          'gpu',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(gpu.exitCode, 64);
      expect(gpu.stderr, contains('requires --backend cpu'));
    });

    test(
      'wires hash-pinned CPU image preservation without downloads',
      () async {
        final missing = await runLocalE2e(
          const ['--scenario', 'litert-lm-media-preservation', '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(missing.exitCode, 64);
        expect(missing.stderr, contains('--model-path is required'));
        final result = await runLocalE2e(
          const [
            '--scenario',
            'litert-lm-media-preservation',
            '--model-path',
            '/model.litertlm',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains('LITERT_LM_VISION_MODEL=/model.litertlm'),
        );
        expect(
          result.stdout,
          contains(
            'dart test --run-skipped -p vm -j 1 -t local-only '
            'test/e2e/backends/litert_lm_media_preservation_e2e_test.dart',
          ),
        );
        expect(result.stdout, isNot(contains('curl')));
        expect(result.stdout, isNot(contains('wget')));
        final gpu = await runLocalE2e(
          const [
            '--scenario',
            'litert-lm-media-preservation',
            '--model-path',
            '/model.litertlm',
            '--backend',
            'gpu',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(gpu.exitCode, 64);
        expect(gpu.stderr, contains('requires --backend cpu'));
      },
    );

    test(
      'requires a model and wires the bounded LiteRT lifecycle scenario',
      () async {
        final missing = await runLocalE2e(
          const ['--scenario', 'litert-lm-lifecycle', '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(missing.exitCode, 64);
        final result = await runLocalE2e(
          const [
            '--scenario',
            'litert-lm-lifecycle',
            '--model-path',
            '/model.litertlm',
            '--backend',
            'gpu',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(result.exitCode, 0);
        expect(result.stdout, contains('LITERT_LM_MODEL=/model.litertlm'));
        expect(result.stdout, contains('LITERT_LM_BACKEND=gpu'));
        expect(
          result.stdout,
          contains('test/e2e/backends/litert_lm_lifecycle_e2e_test.dart'),
        );
      },
    );

    test(
      'requires a model and wires the native prompt cancel scenario',
      () async {
        final missing = await runLocalE2e(
          const ['--scenario', 'native-prompt-cancel', '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(missing.exitCode, 64);
        final result = await runLocalE2e(
          const [
            '--scenario',
            'native-prompt-cancel',
            '--model-path',
            '/model.gguf',
            '--backend',
            'metal',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(result.exitCode, 0);
        expect(result.stdout, contains('PROMPT_CANCEL_MODEL=/model.gguf'));
        expect(result.stdout, contains('PROMPT_CANCEL_BACKEND=metal'));
        expect(
          result.stdout,
          contains('test/e2e/backends/prompt_cancel_e2e_test.dart'),
        );
      },
    );

    test(
      'requires a model and wires the native exit teardown scenario',
      () async {
        final missing = await runLocalE2e(
          const ['--scenario', 'native-exit-teardown', '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(missing.exitCode, 64);
        final result = await runLocalE2e(
          const [
            '--scenario',
            'native-exit-teardown',
            '--model-path',
            '/model.gguf',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(result.exitCode, 0);
        expect(result.stdout, contains('EXIT_TEARDOWN_MODEL=/model.gguf'));
        expect(
          result.stdout,
          contains('test/e2e/backends/llama_cpp_exit_teardown_e2e_test.dart'),
        );
      },
    );

    test(
      'dry-runs a Flutter device scenario with the requested device',
      () async {
        final result = await runLocalE2e(
          const [
            '--scenario',
            'chat-app-model-cache',
            '--device',
            'macos',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains('chat-app-model-cache'));
        expect(
          result.stdout,
          contains(
            'cd /repo/example/chat_app && '
            '/repo/tool/testing/without_app_nap.sh '
            'com.example.llamaDartChatExample flutter test --run-skipped '
            '-t local-only integration_test/model_cache_mmproj_e2e_test.dart '
            '-d macos',
          ),
        );
      },
    );

    test('runs macOS device scenarios with App Nap disabled', () async {
      final deviceScenarios = buildLocalE2eScenarios(projectRoot: '/repo')
          .where(
            (scenario) =>
                scenario.group == LocalE2eScenarioGroup.flutterDevice &&
                scenario.requiresDevice,
          )
          .map((scenario) => scenario.name)
          .toList();
      expect(deviceScenarios, contains('chat-app-text-image-coexistence'));

      for (final name in deviceScenarios) {
        Future<String> dryRun(String device) async {
          final result = await runLocalE2e(
            [
              '--scenario',
              name,
              '--device',
              device,
              if (name == 'chat-app-litert-json-schema') ...[
                '--model-path',
                '/m.litertlm',
                '--backend',
                'cpu',
              ],
              '--dry-run',
            ],
            projectRoot: '/repo',
            displayShell: LocalE2eDisplayShell.posix,
          );
          expect(result.exitCode, 0, reason: '$name: ${result.stderr}');
          return result.stdout;
        }

        final macos = await dryRun('macos');
        expect(
          macos,
          contains(
            'cd /repo/example/chat_app && '
            '/repo/tool/testing/without_app_nap.sh '
            'com.example.llamaDartChatExample flutter test ',
          ),
          reason: name,
        );
        expect(
          macos,
          isNot(contains('&& flutter test')),
          reason: '$name runs Flutter without the App Nap guard',
        );
        expect(
          await dryRun('ios'),
          isNot(contains('without_app_nap')),
          reason: name,
        );
      }
    });

    test('dry-runs the LiteRT-LM reload memory device scenario', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-litert-reload-memory',
          '--device',
          'macos',
          '--model-path',
          '/models/Qwen3-0.6B.litertlm',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo/example/chat_app && '
          '/repo/tool/testing/without_app_nap.sh '
          'com.example.llamaDartChatExample flutter test --run-skipped '
          '-t local-only '
          'integration_test/litert_lm_reload_memory_e2e_test.dart '
          '-d macos '
          '--dart-define=LITERT_RELOAD_MODEL=/models/Qwen3-0.6B.litertlm',
        ),
      );
    });

    test('the reload memory scenario downloads the model by default', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-litert-reload-memory',
          '--device',
          'android',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('-d android'));
      expect(result.stdout, isNot(contains('LITERT_RELOAD_MODEL')));
    });

    test('dry-runs the native JSON Schema device scenario', () async {
      Future<LocalE2eResult> dryRun(List<String> extra) => runLocalE2e(
        [
          '--scenario',
          'chat-app-litert-json-schema',
          '--device',
          'android',
          ...extra,
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      for (final invalid in [
        ['--backend', 'cpu'],
        ['--model-path', '/m.litertlm'],
        ['--model-path', '/m.litertlm', '--backend', 'npu'],
        for (final secret in [
          'https://user:token@example.com/m.litertlm',
          'https://example.com/m.litertlm?X-Amz-Signature=abc',
          'https://example.com/m.litertlm#token',
          'https://[bad/token?x=1',
          'https://h:port/m?token=S',
          'HTTPS://user:token@example.com/m.litertlm',
        ])
          ['--model-path', secret, '--backend', 'cpu'],
      ]) {
        final rejected = await dryRun(invalid);
        expect(rejected.exitCode, 64, reason: '$invalid');
        expect(rejected.stdout, isNot(contains('token')));
        expect(rejected.stderr, isNot(contains('token')));
      }
      final path = await dryRun([
        '--model-path',
        '/data/local/tmp/Qwen3-0.6B.litertlm',
        '--backend',
        'gpu',
      ]);
      expect(path.exitCode, 0);
      expect(
        path.stdout,
        contains(
          'integration_test/litert_lm_json_schema_e2e_test.dart -d android '
          '--dart-define=LITERT_LM_MODEL=/data/local/tmp/Qwen3-0.6B.litertlm '
          '--dart-define=LITERT_LM_BACKEND=gpu',
        ),
      );
      final upper = await dryRun([
        '--model-path',
        'HTTPS://example.com/Qwen3-0.6B.litertlm',
        '--backend',
        'cpu',
      ]);
      expect(
        upper.stdout,
        contains(
          '--dart-define=LITERT_LM_MODEL_URL='
          'HTTPS://example.com/Qwen3-0.6B.litertlm',
        ),
      );
      final url = await dryRun([
        '--model-path',
        'http://10.0.2.2:8765/gemma-4-E2B-it.litertlm',
        '--backend',
        'cpu',
      ]);
      expect(
        url.stdout,
        contains(
          '--dart-define=LITERT_LM_MODEL_URL='
          'http://10.0.2.2:8765/gemma-4-E2B-it.litertlm',
        ),
      );
    });

    test('dry-runs the LiteRT-LM read-only bundle device scenario', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-litert-read-only-bundle',
          '--device',
          'ios',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo/example/chat_app && flutter test --run-skipped '
          '-t local-only '
          'integration_test/litert_lm_read_only_bundle_e2e_test.dart '
          '-d ios',
        ),
      );
      expect(result.stdout, isNot(contains('LITERT_READ_ONLY_MODEL')));
    });

    test('the read-only bundle scenario passes a supplied model', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-litert-read-only-bundle',
          '--device',
          'macos',
          '--model-path',
          '/models/Qwen3-0.6B.litertlm',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo/example/chat_app && '
          '/repo/tool/testing/without_app_nap.sh '
          'com.example.llamaDartChatExample flutter test --run-skipped '
          '-t local-only '
          'integration_test/litert_lm_read_only_bundle_e2e_test.dart '
          '-d macos '
          '--dart-define=LITERT_READ_ONLY_MODEL=/models/Qwen3-0.6B.litertlm',
        ),
      );
    });

    test('dry-runs the image settings comparison device scenario', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-image-settings-comparison',
          '--device',
          'ios',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo/example/chat_app && flutter test --run-skipped '
          '-t local-only '
          'integration_test/image_settings_comparison_e2e_test.dart '
          '-d ios',
        ),
      );
    });

    test('dry-runs the text and image coexistence device scenario', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-text-image-coexistence',
          '--device',
          'android',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo/example/chat_app && flutter test --run-skipped '
          '-t local-only '
          'integration_test/text_image_coexistence_e2e_test.dart '
          '-d android',
        ),
      );
    });

    test('dry-runs the micro-batch sweep device scenario', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-micro-batch-sweep',
          '--device',
          'android',
          '--model-path',
          '/data/local/tmp/Qwen3.5-0.8B-Q4_0.gguf',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo/example/chat_app && flutter test --run-skipped '
          '-t local-only '
          'integration_test/micro_batch_sweep_e2e_test.dart '
          '-d android '
          '--dart-define=MICRO_BATCH_SWEEP_MODEL='
          '/data/local/tmp/Qwen3.5-0.8B-Q4_0.gguf',
        ),
      );
    });

    test('dry-runs Web Qwen3-ASR file and microphone transcription', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-web-speech-to-text-smoke',
          '--audio-path',
          'test/fixtures/speech.wav',
          '--model-url',
          'https://example.com/qwen-asr.gguf',
          '--mmproj-url',
          'https://example.com/qwen-asr-mmproj.gguf',
          '--expect',
          'Known transcript.',
          '--skip-build',
          '--python',
          '/custom/python',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('validate_chat_app_web_build.sh'));
      expect(
        result.stdout,
        contains('--model-url https://example.com/qwen-asr.gguf'),
      );
      expect(
        result.stdout,
        contains('--mmproj-url https://example.com/qwen-asr-mmproj.gguf'),
      );
      expect(
        result.stdout,
        contains('--speech-audio-path test/fixtures/speech.wav'),
      );
      expect(result.stdout, contains('--speech-microphone'));
      expect(result.stdout, contains('--microphone-allow-any-response'));
      expect(result.stdout, contains("--expect 'Known transcript.'"));
    });

    for (final fixture in ['speech.mp3', 'speech.FLAC']) {
      test('dry-runs Web Qwen3-ASR $fixture file transcription only', () async {
        final result = await runLocalE2e(
          [
            '--scenario',
            'chat-app-web-speech-to-text-smoke',
            '--audio-path',
            'test/fixtures/$fixture',
            '--expect',
            'Known transcript.',
            '--skip-build',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains('--speech-audio-path test/fixtures/$fixture'),
        );
        expect(result.stdout, isNot(contains('--speech-microphone')));
        expect(
          result.stdout,
          isNot(contains('--microphone-allow-any-response')),
        );
      });
    }

    test('requires a fixture and expected text for Web speech smoke', () async {
      final result = await runLocalE2e(
        const ['--scenario', 'chat-app-web-speech-to-text-smoke', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('--audio-path'));
      expect(result.stderr, contains('--expect'));
    });

    test('dry-runs Web Qwen3-TTS synthesis and WAV export', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-web-text-to-speech-smoke',
          '--model-url',
          'https://example.com/qwen-tts.gguf',
          '--mmproj-url',
          'https://example.com/qwen-tts-mmproj.gguf',
          '--audio-path',
          'test/fixtures/speaker.wav',
          '--skip-build',
          '--python',
          '/custom/python',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('validate_chat_app_web_build.sh'));
      expect(
        result.stdout,
        contains('playwright_chat_app_text_to_speech_smoke.py'),
      );
      expect(
        result.stdout,
        contains('--model-url https://example.com/qwen-tts.gguf'),
      );
      expect(
        result.stdout,
        contains('--mmproj-url https://example.com/qwen-tts-mmproj.gguf'),
      );
      expect(
        result.stdout,
        contains('--speaker-audio-path test/fixtures/speaker.wav'),
      );
    });

    test(
      'production smoke builds once and tests root with separate model server',
      () async {
        final result = await runLocalE2e(
          const ['--scenario', 'chat-app-web-production-smoke', '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(result.exitCode, 0);
        final output = result.stdout.toString();
        expect(
          'scripts/build_chat_app_web.sh'.allMatches(output),
          hasLength(1),
        );
        expect(output, contains('CHAT_APP_BASE_HREF=/'));
        expect(
          output,
          contains(
            '--directory example/chat_app/build/web --port 7358 --coep require-corp',
          ),
        );
        expect(output, contains('--cors-origin http://127.0.0.1:7358'));
        expect(
          output,
          contains('http://127.0.0.1:7358/?llamadart_mock_bridge=echo'),
        );
        expect(
          output,
          contains(
            '--model-url http://127.0.0.1:7359/.dart_tool/test_models/stories15M.gguf',
          ),
        );
        expect(
          output,
          contains(
            'playwright_chat_app_real_model_smoke.py http://127.0.0.1:7358/',
          ),
        );
        expect(
          output,
          contains(
            '--expect-penalty-prompt-tokens-probe '
            '--expect-penalty-prompt-tokens-option absent',
          ),
        );
        final reuse = await runLocalE2e(
          const [
            '--scenario',
            'chat-app-web-production-smoke',
            '--skip-build',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(reuse.exitCode, 0);
        expect(
          reuse.stdout,
          contains('scripts/validate_chat_app_web_build.sh'),
        );
        expect(reuse.stdout, isNot(contains('scripts/build_chat_app_web.sh')));
      },
    );

    test(
      'dry-runs Web real-model smoke with build, serve, and Playwright steps',
      () async {
        final result = await runLocalE2e(
          const [
            '--scenario',
            'chat-app-web-real-model-smoke',
            '--model-url',
            'http://127.0.0.1:7358/models/tiny.gguf',
            '--expect',
            'ok',
            '--allow-any-response',
            '--python',
            '/custom/python',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains('scripts/build_chat_app_web.sh'));
        expect(
          result.stdout,
          contains(
            'CHAT_APP_BASE_HREF=/example/chat_app/build/web/ '
            'bash scripts/build_chat_app_web.sh',
          ),
        );
        expect(result.stdout, contains('serve_static_with_headers.py'));
        expect(
          result.stdout,
          contains('playwright_chat_app_real_model_smoke.py'),
        );
        expect(
          result.stdout,
          contains(
            '/custom/python tool/testing/playwright_chat_app_real_model_smoke.py',
          ),
        );
        expect(
          result.stdout,
          contains('--model-url http://127.0.0.1:7358/models/tiny.gguf'),
        );
        expect(result.stdout, contains('--expect ok'));
        expect(result.stdout, contains('--allow-any-response'));
        expect(
          result.stdout,
          contains(
            '--expect-penalty-prompt-tokens-probe '
            '--expect-penalty-prompt-tokens-option absent',
          ),
        );
        expect(result.stdout, isNot(contains('--tools')));
      },
    );

    test('dry-runs the Web tool penalty smoke and requires a model', () async {
      final missing = await runLocalE2e(
        const ['--scenario', 'chat-app-web-tool-penalty-smoke', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(missing.exitCode, 64);
      expect(missing.stderr, contains('--model-url'));

      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-web-tool-penalty-smoke',
          '--model-url',
          'http://127.0.0.1:7358/models/tools.gguf',
          '--allow-any-response',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          '--tools --expect-penalty-prompt-tokens-probe '
          '--expect-penalty-prompt-tokens-option absent --expect-lazy-grammar',
        ),
      );
    });

    test(
      'dry-runs Web mock smoke with build, serve, and Playwright steps',
      () async {
        final result = await runLocalE2e(
          const [
            '--scenario',
            'chat-app-web-mock-smoke',
            '--model-url',
            'https://example.com/custom-mock.gguf',
            '--python',
            '/custom/python',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains('scripts/build_chat_app_web.sh'));
        expect(result.stdout, contains('serve_static_with_headers.py'));
        expect(result.stdout, contains('playwright_chat_app_mock_smoke.py'));
        expect(
          result.stdout,
          contains(
            '/custom/python tool/testing/playwright_chat_app_mock_smoke.py',
          ),
        );
        expect(
          result.stdout,
          contains(
            'http://127.0.0.1:7358/example/chat_app/build/web/?llamadart_mock_bridge=echo',
          ),
        );
        expect(
          result.stdout,
          contains('--model-url https://example.com/custom-mock.gguf'),
        );
      },
    );

    test('dry-runs packaged bridge smoke with build and serve steps', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'bridge-smoke',
          '--python',
          '/custom/python',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'CHAT_APP_BASE_HREF=/example/chat_app/build/web/ '
          'bash scripts/build_chat_app_web.sh',
        ),
      );
      expect(result.stdout, contains('serve_static_with_headers.py'));
      expect(
        result.stdout,
        contains(
          '/custom/python tool/testing/playwright_bridge_smoke.py '
          'http://127.0.0.1:7358/example/chat_app/build/web/',
        ),
      );
    });

    test('validates an existing packaged bridge build when skipped', () async {
      final result = await runLocalE2e(
        const ['--scenario', 'bridge-smoke', '--skip-build', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains('bash scripts/validate_chat_app_web_build.sh'),
      );
      expect(result.stdout, isNot(contains('scripts/build_chat_app_web.sh')));
      expect(
        result.stdout,
        contains('http://127.0.0.1:7358/example/chat_app/build/web/'),
      );
    });

    test('prefers repo-local Playwright Python by default', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'run_local_e2e_python_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final pythonPath = Platform.isWindows
          ? '${tempDir.path}/.dart_tool/playwright-python/Scripts/python.exe'
          : '${tempDir.path}/.dart_tool/playwright-python/bin/python';
      await File(pythonPath).create(recursive: true);

      final result = await runLocalE2e(
        [
          '--scenario',
          'chat-app-web-litert-gemma4-smoke',
          '--skip-build',
          '--dry-run',
        ],
        projectRoot: tempDir.path,
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains(pythonPath));
      expect(
        result.stdout,
        contains('bash scripts/validate_chat_app_web_build.sh'),
      );
      expect(
        result.stdout,
        contains('tool/testing/playwright_chat_app_real_model_smoke.py'),
      );
    });

    test(
      'dry-runs GGUF chat feature smoke with model path and backend',
      () async {
        final result = await runLocalE2e(
          const [
            '--scenario',
            'gguf-chat-features-smoke',
            '--model-path',
            'models/Qwen3.5-0.8B-Q4_K_M.gguf',
            '--backend',
            'cpu',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains('gguf-chat-features-smoke'));
        expect(
          result.stdout,
          contains(
            "cd /repo && GGUF_AUDIO_PATH='' "
            "GGUF_AUDIO_EXPECTED_TEXT='' dart run "
            'tool/gguf_chat_features_smoke.dart '
            'models/Qwen3.5-0.8B-Q4_K_M.gguf cpu',
          ),
        );
      },
    );

    test('dry-runs GGUF chat feature smoke with multimodal inputs', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'gguf-chat-features-smoke',
          '--model-path',
          'models/Qwen3.5-0.8B-Q4_K_M.gguf',
          '--backend',
          'cpu',
          '--mmproj-path',
          'models/Qwen3.5-0.8B-mmproj-F16.gguf',
          '--image-path',
          'test/fixtures/image.png',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          "cd /repo && GGUF_AUDIO_PATH='' "
          "GGUF_AUDIO_EXPECTED_TEXT='' dart run "
          'tool/gguf_chat_features_smoke.dart '
          'models/Qwen3.5-0.8B-Q4_K_M.gguf cpu '
          'models/Qwen3.5-0.8B-mmproj-F16.gguf test/fixtures/image.png',
        ),
      );
    });

    test('dry-runs GGUF audio chat with an exact expected answer', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'gguf-audio-chat-smoke',
          '--model-path',
          'models/gemma-4-E2B-it-Q4_K_S.gguf',
          '--backend',
          'metal',
          '--mmproj-path',
          'models/gemma-4-E2B-it-mmproj-F16.gguf',
          '--audio-path',
          'test/fixtures/question.wav',
          '--expect',
          '4',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains('GGUF_AUDIO_PATH=test/fixtures/question.wav'),
      );
      expect(result.stdout, contains('GGUF_AUDIO_EXPECTED_TEXT=4'));
      expect(
        result.stdout,
        contains(
          'dart run tool/gguf_chat_features_smoke.dart '
          'models/gemma-4-E2B-it-Q4_K_S.gguf metal '
          'models/gemma-4-E2B-it-mmproj-F16.gguf',
        ),
      );
    });

    test('requires an exact expected GGUF audio answer', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'gguf-audio-chat-smoke',
          '--model-path',
          'models/gemma-4-E2B-it-Q4_K_S.gguf',
          '--mmproj-path',
          'models/gemma-4-E2B-it-mmproj-F16.gguf',
          '--audio-path',
          'test/fixtures/question.wav',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('a nonempty --expect'));
      expect(result.stderr, contains('gguf-audio-chat-smoke'));
    });

    test('rejects image input for the dedicated GGUF audio smoke', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'gguf-audio-chat-smoke',
          '--model-path',
          'models/gemma-4-E2B-it-Q4_K_S.gguf',
          '--mmproj-path',
          'models/gemma-4-E2B-it-mmproj-F16.gguf',
          '--image-path',
          'test/fixtures/image.png',
          '--audio-path',
          'test/fixtures/question.wav',
          '--expect',
          '4',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('--image-path is not supported'));
    });

    test('dry-runs typed speech-to-text with exact fixture inputs', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'speech-to-text-smoke',
          '--model-path',
          'models/Qwen3-ASR-0.6B-Q8_0.gguf',
          '--mmproj-path',
          'models/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf',
          '--audio-path',
          'test/fixtures/speech.wav',
          '--expect',
          'Known transcript.',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('speech-to-text-smoke'));
      expect(
        result.stdout,
        contains('LLAMADART_STT_MODEL_PATH=models/Qwen3-ASR-0.6B-Q8_0.gguf'),
      );
      expect(
        result.stdout,
        contains(
          'LLAMADART_STT_MMPROJ_PATH=models/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf',
        ),
      );
      expect(
        result.stdout,
        contains('LLAMADART_STT_AUDIO_PATH=test/fixtures/speech.wav'),
      );
      expect(
        result.stdout,
        contains("LLAMADART_STT_EXPECTED_TEXT='Known transcript.'"),
      );
      expect(
        result.stdout,
        contains('test/e2e/backends/speech_to_text_e2e_test.dart'),
      );
    });

    test('requires an exact expected speech transcript', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'speech-to-text-smoke',
          '--model-path',
          'models/Qwen3-ASR-0.6B-Q8_0.gguf',
          '--mmproj-path',
          'models/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf',
          '--audio-path',
          'test/fixtures/speech.wav',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('a nonempty --expect'));
    });

    test('dry-runs dedicated LiteRT-LM ASR with exact inputs', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'litert-lm-asr-smoke',
          '--model-path',
          'models/moonshine.tflite',
          '--tokenizer-path',
          'models/tokenizer.json',
          '--audio-path',
          'test/fixtures/speech.wav',
          '--model-preset',
          'moonshine-tiny',
          '--expect',
          'Known transcript.',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('litert-lm-asr-smoke'));
      expect(result.stdout, contains('tool/litert_lm_asr_smoke.dart'));
      expect(result.stdout, contains('models/moonshine.tflite'));
      expect(result.stdout, contains('models/tokenizer.json'));
      expect(result.stdout, contains('test/fixtures/speech.wav'));
      expect(result.stdout, contains('moonshine-tiny'));
      expect(result.stdout, contains("'Known transcript.'"));
    });

    test('requires all dedicated LiteRT-LM ASR inputs', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'litert-lm-asr-smoke',
          '--model-path',
          'models/moonshine.tflite',
          '--audio-path',
          'test/fixtures/speech.wav',
          '--expect',
          'Known transcript.',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('--tokenizer-path'));
    });

    test(
      'dry-runs hash-bound ASR preservation without an expectation',
      () async {
        final result = await runLocalE2e(
          const [
            '--scenario',
            'litert-lm-asr-preservation',
            '--model-path',
            'models/whisper.tflite',
            '--tokenizer-path',
            'models/tokenizer.json',
            '--audio-path',
            'test/fixtures/jfk.wav',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains('litert_lm_asr_preservation_e2e_test.dart'),
        );
        expect(result.stdout, contains('LITERT_LM_ASR_MODEL'));
        expect(result.stdout, contains('models/whisper.tflite'));
        expect(result.stdout, contains('LITERT_LM_ASR_TOKENIZER'));
        expect(result.stdout, contains('LITERT_LM_ASR_AUDIO'));
        expect(result.stdout, contains('--run-skipped'));
      },
    );

    test('requires all hash-bound ASR preservation fixture paths', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'litert-lm-asr-preservation',
        '--model-path',
        'models/whisper.tflite',
        '--audio-path',
        'test/fixtures/jfk.wav',
        '--dry-run',
      ], projectRoot: '/repo');
      expect(result.exitCode, 64);
      expect(result.stderr, contains('--tokenizer-path'));
    });

    test('rejects non-CPU ASR preservation requests', () async {
      final result = await runLocalE2e(const [
        '--scenario',
        'litert-lm-asr-preservation',
        '--model-path',
        'models/whisper.tflite',
        '--tokenizer-path',
        'models/tokenizer.json',
        '--audio-path',
        'test/fixtures/jfk.wav',
        '--backend',
        'gpu',
        '--dry-run',
      ], projectRoot: '/repo');
      expect(result.exitCode, 64);
      expect(result.stderr, contains('requires --backend cpu'));
    });

    test('dry-runs typed text-to-speech with model and projector', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'text-to-speech-smoke',
          '--model-path',
          'models/Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf',
          '--mmproj-path',
          'models/mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('text-to-speech-smoke'));
      expect(
        result.stdout,
        contains(
          'LLAMADART_TTS_MODEL_PATH=models/Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf',
        ),
      );
      expect(
        result.stdout,
        contains(
          'LLAMADART_TTS_MMPROJ_PATH=models/mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf',
        ),
      );
      expect(
        result.stdout,
        contains(
          'LLAMADART_TTS_OUTPUT_PATH=/repo/build/text-to-speech-smoke.wav',
        ),
      );
      expect(
        result.stdout,
        contains('test/e2e/backends/text_to_speech_e2e_test.dart'),
      );
    });

    test(
      'dry-runs the text-to-speech model families from the environment',
      () async {
        final result = await runLocalE2e(
          const ['--scenario', 'text-to-speech-models-smoke', '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains(
            'LLAMADART_TTS_OUTPUT_DIR=/repo/build/text-to-speech-models',
          ),
        );
        expect(
          result.stdout,
          contains('test/e2e/backends/text_to_speech_models_e2e_test.dart'),
        );
      },
    );

    test('requires a model and projector for text-to-speech', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'text-to-speech-smoke',
          '--model-path',
          'models/Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('--model-path and --mmproj-path'));
    });

    test('dry-runs image generation in the opted-in example', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'image-generation-smoke',
          '--model-path',
          'models/sdxs-512-tinySDdistilled_Q8_0.gguf',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          "cd /repo/example/basic_app && LLAMADART_SDXS_MODEL="
          "models/sdxs-512-tinySDdistilled_Q8_0.gguf "
          "LLAMADART_IMAGE_OUTPUT_DIR=/repo/build/image-generation-smoke "
          "dart test --configuration test/image_generation_smoke.yaml -t local-only "
          "test/image_generation_e2e_test.dart",
        ),
      );
      expect(result.stdout, isNot(contains('--run-skipped')));
    });

    test('image smoke configuration preserves unavailable-case skips', () async {
      final directory = Directory.systemTemp.createTempSync(
        'image-smoke-skip-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final fixture = File('${directory.path}/skip_control_test.dart');
      fixture.writeAsStringSync("""
@Tags(['local-only'])
library;
import 'package:test/test.dart';
void main() {
  test('available image control', () => expect(1, 1));
  test('unavailable image control', () => fail('skip was overridden'),
      skip: 'Unavailable model negative control');
}
""");
      // Resolve only package:test in the scratch package. A nested root
      // `dart test` re-bundles native assets held open by the parent on Windows.
      final testLibrary = (await Isolate.resolvePackageUri(
        Uri.parse('package:test/test.dart'),
      ))!;
      final testPubspec = File.fromUri(
        testLibrary.resolve('../pubspec.yaml'),
      ).readAsStringSync();
      final testVersion = RegExp(
        r'^version: ([^\s]+)$',
        multiLine: true,
      ).firstMatch(testPubspec)!.group(1)!;
      File('${directory.path}/pubspec.yaml').writeAsStringSync("""
name: image_smoke_skip_control
environment:
  sdk: ^3.10.7
dev_dependencies:
  test: $testVersion
""");
      final prepared = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: directory.path);
      expect(
        prepared.exitCode,
        0,
        reason: '${prepared.stdout}\n${prepared.stderr}',
      );
      final configuration = File(
        'example/basic_app/test/image_generation_smoke.yaml',
      ).absolute.path;
      final result = await Process.run(Platform.resolvedExecutable, [
        'test',
        '--configuration',
        configuration,
        '-t',
        'local-only',
        '-r',
        'expanded',
        fixture.path,
      ], workingDirectory: directory.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('Unavailable model negative control'));
      expect(result.stdout, contains('+1 ~1: All tests passed!'));
    });

    test('dry-runs the image exit teardown in the opted-in example, and '
        'requires its model', () async {
      final missing = await runLocalE2e(
        const ['--scenario', 'image-exit-teardown', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(missing.exitCode, 64);

      final result = await runLocalE2e(
        const [
          '--scenario',
          'image-exit-teardown',
          '--model-path',
          '/sdxs.gguf',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo/example/basic_app && IMAGE_EXIT_MODEL=/sdxs.gguf '
          '${Platform.isLinux ? 'IMAGE_EXIT_BACKEND=auto IMAGE_EXIT_CHAT_BACKEND=auto ' : ''}'
          'dart test --run-skipped -t local-only '
          'test/image_exit_teardown_e2e_test.dart',
        ),
      );

      final cpu = await runLocalE2e(
        const [
          '--scenario',
          'image-exit-teardown',
          '--model-path',
          '/sdxs.gguf',
          '--backend',
          'cpu',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(cpu.exitCode, 0);
      expect(
        cpu.stdout,
        contains(
          'cd /repo/example/basic_app && IMAGE_EXIT_MODEL=/sdxs.gguf '
          '${Platform.isLinux ? 'IMAGE_EXIT_BACKEND=cpu IMAGE_EXIT_CHAT_BACKEND=cpu ' : ''}'
          'dart test --run-skipped -t local-only '
          'test/image_exit_teardown_e2e_test.dart',
        ),
      );
    });

    test('dry-runs the macOS quit scenario as a host test of the chat app, '
        'and requires its model', () async {
      final missing = await runLocalE2e(
        const ['--scenario', 'chat-app-macos-quit', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(missing.exitCode, 64);
      expect(
        missing.stderr,
        contains('--model-path is required for chat-app-macos-quit'),
      );

      final result = await runLocalE2e(
        const [
          '--scenario',
          'chat-app-macos-quit',
          '--model-path',
          '/chat.gguf',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo/example/chat_app && MACOS_QUIT_CHAT_MODEL=/chat.gguf '
          'flutter test --run-skipped -t local-only '
          'test/macos_quit_e2e_test.dart\n',
        ),
      );
    });

    test(
      'active Flutter shutdown requires model and exact runtime headers',
      () async {
        const args = [
          '--scenario',
          'chat-app-flutter-active-shutdown',
          '--dry-run',
        ];
        final missingModel = await runLocalE2e(
          args,
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
          environment: const {},
        );
        expect(missingModel.exitCode, 64);
        expect(missingModel.stderr, contains('--model-path is required'));
        final withModel = [...args, '--model-path', '/chat.gguf'];
        final missingHeaders = await runLocalE2e(
          withModel,
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
          environment: const {},
        );
        expect(missingHeaders.exitCode, 64);
        expect(missingHeaders.stderr, contains('FLUTTER_SHUTDOWN_HEADERS'));
        final ready = await runLocalE2e(
          withModel,
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
          environment: const {'FLUTTER_SHUTDOWN_HEADERS': '/headers'},
        );
        expect(ready.exitCode, 0);
        expect(ready.stdout, contains('test/flutter_shutdown_e2e_test.dart'));
      },
    );

    test(
      'image Flutter shutdown requires model and exact runtime headers',
      () async {
        const args = [
          '--scenario',
          'chat-app-flutter-image-shutdown',
          '--dry-run',
        ];
        final missingModel = await runLocalE2e(
          args,
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
          environment: const {},
        );
        expect(missingModel.exitCode, 64);
        expect(missingModel.stderr, contains('--model-path is required'));
        final withModel = [...args, '--model-path', '/chat.gguf'];
        final missingHeaders = await runLocalE2e(
          withModel,
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
          environment: const {},
        );
        expect(missingHeaders.exitCode, 64);
        expect(missingHeaders.stderr, contains('FLUTTER_SHUTDOWN_HEADERS'));
        final ready = await runLocalE2e(
          withModel,
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
          environment: const {'FLUTTER_SHUTDOWN_HEADERS': '/headers'},
        );
        expect(ready.exitCode, 0);
        expect(
          ready.stdout,
          contains('test/flutter_image_shutdown_e2e_test.dart'),
        );
        expect(ready.stdout, contains('--no-pub'));
      },
    );

    test('ControlNet qualification requires a checkpoint and ControlNet and '
        'selects the maintained CPU suite', () async {
      for (final (arguments, environment) in [
        (
          const ['--scenario', 'image-controlnet', '--dry-run'],
          const {'LLAMADART_SD15_CONTROLNET': '/canny.safetensors'},
        ),
        (
          const [
            '--scenario',
            'image-controlnet',
            '--model-path',
            '/sd15.safetensors',
            '--dry-run',
          ],
          const <String, String>{},
        ),
      ]) {
        final missing = await runLocalE2e(
          arguments,
          projectRoot: '/repo',
          environment: environment,
        );
        expect(missing.exitCode, 64);
        expect(missing.stderr, contains('LLAMADART_SD15_CONTROLNET'));
        expect(missing.stderr, contains('--model-path <sd15-checkpoint>'));
      }
      final ready = await runLocalE2e(
        const [
          '--scenario',
          'image-controlnet',
          '--model-path',
          '/sd15.safetensors',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
        environment: const {'LLAMADART_SD15_CONTROLNET': '/canny.safetensors'},
      );
      expect(ready.exitCode, 0);
      expect(ready.stdout, contains('test/image_controlnet_e2e_test.dart'));
      expect(ready.stdout, contains('LLAMADART_SD15_MODEL=/sd15.safetensors'));
      expect(ready.stdout, contains('test/image_generation_smoke.yaml'));
    });

    test('reference-editing qualification requires the transformer and '
        'every component, and selects the maintained suite', () async {
      const components = {
        'LLAMADART_REFERENCE_EDIT_VAE': '/ae.safetensors',
        'LLAMADART_REFERENCE_EDIT_CLIP_L': '/clip_l.gguf',
        'LLAMADART_REFERENCE_EDIT_T5XXL': '/t5xxl.gguf',
      };
      const withModel = [
        '--scenario',
        'image-reference-editing',
        '--model-path',
        '/kontext.gguf',
        '--dry-run',
      ];
      for (final (arguments, environment) in [
        (
          const ['--scenario', 'image-reference-editing', '--dry-run'],
          components,
        ),
        for (final name in components.keys)
          (withModel, {...components}..remove(name)),
      ]) {
        final missing = await runLocalE2e(
          arguments,
          projectRoot: '/repo',
          environment: environment,
        );
        expect(missing.exitCode, 64);
        expect(missing.stderr, contains('image-reference-editing'));
        expect(missing.stderr, contains('LLAMADART_REFERENCE_EDIT_T5XXL'));
      }
      final ready = await runLocalE2e(
        withModel,
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
        environment: components,
      );
      expect(ready.exitCode, 0);
      expect(
        ready.stdout,
        contains('test/image_reference_editing_e2e_test.dart'),
      );
      expect(
        ready.stdout,
        contains('LLAMADART_REFERENCE_EDIT_DIFFUSION=/kontext.gguf'),
      );
      expect(
        ready.stdout,
        contains('LLAMADART_REFERENCE_EDIT_T5XXL=/t5xxl.gguf'),
      );
      expect(ready.stdout, contains('test/image_generation_smoke.yaml'));
    });

    test('hires-fix qualification requires a checkpoint and a known recipe '
        'and device, and selects the maintained suite', () async {
      for (final (arguments, environment) in [
        (
          const ['--scenario', 'image-hires-fix', '--dry-run'],
          const <String, String>{},
        ),
        (
          const [
            '--scenario',
            'image-hires-fix',
            '--model-path',
            '/sd15.safetensors',
            '--dry-run',
          ],
          const {'LLAMADART_HIRES_RECIPE': 'sdxl'},
        ),
        (
          const [
            '--scenario',
            'image-hires-fix',
            '--model-path',
            '/sd15.safetensors',
            '--dry-run',
          ],
          const {'LLAMADART_HIRES_DEVICE': 'vulkan'},
        ),
      ]) {
        final missing = await runLocalE2e(
          arguments,
          projectRoot: '/repo',
          environment: environment,
        );
        expect(missing.exitCode, 64);
        expect(missing.stderr, contains('image-hires-fix'));
        expect(missing.stderr, contains('LLAMADART_HIRES_RECIPE'));
      }
      final ready = await runLocalE2e(
        const [
          '--scenario',
          'image-hires-fix',
          '--model-path',
          '/sd-turbo.gguf',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
        environment: const {
          'LLAMADART_HIRES_RECIPE': 'turbo',
          'LLAMADART_HIRES_DEVICE': 'gpu',
        },
      );
      expect(ready.exitCode, 0);
      expect(ready.stdout, contains('test/image_hires_fix_e2e_test.dart'));
      expect(ready.stdout, contains('LLAMADART_HIRES_MODEL=/sd-turbo.gguf'));
      expect(ready.stdout, contains('LLAMADART_HIRES_RECIPE=turbo'));
      expect(ready.stdout, contains('LLAMADART_HIRES_DEVICE=gpu'));
      expect(ready.stdout, contains('test/image_generation_smoke.yaml'));
    });

    test(
      'container qualification requires both manifest and independent references',
      () async {
        for (final arguments in [
          const ['--scenario', 'image-container-formats', '--dry-run'],
          const [
            '--scenario',
            'image-container-formats',
            '--model-path',
            'models.json',
            '--dry-run',
          ],
        ]) {
          final result = await runLocalE2e(
            arguments,
            projectRoot: '/repo',
            environment: const {},
          );
          expect(result.exitCode, 64);
          expect(
            result.stderr,
            contains('LLAMADART_IMAGE_CONTAINER_REFERENCES'),
          );
        }
        final result = await runLocalE2e(
          const [
            '--scenario',
            'image-container-formats',
            '--model-path',
            'models.json',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
          environment: const {
            'LLAMADART_IMAGE_CONTAINER_REFERENCES': '/references',
          },
        );
        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains(
            'cd /repo/example/basic_app && LLAMADART_IMAGE_CONTAINER_SET=models.json',
          ),
        );
        expect(
          result.stdout,
          contains(
            'LLAMADART_IMAGE_OUTPUT_DIR=/repo/build/image-container-formats',
          ),
        );
        expect(result.stdout, contains('test/image_generation_e2e_test.dart'));
        expect(
          result.stdout,
          contains(r"--name '^checkpoint containers preserve CPU pixels$'"),
        );
        expect(result.stdout, isNot(contains('--run-skipped')));
      },
    );

    test(
      'original container diagnosis requires a plan and selects bounded operator',
      () async {
        final missing = await runLocalE2e(const [
          '--scenario',
          'image-original-containers',
          '--dry-run',
        ], projectRoot: '/repo');
        expect(missing.exitCode, 64);
        final ready = await runLocalE2e(const [
          '--scenario',
          'image-original-containers',
          '--model-path',
          'admitted.json',
          '--dry-run',
        ], projectRoot: '/repo');
        expect(ready.exitCode, 0);
        expect(ready.stdout, contains('sd_original_mode/run.py'));
        expect(ready.stdout, contains('--plan admitted.json'));
        expect(ready.stdout, contains('--execute'));
        expect(ready.stdout, contains('/repo/build/image-original-containers'));
      },
    );

    test(
      'local image sets require a source and select builder plus public suite',
      () async {
        const args = ['--scenario', 'image-local-checkpoint-sets', '--dry-run'];
        final missing = await runLocalE2e(
          args,
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(missing.exitCode, 64);
        final ready = await runLocalE2e(
          [...args, '--model-path', '/full.safetensors'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(ready.exitCode, 0);
        expect(
          ready.stdout,
          contains('split_local_checkpoint.py /full.safetensors'),
        );
        expect(ready.stdout, contains('test/local_image_set_e2e_test.dart'));
        expect(ready.stdout, contains('/repo/build/local-image-set-fixture'));
      },
    );

    test(
      'image editing requires a checkpoint and selects the maintained CPU suite',
      () async {
        const args = ['--scenario', 'image-editing', '--dry-run'];
        final missing = await runLocalE2e(
          args,
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(missing.exitCode, 64);
        expect(missing.stderr, contains('--model-path <sd-turbo.gguf>'));
        final ready = await runLocalE2e(
          [...args, '--model-path', '/model.gguf'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(ready.exitCode, 0);
        expect(ready.stdout, contains('test/image_editing_e2e_test.dart'));
        expect(ready.stdout, contains('LLAMADART_SD_TURBO_MODEL=/model.gguf'));
        expect(ready.stdout, contains('test/image_generation_smoke.yaml'));
      },
    );

    test('requires an SDXS model for image generation', () async {
      final result = await runLocalE2e(
        const ['--scenario', 'image-generation-smoke', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('--model-path <sdxs.gguf> is required'));
    });

    test('passes the GGUF stop-sequence backend only when given', () async {
      Future<String> dryRun(List<String> backend) async {
        final result = await runLocalE2e(
          [
            '--scenario',
            'gguf-stop-sequences',
            '--model-path',
            'models/chat.gguf',
            ...backend,
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(result.exitCode, 0);
        return result.stdout;
      }

      expect(
        await dryRun(const []),
        contains(
          'GGUF_STOP_MODEL=models/chat.gguf dart test -p vm --run-skipped '
          'test/e2e/backends/gguf_stop_sequences_e2e_test.dart',
        ),
      );
      expect(
        await dryRun(const ['--backend', 'metal']),
        contains('GGUF_STOP_MODEL=models/chat.gguf GGUF_STOP_BACKEND=metal '),
      );
    });

    test(
      'dry-runs the tool-result image smoke with model and projector',
      () async {
        final missing = await runLocalE2e(
          const ['--scenario', 'tool-result-image-smoke', '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(missing.exitCode, 64);
        expect(
          missing.stderr,
          contains('--model-path and --mmproj-path are required'),
        );

        final ready = await runLocalE2e(
          const [
            '--scenario',
            'tool-result-image-smoke',
            '--model-path',
            'models/qwen3-vl.gguf',
            '--mmproj-path',
            'models/mmproj.gguf',
            '--backend',
            'metal',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(ready.exitCode, 0);
        expect(
          ready.stdout,
          contains(
            'LLAMADART_TOOL_MEDIA_MODEL=models/qwen3-vl.gguf '
            'LLAMADART_TOOL_MEDIA_MMPROJ=models/mmproj.gguf '
            'LLAMADART_TOOL_MEDIA_BACKEND=metal dart test -p vm --run-skipped '
            '-t local-only test/e2e/backends/tool_result_media_e2e_test.dart',
          ),
        );
      },
    );

    test('the tool-result image smoke passes the chat template override '
        'through only when it is set', () async {
      const variable = 'LLAMADART_TOOL_MEDIA_CHAT_TEMPLATE';
      const template = 'test/fixtures/templates/Qwen3-VL-2B-Instruct.jinja';
      Future<String> dryRun(Map<String, String> environment) async {
        final result = await runLocalE2e(
          const [
            '--scenario',
            'tool-result-image-smoke',
            '--model-path',
            'models/qwen3-vl.gguf',
            '--mmproj-path',
            'models/mmproj.gguf',
            '--dry-run',
          ],
          projectRoot: '/repo',
          environment: environment,
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(result.exitCode, 0, reason: result.stderr);
        return result.stdout;
      }

      expect(
        await dryRun({variable: template}),
        contains('$variable=$template'),
      );
      expect(await dryRun(const {}), isNot(contains(variable)));
    });

    test('dry-runs the decision model smoke with model and head', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'decision-model-smoke',
          '--model-path',
          'models/laya-Q8_0.gguf',
          '--head-path',
          'models/laya-head.safetensors',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Scenario: decision-model-smoke'));
      expect(
        result.stdout,
        contains(
          'LLAMADART_DECISION_MODEL_PATH=models/laya-Q8_0.gguf '
          'LLAMADART_DECISION_HEAD_PATH=models/laya-head.safetensors '
          'dart test -p vm --run-skipped -t local-only '
          'test/e2e/backends/decision_engine_e2e_test.dart',
        ),
      );
      expect(result.stdout, isNot(contains('LLAMADART_DECISION_CONFIG_PATH')));
      expect(result.stdout, isNot(contains('LLAMADART_DECISION_BACKEND')));
    });

    test('passes the decision config path and explicit backend', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'decision-model-smoke',
          '--model-path',
          'models/laya-Q8_0.gguf',
          '--head-path',
          'checkpoint/model.safetensors',
          '--config-path',
          'checkpoint/rl_agent_config.json',
          '--backend',
          'metal',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'LLAMADART_DECISION_HEAD_PATH=checkpoint/model.safetensors '
          'LLAMADART_DECISION_CONFIG_PATH=checkpoint/rl_agent_config.json '
          'LLAMADART_DECISION_BACKEND=metal dart test',
        ),
      );
    });

    for (final (name, args) in [
      ('model', ['--head-path', 'models/laya-head.safetensors']),
      ('head', ['--model-path', 'models/laya-Q8_0.gguf']),
    ]) {
      test('requires a decision $name path', () async {
        final result = await runLocalE2e(
          ['--scenario', 'decision-model-smoke', ...args, '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 64);
        expect(
          result.stderr,
          contains(
            '--model-path and --head-path are required for '
            'decision-model-smoke.',
          ),
        );
      });
    }

    test('requires a head path before a decision config path', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'decision-model-smoke',
          '--model-path',
          'models/laya-Q8_0.gguf',
          '--config-path',
          'checkpoint/rl_agent_config.json',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('--config-path requires --head-path.'));
    });

    test('rejects a head path outside the decision scenario', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'text-to-speech-smoke',
          '--model-path',
          'models/Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf',
          '--mmproj-path',
          'models/mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf',
          '--head-path',
          'models/laya-head.safetensors',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains('--head-path is not supported by text-to-speech-smoke.'),
      );
    });

    test('dry-runs the Web decision smoke on the WebGPU Chrome platform '
        'with bridge assets where the test reads them', () async {
      final result = await runLocalE2e(
        const ['--scenario', 'decision-model-web-smoke', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Scenario: decision-model-web-smoke'));
      expect(
        result.stdout,
        contains(
          'WEBGPU_BRIDGE_OUT_DIR=/repo/build/decision_web_e2e/bridge '
          'bash scripts/fetch_webgpu_bridge_assets.sh',
        ),
      );
      expect(
        result.stdout,
        contains(
          'dart test -p chrome-webgpu --run-skipped -t local-only '
          'test/e2e/backends/decision_engine_web_e2e_test.dart',
        ),
      );
      final e2e = File(
        'test/e2e/backends/decision_engine_web_e2e_test.dart',
      ).readAsStringSync();
      expect(e2e, contains("@Tags(['local-only', 'e2e'])"));
      expect(e2e, contains("'../../../build/decision_web_e2e/'"));
    });

    test('dry-runs Web speech cancellation with pinned assets and '
        'the WebGPU Chrome platform', () async {
      final result = await runLocalE2e(
        const ['--scenario', 'web-speech-task-cancel', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Scenario: web-speech-task-cancel'));
      expect(
        result.stdout,
        contains(
          'WEBGPU_BRIDGE_OUT_DIR=/repo/build/web_speech_task_cancel/bridge '
          'bash scripts/fetch_webgpu_bridge_assets.sh',
        ),
      );
      expect(
        result.stdout,
        contains(
          'dart test -p chrome-webgpu --run-skipped -t local-only '
          'test/e2e/webgpu/speech_task_cancellation_e2e_test.dart',
        ),
      );
    });

    test('defines the chrome-webgpu platform with WebGPU and '
        'SharedArrayBuffer', () {
      final config =
          loadYaml(File('dart_test.yaml').readAsStringSync()) as YamlMap;
      final platform =
          (config['define_platforms'] as YamlMap)['chrome-webgpu'] as YamlMap;
      final settings = platform['settings'] as YamlMap;

      expect(platform['extends'], 'chrome');
      // Headless test Chrome adds --disable-gpu, which leaves no adapter.
      expect(settings['headless'], isFalse);
      expect(
        (settings['arguments'] as String).split(RegExp(r'\s+')),
        containsAll([
          '--headless=new',
          '--enable-unsafe-webgpu',
          '--enable-features=SharedArrayBuffer,'
              'SharedArrayBufferUnrestrictedAccessAllowed',
        ]),
      );
      expect(config['platforms'], ['vm', 'chrome']);
    });

    test('rejects a head path for the Web decision smoke', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'decision-model-web-smoke',
          '--head-path',
          'models/laya-head.safetensors',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains('--head-path is not supported by decision-model-web-smoke.'),
      );
    });

    test('requires mmproj path before GGUF image path', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'gguf-chat-features-smoke',
          '--model-path',
          'models/Qwen3.5-0.8B-Q4_K_M.gguf',
          '--image-path',
          'test/fixtures/image.png',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('--image-path requires --mmproj-path'));
    });

    test(
      'dry-runs llama.cpp speculative benchmark with matrix options',
      () async {
        final result = await runLocalE2e(
          const [
            '--scenario',
            'llama-cpp-speculative-benchmark',
            '--model-path',
            'models/Qwen3.5-0.8B-Q4_K_M.gguf',
            '--backend',
            'cpu',
            '--speculative-cases',
            'baseline,ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,mixed-ngram',
            '--benchmark-max-tokens',
            '128',
            '--benchmark-runs',
            '3',
            '--draft-token-max',
            '1,2',
            '--ngram-size-m',
            '8,16',
            '--ngram-token-max',
            '64',
            '--benchmark-warmups',
            '1',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains('llama-cpp-speculative-benchmark'));
        expect(
          result.stdout,
          contains(
            'cd /repo && dart run '
            'tool/testing/llama_cpp_speculative_benchmark.dart '
            '--model models/Qwen3.5-0.8B-Q4_K_M.gguf '
            '--cases baseline,ngram-simple,ngram-map-k,ngram-map-k4v,'
            'ngram-mod,mixed-ngram --backend cpu --gpu-layers 0 '
            '--max-tokens 128 --runs 3 --draft-token-max 1,2 --warmups 1 '
            '--ngram-size-m 8,16 --ngram-token-max 64',
          ),
        );
      },
    );

    test('dry-runs llama.cpp speculative benchmark with draft model', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'llama-cpp-speculative-benchmark',
          '--model-path',
          'models/qwen2.5-1.5b-instruct-q4_k_m.gguf',
          '--draft-model-path',
          'models/qwen2.5-0.5b-instruct-q4_k_m.gguf',
          '--speculative-cases',
          'baseline,draft-simple,mixed-ngram-draft-simple',
          '--benchmark-max-tokens',
          '16',
          '--benchmark-runs',
          '1',
          '--draft-token-max',
          '1',
          '--benchmark-warmups',
          '0',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains(
          'cd /repo && dart run '
          'tool/testing/llama_cpp_speculative_benchmark.dart '
          '--model models/qwen2.5-1.5b-instruct-q4_k_m.gguf '
          '--cases baseline,draft-simple,mixed-ngram-draft-simple '
          '--backend auto --gpu-layers 0 --max-tokens 16 --runs 1 '
          '--draft-token-max 1 --warmups 0 '
          '--draft-model models/qwen2.5-0.5b-instruct-q4_k_m.gguf',
        ),
      );
    });

    test(
      'dry-runs llama.cpp speculative benchmark with generated ngram cache',
      () async {
        final result = await runLocalE2e(
          const [
            '--scenario',
            'llama-cpp-speculative-benchmark',
            '--model-path',
            'models/Qwen3.5-0.8B-Q4_K_M.gguf',
            '--speculative-cases',
            'baseline,ngram-cache',
            '--ngram-cache-build-static-path',
            '/tmp/llamadart-ngram-cache.bin',
            '--ngram-cache-build-text',
            'alpha beta gamma alpha beta delta',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains(
            '--cases baseline,ngram-cache --backend auto --gpu-layers 0 '
            '--max-tokens 128 --runs 3 --draft-token-max 1,2 --warmups 1 '
            '--ngram-cache-build-static-path '
            '/tmp/llamadart-ngram-cache.bin --ngram-cache-build-text '
            "'alpha beta gamma alpha beta delta'",
          ),
        );
      },
    );

    test('requires model path for llama.cpp speculative benchmark', () async {
      final result = await runLocalE2e(
        const ['--scenario', 'llama-cpp-speculative-benchmark', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains(
          '--model-path is required for llama-cpp-speculative-benchmark',
        ),
      );
    });

    test('dry-runs llama.cpp chat-template smoke with model path', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'llama-cpp-chat-template-smoke',
          '--model-path',
          'models/Qwen3.5-0.8B-Q4_K_M.gguf',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('llama-cpp-chat-template-smoke'));
      expect(
        result.stdout,
        contains(
          'LLAMADART_LLAMA_CPP_TEMPLATE_MODEL_PATH='
          'models/Qwen3.5-0.8B-Q4_K_M.gguf',
        ),
      );
      expect(
        result.stdout,
        contains(
          'dart test --run-skipped -t local-only '
          'test/e2e/backends/llama_cpp_chat_template_backend_e2e_test.dart',
        ),
      );
    });

    test('requires model path for llama.cpp chat-template smoke', () async {
      final result = await runLocalE2e(
        const ['--scenario', 'llama-cpp-chat-template-smoke'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains('--model-path is required for llama-cpp-chat-template-smoke'),
      );
    });

    for (final scenario in [
      'gemma4-mtp-smoke',
      'native-embedding-benchmark',
      'native-embedding-sweep',
    ]) {
      test('requires model path for $scenario dry-run', () async {
        final result = await runLocalE2e(
          ['--scenario', scenario, '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 64);
        expect(
          result.stderr,
          contains('--model-path is required for $scenario'),
        );
      });
    }

    for (final scenario in [
      'validation-harness',
      'validation-voice-round-trip',
      'validation-speech-stt',
      'validation-speech-tts',
      'validation-speech-litert-asr',
    ]) {
      test('resolves the validation package first for $scenario', () async {
        final result = await runLocalE2e(
          ['--scenario', scenario, '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        final commands = result.stdout
            .split('\n')
            .where((line) => line.startsWith('  cd '))
            .toList();
        expect(commands, hasLength(greaterThan(1)));
        expect(
          commands.first,
          '  cd /repo/packages/llamadart_validation && dart pub get',
        );
      });
    }

    test('requires model path for LiteRT-LM chat feature smoke', () async {
      final result = await runLocalE2e(
        const ['--scenario', 'litert-lm-chat-features-smoke'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains('--model-path is required for litert-lm-chat-features-smoke'),
      );
    });

    test('dry-runs LiteRT-LM chat feature smoke with model path', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'litert-lm-chat-features-smoke',
          '--model-path',
          'models/gemma-4-E2B-it.litertlm',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('litert-lm-chat-features-smoke'));
      expect(
        result.stdout,
        contains(
          "cd /repo && LITERT_LM_AUDIO_PATH='' "
          "LITERT_LM_AUDIO_EXPECTED_TEXT='' dart run "
          'tool/litert_lm_chat_features_smoke.dart '
          'models/gemma-4-E2B-it.litertlm auto',
        ),
      );
    });

    test('dry-runs LiteRT-LM audio chat with shared CLI flags', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'litert-lm-chat-features-smoke',
          '--model-path',
          'models/gemma-4-E2B-it.litertlm',
          '--backend',
          'gpu',
          '--audio-path',
          'test/fixtures/question.wav',
          '--expect',
          '4',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains('LITERT_LM_AUDIO_PATH=test/fixtures/question.wav'),
      );
      expect(result.stdout, contains('LITERT_LM_AUDIO_EXPECTED_TEXT=4'));
      expect(
        result.stdout,
        contains(
          'dart run tool/litert_lm_chat_features_smoke.dart '
          'models/gemma-4-E2B-it.litertlm gpu',
        ),
      );
    });

    test('requires an exact expected LiteRT-LM audio answer', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'litert-lm-chat-features-smoke',
          '--model-path',
          'models/gemma-4-E2B-it.litertlm',
          '--audio-path',
          'test/fixtures/question.wav',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('A nonempty --expect is required'));
      expect(result.stderr, contains('litert-lm-chat-features-smoke'));
    });

    test(
      'dry-runs Web LiteRT-LM Gemma 4 smoke with LiteRT response capture',
      () async {
        final result = await runLocalE2e(
          const [
            '--scenario',
            'chat-app-web-litert-gemma4-smoke',
            '--skip-build',
            '--dry-run',
          ],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );

        expect(result.exitCode, 0);
        expect(
          result.stdout,
          contains('playwright_chat_app_real_model_smoke.py'),
        );
        expect(
          result.stdout,
          contains('gemma-4-E2B-it-web.litertlm?download=true'),
        );
        expect(result.stdout, contains('--response-source litert'));
        expect(result.stdout, contains('--backend-index 2'));
        expect(result.stdout, contains('--gpu-layers 999'));
        expect(result.stdout, contains('--penalty 1.1'));
      },
    );

    test('dry-runs WebGPU regression with forwarded runner options', () async {
      final result = await runLocalE2e(
        const [
          '--scenario',
          'webgpu-multimodal-regression',
          '--port',
          '9123',
          '--python',
          '/custom/python',
          '--skip-build',
          '--dry-run',
        ],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('PLAYWRIGHT_GATE_PORT=9123'));
      expect(result.stdout, contains('PLAYWRIGHT_PYTHON=/custom/python'));
      expect(result.stdout, contains('LLAMADART_SKIP_WEB_BUILD=1'));
      expect(
        result.stdout,
        contains('bash tool/testing/run_webgpu_multimodal_regression_gate.sh'),
      );
    });

    test('reports unknown scenarios without executing anything', () async {
      final result = await runLocalE2e(
        const ['--scenario', 'does-not-exist', '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );

      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains('Unknown local E2E scenario: does-not-exist'),
      );
      expect(result.stderr, contains('Use --list'));
    });

    test('reports port conflicts before starting Web smoke servers', () async {
      final tempDir = await _createBridgeSmokeFixture();
      addTearDown(() => tempDir.delete(recursive: true));
      const port = 9123;

      final result = await runLocalE2e(
        ['--scenario', 'bridge-smoke', '--skip-build', '--port', '$port'],
        projectRoot: tempDir.path,
        displayShell: LocalE2eDisplayShell.posix,
        foregroundStepRun: _successfulForegroundStep,
        portAvailabilityCheck: (actualPort) async {
          throw StateError(
            'Port $actualPort is already in use; stop the existing server or '
            'choose a different --port.',
          );
        },
      );

      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('Running local E2E scenario: bridge-smoke'),
      );
      expect(result.stderr, contains('Port $port is already in use'));
    });

    test('reports background server startup failures', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'run_local_e2e_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      const port = 9124;

      final result = await runLocalE2e(
        [
          '--scenario',
          'bridge-smoke',
          '--skip-build',
          '--python',
          Platform.resolvedExecutable,
          '--port',
          '$port',
        ],
        projectRoot: tempDir.path,
        displayShell: LocalE2eDisplayShell.posix,
        foregroundStepRun: _successfulForegroundStep,
        portAvailabilityCheck: (_) async {},
        portReadinessWait: (actualPort, _) async {
          throw StateError(
            'Background server exited before port $actualPort became ready '
            '(exit code 1).',
          );
        },
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Background server exited'));
    });
  });

  group('audio chat smoke support', () {
    test('normalizes presentation-only answer differences', () {
      expect(normalizeAudioChatAnswer('  **4.**\n'), '4');
      expect(
        () => verifyExactAudioChatAnswer(
          scenarioName: 'fixture',
          actualText: 'five',
          expectedText: '4',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('reports a stable path-free fixture identity', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'audio_chat_smoke_support_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final audioPath = '${tempDir.path}/private-recording.wav';
      await File(audioPath).writeAsBytes(const <int>[1, 2, 3]);

      final first = await readAudioChatSmokeFixture(audioPath);
      final second = await readAudioChatSmokeFixture(audioPath);
      final metadata = first.toJson();

      expect(first.fixtureId, second.fixtureId);
      expect(first.fixtureId, startsWith('sha256:'));
      expect(first.fixtureId.length, 71);
      expect(metadata, hasLength(2));
      expect(metadata['encodedByteLength'], 3);
      expect(metadata['fixtureId'], first.fixtureId);
      expect(metadata.toString(), isNot(contains(audioPath)));
    });
  });
}

Future<Directory> _createBridgeSmokeFixture() async {
  return Directory.systemTemp.createTemp('run_local_e2e_bridge_test_');
}

Future<ProcessResult> _successfulForegroundStep(LocalE2eCommandStep _) async =>
    ProcessResult(0, 0, '', '');
