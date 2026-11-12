@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../../tool/testing/run_local_e2e.dart';
import '../../../tool/testing/test_matrix.dart';

void main() {
  test(
    'default consumer AOT matrix selects only its explicit manual scenario',
    () async {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'native-default-consumer-aot',
      );
      expect(row.tier, 'platform');
      expect(row.mode, contains('manual local-only'));
      expect(
        row.command,
        'dart run tool/testing/run_local_e2e.dart --scenario native-default-consumer-aot',
      );
      final scenario = buildLocalE2eScenarios().singleWhere(
        (scenario) => scenario.name == row.id,
      );
      expect(scenario.group, LocalE2eScenarioGroup.dartLocalOnly);
      expect(scenario.requiresDevice, isFalse);
      final dryRun = await runLocalE2e(
        ['--scenario', row.id, '--dry-run'],
        projectRoot: '/repo',
        environment: {},
        foregroundStepRun: (_) async {
          fail('manual matrix inspection must not execute qualification');
        },
      );
      expect(dryRun.exitCode, 0);
      expect(
        dryRun.stdout,
        contains('native_default_consumer_qualification/qualify.py'),
      );
      expect(dryRun.stdout, contains('--expected-native-tag'));
      expect(row.useWhen, contains('pipeline-only'));
    },
  );
  group('maintained runtime CI job names', () {
    final ci =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync()) as Map;
    final smoke =
        loadYaml(
              File('.github/workflows/litert_lm_smoke.yml').readAsStringSync(),
            )
            as Map;

    void expectCurrentJobNames(Map<String, String> commands) {
      final jobs = ci['jobs'] as Map;
      final native = jobs['test-other-os'] as Map;
      // The row names the Windows shards once, with a placeholder shard.
      final windowsNames = {
        for (final entry
            in (native['strategy']['matrix']['include'] as List).cast<Map>())
          if (entry['os'] == 'windows-latest')
            (native['name'] as String)
                .replaceAll(r'${{ matrix.lane }}', entry['lane'] as String)
                .replaceAll(
                  r'${{ matrix.shard }}/${{ matrix.shards }}',
                  '<shard>/<shards>',
                ),
      };
      final smokeJob = smoke['jobs']['native-smoke'] as Map;
      String smokeName(String os) {
        expect(
          (smokeJob['strategy']['matrix']['include'] as List).cast<Map>().any(
            (entry) => entry['os'] == os,
          ),
          isTrue,
        );
        return '${smoke['name']} / ${(smokeJob['name'] as String).replaceAll(r'${{ matrix.os }}', os)}';
      }

      final expected = {
        'linux-x64-ci-runtime': [
          jobs['test-linux-web']['name'],
          jobs['native-prompt-reuse-parity']['name'],
          smokeName('ubuntu-latest'),
        ],
        'windows-x64-ci-runtime': [
          ...windowsNames,
          smokeName('windows-latest'),
        ],
      };
      for (final entry in expected.entries) {
        expect(
          RegExp(
            '"([^"]+)"',
          ).allMatches(commands[entry.key]!).map((match) => match.group(1)),
          unorderedEquals(entry.value),
          reason: entry.key,
        );
      }
    }

    final commands = {
      for (final row in testMatrixRows)
        if (row.id == 'linux-x64-ci-runtime' ||
            row.id == 'windows-x64-ci-runtime')
          row.id: row.command,
    };
    test('Linux and Windows rows name the actual workflow jobs', () {
      expectCurrentJobNames(commands);
    });
    test('a stale maintained job name is rejected', () {
      for (final id in commands.keys) {
        expect(
          () => expectCurrentJobNames({
            ...commands,
            id: commands[id]!.replaceFirst('"', '"stale '),
          }),
          throwsA(isA<TestFailure>()),
          reason: id,
        );
      }
    });
  });

  test(
    'Windows registry matrix reaches the explicitly unskipped integration',
    () async {
      final row = testMatrixRows.singleWhere(
        (r) => r.id == 'windows-native-override-registry',
      );
      expect(row.tier, 'platform');
      expect(row.mode, contains('manual'));
      final result = await runLocalE2e([
        '--scenario',
        row.id,
        '--dry-run',
      ], projectRoot: '/repo');
      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.stdout,
        contains(
          '--run-skipped -t local-only test/integration/windows_ggml_registry_qualification_test.dart',
        ),
      );
    },
  );

  for (final entry in {
    'litert-lm-v1-asr-smoke':
        'test/fixtures/litert_lm_v1_asr_qualification.dart',
    'litert-lm-v1-service':
        'test/e2e/backends/litert_lm_v1_service_e2e_test.dart',
  }.entries) {
    test(
      '${entry.key} matrix command reaches the hash-bound qualifier',
      () async {
        final row = testMatrixRows.singleWhere((row) => row.id == entry.key);
        final command = row.command.split(' ');
        final dartIndex = command.indexOf('dart');
        expect(dartIndex, greaterThan(0));
        final environment = <String, String>{
          for (final assignment in command.take(dartIndex))
            assignment.split('=').first: assignment.contains('SHA256=')
                ? List.filled(64, 'a').join()
                : '/local/runtime',
        };
        final arguments = command
            .skip(dartIndex + 3)
            .map((arg) => arg.startsWith('<') ? '/local/fixture' : arg)
            .toList();
        final result = await runLocalE2e(
          [...arguments, '--dry-run'],
          projectRoot: '/repo',
          environment: environment,
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.stdout, contains(entry.value));
        expect(result.stdout, contains('/local/runtime'));
        expect(result.stdout, contains(List.filled(64, 'a').join()));
        expect(result.stdout, contains('/local/fixture'));
      },
    );
  }

  for (final route in ['direct', 'service', 'speech']) {
    test(
      'public v1 $route matrix command reaches the strict public runner',
      () async {
        final row = testMatrixRows.singleWhere(
          (row) => row.id == 'litert-lm-v1-public-$route',
        );
        final command = row.command.split(' '),
            index = row.command.split(' ').indexOf('dart');
        final environment = {
          for (final assignment in command.take(index))
            assignment.split('=').first: assignment.contains('SHA256=')
                ? 'a' * 64
                : '/local/qualified-input',
        };
        final result = await runLocalE2e(
          [
            ...command
                .skip(index + 3)
                .map((value) => value.startsWith('<') ? '/local/model' : value),
            '--dry-run',
          ],
          projectRoot: '/repo',
          environment: environment,
        );
        expect(result.exitCode, 0, reason: result.stderr);
        expect(
          result.stdout,
          contains(
            'test/fixtures/litert_lm_v1_public_qualification.dart $route',
          ),
        );
        expect(result.stdout, isNot(contains('--expect-disabled')));
        expect(row.tier, 'high-risk');
      },
    );
  }

  test('local image-set matrix selects the bounded CPU fixture scenario', () {
    final row = testMatrixRows.singleWhere(
      (r) => r.id == 'image-local-checkpoint-sets',
    );
    expect(row.mode, 'local-only');
    expect(row.covers, contains('source-removal'));
    expect(
      buildLocalE2eScenarios()
          .singleWhere((s) => s.name == row.id)
          .requiresDevice,
      isFalse,
    );
  });
  test('the device JSON Schema matrix command dry-runs its scenario', () async {
    final row = testMatrixRows.singleWhere(
      (row) => row.id == 'chat-app-litert-json-schema',
    );
    expect(row.tier, 'high-risk');
    final args = row.command
        .split(' ')
        .skip(3)
        .map(
          (arg) => switch (arg) {
            '<android|ios|macos>' => 'android',
            '<device-path-or-http-url>' => '/data/local/tmp/m.litertlm',
            _ => arg,
          },
        )
        .toList();
    expect(args[args.indexOf('--scenario') + 1], row.id);
    final result = await runLocalE2e(
      [...args, '--dry-run'],
      projectRoot: '/repo',
      displayShell: LocalE2eDisplayShell.posix,
    );
    expect(result.exitCode, 0, reason: result.stderr);
    expect(
      result.stdout,
      contains(
        'integration_test/litert_lm_json_schema_e2e_test.dart -d android',
      ),
    );
  });
  test(
    'native JSON Schema matrix command reaches its maintained local-only scenario',
    () async {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'litert-lm-json-schema',
      );
      expect(row.tier, 'high-risk');
      expect(row.mode, contains('local-only'));
      final command = row.command.split(' ');
      expect(command.take(3), [
        'dart',
        'run',
        'tool/testing/run_local_e2e.dart',
      ]);
      final args = command
          .skip(3)
          .map(
            (arg) =>
                arg.startsWith('<') ? '/local/corrected-Qwen3.litertlm' : arg,
          )
          .toList();
      expect(args, containsAllInOrder(['--backend', 'cpu']));
      for (final backend in ['cpu', 'gpu']) {
        expect(row.mode, contains(backend.toUpperCase()));
        final other = [...args];
        other[other.indexOf('--backend') + 1] = backend;
        final dryRun = await runLocalE2e(
          [...other, '--dry-run'],
          projectRoot: '/repo',
          displayShell: LocalE2eDisplayShell.posix,
        );
        expect(dryRun.exitCode, 0, reason: dryRun.stderr);
        expect(dryRun.stdout, contains('LITERT_LM_BACKEND=$backend'));
      }
      final result = await runLocalE2e(
        [...args, '--dry-run'],
        projectRoot: '/repo',
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.stdout,
        contains('LITERT_LM_MODEL=/local/corrected-Qwen3.litertlm'),
      );
      expect(
        result.stdout,
        contains(
          'dart test -p vm -j 1 --run-skipped -t local-only test/e2e/backends/litert_lm_json_schema_e2e_test.dart',
        ),
      );
    },
  );
  test('Web grammar matrix dispatches both pinned-asset Wasm suites', () async {
    final row = testMatrixRows.singleWhere(
      (row) => row.id == 'web-lazy-grammar',
    );
    final command = row.command.split(' ');
    expect(command.take(3), ['dart', 'run', 'tool/testing/run_local_e2e.dart']);
    final steps = <LocalE2eCommandStep>[];
    final result = await runLocalE2e(
      command.skip(3).toList(),
      projectRoot: '/repo',
      foregroundStepRun: (step) async {
        steps.add(step);
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(result.exitCode, 0, reason: result.stderr);
    expect(steps, hasLength(2));
    final fetch = steps.first;
    expect(fetch.executable, 'bash');
    expect(fetch.arguments, ['scripts/fetch_webgpu_bridge_assets.sh']);
    expect(fetch.environment, {
      'WEBGPU_BRIDGE_OUT_DIR': '/repo/build/web_lazy_grammar/bridge',
    });
    final tests = steps.last;
    expect(tests.executable, 'dart');
    expect(tests.arguments, [
      'test',
      '-p',
      'chrome-webgpu',
      '--run-skipped',
      '-t',
      'local-only',
      'test/e2e/webgpu/lazy_grammar_e2e_test.dart',
      'test/e2e/webgpu/prompt_penalty_grammar_e2e_test.dart',
    ]);
    for (final step in steps) {
      expect(step.workingDirectory, '/repo');
      expect(step.background, isFalse);
    }
    for (final target in tests.arguments.where(
      (arg) => arg.endsWith('.dart'),
    )) {
      expect(File(target).existsSync(), isTrue, reason: target);
    }
  });

  test('tool-result image matrix row reaches its local-only scenario and '
      'names the closest-family template override', () async {
    final row = testMatrixRows.singleWhere(
      (r) => r.id == 'tool-result-image-smoke',
    );
    expect(row.mode, 'local-only');
    final args = row.command
        .split(' ')
        .skip(3)
        .map((arg) => arg.startsWith('<') ? '/local/model.gguf' : arg)
        .toList();
    final result = await runLocalE2e(
      [...args, '--dry-run'],
      projectRoot: '/repo',
      displayShell: LocalE2eDisplayShell.posix,
    );
    expect(result.exitCode, 0, reason: result.stderr);
    expect(
      result.stdout,
      contains('test/e2e/backends/tool_result_media_e2e_test.dart'),
    );
    expect(row.useWhen, contains('LLAMADART_TOOL_MEDIA_CHAT_TEMPLATE'));
    final template = RegExp(
      r'test/fixtures/templates/\S+\.jinja',
    ).firstMatch(row.useWhen)!.group(0)!;
    expect(File(template).existsSync(), isTrue);
  });
  test('hires-fix matrix identifies its bounded CPU and Metal '
      'qualification', () {
    final row = testMatrixRows.singleWhere((r) => r.id == 'image-hires-fix');
    expect(row.tier, 'targeted');
    expect(row.mode, 'local-only');
    expect(row.covers, contains('macOS CPU or Metal'));
    expect(row.covers, contains('direct-C'));
    final scenario = buildLocalE2eScenarios().singleWhere(
      (s) => s.name == row.id,
    );
    expect(scenario.requiresDevice, isFalse);
    expect(row.command, contains('--scenario image-hires-fix'));
    expect(row.command, contains('LLAMADART_HIRES_DEVICE='));
  });
  test('reference-editing matrix identifies its bounded Metal '
      'qualification', () {
    final row = testMatrixRows.singleWhere(
      (r) => r.id == 'image-reference-editing',
    );
    expect(row.tier, 'targeted');
    expect(row.mode, 'local-only');
    expect(row.covers, contains('macOS Metal'));
    expect(row.covers, contains('direct-C'));
    final scenario = buildLocalE2eScenarios().singleWhere(
      (s) => s.name == row.id,
    );
    expect(scenario.requiresDevice, isFalse);
    expect(row.command, contains('--scenario image-reference-editing'));
    expect(row.command, contains('LLAMADART_REFERENCE_EDIT_T5XXL='));
  });
  test('ControlNet matrix identifies its bounded CPU qualification', () {
    final row = testMatrixRows.singleWhere((r) => r.id == 'image-controlnet');
    expect(row.tier, 'targeted');
    expect(row.mode, 'local-only');
    expect(row.covers, contains('macOS CPU'));
    expect(row.covers, contains('direct-C'));
    final scenario = buildLocalE2eScenarios().singleWhere(
      (s) => s.name == row.id,
    );
    expect(scenario.requiresDevice, isFalse);
    expect(row.command, contains('--scenario image-controlnet'));
    expect(row.command, contains('LLAMADART_SD15_CONTROLNET='));
  });
  test('image editing matrix identifies its bounded CPU qualification', () {
    final row = testMatrixRows.singleWhere((r) => r.id == 'image-editing');
    expect(row.tier, 'targeted');
    expect(row.mode, 'local-only');
    expect(row.covers, contains('macOS CPU'));
    expect(row.covers, contains('direct-C'));
    final scenario = buildLocalE2eScenarios().singleWhere(
      (s) => s.name == row.id,
    );
    expect(scenario.requiresDevice, isFalse);
    expect(row.command, contains('--scenario image-editing'));
  });

  test('LiteRT Web truncation matrix selects its local scenario', () {
    final row = testMatrixRows.singleWhere(
      (row) => row.id == 'litert-lm-web-truncation',
    );
    expect(row.mode, 'local-only');
    expect(row.covers, contains('maxTokens boundary'));
    expect(row.command, contains('--scenario litert-lm-web-truncation'));
    final scenario = buildLocalE2eScenarios().singleWhere(
      (scenario) => scenario.name == row.id,
    );
    expect(scenario.requiresDevice, isFalse);
    expect(scenario.description, contains('existing local model'));
  });

  test('LiteRT Web tool-calling matrix selects its local scenario', () {
    final row = testMatrixRows.singleWhere(
      (row) => row.id == 'litert-lm-web-tool-calling',
    );
    expect(row.mode, 'local-only');
    expect(row.covers, contains('no-tools control'));
    expect(row.command, contains('--scenario litert-lm-web-tool-calling'));
    final scenario = buildLocalE2eScenarios().singleWhere(
      (scenario) => scenario.name == row.id,
    );
    expect(scenario.requiresDevice, isFalse);
    expect(scenario.description, contains('existing local model'));
  });

  test(
    'LiteRT Web history matrix selects the direct-runtime control scenario',
    () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'litert-lm-web-text-history',
      );
      expect(row.tier, 'targeted');
      expect(row.mode, 'local-only');
      expect(row.covers, contains('no-history/no-system'));
      expect(row.command, contains('--scenario litert-lm-web-text-history'));
      final scenario = buildLocalE2eScenarios().singleWhere(
        (scenario) => scenario.name == row.id,
      );
      expect(scenario.requiresDevice, isFalse);
      expect(scenario.description, contains('existing local model'));
    },
  );

  test('text profile row selects the official retrieval production scenario', () {
    final row = testMatrixRows.singleWhere(
      (r) => r.id == 'text-embedding-retrieval',
    );
    expect(row.tier, 'targeted');
    expect(row.mode, contains('local-only'));
    expect(
      row.command,
      'dart run tool/testing/run_local_e2e.dart --scenario text-embedding-retrieval',
    );
    final scenario = buildLocalE2eScenarios().singleWhere(
      (s) => s.name == row.id,
    );
    expect(scenario.requiresDevice, isFalse);
    expect(scenario.description, contains('official float32 CPU reference'));
  });

  test('model-store row names the package CI job and its commands', () {
    final row = testMatrixRows.singleWhere(
      (r) => r.id == 'model-store-contracts',
    );
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    expect(row.tier, 'targeted');
    expect(row.command, contains('CI job model-store'));
    for (final command in [
      'flutter test',
      'dart test -p chrome test/model_store_web_test.dart',
    ]) {
      expect(row.command, contains(command));
      expect(workflow, contains(command));
    }
    expect(
      File('doc/testing_matrix.md').readAsStringSync(),
      contains('`model-store-contracts`'),
    );
  });

  test('examples-tests row names the example package CI job', () {
    final row = testMatrixRows.singleWhere((r) => r.id == 'examples-tests');
    expect(row.tier, 'targeted');
    expect(row.command, contains('"Example Package Tests"'));
    expect(row.command, contains('"Web Chat Contract"'));
    expect(row.command, contains('flutter test test test_vm'));
  });

  test(
    'Genkit matrix exposes independent contract native and release lanes',
    () {
      final contracts = testMatrixRows.singleWhere(
        (row) => row.id == 'genkit-contracts',
      );
      final native = testMatrixRows.singleWhere(
        (row) => row.id == 'genkit-native-cpu',
      );
      final release = testMatrixRows.singleWhere(
        (row) => row.id == 'genkit-release',
      );
      expect(contracts.command, contains('CI job genkit in '));
      expect(contracts.command, isNot(contains('genkit-lower-bounds')));
      expect(contracts.covers, contains('lower bounds'));
      expect(contracts.covers, contains('published/local-core'));
      expect(native.command, contains('LLAMADART_INTEGRATION_MODEL_PATH'));
      expect(native.mode, contains('CPU'));
      expect(release.command, contains('genkit_release_routing_test.dart'));
      expect(release.command, contains('genkit_package_staging_test.dart'));
      expect(release.mode, contains('no publication'));
    },
  );

  test(
    'native multimodal embedding row selects the local reference scenario',
    () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'native-multimodal-embeddings',
      );
      expect(row.mode, 'local-only');
      expect(
        row.command,
        'dart run tool/testing/run_local_e2e.dart --scenario native-multimodal-embeddings',
      );
      expect(row.covers, contains('cancellation'));
      expect(row.useWhen, contains('No downloads'));
    },
  );

  test('native sync Python suites row mirrors the CI Analyze & Lint steps', () {
    final row = testMatrixRows.singleWhere(
      (row) => row.id == 'native-sync-python-suites',
    );
    final ciSuites = RegExp(
      r'^\s*run: python3 (tool/native/test_[\w]+\.py)\s*$',
      multiLine: true,
    ).allMatches(File('.github/workflows/ci.yml').readAsStringSync());
    final expected = [for (final m in ciSuites) 'python3 ${m.group(1)}'];

    expect(expected, hasLength(greaterThanOrEqualTo(4)));
    expect(row.tier, 'targeted');
    expect(row.command.split(' (').first.split(' && '), expected);
    expect(row.command, contains('Python 3.10+'));
    expect(row.useWhen, contains('native_release_pins.dart'));
    expect(row.useWhen, contains('tool/native/'));
  });

  group('test_matrix', () {
    test('has unique row ids', () {
      final ids = testMatrixRows.map((row) => row.id).toList();

      expect(ids.toSet(), hasLength(ids.length));
    });

    test('has stable essential rows for baseline PR validation', () {
      final ids = testMatrixRows.map((row) => row.id).toSet();

      expect(ids, contains('static-format-analyze'));
      expect(ids, contains('root-vm'));
      expect(ids, contains('root-chrome'));
      expect(ids, contains('coverage-lib'));
    });

    test('coverage-lib excludes local-only suites that write empty coverage', () {
      final row = testMatrixRows.singleWhere((row) => row.id == 'coverage-lib');

      expect(
        row.command,
        startsWith(
          'dart test -p vm -j 1 --exclude-tags local-only --coverage=coverage;',
        ),
      );
      expect(
        row.command,
        allOf(
          contains('dart run tool/testing/format_lcov.dart --lcov '),
          contains('--in=coverage/test --out=coverage/lcov.info '),
          contains('--report-on=lib --check-ignore;'),
          endsWith(
            'dart run tool/testing/check_lcov_threshold.dart '
            'coverage/lcov.info 70',
          ),
        ),
      );
    });

    test(
      'keeps workspace preparation ahead of unscoped format and analyze',
      () {
        final row = testMatrixRows.singleWhere(
          (row) => row.id == 'static-format-analyze',
        );

        expect(
          row.command,
          startsWith(
            'dart run tool/prepare_workspace.dart && '
            'dart format --output=none --set-exit-if-changed . && '
            'dart analyze &&',
          ),
        );
      },
    );

    test('documents the LiteRT-LM chat smoke thinking N/A', () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'litert-lm-chat-features-smoke',
      );

      expect(
        row.covers.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'not_applicable with a reason when the bundle template always '
          'closes the think block, as for the Qwen3.5 int8 bundles',
        ),
      );
    });

    test('includes targeted local model smoke rows', () {
      final ids = testMatrixRows.map((row) => row.id).toSet();

      expect(ids, contains('gguf-chat-features-smoke'));
      expect(ids, contains('litert-lm-chat-features-smoke'));
      expect(ids, contains('native-inference-benchmark'));
      expect(ids, contains('llama-cpp-speculative-benchmark'));
      expect(ids, contains('web-mock-chat-smoke'));
      expect(ids, contains('web-real-model-smoke'));
      expect(ids, contains('web-tool-penalty-smoke'));
      expect(ids, contains('webgpu-multimodal-regression'));
      expect(ids, contains('gemma4-webgpu-mem64'));
      expect(ids, contains('physical-ios-speech-e2e'));
      expect(ids, contains('decision-model-smoke'));
      expect(ids, contains('decision-model-web-smoke'));
      expect(ids, contains('web-speech-task-cancel'));
      expect(ids, contains('image-generation-smoke'));
      expect(ids, contains('image-container-formats'));
      expect(ids, contains('image-exit-teardown'));
      expect(ids, contains('chat-app-image-generation-smoke'));
    });

    test(
      'container row selects maintained direct-C local-only qualification',
      () {
        final row = testMatrixRows.singleWhere(
          (row) => row.id == 'image-container-formats',
        );
        expect(row.tier, 'targeted');
        expect(row.mode, 'local-only');
        expect(row.command, contains('--scenario image-container-formats'));
        expect(row.command, contains('--model-path <manifest.json>'));
        expect(row.covers, contains('independent direct-C RGB parity'));
      },
    );

    test('Web tool penalty row is a targeted local-only scenario row', () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'web-tool-penalty-smoke',
      );

      expect(row.tier, 'targeted');
      expect(row.mode, 'local-only');
      expect(row.command, contains('chat-app-web-tool-penalty-smoke'));
    });

    test('Firebase image row builds a maintained image profile', () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'firebase-image-generation-e2e',
      );

      for (final id in ['image-sdxs-cpu', 'image-sdxs-metal']) {
        expect(row.command, contains(id));
        expect(
          File(
            'packages/llamadart_validation/assets/image_profiles/$id.json',
          ).existsSync(),
          isTrue,
        );
      }
      expect(row.command, contains('tool/testing/validation.dart build'));
    });

    test('chat-app image row runs the local-only device test', () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'chat-app-image-generation-smoke',
      );

      expect(row.mode, 'local-only');
      expect(
        row.command,
        contains('integration_test/image_generation_e2e_test.dart'),
      );
      expect(
        File(
          'example/chat_app/integration_test/image_generation_e2e_test.dart',
        ).existsSync(),
        isTrue,
      );
    });

    test('image settings row names its scenario and both profiles', () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'chat-app-image-settings-comparison',
      );

      expect(row.command, contains('chat-app-image-settings-comparison'));
      for (final id in [
        'image-settings-cpu',
        'image-settings-cpu-vae',
        'image-settings-metal',
        'image-settings-metal-taesd',
        'image-settings-metal-vae',
      ]) {
        expect(row.command, contains(id));
        expect(
          File(
            'packages/llamadart_validation/assets/image_profiles/$id.json',
          ).existsSync(),
          isTrue,
        );
      }
      expect(
        File(
          'example/chat_app/integration_test/'
          'image_settings_comparison_e2e_test.dart',
        ).existsSync(),
        isTrue,
      );
    });

    test('rows name local E2E scenarios that the runner defines', () {
      final scenarios = buildLocalE2eScenarios().map((s) => s.name).toSet();
      final referenced = <String>{};
      for (final row in testMatrixRows) {
        if (!row.command.contains('run_local_e2e.dart')) continue;
        final names = RegExp(
          r'--scenario\s+([a-z0-9-]+)',
        ).allMatches(row.command).map((match) => match.group(1)!);
        expect(names, isNotEmpty, reason: row.id);
        for (final name in names) {
          expect(scenarios, contains(name), reason: row.id);
          referenced.add(name);
        }
      }
      expect(referenced, contains('decision-model-smoke'));
      expect(referenced, contains('decision-model-web-smoke'));
      expect(referenced, contains('web-speech-task-cancel'));
      expect(referenced, contains('image-generation-smoke'));
      expect(referenced, contains('image-exit-teardown'));
      expect(referenced, contains('chat-app-macos-quit'));
    });

    test('the macOS quit test is local-only and its probe entrypoint '
        'exists', () {
      final test = File(
        'example/chat_app/test/macos_quit_e2e_test.dart',
      ).readAsStringSync();

      expect(test, contains("@Tags(['local-only'])"));
      expect(test, contains("'integration_test/macos_quit_probe.dart'"));
      expect(
        File(
          'example/chat_app/integration_test/macos_quit_probe.dart',
        ).existsSync(),
        isTrue,
      );
    });

    test('speech-to-text rows take WAV, MP3 or FLAC fixtures', () {
      for (final id in ['speech-to-text-smoke', 'web-speech-to-text-smoke']) {
        final row = testMatrixRows.singleWhere((row) => row.id == id);
        expect(row.command, contains('--audio-path <'));
        expect(row.command, contains('.wav|.mp3|.flac>'));
      }
      final web = testMatrixRows.singleWhere(
        (row) => row.id == 'web-speech-to-text-smoke',
      );
      expect(web.covers, contains('WAV, MP3 or FLAC transcription'));
      expect(web.covers, contains('microphone transcription for a WAV'));
    });

    test('includes targeted physical iOS speech E2E row', () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'physical-ios-speech-e2e',
      );
      expect(row.tier, equals('targeted'));
      expect(row.mode, contains('device'));
      expect(row.covers, contains('physical iOS'));
      expect(row.covers, contains('immutable local artifacts'));
      expect(row.covers, contains('no audio playback'));
      expect(row.covers, contains('llama.cpp Qwen3-ASR'));
      expect(row.covers, contains('LiteRT-LM streaming ASR'));
      expect(row.covers, contains('llama.cpp Qwen3-TTS'));
      expect(row.covers, contains('LiteRT-LM TTS'));
      expect(
        row.command,
        contains('integration_test/physical_ios_speech_e2e_test.dart'),
      );
    });

    test('physical iOS speech row uses wireless-capable Flutter drive', () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'physical-ios-speech-e2e',
      );

      // `flutter test` cannot start a wirelessly tethered physical iOS app.
      // Drive publishes a VM-service port and runs the integration driver.
      expect(row.command, contains('--no-pub'));
      expect(row.command, contains('--publish-port'));
      expect(row.command, contains('--no-start-paused'));
      expect(
        row.command,
        contains(r'--device-vmservice-port="$IOS_SPEECH_DEVICE_VM_PORT"'),
      );
      expect(
        row.command,
        contains(r'--host-vmservice-port="$IOS_SPEECH_HOST_VM_PORT"'),
      );
      expect(
        row.command,
        contains('--driver=test_driver/integration_test.dart'),
      );
      expect(
        row.command,
        contains('--target=integration_test/physical_ios_speech_e2e_test.dart'),
      );
      expect(
        row.command,
        contains('--timeout=21600'),
        reason: 'The drive host must allow the target\'s six-hour timeout.',
      );
      expect(row.command, contains('cd example/chat_app'));
      expect(row.command, contains('flutter drive'));
      expect(row.command, isNot(contains('flutter test')));
      expect(row.command, isNot(contains('--run-skipped')));
      expect(row.command, isNot(contains(' --no-uninstall ')));
      expect(
        row.command,
        isNot(contains('--no-uninstall-first')),
        reason: '`uninstall-first` is a flutter run flag, not a drive flag.',
      );
    });

    test('physical iOS speech row documents app-cache relative paths', () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'physical-ios-speech-e2e',
      );

      // Installing rotates the data-container UUID, so an operator who pins
      // absolute container paths gets unreadable artifacts.
      expect(row.useWhen, contains('@appcache/'));
      expect(row.useWhen, contains('data-container UUID'));
      expect(row.useWhen, contains('absolute'));
    });

    test('physical iOS speech row targets a physical device only', () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'physical-ios-speech-e2e',
      );

      expect(row.command, contains(r'-d "$PHYSICAL_IOS_DEVICE_ID"'));
      expect(row.command, isNot(contains('<physical-ios-device-id>')));
      expect(row.command, isNot(matches(RegExp(r'(^|\s)<[^>]+>'))));
      expect(row.command.toLowerCase(), isNot(contains('simulator')));
      expect(row.command.toLowerCase(), isNot(contains('http://')));
      expect(row.command.toLowerCase(), isNot(contains('https://')));
      expect(row.command.toLowerCase(), isNot(contains('playback')));
      expect(row.command.toLowerCase(), isNot(contains('--run-skipped-if')));
      expect(row.command, isNot(contains('/Containers/Data/Application/')));
      expect(
        row.command,
        isNot(
          matches(
            RegExp(
              r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
              r'[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}',
            ),
          ),
        ),
        reason: 'The command must never pin an install-specific container ID.',
      );
      expect(row.covers.toLowerCase(), isNot(contains('simulator')));
    });

    test('physical iOS speech row passes every required dart define', () {
      final row = testMatrixRows.singleWhere(
        (row) => row.id == 'physical-ios-speech-e2e',
      );

      const requiredDefines = <String>[
        'IOS_SPEECH_QWEN3_ASR_MODEL_PATH',
        'IOS_SPEECH_QWEN3_ASR_MODEL_SHA256',
        'IOS_SPEECH_QWEN3_ASR_MMPROJ_PATH',
        'IOS_SPEECH_QWEN3_ASR_MMPROJ_SHA256',
        'IOS_SPEECH_ASR_AUDIO_PATH',
        'IOS_SPEECH_ASR_AUDIO_SHA256',
        'IOS_SPEECH_ASR_EXPECTED_TRANSCRIPT',
        'IOS_SPEECH_MIC_DURATION_SECONDS',
        'IOS_SPEECH_MIC_EXPECTED_TRANSCRIPT',
        'IOS_SPEECH_LITERT_ASR_MODEL_PATH',
        'IOS_SPEECH_LITERT_ASR_MODEL_SHA256',
        'IOS_SPEECH_LITERT_ASR_TOKENIZER_PATH',
        'IOS_SPEECH_LITERT_ASR_TOKENIZER_SHA256',
        'IOS_SPEECH_LITERT_ASR_PRESET',
        'IOS_SPEECH_LITERT_ASR_AUDIO_PATH',
        'IOS_SPEECH_LITERT_ASR_AUDIO_SHA256',
        'IOS_SPEECH_LITERT_ASR_EXPECTED_TRANSCRIPT',
        'IOS_SPEECH_QWEN3_TTS_MODEL_PATH',
        'IOS_SPEECH_QWEN3_TTS_MODEL_SHA256',
        'IOS_SPEECH_QWEN3_TTS_MMPROJ_PATH',
        'IOS_SPEECH_QWEN3_TTS_MMPROJ_SHA256',
        'IOS_SPEECH_TTS_TEXT',
        'IOS_SPEECH_TTS_OUTPUT_PATH',
        'IOS_SPEECH_TTS_EXPECTED_TRANSCRIPT',
        'IOS_SPEECH_LITERT_LM_MODEL_PATH',
        'IOS_SPEECH_LITERT_LM_MODEL_SHA256',
      ];

      for (final define in requiredDefines) {
        expect(
          row.command,
          contains('--dart-define=$define='),
          reason: 'Command must pass $define.',
        );
        expect(
          row.command,
          contains('--dart-define=$define="\$$define"'),
          reason: 'Command must quote the operator-provided value for $define.',
        );
      }
      expect(
        '--dart-define='.allMatches(row.command).length,
        equals(requiredDefines.length),
        reason: 'Command must not pass unknown or duplicated defines.',
      );
    });

    test('includes explicit platform coverage rows', () {
      final ids = testMatrixRows.map((row) => row.id).toSet();

      expect(ids, contains('linux-x64-ci-runtime'));
      expect(ids, contains('linux-arm64-runtime-smoke'));
      expect(ids, contains('windows-x64-ci-runtime'));
      expect(ids, contains('windows-arm64-hook-coverage'));
      expect(ids, contains('macos-arm64-runtime-smoke'));
      expect(ids, contains('macos-x64-runtime-smoke'));
      expect(ids, contains('ios-arm64-device-smoke'));
      expect(ids, contains('ios-simulator-smoke'));
      expect(ids, contains('android-arm64-device-smoke'));
      expect(ids, contains('android-x64-emulator-smoke'));
      expect(ids, contains('web-chrome-runtime-smoke'));
    });

    test('includes release gate for companion pub packages', () {
      final releaseTable = formatTestMatrix(tier: 'release');

      expect(releaseTable, contains('release-companion-pub-gate'));
      expect(releaseTable, contains('publish_companion_pubdev.yml'));
      expect(releaseTable, contains('pub.dev/api/packages'));
    });

    test('includes high-risk adversarial review rows', () {
      final highRiskTable = formatTestMatrix(tier: 'high-risk');

      expect(highRiskTable, contains('high-risk-exact-head-independent-qa'));
      expect(highRiskTable, contains('structured-output-adversarial'));
      expect(highRiskTable, contains('production-branch deletion'));
      expect(highRiskTable, contains('compiled grammar acceptance/rejection'));
      expect(highRiskTable, contains('auto/required/none tool choice'));
      expect(highRiskTable, contains('pipeline-only'));
      expect(highRiskTable, isNot(contains('root-vm')));
    });

    test('formats PR evidence template with matrix ids', () {
      final template = formatPrEvidenceTemplate(tier: 'essential');

      expect(template, contains('| Matrix row |'));
      expect(template, contains('`root-vm`'));
      expect(template, contains('PASS / FAIL / N/A'));
      expect(template, isNot(contains('`android-arm64-device-smoke`')));
    });

    test('formats targeted matrix table with commands', () {
      final table = formatTestMatrix(tier: 'targeted');

      expect(table, contains('| ID | Tier | Mode |'));
      expect(table, contains('gguf-chat-features-smoke'));
      expect(table, contains('llama-cpp-chat-template-smoke'));
      expect(
        table,
        contains(
          'run_local_e2e.dart --scenario llama-cpp-speculative-benchmark',
        ),
      );
      expect(
        table,
        contains(
          '--draft-model-path <draft.gguf> --backend cpu '
          '--speculative-cases baseline,draft-dspark,ngram-simple,ngram-map-k,'
          'ngram-map-k4v,ngram-mod,ngram-cache,mixed-ngram',
        ),
      );
      expect(
        table,
        contains(
          '--draft-token-max 1,2 --ngram-size-m 8,16 --benchmark-warmups 1',
        ),
      );
      expect(
        table,
        contains(
          '--ngram-cache-build-static-path /tmp/llamadart-ngram-cache.bin',
        ),
      );
      expect(
        table,
        contains('External draft-model strategies require --draft-model-path'),
      );
      expect(table, contains('bundled MTP omits it'));
      expect(table, contains('ngram-cache can use'));
      expect(table, isNot(contains('LLAMADART_MTP_BENCHMARK')));
      expect(table, isNot(contains('llama_cpp_mtp_benchmark.dart')));
      expect(table, contains('run_local_e2e.dart'));
      expect(table, isNot(contains('static-format-analyze')));
    });

    test('formats platform matrix table separately from targeted rows', () {
      final table = formatTestMatrix(tier: 'platform');

      expect(table, contains('linux-x64-ci-runtime'));
      expect(table, contains('ios-arm64-device-smoke'));
      expect(table, contains('web-chrome-runtime-smoke'));
      expect(table, isNot(contains('gguf-chat-features-smoke')));
    });
  });
}
