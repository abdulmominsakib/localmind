#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

/// Regression-sensitive production and governance surfaces.
enum HighRiskSurface {
  structuredOutput,
  backendRuntime,
  artifactConsumer,
  releaseAutomation,
  regressionPolicy,
}

/// Result of classifying changed repository paths.
class HighRiskAssessment {
  const HighRiskAssessment({
    required this.changedFiles,
    required this.surfaces,
  });

  /// Normalized, non-empty paths inspected by the classifier.
  final List<String> changedFiles;

  /// High-risk surfaces reached by the changed paths.
  final Set<HighRiskSurface> surfaces;

  /// Whether the change requires the high-risk pre-merge review.
  bool get isHighRisk => surfaces.isNotEmpty;
}

/// Behavioral proof groups. File hints are deliberately conservative.
enum StructuredImpact {
  inputRenderingHistory,
  outputParsingStreaming,
  grammarSchema,
}

/// Minimum impacts implied by changed production paths. Evidence-only changes
/// cannot expand a known production change into unrelated runtime behavior.
Set<StructuredImpact> structuredImpactHints(Iterable<String> paths) {
  final impacts = <StructuredImpact>{};
  for (final path in paths) {
    impacts.addAll(structuredProductionImpactHints(path) ?? const {});
  }
  return impacts.isEmpty ? StructuredImpact.values.toSet() : impacts;
}

/// A production path's conservative contribution, or `null` for evidence and
/// unrelated paths. An absent contribution is not proof of no runtime effects.
Set<StructuredImpact>? structuredProductionImpactHints(String path) {
  if (!_isStructuredOutput(path) || path.startsWith('test/')) return null;
  if (path == 'lib/src/core/template/template_render_context.dart') {
    return {StructuredImpact.inputRenderingHistory};
  }
  if (const {
    'lib/src/core/template/peg_chat_parser.dart',
    'lib/src/core/template/chat_parse_result.dart',
    'lib/src/core/template/tool_call_fallback_parser.dart',
  }.contains(path)) {
    return {StructuredImpact.outputParsingStreaming};
  }
  if (path.startsWith('lib/src/core/grammar/')) {
    return {StructuredImpact.grammarSchema};
  }
  // Handlers, shared utilities, exports, and unknown paths can mix effects.
  return StructuredImpact.values.toSet();
}

/// Platform-independent result of classifying paths read from standard input.
class HighRiskCliResult {
  const HighRiskCliResult({
    required this.exitCode,
    required this.standardOutput,
    required this.standardError,
  });

  /// Process exit code for the classifier invocation.
  final int exitCode;

  /// Text written to standard output.
  final String standardOutput;

  /// Text written to standard error.
  final String standardError;
}

/// Classifies changed repository paths without reading or executing PR code.
HighRiskAssessment assessHighRiskFiles(Iterable<String> files) {
  final changedFiles = files
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  final surfaces = <HighRiskSurface>{};

  for (final path in changedFiles) {
    if (_isStructuredOutput(path)) {
      surfaces.add(HighRiskSurface.structuredOutput);
    }
    if (_isBackendRuntime(path)) {
      surfaces.add(HighRiskSurface.backendRuntime);
    }
    if (_isArtifactConsumer(path)) {
      surfaces.add(HighRiskSurface.artifactConsumer);
    }
    if (_isReleaseAutomation(path)) {
      surfaces.add(HighRiskSurface.releaseAutomation);
    }
    if (_isRegressionPolicy(path)) {
      surfaces.add(HighRiskSurface.regressionPolicy);
    }
  }

  return HighRiskAssessment(changedFiles: changedFiles, surfaces: surfaces);
}

/// Whether [path] is a GitHub Actions workflow or composite action. Each is a
/// high-risk policy surface, and readiness evidence cites them as the
/// production code their tooling tests load.
bool isWorkflowPath(String path) =>
    path.startsWith('.github/workflows/') ||
    path.startsWith('.github/actions/');

bool _isPublicEntrypoint(String path) {
  return path == 'packages/genkit_llamadart/lib/genkit_llamadart.dart' ||
      path == 'packages/genkit_llamadart/lib/experimental.dart' ||
      path == 'lib/llamadart.dart' ||
      path == 'lib/backend.dart' ||
      path == 'lib/llama_cpp_bindings.dart';
}

