@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/testing/run_local_e2e.dart';
import '../../fixtures/litert_lm_v1_schema_contract.dart';

void main() {
  final expected = {'café': '日本 😊', 'count': 3, 'active': true, 'empty': null};
  test(
    'schema oracle accepts exact Unicode and typed fields in arbitrary order',
    () {
      expect(
        requireV1SchemaTypedResponse(
          jsonEncode({
            'empty': null,
            'active': true,
            'count': 3,
            'café': '日本 😊',
          }),
        ),
        expected,
      );
    },
  );
  test('schema integer accepts equivalent numeric 3.0 representation', () {
    expect(
      requireV1SchemaTypedResponse(
        jsonEncode({...expected, 'count': 3.0}),
      )['count'],
      3,
    );
  });
  for (final text in [
    'BANANA',
    '<think>reason</think>{}',
    '```json\n{}\n```',
    'prefix {}',
    '${jsonEncode(expected)} trailing',
  ]) {
    test('schema oracle refuses framing or unconstrained output $text', () {
      expect(() => requireV1SchemaTypedResponse(text), throwsStateError);
    });
  }
  final wrong = <Object?>[
    {...expected, 'café': '日本'},
    {...expected, 'count': 3.5},
    {...expected, 'count': '3'},
    {...expected, 'active': 'true'},
    {...expected, 'active': 1},
    {...expected, 'empty': ''},
    {...expected, 'extra': true},
    {...expected}..remove('empty'),
    [],
    null,
  ];
  for (var index = 0; index < wrong.length; index++) {
    test('schema oracle refuses wrong type/value/shape $index', () {
      expect(
        () => requireV1SchemaTypedResponse(jsonEncode(wrong[index])),
        throwsStateError,
      );
    });
  }
  test(
    'plain counterexample and followup cannot accept sticky JSON constraints',
    () {
      requireV1SchemaPlainControl('BANANA');
      expect(
        () => requireV1SchemaPlainControl(jsonEncode(expected)),
        throwsStateError,
      );
      expect(
        () => requireV1SchemaPlainControl('BANANA explanation'),
        throwsStateError,
      );
    },
  );
  test(
    'schema qualifier model lock matches the existing published CPU profile',
    () {
      final profile =
          jsonDecode(
                File(
                  'packages/llamadart_validation/assets/profiles/chat-litert-cpu.json',
                ).readAsStringSync(),
              )
              as Map;
      expect((profile['model'] as Map)['sha256'], v1SchemaModelSha256);
      expect((profile['model'] as Map)['bytes'], v1SchemaModelBytes);
    },
  );
  final identity = {
    'LITERT_LM_V1_LIBRARY': '/candidate/libLiteRtLm.dylib',
    'LITERT_LM_V1_LIBRARY_SHA256': 'a' * 64,
    'LITERT_LM_V1_MODEL_SHA256': v1SchemaModelSha256,
  };
  test(
    'schema scenario selects bounded child mode with a fixed profile identity',
    () async {
      final result = await runLocalE2e(
        [
          '--scenario',
          'litert-lm-v1-json-schema',
          '--model-path',
          '/Qwen3-0.6B.litertlm',
          '--backend',
          'cpu',
          '--dry-run',
        ],
        projectRoot: '/repo',
        environment: identity,
        displayShell: LocalE2eDisplayShell.posix,
      );
      expect(result.exitCode, 0);
      expect(result.stdout, contains('LITERT_LM_V1_SCHEMA_QUALIFICATION=1'));
      expect(
        result.stdout,
        contains('test/e2e/backends/litert_lm_v1_service_e2e_test.dart'),
      );
      expect(result.stdout, contains(v1SchemaModelSha256));
    },
  );
  for (final entry in {
    'wrong-model': {...identity, 'LITERT_LM_V1_MODEL_SHA256': 'b' * 64},
    'missing-library': {...identity}..remove('LITERT_LM_V1_LIBRARY'),
    'missing-library-hash': {...identity}
      ..remove('LITERT_LM_V1_LIBRARY_SHA256'),
  }.entries) {
    test('schema scenario refuses ${entry.key} before execution', () async {
      final result = await runLocalE2e(
        [
          '--scenario',
          'litert-lm-v1-json-schema',
          '--model-path',
          '/Qwen3-0.6B.litertlm',
          '--backend',
          'cpu',
          '--dry-run',
        ],
        projectRoot: '/repo',
        environment: entry.value,
      );
      expect(result.exitCode, 64);
    });
  }
  test(
    'schema scenario refuses GPU and missing model before execution',
    () async {
      for (final args in [
        <String>['--backend', 'gpu', '--model-path', '/model'],
        <String>['--backend', 'cpu'],
      ]) {
        final result = await runLocalE2e(
          ['--scenario', 'litert-lm-v1-json-schema', ...args, '--dry-run'],
          projectRoot: '/repo',
          environment: identity,
        );
        expect(result.exitCode, 64);
      }
    },
  );
}
