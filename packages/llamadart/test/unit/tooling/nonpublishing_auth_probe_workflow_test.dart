@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

YamlMap workflow() =>
    loadYaml(
          File(
            '.github/workflows/nonpublishing_release_auth_probe.yml',
          ).readAsStringSync(),
        )
        as YamlMap;

List<YamlMap> steps(YamlMap job) => (job['steps'] as YamlList).cast<YamlMap>();

void expectGuard(Object? value, List<String> conditions) {
  expect(value, isA<String>());
  final expression = value as String;
  expect(expression, startsWith(r'${{'));
  expect(expression, endsWith('}}'));
  // Exact conjunction terms reject an OR bypass as well as missing guards.
  final terms = expression
      .substring(3, expression.length - 2)
      .trim()
      .split('&&')
      .map((term) => term.trim().replaceAll(RegExp(r'\s+'), ' '));
  expect(terms, unorderedEquals(conditions));
}

void main() {
  test('probe accepts only manual expected SHA and diagnostic tag pushes', () {
    final config = workflow();
    final triggers = config['on'] as YamlMap;
    expect(triggers.keys, unorderedEquals(['workflow_dispatch', 'push']));
    final inputs = triggers['workflow_dispatch']['inputs'] as YamlMap;
    expect(inputs.keys, ['expected_sha']);
    final expectedSha = inputs['expected_sha'] as YamlMap;
    expect(expectedSha['required'], isTrue);
    expect(expectedSha['type'], 'string');
    expect(expectedSha.containsKey('default'), isFalse);
    expect(triggers['push'], {
      'tags': ['ci-auth-probe-*'],
    });
  });

  test(
    'probe has read-only permissions and invocation-isolated concurrency',
    () {
      final config = workflow();
      expect(config['permissions'], {'contents': 'read', 'actions': 'read'});
      expect(config['env'], isNull);
      expect(config['defaults'], isNull);
      expect(config['concurrency'], {
        'group': r'nonpublishing-auth-probe-${{ github.run_id }}',
        'cancel-in-progress': false,
      });
      final jobs = config['jobs'] as YamlMap;
      expect(jobs.keys, unorderedEquals(['sender', 'receiver']));
      for (final job in jobs.values.cast<YamlMap>()) {
        expect(job['permissions'], isNull);
        expect(job['uses'], isNull);
        expect(job['secrets'], isNull);
        expect(job['env'], isNull);
        expect(job['defaults'], isNull);
        expect(job['concurrency'], isNull);
      }
    },
  );

  test('sender and receiver guards reject other events and unsafe pushes', () {
    final jobs = workflow()['jobs'] as YamlMap;
    expectGuard(jobs['sender']['if'], [
      "github.event_name == 'workflow_dispatch'",
      "github.repository == 'leehack/llamadart'",
      "github.ref == 'refs/heads/main'",
      'github.run_attempt == 1',
    ]);
    expectGuard(jobs['receiver']['if'], [
      "github.event_name == 'push'",
      "github.repository == 'leehack/llamadart'",
      "startsWith(github.ref, 'refs/tags/ci-auth-probe-')",
      'github.event.created == true',
      'github.event.deleted == false',
      'github.event.forced == false',
      'github.run_attempt == 1',
    ]);
  });

  test('only the sender helper receives the release credential', () {
    final jobs = workflow()['jobs'] as YamlMap;
    for (final role in ['sender', 'receiver']) {
      final job = jobs[role] as YamlMap;
      expect(job['runs-on'], 'ubuntu-latest');
      expect(job['timeout-minutes'], allOf(isA<int>(), greaterThan(0)));
      expect(
        job['timeout-minutes'],
        lessThanOrEqualTo(role == 'sender' ? 12 : 5),
      );
      final jobSteps = steps(job);
      expect(jobSteps, hasLength(3));
      final checkout = jobSteps[0];
      expect(checkout['uses'], 'actions/checkout@v7');
      expect(checkout['with'], {
        'ref': r'${{ github.sha }}',
        'persist-credentials': false,
      });
      expect(checkout['run'], isNull);
      expect(checkout['env'], isNull);
      final helper = jobSteps[1];
      expect(helper['uses'], isNull);
      expect(helper['if'], isNull);
      expect(helper['continue-on-error'], isNull);
      expect(
        helper['run'],
        'python3 tool/release/nonpublishing_auth_probe.py $role',
      );
      final expectedEnv = <String, String>{
        'PROBE_OWNER_ID': r'${{ github.repository_owner_id }}',
        'PROBE_REPOSITORY_ID': r'${{ github.repository_id }}',
        'PROBE_READ_TOKEN': r'${{ github.token }}',
        if (role == 'sender') ...{
          'EXPECTED_SHA': r'${{ inputs.expected_sha }}',
          'RELEASE_AUTOMATION_TOKEN':
              r'${{ secrets.RELEASE_AUTOMATION_TOKEN }}',
        },
      };
      expect(helper['env'], expectedEnv);
      // Inspect all parsed step fields, including names and action inputs, so
      // another credential interpolation cannot hide outside the helper env.
      for (final step in jobSteps) {
        final fields = Map<Object?, Object?>.from(step);
        if (identical(step, helper)) fields.remove('env');
        expect(fields.toString(), isNot(contains('secrets.')));
        expect(fields.toString(), isNot(contains('RELEASE_AUTOMATION_TOKEN')));
      }
    }
  });

  test('both roles retain nonoverwriting attempt-bound outcome artifacts', () {
    final jobs = workflow()['jobs'] as YamlMap;
    for (final role in ['sender', 'receiver']) {
      final artifact = steps(jobs[role] as YamlMap)[2];
      expect(artifact['uses'], 'actions/upload-artifact@v7');
      expect(artifact['run'], isNull);
      expect(artifact['env'], isNull);
      expect(artifact['if'], 'always()');
      expect(artifact['with'], {
        'name':
            'auth-probe-$role-'
            r'${{ github.run_id }}-attempt-${{ github.run_attempt }}',
        'path': r'${{ runner.temp }}/auth-probe/',
        'if-no-files-found': 'error',
        'overwrite': false,
        'retention-days': 7,
      });
    }
  });
}