bool _isStructuredOutput(String path) {
  return _isPublicEntrypoint(path) ||
      path.startsWith('packages/genkit_llamadart/lib/src/core/streaming/') ||
      path.startsWith(
        'packages/genkit_llamadart/lib/src/integration/genkit/converters/',
      ) ||
      const {
        'packages/genkit_llamadart/lib/src/integration/genkit/actions/model_action.dart',
        'packages/genkit_llamadart/lib/src/integration/genkit/plugin.dart',
        'packages/genkit_llamadart/lib/src/integration/genkit/bidi_plugin.dart',
        'packages/genkit_llamadart/lib/src/integration/genkit/request_support.dart',
      }.contains(path) ||
      path.startsWith('lib/src/core/template/') ||
      path.startsWith('lib/src/core/grammar/') ||
      path.startsWith('lib/src/core/models/tools/') ||
      path == 'tool/gen_litert_lm_templates.dart' ||
      path.startsWith('tool/litert_lm_templates/') ||
      path.contains('/chat_template') ||
      path.contains('/structured_output') ||
      path.endsWith('/tool_choice.dart') ||
      path.endsWith('/completion_chunk.dart') ||
      _isStructuredOutputEvidence(path) ||
      (path.startsWith('tool/testing/') &&
          (path.contains('template') ||
              path.contains('grammar') ||
              path.contains('structured')));
}

bool _isStructuredOutputEvidence(String path) {
  return const {
        'packages/genkit_llamadart/test/integration/genkit/plugin/real_model_constrained_grammar_test.dart',
        'packages/genkit_llamadart/test/integration/genkit/plugin/real_model_rich_tool_schemas_test.dart',
        'packages/genkit_llamadart/test/integration/genkit/test_support/tool_schema_grammar_validation.dart',
      }.contains(path) ||
      path ==
          'test/integration/core/grammar/'
              'generated_tool_schema_grammar_test.dart' ||
      path == 'tool/testing/run_llama_cpp_chat_tests.sh' ||
      path == 'tool/testing/prepare_llama_cpp_source.sh' ||
      path == 'tool/testing/build_llama_cpp_runtime_gbnf_validator.sh' ||
      path == 'tool/testing/llama_cpp_templates.ref' ||
      path == 'test/e2e/template/llama_cpp_chat_tests_e2e_test.dart' ||
      path ==
          'test/e2e/template/'
              'specialized_tool_grammar_validation_e2e_test.dart' ||
      path.startsWith('test/integration/core/template/') ||
      path.startsWith('test/fixtures/templates/') ||
      path.startsWith('test/unit/core/template/');
}

bool _isBackendRuntime(String path) {
  return _isPublicEntrypoint(path) ||
      path.startsWith('packages/genkit_llamadart/lib/') ||
      path.startsWith('lib/src/backends/') ||
      path.startsWith('lib/src/core/engine/') ||
      path.startsWith('lib/src/core/models/') ||
      path.startsWith('lib/src/core/speech/') ||
      path.startsWith('lib/src/platform/') ||
      path == 'lib/src/core/cache_policy.dart' ||
      path.contains('/capabilit');
}

bool _isArtifactConsumer(String path) {
  return path == '.pubignore' ||
      path == 'packages/genkit_llamadart/pubspec.yaml' ||
      path == 'packages/genkit_llamadart/pubspec_overrides.yaml' ||
      path == 'packages/genkit_llamadart/.pubignore' ||
      path == 'pubspec.yaml' ||
      path == 'pubspec.lock' ||
      path == 'ffigen.yaml' ||
      path.startsWith('hook/') ||
      path.startsWith('lib/src/hook/') ||
      path.startsWith('tool/native/') ||
      path == 'tool/testing/check_webgpu_bridge_tag.dart' ||
      path == 'tool/testing/check_native_release_digests.dart' ||
      path == 'scripts/check_native_link_deps.sh' ||
      path == 'scripts/fetch_webgpu_bridge_assets.sh' ||
      path == 'scripts/build_chat_app_web.sh' ||
      path == 'scripts/validate_chat_app_web_build.sh' ||
      path == 'scripts/verify_chat_app_web_deployment.sh' ||
      path == 'example/chat_app/web/index.html' ||
      path.startsWith('packages/llamadart_llama_cpp_flutter/') ||
      path.startsWith('packages/llamadart_litert_lm_flutter/') ||
      path.startsWith('packages/llamadart_stable_diffusion_flutter/');
}

