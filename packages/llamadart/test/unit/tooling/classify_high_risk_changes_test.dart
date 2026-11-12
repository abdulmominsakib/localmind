@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/testing/classify_high_risk_changes.dart';

Future<HighRiskCliResult> runClassifier(List<int> input) =>
    classifyHighRiskInput(Stream.value(input));

void main() {
  test('impact hints separate known boundaries and union mixed effects', () {
    const render = 'lib/src/core/template/template_render_context.dart';
    const parser = 'lib/src/core/template/peg_chat_parser.dart';
    expect(
      structuredImpactHints(['lib/src/core/template/tool_schema_utils.dart']),
      StructuredImpact.values.toSet(),
    );
    const grammar = 'lib/src/core/grammar/gbnf_grammar_generator.dart';
    expect(structuredImpactHints([render]), {
      StructuredImpact.inputRenderingHistory,
    });
    expect(structuredImpactHints([parser]), {
      StructuredImpact.outputParsingStreaming,
    });
    expect(structuredImpactHints([grammar]), {StructuredImpact.grammarSchema});
    expect(
      structuredImpactHints([render, parser, grammar]),
      StructuredImpact.values.toSet(),
    );
    expect(
      structuredImpactHints(['lib/src/core/template/new_helper.dart']),
      StructuredImpact.values.toSet(),
    );
    expect(
      structuredImpactHints([
        'lib/src/core/template/handlers/qwen3_handler.dart',
      ]),
      StructuredImpact.values.toSet(),
    );
    expect(
      structuredImpactHints(['test/unit/core/template/handler_test.dart']),
      StructuredImpact.values.toSet(),
    );
    expect(
      assessHighRiskFiles([
        'tool/testing/high_risk_readiness_evidence.v1.schema.json',
      ]).surfaces,
      contains(HighRiskSurface.regressionPolicy),
    );
  });

  test('paths alone never establish an empty export contribution', () {
    expect(
      structuredProductionImpactHints('lib/llamadart.dart'),
      StructuredImpact.values.toSet(),
    );
    expect(
      structuredProductionImpactHints('lib/src/core/image/new_image.dart'),
      isNull,
    );
    expect(
      structuredImpactHints(['lib/src/core/image/new_image.dart']),
      StructuredImpact.values.toSet(),
    );
    expect(
      structuredImpactHints(['test/unit/core/template/new_test.dart']),
      StructuredImpact.values.toSet(),
    );
  });

  group('assessHighRiskFiles', () {
    test('only exact root ffigen config is an artifact consumer', () {
      expect(assessHighRiskFiles(['ffigen.yaml']).surfaces, {
        HighRiskSurface.artifactConsumer,
      });
      for (final path in [
        'ffigen.yml',
        'ffigen.yaml.backup',
        'nested/ffigen.yaml',
        'analysis_options.yaml',
        'dart_test.yaml',
      ]) {
        expect(assessHighRiskFiles([path]).isHighRisk, isFalse, reason: path);
      }
    });

    test(
      'independent Genkit runtime, schema, archive and policy paths retain gates',
      () {
        const prefix = 'packages/genkit_llamadart/';
        expect(
          assessHighRiskFiles([
            'tool/release/genkit_release_helpers.sh',
          ]).surfaces,
          contains(HighRiskSurface.releaseAutomation),
        );
        for (final path in [
          'lib/src/core/runtime/engine_registry.dart',
          'lib/src/api/runtime_owner.dart',
          'lib/src/api/model_preparation.dart',
        ]) {
          expect(
            assessHighRiskFiles(['$prefix$path']).surfaces,
            contains(HighRiskSurface.backendRuntime),
            reason: path,
          );
        }
        for (final path in [
          'lib/genkit_llamadart.dart',
          'lib/experimental.dart',
          'lib/src/core/streaming/completion_accumulator.dart',
          'lib/src/integration/genkit/converters/schema_to_tool_params.dart',
          'lib/src/integration/genkit/converters/genkit_to_llama.dart',
          'lib/src/integration/genkit/actions/model_action.dart',
        ]) {
          expect(
            assessHighRiskFiles(['$prefix$path']).surfaces,
            containsAll({
              HighRiskSurface.structuredOutput,
              HighRiskSurface.backendRuntime,
            }),
            reason: path,
          );
        }
        for (final path in [
          'pubspec.yaml',
          '.pubignore',
          'pubspec_overrides.yaml',
        ]) {
          expect(
            assessHighRiskFiles(['$prefix$path']).surfaces,
            contains(HighRiskSurface.artifactConsumer),
            reason: path,
          );
        }
        expect(
          assessHighRiskFiles(['${prefix}CONTRIBUTING.md']).surfaces,
          contains(HighRiskSurface.regressionPolicy),
        );
        expect(
          assessHighRiskFiles(['$prefix.github/check_docs.py']).surfaces,
          contains(HighRiskSurface.regressionPolicy),
        );
        for (final path in [
          'test/integration/genkit/plugin/real_model_constrained_grammar_test.dart',
          'test/integration/genkit/plugin/real_model_rich_tool_schemas_test.dart',
          'test/integration/genkit/test_support/tool_schema_grammar_validation.dart',
        ]) {
          expect(
            assessHighRiskFiles(['$prefix$path']).surfaces,
            contains(HighRiskSurface.structuredOutput),
          );
        }
        expect(assessHighRiskFiles(['${prefix}README.md']).isHighRisk, isFalse);
        expect(
          assessHighRiskFiles(['${prefix}doc/usage.md']).isHighRisk,
          isFalse,
        );
      },
    );

    test('classifies structured-output production and parity changes', () {
      final assessment = assessHighRiskFiles([
        'lib/src/core/template/chat_template_handler.dart',
        'lib/src/core/grammar/gbnf_grammar_generator.dart',
        'tool/testing/run_template_parity_suites.sh',
      ]);

      expect(assessment.isHighRisk, isTrue);
      expect(assessment.surfaces, contains(HighRiskSurface.structuredOutput));
    });

    test('protects landed compiled grammar and upstream parity evidence', () {
      for (final path in [
        'test/integration/core/grammar/'
            'generated_tool_schema_grammar_test.dart',
        'tool/testing/run_llama_cpp_chat_tests.sh',
        'tool/testing/prepare_llama_cpp_source.sh',
        'tool/testing/build_llama_cpp_runtime_gbnf_validator.sh',
        'tool/testing/llama_cpp_templates.ref',
        'test/e2e/template/'
            'specialized_tool_grammar_validation_e2e_test.dart',
        'test/fixtures/templates/Kimi-K3.jinja',
      ]) {
        expect(
          assessHighRiskFiles([path]).surfaces,
          contains(HighRiskSurface.structuredOutput),
          reason: path,
        );
      }
    });

    test(
      'classifies LiteRT template generator inputs as structured output',
      () {
        final assessment = assessHighRiskFiles([
          'tool/gen_litert_lm_templates.dart',
          'tool/litert_lm_templates/gemma3.jinja',
        ]);

        expect(assessment.surfaces, contains(HighRiskSurface.structuredOutput));
      },
    );

    test('classifies every public entrypoint as an API surface', () {
      for (final entrypoint in [
        'lib/llamadart.dart',
        'lib/backend.dart',
        'lib/llama_cpp_bindings.dart',
      ]) {
        expect(
          assessHighRiskFiles([entrypoint]).surfaces,
          containsAll({
            HighRiskSurface.structuredOutput,
            HighRiskSurface.backendRuntime,
          }),
          reason: entrypoint,
        );
      }
    });

    test('classifies backend, capability, and artifact consumers', () {
      final assessment = assessHighRiskFiles([
        'lib/src/backends/webgpu/webgpu_backend.dart',
        'lib/src/core/models/backend_capabilities.dart',
        'lib/src/core/cache_policy.dart',
        'scripts/fetch_webgpu_bridge_assets.sh',
      ]);

      expect(
        assessment.surfaces,
        containsAll({
          HighRiskSurface.backendRuntime,
          HighRiskSurface.artifactConsumer,
        }),
      );
    });

    test('classifies runtime pin checks as artifact consumers', () {
      for (final path in [
        'tool/testing/check_webgpu_bridge_tag.dart',
        'tool/testing/check_native_release_digests.dart',
      ]) {
        expect(
          assessHighRiskFiles([path]).surfaces,
          contains(HighRiskSurface.artifactConsumer),
          reason: path,
        );
      }
    });

    test(
      'classifies every Flutter Apple companion as an artifact consumer',
      () {
        for (final companion in [
          'llamadart_llama_cpp_flutter',
          'llamadart_litert_lm_flutter',
          'llamadart_stable_diffusion_flutter',
        ]) {
          final assessment = assessHighRiskFiles([
            'packages/$companion/darwin/$companion/Package.swift',
          ]);

          expect(
            assessment.surfaces,
            contains(HighRiskSurface.artifactConsumer),
            reason: companion,
          );
        }
      },
    );

    test('classifies release and regression-policy changes', () {
      final assessment = assessHighRiskFiles([
        '.github/workflows/release_on_prep_merge.yml',
        '.github/pull_request_template.md',
        'CONTRIBUTING.md',
        'tool/git/safe_pr_head_update.dart',
        'tool/git/pr_head_update_evidence.schema.json',
        'test/unit/tooling/safe_pr_head_update_test.dart',
        'doc/pr_branch_writer_inventory.md',
        'doc/high_risk_pre_merge_readiness.md',
        'tool/testing/high_risk_readiness.dart',
        'tool/testing/release_metadata_readiness.dart',
        'tool/testing/high_risk_readiness_evidence.schema.json',
        'test/unit/tooling/high_risk_readiness_test.dart',
      ]);

      expect(
        assessment.surfaces,
        containsAll({
          HighRiskSurface.releaseAutomation,
          HighRiskSurface.regressionPolicy,
        }),
      );
    });

    test('classifies CI selection and hosted-demo deploy scripts', () {
      for (final path in [
        'tool/ci/deploy_guard.py',
        'tool/ci/select_jobs.py',
        'tool/ci/web_deployment.py',
      ]) {
        expect(assessHighRiskFiles([path]).surfaces, {
          HighRiskSurface.releaseAutomation,
          HighRiskSurface.regressionPolicy,
        }, reason: path);
      }
      for (final path in [
        'tool/ci/check_genkit_package_score.py',
        'tool/ci/litert_lm_temp_canary.sh',
        'tool/ci/new_gate.py',
      ]) {
        expect(assessHighRiskFiles([path]).surfaces, {
          HighRiskSurface.regressionPolicy,
        }, reason: path);
      }
      expect(
        assessHighRiskFiles([
          'tool/ci/deploy_guard.py',
          'tool/ci/select_jobs.py',
          'test/ci/test_deploy_guard.py',
        ]).isHighRisk,
        isTrue,
      );
    });

    test('keeps sibling paths of tool/ci and test/ci scripts standard', () {
      for (final path in [
        'tool/ci_foo.py',
        'tool/cifoo/x.py',
        'tool/ci',
        'test/ci/test_unlisted.py',
      ]) {
        expect(assessHighRiskFiles([path]).isHighRisk, isFalse, reason: path);
      }
    });

    final toolCiListing = _gitListing('tool/ci');
    test('every tool/ci script is high-risk and has a CODEOWNERS entry', () {
      expect(toolCiListing.failure, isNull);
      final lines = File('.github/CODEOWNERS').readAsLinesSync();

      expect(toolCiListing.scripts, isNotEmpty);
      for (final path in toolCiListing.scripts) {
        expect(assessHighRiskFiles([path]).isHighRisk, isTrue, reason: path);
        expect(
          isCodeownersOwned(lines, path),
          isTrue,
          reason: '$path needs a CODEOWNERS entry',
        );
      }
    }, skip: toolCiListing.skipReason);

    test('a git failure inside a work tree fails instead of skipping', () {
      final listing = _gitListing(
        'tool/ci',
        environment: {'GIT_INDEX_FILE': Directory.systemTemp.path},
      );

      expect(listing.skipReason, isNull);
      expect(listing.failure, isNotNull);
    });

    test('a directory outside any work tree skips the ownership check', () {
      final outside = Directory.systemTemp.createTempSync('no_git_');
      addTearDown(() => outside.deleteSync(recursive: true));

      final listing = _gitListing('tool/ci', workingDirectory: outside.path);

      expect(listing.skipReason, contains('not inside a git checkout'));
      expect(listing.failure, isNull);
    });

    test('CODEOWNERS matching honors directories, comments and last match', () {
      const path = 'tool/ci/select_jobs.py';
      expect(isCodeownersOwned(['/tool/ci/select_jobs.py @a'], path), isTrue);
      expect(isCodeownersOwned(['/tool/ci/ @a'], path), isTrue);
      expect(isCodeownersOwned(['/tool/ci @a'], path), isFalse);
      expect(isCodeownersOwned(['/tool/ci_x/ @a'], path), isFalse);
      expect(isCodeownersOwned(['#/tool/ci/ @a', '  '], path), isFalse);
      expect(isCodeownersOwned(['/tool/ci/ @a', path], path), isFalse);
      expect(isCodeownersOwned([path, '/tool/ci/ @a'], path), isTrue);
    });

    test('keeps ordinary docs-only changes standard risk', () {
      final assessment = assessHighRiskFiles([
        'website/docs/guides/model-downloads.md',
      ]);

      expect(assessment.isHighRisk, isFalse);
      expect(
        formatHighRiskAssessment(assessment),
        'Classification: standard\n',
      );
    });

    test('release metadata validator alone remains regression-policy risk', () {
      expect(
        assessHighRiskFiles([
          'tool/testing/release_metadata_readiness.dart',
        ]).surfaces,
        {HighRiskSurface.regressionPolicy},
      );
    });

    test('classifies composite actions like the workflows that call them', () {
      expect(
        assessHighRiskFiles([
          '.github/actions/companion-package/action.yml',
        ]).surfaces,
        {HighRiskSurface.regressionPolicy},
      );
    });

    test('normalizes blank input and prints deterministic surfaces', () {
      final assessment = assessHighRiskFiles([
        '',
        '  ',
        ' lib/src/backends/backend.dart ',
        '.github/workflows/ci.yml',
      ]);

      expect(
        formatHighRiskAssessment(assessment),
        'Classification: high-risk\n'
        'Surfaces: backendRuntime, regressionPolicy\n'
        'Required matrix: '
        'dart run tool/testing/test_matrix.dart --tier high-risk\n',
      );
    });
  });

  group('classifier CLI', () {
    test(
      'rejects whitespace-only input instead of reporting standard',
      () async {
        final result = await runClassifier(utf8.encode('  \n\t\n'));

        expect(result.exitCode, 64);
        expect(result.standardOutput, isEmpty);
        expect(
          result.standardError,
          contains('No changed paths were provided.'),
        );
        expect(
          result.standardError,
          isNot(contains('Classification: standard')),
        );
      },
    );

    test('rejects malformed UTF-8 without a traceback', () async {
      final result = await runClassifier([0xff, 0x0a]);

      expect(result.exitCode, 65);
      expect(result.standardOutput, isEmpty);
      expect(
        result.standardError,
        contains('Changed paths must be valid UTF-8.'),
      );
      expect(result.standardError, isNot(contains('FormatException')));
      expect(result.standardError, isNot(contains('Unhandled exception')));
    });
  });
}

