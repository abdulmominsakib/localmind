@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const workflowPath =
    '.github/workflows/native_default_consumer_qualification.yml';

YamlMap workflow() =>
    loadYaml(File(workflowPath).readAsStringSync()) as YamlMap;

YamlMap qualification() => workflow()['jobs']['qualify'] as YamlMap;

List<YamlMap> steps() => (qualification()['steps'] as YamlList).cast<YamlMap>();

YamlMap step(String id) => steps().singleWhere((step) => step['id'] == id);

void main() {
  test(
    'qualification is explicit dispatch with reviewed SHA and source-pin verification',
    () {
      final config = workflow();
      final triggers = config['on'] as YamlMap;
      expect(
        triggers.keys,
        unorderedEquals(['workflow_dispatch', 'workflow_call']),
      );
      expect(triggers['workflow_call'], {
        'inputs': {
          'expected_sha': {'required': true, 'type': 'string'},
          'expected_native_tag': {'required': true, 'type': 'string'},
        },
      });
      final inputs = triggers['workflow_dispatch']['inputs'] as YamlMap;
      expect(
        inputs.keys,
        unorderedEquals(['expected_sha', 'expected_native_tag']),
      );
      expect(inputs['expected_sha']['required'], isTrue);
      expect(inputs['expected_sha']['type'], 'string');
      expect(inputs['expected_native_tag']['required'], isTrue);
      expect(inputs['expected_native_tag']['type'], 'choice');
      expect(inputs['expected_native_tag']['options'], [
        'v0.8.0-2',
        'v0.8.0-3',
        'v0.9.0',
      ]);
      final guard = qualification()['if'] as String;
      expect(guard, startsWith(r'${{'));
      expect(guard, endsWith('}}'));
      expect(
        guard
            .substring(3, guard.length - 2)
            .trim()
            .split('&&')
            .map((term) => term.trim()),
        unorderedEquals([
          "github.event_name == 'workflow_dispatch'",
          "github.repository == 'leehack/llamadart'",
          'github.run_attempt == 1',
        ]),
      );
    },
  );

  test(
    'qualification keeps read-only authority and fixed platform SDK matrix',
    () {
      final config = workflow();
      expect(config['permissions'], {'contents': 'read'});
      expect(config['jobs'].keys, ['qualify']);
      expect(config['env'], isNull);
      expect(config['defaults'], isNull);
      final job = qualification();
      expect(job['permissions'], isNull);
      expect(job['uses'], isNull);
      expect(job['secrets'], isNull);
      expect(job['defaults'], isNull);
      expect(job['runs-on'], r'${{ matrix.os }}');
      expect(
        job['timeout-minutes'],
        allOf(greaterThan(0), lessThanOrEqualTo(75)),
      );
      expect(job['strategy']['fail-fast'], isFalse);
      expect(job['strategy']['matrix'], {
        'include': [
          {'os': 'macos-15', 'platform': 'macos', 'arch': 'arm64'},
          {'os': 'windows-2022', 'platform': 'windows', 'arch': 'x64'},
        ],
      });
      expect(config['concurrency'], {
        'group': r'native-default-aot-${{ github.run_id }}',
        'cancel-in-progress': false,
      });
      final checkouts = steps().where(
        (step) => step['uses'] == 'actions/checkout@v7',
      );
      expect(checkouts.single['with'], {
        'ref': r'${{ github.sha }}',
        'fetch-depth': 0,
        'persist-credentials': false,
      });
      final flutter = steps().singleWhere(
        (step) => step['uses'] == 'subosito/flutter-action@v2',
      );
      expect(flutter['with'], {
        'flutter-version': File('.flutter-version').readAsStringSync().trim(),
        'channel': 'stable',
        'cache': false,
      });
      final python = steps().singleWhere(
        (step) => step['uses'] == 'actions/setup-python@v7',
      );
      expect(python['with'], {'python-version': '3.12'});
      expect(
        steps().map((step) => step['uses']).whereType<String>(),
        unorderedEquals([
          'actions/checkout@v7',
          'actions/setup-python@v7',
          'subosito/flutter-action@v2',
          'actions/upload-artifact@v7',
        ]),
      );
      expect(steps(), hasLength(7));
      expect(config.toString(), isNot(contains('secrets.')));
      final scripts = steps()
          .map((step) => step['run'])
          .whereType<String>()
          .join('\n');
      expect(
        scripts,
        isNot(
          matches(
            RegExp(
              r'\b(?:publish|deploy|dispatch|push|createRef|updateRef|deleteRef)\b',
              caseSensitive: false,
            ),
          ),
        ),
      );
      for (final forbidden in [
        '/git/refs',
        'Authorization',
        'Bearer',
        'GITHUB_TOKEN',
      ]) {
        expect(scripts, isNot(contains(forbidden)));
      }
      for (final item in steps()) {
        expect(item['env'], isNull);
        expect(item['continue-on-error'], isNull);
      }
    },
  );

  test(
    'runner paths bind in step scope and job env uses only available contexts',
    () async {
      final jobEnv = qualification()['env'] as YamlMap;
      const allowedJobContexts = {
        'github',
        'inputs',
        'matrix',
        'needs',
        'secrets',
        'strategy',
        'vars',
      };
      for (final value in jobEnv.values.whereType<String>()) {
        for (final expression in RegExp(r'\$\{\{(.*?)\}\}').allMatches(value)) {
          for (final context in RegExp(
            r'([A-Za-z_][A-Za-z0-9_]*)\.',
          ).allMatches(expression[1]!)) {
            expect(allowedJobContexts, contains(context[1]));
          }
        }
      }
      expect(jobEnv.containsKey('LLAMADART_DEFAULT_AOT_MODEL_PATH'), isFalse);
      expect(jobEnv.containsKey('LLAMADART_DEFAULT_AOT_OUTPUT_ROOT'), isFalse);
      final ordered = steps();
      final ids = ordered.map((item) => item['id']).toList();
      final pathsIndex = ids.indexOf('paths');
      final inputsIndex = ids.indexOf('inputs');
      final qualificationIndex = ids.indexOf('qualification');
      for (final index in [pathsIndex, inputsIndex, qualificationIndex]) {
        expect(index, greaterThanOrEqualTo(0));
      }
      expect(pathsIndex, lessThan(inputsIndex));
      expect(pathsIndex, lessThan(qualificationIndex));
      final binding = ordered[pathsIndex];
      expect(binding['shell'], 'python');
      expect(binding['if'], isNull);
      final root = Directory.systemTemp.createTempSync('runner path context ');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final attempt in ['1', '2']) {
        final environmentFile = File('${root.path}/env-$attempt');
        final result = await Process.run(
          Platform.isWindows ? 'python' : 'python3',
          ['-c', binding['run'] as String],
          environment: {
            'RUNNER_TEMP': root.path,
            'GITHUB_RUN_ID': '123456',
            'GITHUB_RUN_ATTEMPT': attempt,
            'GITHUB_ENV': environmentFile.path,
          },
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final owned = Directory(
          '${root.path}/native-default-aot-123456-$attempt',
        );
        final values = {
          for (final line in environmentFile.readAsLinesSync())
            line.substring(0, line.indexOf('=')): line.substring(
              line.indexOf('=') + 1,
            ),
        };
        expect(
          values.keys,
          unorderedEquals([
            'LLAMADART_DEFAULT_AOT_MODEL_PATH',
            'LLAMADART_DEFAULT_AOT_OUTPUT_ROOT',
          ]),
        );
        expect(
          File(values['LLAMADART_DEFAULT_AOT_MODEL_PATH']!).uri,
          File('${owned.path}/qwen2.5-1.5b-instruct-q4_k_m.gguf').uri,
        );
        expect(
          Directory(values['LLAMADART_DEFAULT_AOT_OUTPUT_ROOT']!).uri,
          Directory('${owned.path}/results').uri,
        );
        expect(owned.existsSync(), isFalse);
      }
    },
  );

  test(
    'driver route has verification-only inputs and retains attempt-bound evidence',
    () {
      final job = qualification();
      final env = job['env'] as YamlMap;
      expect(
        env.keys,
        unorderedEquals([
          'PYTHONDONTWRITEBYTECODE',
          'QUALIFICATION_PLATFORM',
          'QUALIFICATION_ARCH',
          'LLAMADART_DEFAULT_AOT_EXPECTED_SHA',
          'LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG',
        ]),
      );
      expect(env['PYTHONDONTWRITEBYTECODE'], '1');
      expect(env['QUALIFICATION_PLATFORM'], r'${{ matrix.platform }}');
      expect(env['QUALIFICATION_ARCH'], r'${{ matrix.arch }}');
      expect(
        env['LLAMADART_DEFAULT_AOT_EXPECTED_SHA'],
        r'${{ inputs.expected_sha }}',
      );
      expect(
        env['LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG'],
        r'${{ inputs.expected_native_tag }}',
      );
      final driver = step('qualification');
      expect(driver['shell'], 'python');
      expect(driver['if'], isNull);
      final command = driver['run'] as String;
      expect(
        command,
        contains(
          'test/fixtures/native_default_consumer_qualification/qualify.py',
        ),
      );
      for (final argument in [
        '--core-root',
        '--expected-core-sha',
        '--expected-native-tag',
        '--model',
        '--output',
      ]) {
        expect(command, contains("'$argument'"));
      }
      expect(command, contains('subprocess.call(command)'));
      expect(
        RegExp(r"'--[a-z-]+'").allMatches(command).map((match) => match[0]),
        [
          "'--core-root'",
          "'--expected-core-sha'",
          "'--expected-native-tag'",
          "'--model'",
          "'--output'",
        ],
      );
      expect(RegExp(r'subprocess\.call\(').allMatches(command), hasLength(1));
      expect(command, isNot(contains(r'${{')));
      expect(command, isNot(contains('shell=True')));
      expect(command, isNot(contains('--native-tag')));
      final upload = steps().singleWhere(
        (step) => step['uses'] == 'actions/upload-artifact@v7',
      );
      expect(upload['if'], r'${{ always() }}');
      expect(
        upload['with']['name'],
        r'native-default-aot-${{ matrix.platform }}-${{ github.sha }}-${{ github.run_id }}-attempt-${{ github.run_attempt }}',
      );
      expect(upload['with']['overwrite'], isFalse);
      expect(upload['with']['retention-days'], 7);
      expect(upload['with']['if-no-files-found'], 'error');
      expect(
        upload['with']['path'],
        contains(r'${{ env.LLAMADART_DEFAULT_AOT_OUTPUT_ROOT }}'),
      );
      expect(upload['with']['path'], contains('/preflight.json'));
      expect(upload['with']['path'], isNot(contains('.gguf')));
    },
  );

  test(
    'fixed model source uses bounded streaming identity checks without input interpolation',
    () {
      final prepare = step('inputs');
      expect(prepare['shell'], 'python');
      expect(prepare['if'], isNull);
      final script = prepare['run'] as String;
      expect(
        script,
        contains(
          '91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf',
        ),
      );
      expect(script, contains('expected_bytes = 1117320736'));
      expect(
        script,
        contains(
          "expected_digest = '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e'",
        ),
      );
      expect(script, contains('response.read(1024 * 1024)'));
      expect(script, contains('if size > expected_bytes:'));
      expect(
        script,
        contains(
          'size != expected_bytes or digest.hexdigest() != expected_digest',
        ),
      );
      expect(script, contains("model.open('xb')"));
      expect(script, contains('root.mkdir(parents=True, exist_ok=False)'));
      expect(script, contains("'qualified': False"));
      expect(script, isNot(contains(r'${{')));
      expect(script, isNot(contains('print(')));
      expect(RegExp(r'opener\.open\(').allMatches(script), hasLength(1));
      expect(
        script,
        contains(
          "raise SystemExit('fixed model download or identity verification failed') from None",
        ),
      );
    },
  );

  test(
    'real workflow preflight refuses input/source/host drift before the model request',
    () async {
      final root = Directory.systemTemp.createTempSync('default-aot-workflow-');
      addTearDown(() => root.deleteSync(recursive: true));
      final pin = File('${root.path}/lib/src/hook/native_release_pins.dart');
      pin.parent.createSync(recursive: true);
      pin.writeAsStringSync("const llamaCppTag = 'v0.8.0-2';\n");
      const sha = '1111111111111111111111111111111111111111';
      const child = r'''
import os
from pathlib import Path
import platform
import subprocess
import sys
import types
import urllib.request
platform.machine = lambda: os.environ.get('TEST_MACHINE', 'arm64')
sys.platform = os.environ.get('TEST_PLATFORM', 'darwin')
subprocess.run = lambda *a, **k: types.SimpleNamespace(stdout=os.environ.get('TEST_CHECKOUT', os.environ['GITHUB_SHA']))
class Download:
    def open(self, *a, **k):
        marker = Path(sys.argv[2])
        marker.write_text(marker.read_text() + 'attempt\n' if marker.exists() else 'attempt\n')
        raise RuntimeError('synthetic transport stop')
urllib.request.build_opener = lambda *a, **k: Download()
exec(sys.argv[1], {})
''';
      final cases = <(String, Map<String, String>, bool)>[
        (
          'invalid-sha',
          {'LLAMADART_DEFAULT_AOT_EXPECTED_SHA': 'not-a-sha'},
          false,
        ),
        (
          'event-drift',
          {
            'GITHUB_SHA': '2222222222222222222222222222222222222222',
            'TEST_CHECKOUT': sha,
          },
          false,
        ),
        (
          'checkout-drift',
          {'TEST_CHECKOUT': '2222222222222222222222222222222222222222'},
          false,
        ),
        (
          'pin-drift',
          {'LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG': 'v0.8.0-3'},
          false,
        ),
        ('wrong-platform', {'TEST_PLATFORM': 'win32'}, false),
        ('wrong-architecture', {'TEST_MACHINE': 'amd64'}, false),
        (
          'unqualified-macos-x64',
          {'QUALIFICATION_ARCH': 'x64', 'TEST_MACHINE': 'amd64'},
          false,
        ),
        ('valid-baseline-transport-stop', {}, true),
        (
          'valid-windows-baseline-transport-stop',
          {
            'QUALIFICATION_PLATFORM': 'windows',
            'QUALIFICATION_ARCH': 'x64',
            'TEST_PLATFORM': 'win32',
            'TEST_MACHINE': 'AMD64',
          },
          true,
        ),
      ];
      for (final (label, overrides, requestsModel) in cases) {
        final output = '${root.path}/$label/results';
        final marker = File('${root.path}/$label-download');
        final result = await Process.run(
          Platform.isWindows ? 'python' : 'python3',
          ['-c', child, step('inputs')['run'] as String, marker.path],
          workingDirectory: root.path,
          environment: {
            'LLAMADART_DEFAULT_AOT_EXPECTED_SHA': sha,
            'LLAMADART_DEFAULT_AOT_EXPECTED_NATIVE_TAG': 'v0.8.0-2',
            'LLAMADART_DEFAULT_AOT_MODEL_PATH':
                '${root.path}/$label/model.gguf',
            'LLAMADART_DEFAULT_AOT_OUTPUT_ROOT': output,
            'GITHUB_SHA': sha,
            'QUALIFICATION_PLATFORM': 'macos',
            'QUALIFICATION_ARCH': 'arm64',
            ...overrides,
          },
        );
        expect(result.exitCode, 1, reason: '$label: ${result.stderr}');
        expect(marker.existsSync(), requestsModel, reason: label);
        if (marker.existsSync()) expect(marker.readAsLinesSync(), ['attempt']);
        final receipt =
            jsonDecode(
                  File('${root.path}/$label/preflight.json').readAsStringSync(),
                )
                as Map;
        expect(receipt['qualified'], isFalse);
        expect(receipt['status'], 'started');
        expect(Directory(output).existsSync(), isFalse);
      }
    },
  );
}