bool _isReleaseAutomation(String path) {
  if (path.startsWith('tool/release/') ||
      path.startsWith('scripts/release/') ||
      path == 'tool/testing/verify_release_docs_versions.dart' ||
      path == 'tool/ci/deploy_guard.py' ||
      path == 'tool/ci/web_deployment.py' ||
      // The deploy guard reuses this selection to decide whether a newer push
      // supersedes a hosted-demo build.
      path == 'tool/ci/select_jobs.py') {
    return true;
  }
  if (!isWorkflowPath(path)) return false;
  final name = path.split('/').last;
  return name.contains('publish') ||
      name.contains('release') ||
      name.contains('deploy') ||
      name.contains('sync') ||
      name == 'docs_version_cut.yml';
}

bool _isRegressionPolicy(String path) {
  return path == 'packages/genkit_llamadart/AGENTS.md' ||
      path == 'packages/genkit_llamadart/CONTRIBUTING.md' ||
      path.startsWith('packages/genkit_llamadart/.github/') ||
      path == 'AGENTS.md' ||
      path == 'CONTRIBUTING.md' ||
      path == '.github/CODEOWNERS' ||
      path == '.github/pull_request_template.md' ||
      isWorkflowPath(path) ||
      path.startsWith('tool/ci/') ||
      path == 'doc/testing_matrix.md' ||
      path == 'doc/pr_branch_writer_inventory.md' ||
      path == 'doc/high_risk_pre_merge_readiness.md' ||
      path == 'tool/testing/test_matrix.dart' ||
      path == 'tool/testing/classify_high_risk_changes.dart' ||
      path == 'tool/testing/high_risk_readiness.dart' ||
      path == 'tool/testing/release_metadata_readiness.dart' ||
      path == 'tool/testing/high_risk_readiness_evidence.schema.json' ||
      path == 'tool/testing/high_risk_readiness_evidence.v1.schema.json' ||
      path == 'test/unit/tooling/test_matrix_test.dart' ||
      path == 'test/unit/tooling/classify_high_risk_changes_test.dart' ||
      path == 'test/unit/tooling/high_risk_review_policy_test.dart' ||
      path == 'test/unit/tooling/high_risk_readiness_test.dart' ||
      path == 'tool/git/safe_pr_head_update.dart' ||
      path == 'tool/git/pr_head_update_evidence.schema.json' ||
      path == 'test/unit/tooling/safe_pr_head_update_test.dart';
}

/// Formats the contributor-facing classification result.
String formatHighRiskAssessment(HighRiskAssessment assessment) {
  if (!assessment.isHighRisk) {
    return 'Classification: standard\n';
  }
  final surfaces = assessment.surfaces.map((surface) => surface.name).toList()
    ..sort();
  return 'Classification: high-risk\n'
      'Surfaces: ${surfaces.join(', ')}\n'
      'Required matrix: '
      'dart run tool/testing/test_matrix.dart --tier high-risk\n';
}

String _usage() => '''Usage:
  git diff --name-only --no-renames <base>...HEAD | \\
    dart run tool/testing/classify_high_risk_changes.dart

The command reads one changed repository path per line from standard input.
''';

Future<List<String>> _readPaths(Stream<List<int>> input) async {
  return input.transform(utf8.decoder).transform(const LineSplitter()).toList();
}

/// Classifies UTF-8 path input without starting another Dart process.
///
/// Keeping stdin handling injectable makes the error contract portable on
/// Windows, where recursively starting `dart run` from `dart test` can block
/// on the package build-hook lock.
Future<HighRiskCliResult> classifyHighRiskInput(Stream<List<int>> input) async {
  late final List<String> paths;
  try {
    paths = await _readPaths(input);
  } on FormatException {
    return HighRiskCliResult(
      exitCode: 65,
      standardOutput: '',
      standardError: 'Changed paths must be valid UTF-8.\n${_usage()}',
    );
  }
  final assessment = assessHighRiskFiles(paths);
  if (assessment.changedFiles.isEmpty) {
    return HighRiskCliResult(
      exitCode: 64,
      standardOutput: '',
      standardError: 'No changed paths were provided.\n${_usage()}',
    );
  }
  return HighRiskCliResult(
    exitCode: 0,
    standardOutput: formatHighRiskAssessment(assessment),
    standardError: '',
  );
}

Future<void> main(List<String> args) async {
  if (args.length == 1 && (args.single == '--help' || args.single == '-h')) {
    stdout.write(_usage());
    return;
  }
  if (args.isNotEmpty) {
    stderr.write(_usage());
    exitCode = 64;
    return;
  }

  final result = await classifyHighRiskInput(stdin);
  stdout.write(result.standardOutput);
  stderr.write(result.standardError);
  exitCode = result.exitCode;
}