/// Whether the last matching CODEOWNERS line assigns [path] an owner.
bool isCodeownersOwned(List<String> lines, String path) {
  bool? owned;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    final pattern = parts.first.startsWith('/')
        ? parts.first.substring(1)
        : parts.first;
    if (pattern == path ||
        (pattern.endsWith('/') && path.startsWith(pattern))) {
      owned = parts.length > 1;
    }
  }
  return owned ?? false;
}

typedef GitListing = ({
  List<String> scripts,
  String? skipReason,
  String? failure,
});

// Skip only when git is missing or the directory is not a work tree; a git
// error inside a work tree must fail the caller.
GitListing _gitListing(
  String directory, {
  Map<String, String>? environment,
  String? workingDirectory,
}) {
  GitListing skipped(String reason) =>
      (scripts: const [], skipReason: reason, failure: null);
  final ProcessResult inside;
  try {
    inside = Process.runSync(
      'git',
      ['rev-parse', '--is-inside-work-tree'],
      environment: environment,
      workingDirectory: workingDirectory,
    );
  } on ProcessException catch (error) {
    return skipped('git is unavailable: $error');
  }
  if (inside.exitCode != 0 || (inside.stdout as String).trim() != 'true') {
    return skipped('not inside a git checkout');
  }
  // Tracked files only: Python tests leave untracked bytecode caches here.
  final result = Process.runSync(
    'git',
    ['ls-files', '-z', directory],
    environment: environment,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    return (
      scripts: const [],
      skipReason: null,
      failure: 'git ls-files exited ${result.exitCode}: ${result.stderr}',
    );
  }
  return (
    scripts: (result.stdout as String)
        .split('\u0000')
        .where((path) => path.isNotEmpty)
        .toList(),
    skipReason: null,
    failure: null,
  );
}
