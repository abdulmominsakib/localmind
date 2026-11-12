@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

YamlMap workflow(String name) =>
    loadYaml(File('.github/workflows/$name.yml').readAsStringSync()) as YamlMap;

Iterable<YamlMap> checkouts(YamlMap workflow) sync* {
  for (final job in (workflow['jobs'] as YamlMap).values) {
    for (final step in (job['steps'] as YamlList? ?? [])) {
      if (step is YamlMap &&
          (step['uses'] as String? ?? '').startsWith('actions/checkout@')) {
        yield step;
      }
    }
  }
}

void main() {
  test(
    'trusted PR advisory checks out only its immutable trusted revision',
    () {
      final config = workflow('high_risk_readiness');
      expect(
        (config['on'] as YamlMap).containsKey('pull_request_target'),
        isTrue,
      );
      final checkout = checkouts(config).single;
      expect(checkout['with']['ref'], r'${{ github.sha }}');
      expect(checkout['with']['persist-credentials'], isFalse);
      expect(config['permissions'], {
        'contents': 'read',
        'pull-requests': 'read',
      });
    },
  );

  test('workflow-run docs checkout cannot select triggering fork code', () {
    final config = workflow('docs_pages');
    expect(config['on']['workflow_run']['workflows'], ['Docs Version Cut']);
    final inputs = checkouts(config).single['with'] as YamlMap;
    expect(inputs.containsKey('ref'), isFalse);
    expect(inputs.containsKey('repository'), isFalse);
    expect(inputs['fetch-depth'], 0);
  });

  test('all checkouts use v7 without opting out of the unsafe fork guard', () {
    final files = Directory('.github/workflows').listSync().whereType<File>();
    var count = 0;
    for (final file in files.where((file) => file.path.endsWith('.yml'))) {
      final config = loadYaml(file.readAsStringSync()) as YamlMap;
      for (final checkout in checkouts(config)) {
        count++;
        expect(checkout['uses'], 'actions/checkout@v7', reason: file.path);
        final inputs = checkout['with'] as YamlMap?;
        expect(
          inputs?.containsKey('allow-unsafe-pr-checkout') ?? false,
          isFalse,
          reason: file.path,
        );
      }
    }
    expect(count, greaterThan(0));
  });

  test('release checkout retains merged provenance and no credentials', () {
    final checkout = checkouts(workflow('release_on_prep_merge')).single;
    expect(checkout['if'], r"steps.gate.outputs.should_release == 'true'");
    expect(
      checkout['with']['ref'],
      r'${{ github.event.pull_request.merge_commit_sha }}',
    );
    expect(checkout['with']['fetch-depth'], 0);
    expect(checkout['with']['persist-credentials'], isFalse);
  });
}
