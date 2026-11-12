@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  group('high-risk review policy', () {
    test('PR template retains the exact-head blocking evidence fields', () {
      final template = read('.github/pull_request_template.md');

      for (final field in [
        '**Classification:**',
        '**Implementation task:**',
        '**Independent blocking QA task:**',
        '**Exact head / current base:**',
        '**Production-branch deletion, bypass, or miswire proof:**',
        '**Affected-family real-model/artifact evidence:**',
        '**Explicit unavailable-family or other N/A evidence:**',
        '**Known PR-caused P1 regressions:**',
        '**Unresolved review threads:**',
      ]) {
        expect(template, contains(field), reason: 'missing $field');
      }
    });

    test('agent and matrix guidance preserve zero-regression boundaries', () {
      final agentGuidance = read('AGENTS.md');
      final matrix = read('doc/testing_matrix.md');

      expect(agentGuidance, contains('zero known PR-caused P1 regressions'));
      expect(agentGuidance, contains('zero unresolved review threads'));
      expect(agentGuidance, contains('pipeline-only evidence'));
      expect(matrix, contains('branch is deleted, bypassed, or miswired'));
      expect(matrix, contains('A known PR-caused P1 or any unresolved'));
      expect(matrix, contains('--name-only --no-renames'));
      expect(matrix, contains('compiled production-path coverage'));
    });

    test('batch integration PR rule keeps its audit and merge boundaries', () {
      final agentGuidance = read('AGENTS.md');
      final runbook = read('doc/high_risk_pre_merge_readiness.md');
      const auditBoundary =
          'only together with a passing integration audit of the integration '
          'head';

      for (final document in [agentGuidance, runbook]) {
        expect(document, contains('rebase merge, never squash'));
        expect(document, contains(auditBoundary));
      }
      expect(agentGuidance, contains('a new integration branch and PR'));
      expect(runbook, contains('listed per hunk, not per file'));
      expect(runbook, contains('new integration branch and PR cut from'));
      expect(runbook, contains('reviewed as a change in its own right'));
    });

    test('classifier help preserves rename and deletion visibility', () {
      final classifier = read('tool/testing/classify_high_risk_changes.dart');

      expect(
        classifier,
        contains('git diff --name-only --no-renames <base>...HEAD'),
      );
      expect(classifier, isNot(contains('git diff --name-only <base>...HEAD')));
    });

    test('CODEOWNERS protects policy and landed execution evidence', () {
      final codeowners = read('.github/CODEOWNERS');

      for (final path in [
        'AGENTS.md',
        'CONTRIBUTING.md',
        'doc/testing_matrix.md',
        'doc/pr_branch_writer_inventory.md',
        'doc/high_risk_pre_merge_readiness.md',
        'tool/testing/test_matrix.dart',
        'tool/testing/classify_high_risk_changes.dart',
        'tool/testing/high_risk_readiness.dart',
        'tool/testing/high_risk_readiness_evidence.schema.json',
        'tool/testing/run_template_parity_suites.sh',
        'tool/testing/run_llama_cpp_chat_tests.sh',
        'tool/testing/prepare_llama_cpp_source.sh',
        'tool/testing/llama_cpp_templates.ref',
        'tool/gen_litert_lm_templates.dart',
        'tool/litert_lm_templates/ @leehack',
        'test/integration/core/grammar/'
            'generated_tool_schema_grammar_test.dart',
        'test/e2e/template/'
            'specialized_tool_grammar_validation_e2e_test.dart',
        'test/unit/tooling/high_risk_review_policy_test.dart',
        'test/unit/tooling/high_risk_readiness_test.dart',
        'tool/git/safe_pr_head_update.dart',
        'tool/git/pr_head_update_evidence.schema.json',
        'test/unit/tooling/safe_pr_head_update_test.dart',
        'tool/testing/check_native_release_digests.dart',
      ]) {
        final rule = path.endsWith(' @leehack') ? path : '$path @leehack';
        expect(codeowners, contains(rule), reason: path);
      }
    });

    test('guidance documents machine-verifiable evaluator and runbook', () {
      final agentGuidance = read('AGENTS.md');
      final contributing = read('CONTRIBUTING.md');
      final matrix = read('doc/testing_matrix.md');

      expect(agentGuidance, contains('high_risk_readiness.dart'));
      expect(
        agentGuidance,
        contains('high_risk_readiness_evidence.schema.json'),
      );
      expect(agentGuidance, contains('doc/high_risk_pre_merge_readiness.md'));
      expect(contributing, contains('high_risk_readiness.dart'));
      expect(contributing, contains('doc/high_risk_pre_merge_readiness.md'));
      expect(matrix, contains('high_risk_readiness.dart'));
      expect(matrix, contains('doc/high_risk_pre_merge_readiness.md'));
    });

    test(
      'local evaluator and workflow preserve the external trust boundary',
      () {
        final evaluator = read('tool/testing/high_risk_readiness.dart');
        final workflow = read('.github/workflows/high_risk_readiness.yml');
        final runbook = read('doc/high_risk_pre_merge_readiness.md');

        expect(evaluator, contains('unverifiedPrerequisites'));
        expect(evaluator, contains('standardRiskDiagnostic'));
        expect(
          evaluator,
          contains("'independent_auditor_authenticated': false"),
        );
        expect(evaluator, isNot(contains('LLAMADART_READINESS_APP_ID')));
        expect(evaluator, isNot(contains('LLAMADART_READINESS_PRIVATE_KEY')));
        expect(evaluator, isNot(contains('Platform.environment')));
        expect(workflow, isNot(contains('workflow_dispatch:')));
        expect(
          workflow,
          isNot(
            contains(r'ref: ${{ github.event.repository.default_branch }}'),
          ),
        );
        expect(workflow, contains('Read-only advisory'));
        expect(workflow, contains('observed_head'));
        expect(workflow, contains('current_head'));
        expect(workflow, contains('observed_base'));
        expect(workflow, contains('current_base'));
        expect(workflow, contains('observed_changed_files'));
        expect(workflow, contains('current_changed_files'));
        expect(workflow, contains('--paginate --slurp'));
        expect(workflow, contains(r'($files | length) == $expected'));
        expect(workflow, contains('def safe_path:'));
        expect(workflow, contains(r'test("[\u0000-\u001F\u007F]")'));
        expect(workflow, contains('exit 1'));
        expect(workflow, isNot(contains('|| true')));
        expect(workflow, isNot(contains('PRIVATE_KEY')));
        expect(runbook, contains('manual repository-local review'));
        expect(
          runbook,
          contains(
            'Protected external enforcement is intentionally '
            'unconfigured',
          ),
        );
        expect(
          runbook,
          contains('must not add credentials or a required check until'),
        );
        expect(runbook, contains('must not be selected as a required'));
      },
    );

    test('high-risk advisory warns instead of failing the check', () {
      final workflow = read('.github/workflows/high_risk_readiness.yml');
      final steps = workflow
          .split(RegExp(r'^      - name: ', multiLine: true))
          .skip(1)
          .toList();
      final advisory = steps.singleWhere(
        (step) => step.contains("is_high_risk == 'true'"),
      );

      expect(advisory, contains('::warning::'));
      expect(advisory, isNot(contains('::error::')));
      expect(advisory, isNot(contains('exit 1')));
      expect(advisory, contains('High-risk readiness advisory'));
      expect(advisory, contains('tool/testing/high_risk_readiness.dart'));
      expect(advisory, contains('doc/high_risk_pre_merge_readiness.md'));
      expect(workflow, isNot(contains('Fail closed')));
    });

    test('advisory still fails on malformed or unsafe diagnostic input', () {
      final workflow = read('.github/workflows/high_risk_readiness.yml');
      final classify = workflow
          .split(RegExp(r'^      - name: ', multiLine: true))
          .singleWhere((step) => step.contains('id: classify'));

      expect(classify, contains('set -euo pipefail'));
      expect(classify, contains('::error::Invalid pull request number.'));
      expect(classify, contains('exit 64'));
      expect(classify, contains('exit 65'));
      expect(
        classify,
        contains(
          '::error::PR head, base, or changed-file count changed while the '
          'inventory was read.',
        ),
      );
      expect(classify, contains('exit 1'));
      expect(classify, contains('jq -e --argjson expected'));
    });

    test('schema makes evaluator decisions computed and enum-complete', () {
      final schema = read(
        'tool/testing/high_risk_readiness_evidence.schema.json',
      );

      expect(schema, contains(r'"additionalProperties": false'));
      expect(schema, contains(r'"evaluation"'));
      expect(schema, contains(r'"unverifiedPrerequisites"'));
      expect(schema, contains(r'"standardRiskDiagnostic"'));
      expect(schema, contains(r'"externalPrerequisitesUnavailable"'));
      expect(schema, isNot(contains(r'"decision": "ready"')));
    });
  });
}
