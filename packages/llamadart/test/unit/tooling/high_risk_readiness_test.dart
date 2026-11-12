@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/testing/check_webgpu_bridge_tag.dart';
import '../../../tool/testing/classify_high_risk_changes.dart';
import '../../../tool/testing/high_risk_readiness.dart';
import '../../../tool/testing/release_metadata_readiness.dart';
import 'support/bounded_process.dart';

const baseSha = '1111111111111111111111111111111111111111';
const headSha = '2222222222222222222222222222222222222222';
const otherSha = '3333333333333333333333333333333333333333';
const compiledTest =
    'test/integration/core/grammar/generated_tool_schema_grammar_test.dart';
const backendTest = 'test/unit/backends/example_backend_test.dart';
const context = PullRequestContext(
  repository: 'leehack/llamadart',
  prNumber: 419,
  headSha: headSha,
  baseSha: baseSha,
  author: 'contributor-dev',
);

class FakeRepositoryState implements RepositoryStateReader {
  FakeRepositoryState({
    required this.changes,
    Set<String>? existingPaths,
    this.commitsExist = true,
    this.baseIsAncestor = true,
    this.pathProbeThrows = false,
    this.files = const {},
  }) : existingPaths =
           existingPaths ??
           changes
               .where((change) => change.kind != RepositoryChangeKind.deleted)
               .map((change) => change.path)
               .toSet();

  final List<RepositoryChange> changes;
  final Set<String> existingPaths;
  final bool commitsExist;
  final bool baseIsAncestor;
  final bool pathProbeThrows;
  final Map<String, Map<String, ReadinessFile>> files;
  var repositoryCallCount = 0;

  @override
  Future<ReadinessFile?> fileAt(
    String sha,
    String path, {
    String? workingDirectory,
  }) async =>
      files[sha]?[path] ??
      (files.isEmpty && existingPaths.contains(path)
          ? (mode: '100644', contents: 'regression case\nproductionCall();')
          : null);

  @override
  Future<bool> commitExists(String sha, {String? workingDirectory}) async {
    repositoryCallCount++;
    return commitsExist;
  }

  @override
  Future<bool> isAncestor(
    String ancestor,
    String descendant, {
    String? workingDirectory,
  }) async {
    repositoryCallCount++;
    return baseIsAncestor;
  }

  @override
  Future<List<RepositoryChange>> changedFiles(
    String baseSha,
    String headSha, {
    String? workingDirectory,
  }) async {
    repositoryCallCount++;
    return changes;
  }

  @override
  Future<bool> pathIsRegularFileAt(
    String headSha,
    String path, {
    String? workingDirectory,
  }) async {
    repositoryCallCount++;
    if (pathProbeThrows) {
      throw StateError('candidate-tree probe failed');
    }
    return existingPaths.contains(path);
  }
}

class _UnreadableBlobState extends FakeRepositoryState {
  _UnreadableBlobState({
    required this.sha,
    required this.path,
    required super.changes,
    super.existingPaths,
    super.files,
  });

  final String sha;
  final String path;

  @override
  Future<ReadinessFile?> fileAt(
    String sha,
    String path, {
    String? workingDirectory,
  }) {
    if (sha == this.sha && path == this.path) {
      throw const FormatException('Invalid UTF-8 blob.');
    }
    return super.fileAt(sha, path, workingDirectory: workingDirectory);
  }
}

const structuredSource = 'lib/src/core/template/chat_template_handler.dart';
const backendSource = 'lib/src/backends/example_backend.dart';
List<Map<String, dynamic>> productionRefs(String path) => [
  {'path': path, 'snippet': 'productionCall();'},
];
Map<String, dynamic> testProof(String path) => {
  'test_case': 'regression case',
  'test_snippet': 'productionCall();',
  'production_refs': productionRefs(path),
  'command': 'dart test --name "regression case"',
  'head_result': 'pass',
  'control_result': 'fail',
  'control_kind': 'mutation',
  'control_description': 'Bypass productionCall at the changed branch.',
  'evidence_notes':
      'Independent reviewer inspected reachability and control failure.',
};
Map<String, dynamic> impactProof(String path, {bool applicable = true}) => {
  'applicable': applicable,
  'rationale': 'Independent exact-pair review of production callsites.',
  'production_refs': productionRefs(path),
};

Map<String, dynamic> structuredEvidence() => <String, dynamic>{
  'schema': 'llamadart.high-risk-readiness-evidence',
  'schema_version': '2.0.0',
  'timestamp': '2026-08-28T12:00:00.000Z',
  'correlation_id': 'issue-419-audit-1',
  'repository': context.repository,
  'pr_number': context.prNumber,
  'expected_pr_head_sha': context.headSha,
  'current_base_sha': context.baseSha,
  'pr_author': context.author,
  'classification': 'high-risk',
  'surfaces': ['structuredOutput'],
  'required_matrix_row_ids': [
    'high-risk-exact-head-independent-qa',
    'structured-output-adversarial',
  ],
  'matrix_row_evidence': {
    'high-risk-exact-head-independent-qa': {
      'row_id': 'high-risk-exact-head-independent-qa',
      'result': 'pass',
      'command': 'fresh Codex audit of exact head and base',
      'evidence_notes': 'Production call sites and deletion-sensitive tests.',
    },
    'structured-output-adversarial': {
      'row_id': 'structured-output-adversarial',
      'result': 'pass',
      'command': './tool/testing/run_template_parity_suites.sh',
      'evidence_notes': 'Compiled acceptance and rejection completed.',
    },
  },
  'independent_audit': {
    'auditor_identity': 'codex-audit-419',
    'audit_kind': 'codex-adversarial',
    'audit_head_sha': context.headSha,
    'audit_base_sha': context.baseSha,
    'decision': 'accepted',
    'unresolved_review_threads': 0,
    'known_pr_caused_p1_regressions': 0,
    'summary': 'Independent audit completed against production call sites.',
  },
  'test_evidence': {compiledTest: testProof(structuredSource)},
  'structured_output_evidence': {
    'impacts': {
      for (final impact in StructuredImpact.values)
        impact.name: impactProof(structuredSource),
    },
    'coverage': {
      'input_rendering_history': [compiledTest],
      'compiled_grammar_acceptance': [compiledTest],
      'compiled_grammar_rejection': [compiledTest],
      'schema_reconstruction': [compiledTest],
      'streaming_rollback': [compiledTest],
      'tool_choice_thinking': [compiledTest],
      'upstream_parity': [compiledTest],
    },
    'families': [
      {
        'family': 'qwen3',
        'status': 'tested',
        'evidence_test_paths': [compiledTest],
        'rationale': 'Affected-family production fixture was exercised.',
      },
    ],
  },
  'affected_test_paths': [compiledTest],
  'evaluation': null,
};

Map<String, dynamic> backendEvidence() {
  final evidence = structuredEvidence();
  evidence['surfaces'] = ['backendRuntime'];
  evidence['required_matrix_row_ids'] = ['high-risk-exact-head-independent-qa'];
  evidence['matrix_row_evidence'] = {
    'high-risk-exact-head-independent-qa':
        (evidence['matrix_row_evidence']
            as Map<String, dynamic>)['high-risk-exact-head-independent-qa'],
  };
  evidence['structured_output_evidence'] = null;
  evidence['affected_test_paths'] = [backendTest];
  evidence['test_evidence'] = {backendTest: testProof(backendSource)};
  return evidence;
}

Map<String, dynamic> metadataEvidence() {
  final evidence = backendEvidence();
  evidence['surfaces'] = ['artifactConsumer'];
  (evidence['required_matrix_row_ids'] as List).add(releaseMetadataRow);
  (evidence['matrix_row_evidence'] as Map)[releaseMetadataRow] = {
    'row_id': releaseMetadataRow,
    'result': 'pass',
    'command': releaseMetadataCommand,
    'evidence_notes':
        'Strict verifier and existing companion-pin tests passed on exact head.',
  };
  evidence['affected_test_paths'] = [releaseMetadataTest];
  evidence['test_evidence'] = <String, dynamic>{};
  return evidence;
}

const metadataLockPaths = <String, String>{
  'example/chat_app/pubspec.lock': '../..',
  'packages/llamadart_validation/pubspec.lock': '../..',
  'website/examples/observability/pubspec.lock': '../../..',
};

Map<String, Map<String, ReadinessFile>> metadataFiles() {
  ReadinessFile file(String text) => (mode: '100644', contents: text);
  final base = <String, ReadinessFile>{
    'pubspec.yaml': file(
      'name: llamadart\nversion: 0.8.22\ndependencies:\n  yaml: ^3.1.3\n',
    ),
    for (final path in releaseMetadataDocs)
      path: file(
        path.contains('CHANGELOG') || path.contains('recent-releases')
            ? '# Changes\n\n## Unreleased\n\n* Update.\n\n## 0.8.22\n\n* History.\n'
            : '# Install\n\n```yaml\ndependencies:\n  llamadart: ^0.8.22\n```\n',
      ),
    for (final lock in metadataLockPaths.entries)
      lock.key: file(
        'packages:\n  llamadart:\n    dependency: "direct main"\n'
        '    description:\n      path: "${lock.value}"\n'
        '      relative: true\n    source: path\n'
        '    version: "0.8.22"\n'
        '  yaml:\n    dependency: transitive\n'
        '    description:\n      name: yaml\n      sha256: abc123\n'
        '      url: "https://pub.dev"\n    source: hosted\n'
        '    version: "3.1.3"\n'
        'sdks:\n  dart: ">=3.13.0 <4.0.0"\n',
      ),
    releaseMetadataVerifier: file('// maintained verifier\n'),
    releaseMetadataTest: file(
      '// existing negative companion pin regressions\n',
    ),
  };
  final head = Map<String, ReadinessFile>.from(base);
  for (final path in [
    'pubspec.yaml',
    ...releaseMetadataDocs,
    ...metadataLockPaths.keys,
  ]) {
    final old = base[path]!;
    head[path] = file(
      path.contains('CHANGELOG') || path.contains('recent-releases')
          ? old.contents.replaceFirst('## Unreleased', '## 0.8.23')
          : old.contents.replaceAll('0.8.22', '0.8.23'),
    );
  }
  return {baseSha: base, headSha: head};
}

Future<HighRiskReadinessResult> evaluateMetadata({
  Map<String, dynamic>? evidence,
  Map<String, Map<String, ReadinessFile>>? files,
  List<RepositoryChange>? changes,
}) => HighRiskReadinessEvaluator(
  repositoryState: FakeRepositoryState(
    changes:
        changes ??
        [
          for (final path in [
            'pubspec.yaml',
            ...releaseMetadataDocs,
            ...metadataLockPaths.keys,
          ])
            RepositoryChange(path: path, kind: RepositoryChangeKind.modified),
        ],
    files: files ?? metadataFiles(),
  ),
).evaluate(evidence: evidence ?? metadataEvidence(), context: context);

Map<String, dynamic> standardEvidence() {
  final evidence = backendEvidence();
  evidence['classification'] = 'standard';
  evidence['surfaces'] = <String>[];
  evidence['required_matrix_row_ids'] = <String>[];
  evidence['matrix_row_evidence'] = <String, dynamic>{};
  evidence['independent_audit'] = null;
  evidence['affected_test_paths'] = <String>[];
  evidence['test_evidence'] = <String, dynamic>{};
  return evidence;
}

HighRiskReadinessEvaluator evaluatorFor(
  List<RepositoryChange> changes, {
  Set<String>? existingPaths,
  bool commitsExist = true,
  bool baseIsAncestor = true,
  bool pathProbeThrows = false,
}) => HighRiskReadinessEvaluator(
  repositoryState: FakeRepositoryState(
    changes: changes,
    existingPaths: existingPaths,
    commitsExist: commitsExist,
    baseIsAncestor: baseIsAncestor,
    pathProbeThrows: pathProbeThrows,
  ),
  clock: () => DateTime.utc(2026, 8, 28, 13),
);

const structuredChanges = <RepositoryChange>[
  RepositoryChange(
    path: 'lib/src/core/template/chat_template_handler.dart',
    kind: RepositoryChangeKind.modified,
  ),
  RepositoryChange(path: compiledTest, kind: RepositoryChangeKind.modified),
];

const backendChanges = <RepositoryChange>[
  RepositoryChange(
    path: 'lib/src/backends/example_backend.dart',
    kind: RepositoryChangeKind.modified,
  ),
  RepositoryChange(path: backendTest, kind: RepositoryChangeKind.added),
];

Future<HighRiskReadinessResult> evaluateStructured(
  Map<String, dynamic> evidence, {
  List<RepositoryChange> changes = structuredChanges,
  Set<String>? existingPaths,
}) => evaluatorFor(
  changes,
  existingPaths: existingPaths,
).evaluate(evidence: evidence, context: context);

void expectFailure(
  HighRiskReadinessResult result,
  ReadinessFailureClassification failure,
) {
  expect(result.decision, ReadinessDecision.rejected);
  expect(result.failureClassification, failure);
  expect(result.isReady, isFalse);
}

void expectEmittedIdentity(
  HighRiskReadinessResult result, {
  required String repository,
  required int prNumber,
  required String headSha,
  required String baseSha,
  required String author,
}) {
  for (final output in <Map<String, Object?>>[
    result.evidence,
    result.toJson(),
  ]) {
    expect(output['repository'], repository);
    expect(output['pr_number'], prNumber);
    expect(output['expected_pr_head_sha'], headSha);
    expect(output['current_base_sha'], baseSha);
    expect(output['pr_author'], author);
  }
  expect(() => jsonEncode(result.toJson()), returnsNormally);
}

void expectContextBoundIdentity(HighRiskReadinessResult result) =>
    expectEmittedIdentity(
      result,
      repository: context.repository,
      prNumber: context.prNumber,
      headSha: context.headSha,
      baseSha: context.baseSha,
      author: context.author,
    );

void mutateIdentityToOtherValidValues(Map<String, dynamic> evidence) {
  evidence['repository'] = 'attacker/fork';
  evidence['pr_number'] = 420;
  evidence['expected_pr_head_sha'] = otherSha;
  evidence['current_base_sha'] = otherSha;
  evidence['pr_author'] = 'other-author';
}

void main() {
  for (final scenario in [
    (
      'lib/src/core/template/peg_chat_parser.dart',
      'outputParsingStreaming',
      {
        'schema_reconstruction',
        'streaming_rollback',
        'tool_choice_thinking',
        'upstream_parity',
      },
    ),
    (
      'lib/src/core/grammar/gbnf_grammar_generator.dart',
      'grammarSchema',
      {
        'compiled_grammar_acceptance',
        'compiled_grammar_rejection',
        'schema_reconstruction',
        'tool_choice_thinking',
        'upstream_parity',
      },
    ),
  ]) {
    test(
      '${scenario.$2} keeps only applicable gates and rejects each missing gate',
      () async {
        final evidence =
            jsonDecode(
                  jsonEncode(
                    structuredEvidence(),
                  ).replaceAll(structuredSource, scenario.$1),
                )
                as Map<String, dynamic>;
        final structured = evidence['structured_output_evidence'] as Map;
        for (final impact in StructuredImpact.values) {
          structured['impacts'][impact.name]['applicable'] =
              impact.name == scenario.$2;
        }
        for (final axis in (structured['coverage'] as Map).keys) {
          if (!scenario.$3.contains(axis)) {
            structured['coverage'][axis] = <String>[];
          }
        }
        Future<HighRiskReadinessResult> evaluate() => evaluatorFor(
          [
            RepositoryChange(
              path: scenario.$1,
              kind: RepositoryChangeKind.modified,
            ),
          ],
          existingPaths: {scenario.$1, compiledTest},
        ).evaluate(evidence: evidence, context: context);
        expect(
          (await evaluate()).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
        for (final axis in scenario.$3) {
          structured['coverage'][axis] = <String>[];
          expectFailure(
            await evaluate(),
            ReadinessFailureClassification.missingStructuredOutputEvidence,
          );
          structured['coverage'][axis] = [compiledTest];
        }
      },
    );
  }
  group('v2 impact and existing-test evidence', () {
    const source = 'lib/src/core/template/template_render_context.dart';
    const testPath =
        'test/unit/core/template/template_render_context_test.dart';
    Map<String, dynamic> renderingEvidence() {
      final evidence =
          jsonDecode(
                jsonEncode(structuredEvidence())
                    .replaceAll(structuredSource, source)
                    .replaceAll(compiledTest, testPath),
              )
              as Map<String, dynamic>;
      final structured = evidence['structured_output_evidence'] as Map;
      final coverage = structured['coverage'] as Map;
      for (final axis in coverage.keys) {
        if (!{'input_rendering_history', 'upstream_parity'}.contains(axis)) {
          coverage[axis] = <String>[];
        }
      }
      for (final impact in ['outputParsingStreaming', 'grammarSchema']) {
        structured['impacts'][impact]['applicable'] = false;
      }
      return evidence;
    }

    Future<HighRiskReadinessResult> evaluateRendering(
      Map<String, dynamic> evidence, {
      List<RepositoryChange>? changes,
      Map<String, Map<String, ReadinessFile>> files = const {},
    }) => HighRiskReadinessEvaluator(
      repositoryState: FakeRepositoryState(
        changes:
            changes ??
            const [
              RepositoryChange(
                path: source,
                kind: RepositoryChangeKind.modified,
              ),
            ],
        existingPaths: {source, testPath, structuredSource},
        files: files,
      ),
    ).evaluate(evidence: evidence, context: context);

    test(
      'existing test evidence reads committed blobs, not working tree edits',
      () async {
        final repo = Directory.systemTemp.createTempSync(
          'impact-evidence-git-',
        );
        addTearDown(() => repo.deleteSync(recursive: true));
        String git(List<String> args) {
          final result = Process.runSync(
            'git',
            args,
            workingDirectory: repo.path,
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
          return (result.stdout as String).trim();
        }

        git(['init', '--quiet']);
        git(['config', 'user.name', 'Impact evidence test']);
        git(['config', 'user.email', 'impact@example.invalid']);
        final sourceFile = File('${repo.path}/$source');
        sourceFile.parent.createSync(recursive: true);
        sourceFile.writeAsStringSync('bool productionCall() => false;\n');
        final testFile = File('${repo.path}/$testPath');
        testFile.parent.createSync(recursive: true);
        testFile.writeAsStringSync(
          "void main() { test('regression case', () { productionCall(); }); }\n",
        );
        git(['add', '.']);
        git(['commit', '--quiet', '-m', 'base']);
        final base = git(['rev-parse', 'HEAD']);
        sourceFile.writeAsStringSync('bool productionCall() => true;\n');
        git(['add', '.']);
        git(['commit', '--quiet', '-m', 'head']);
        final head = git(['rev-parse', 'HEAD']);
        final evidence = renderingEvidence()
          ..['expected_pr_head_sha'] = head
          ..['current_base_sha'] = base;
        evidence['independent_audit']['audit_head_sha'] = head;
        evidence['independent_audit']['audit_base_sha'] = base;
        final refs = [
          {'path': source, 'snippet': 'bool productionCall() => true;'},
        ];
        evidence['test_evidence'][testPath]['production_refs'] = refs;
        for (final impact in StructuredImpact.values) {
          evidence['structured_output_evidence']['impacts'][impact
                  .name]['production_refs'] =
              refs;
        }
        Future<HighRiskReadinessResult> evaluate() =>
            const HighRiskReadinessEvaluator().evaluate(
              evidence: evidence,
              context: PullRequestContext(
                repository: context.repository,
                prNumber: context.prNumber,
                headSha: head,
                baseSha: base,
                author: context.author,
              ),
              workingDirectory: repo.path,
            );
        expect(
          (await evaluate()).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
        testFile.writeAsStringSync('invented local test case');
        evidence['test_evidence'][testPath]['test_case'] =
            'invented local test case';
        expectFailure(
          await evaluate(),
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        evidence['test_evidence'][testPath]['test_case'] = 'regression case';
        refs.single['snippet'] = 'bool productionCall() => false;';
        sourceFile.writeAsStringSync('bool productionCall() => false;');
        expectFailure(
          await evaluate(),
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
      },
    );
    test(
      'rendering-only accepts unchanged relevant test without grammar edits',
      () async {
        final result = await evaluateRendering(renderingEvidence());
        expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
        expect(result.changedFiles.map((change) => change.path), [source]);
      },
    );
    test(
      'evidence-only grammar file edits do not invent runtime effects',
      () async {
        final result = await evaluateRendering(
          renderingEvidence(),
          changes: const [
            RepositoryChange(path: source, kind: RepositoryChangeKind.modified),
            RepositoryChange(
              path: compiledTest,
              kind: RepositoryChangeKind.modified,
            ),
          ],
        );
        expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
      },
    );
    test('changed test filename alone is insufficient', () async {
      final evidence = renderingEvidence()
        ..['test_evidence'] = <String, dynamic>{};
      expectFailure(
        await evaluateRendering(
          evidence,
          changes: const [
            RepositoryChange(path: source, kind: RepositoryChangeKind.modified),
            RepositoryChange(
              path: testPath,
              kind: RepositoryChangeKind.modified,
            ),
          ],
        ),
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
    });
    for (final field in ['test_case', 'test_snippet']) {
      test('rejects invented existing-test $field', () async {
        final evidence = renderingEvidence();
        evidence['test_evidence'][testPath][field] =
            'invented unreachable case';
        expectFailure(
          await evaluateRendering(evidence),
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
      });
    }
    test('rejects disconnected existing-test production references', () async {
      final evidence = renderingEvidence();
      evidence['test_evidence'][testPath]['production_refs'] = productionRefs(
        structuredSource,
      );
      expectFailure(
        await evaluateRendering(evidence),
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
    });
    for (final field in ['rationale', 'production_refs']) {
      test('rejects empty impact $field', () async {
        final evidence = renderingEvidence();
        evidence['structured_output_evidence']['impacts']['grammarSchema'][field] =
            field == 'rationale' ? ' ' : [];
        expectFailure(
          await evaluateRendering(evidence),
          ReadinessFailureClassification.schemaViolation,
        );
      });
    }
    test('rejects author-only exclusion review', () async {
      final evidence = renderingEvidence();
      evidence['independent_audit']['auditor_identity'] = context.author;
      expectFailure(
        await evaluateRendering(evidence),
        ReadinessFailureClassification.selfApprovalProhibited,
      );
    });
    test('rejects omitted mixed production effects', () async {
      expectFailure(
        await evaluateRendering(
          renderingEvidence(),
          changes: const [
            RepositoryChange(path: source, kind: RepositoryChangeKind.modified),
            RepositoryChange(
              path: structuredSource,
              kind: RepositoryChangeKind.modified,
            ),
          ],
        ),
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
    });
    test(
      'renaming mixed source into rendering cannot erase source effects',
      () async {
        final evidence = renderingEvidence();
        final refs = [
          ...productionRefs(source),
          ...productionRefs(structuredSource),
        ];
        evidence['test_evidence'][testPath]['production_refs'] = refs;
        for (final impact in StructuredImpact.values) {
          evidence['structured_output_evidence']['impacts'][impact
                  .name]['production_refs'] =
              refs;
        }
        final result = await evaluateRendering(
          evidence,
          changes: const [
            RepositoryChange(
              path: source,
              previousPath: structuredSource,
              kind: RepositoryChangeKind.renamed,
            ),
          ],
        );
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains('cannot be excluded'));
      },
    );
    test('unknown handler cannot exclude parser or grammar', () async {
      final evidence = structuredEvidence();
      evidence['structured_output_evidence']['impacts']['grammarSchema']['applicable'] =
          false;
      expectFailure(
        await evaluateStructured(evidence),
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
    });
    test('rejects missing required rendering checks', () async {
      final evidence = renderingEvidence();
      evidence['structured_output_evidence']['coverage']['input_rendering_history'] =
          [];
      expectFailure(
        await evaluateRendering(evidence),
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
    });
    for (final field in ['control_description', 'evidence_notes', 'command']) {
      test('rejects empty causal $field', () async {
        final evidence = renderingEvidence();
        evidence['test_evidence'][testPath][field] = '';
        expectFailure(
          await evaluateRendering(evidence),
          ReadinessFailureClassification.schemaViolation,
        );
      });
    }
    test('rejects nonfailing counterfactual', () async {
      final evidence = renderingEvidence();
      evidence['test_evidence'][testPath]['control_result'] = 'pass';
      expectFailure(
        await evaluateRendering(evidence),
        ReadinessFailureClassification.schemaViolation,
      );
    });
    test('rejects old schema explicitly', () async {
      final evidence = renderingEvidence()..['schema_version'] = '1.0.0';
      final result = await evaluateRendering(evidence);
      expectFailure(result, ReadinessFailureClassification.schemaViolation);
      expect(result.message, contains('historical v1'));
    });
    test('rejects stale pair on rendering exclusion', () async {
      for (final field in ['audit_head_sha', 'audit_base_sha']) {
        final evidence = renderingEvidence();
        evidence['independent_audit'][field] = otherSha;
        expect(
          (await evaluateRendering(evidence)).decision,
          ReadinessDecision.rejected,
        );
      }
    });
  });

  group('Git-bound additive image export impacts', () {
    const barrel = 'lib/llamadart.dart';
    const target = 'lib/src/core/image/image_editing_request.dart';
    const imageTest = 'test/unit/core/image/image_editing_request_test.dart';
    const addition =
        "export 'src/core/image/image_editing_request.dart'\n"
        '    show ImageEditingPixels, ImageEditingRequest;\n';
    const oldBarrel =
        'library;\n'
        "export 'src/core/exceptions.dart';\n"
        "export 'src/core/image/image_generation_request.dart';\n"
        "export 'src/core/image/generated_image.dart';\n";
    const imageSource =
        "import 'dart:typed_data';\n"
        "import '../exceptions.dart';\n"
        "import 'image_generation_driver.dart';\n"
        "import 'image_generation_request.dart';\n"
        'final class ImageEditingPixels {}\n'
        'final class ImageEditingRequest extends ImageGenerationRequest {}\n'
        'void validateImageEditingRecipe() {}\n';
    Map<String, Map<String, ReadinessFile>> imageFiles() {
      final old = <String, ReadinessFile>{
        barrel: (mode: '100644', contents: oldBarrel),
        'lib/src/core/exceptions.dart': (
          mode: '100644',
          contents: 'class LlamaException {}',
        ),
        'lib/src/core/image/image_generation_request.dart': (
          mode: '100644',
          contents: 'class ImageGenerationRequest {}',
        ),
        'lib/src/core/image/generated_image.dart': (
          mode: '100644',
          contents:
              "import 'dart:typed_data';\n"
              "import 'image_generation_driver.dart';\n"
              'class GeneratedImage {}',
        ),
        'lib/src/core/image/image_generation_driver.dart': (
          mode: '100644',
          contents: 'class ImageGenerationSessionRequest {}',
        ),
        imageTest: (
          mode: '100644',
          contents:
              "void main() { test('regression case', () { productionCall(); }); }",
        ),
      };
      return {
        baseSha: old,
        headSha: {
          ...old,
          barrel: (mode: '100644', contents: oldBarrel + addition),
          target: (mode: '100644', contents: imageSource),
        },
      };
    }

    const imageChanges = [
      RepositoryChange(path: barrel, kind: RepositoryChangeKind.modified),
      RepositoryChange(path: target, kind: RepositoryChangeKind.added),
    ];
    Map<String, dynamic> imageEvidence() {
      final evidence = structuredEvidence();
      evidence['surfaces'] = ['structuredOutput', 'backendRuntime'];
      evidence['affected_test_paths'] = [imageTest];
      final refs = <Map<String, dynamic>>[
        {'path': barrel, 'snippet': addition.trim()},
        {'path': target, 'snippet': 'final class ImageEditingPixels {}'},
      ];
      evidence['test_evidence'] = {
        imageTest: testProof(barrel)
          ..['production_refs'] = <Map<String, dynamic>>[
            for (final ref in refs) {...ref},
          ],
      };
      final structured = evidence['structured_output_evidence'] as Map;
      for (final axis in (structured['coverage'] as Map).keys) {
        structured['coverage'][axis] = <String>[];
      }
      for (final impact in StructuredImpact.values) {
        structured['impacts'][impact.name] = {
          'applicable': false,
          'rationale':
              'Independent review excludes this chat effect for the image classes.',
          'production_refs': <Map<String, dynamic>>[
            for (final ref in refs) {...ref},
          ],
        };
      }
      structured['families'] = [
        {
          'family': 'sd2',
          'status': 'tested',
          'evidence_test_paths': [imageTest],
          'rationale': 'Image family fixture with public exports was reviewed.',
        },
      ];
      return evidence;
    }

    Future<HighRiskReadinessResult> evaluateImage({
      Map<String, dynamic>? evidence,
      Map<String, Map<String, ReadinessFile>>? files,
      List<RepositoryChange> changes = imageChanges,
    }) {
      final state = files ?? imageFiles();
      return HighRiskReadinessEvaluator(
        repositoryState: FakeRepositoryState(
          changes: changes,
          existingPaths: state[headSha]!.keys.toSet(),
          files: state,
        ),
      ).evaluate(evidence: evidence ?? imageEvidence(), context: context);
    }

    test(
      'proven empty contribution keeps high-risk and external prerequisites',
      () async {
        final result = await evaluateImage();
        expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
        expect(
          result.failureClassification,
          ReadinessFailureClassification.externalPrerequisitesUnavailable,
        );
        expect(result.changedFiles.map((change) => change.path), [
          barrel,
          target,
        ]);
      },
    );

    test('reads only Git blobs despite forged working tree source', () async {
      final repo = Directory.systemTemp.createTempSync('image-export-git-');
      addTearDown(() => repo.deleteSync(recursive: true));
      String git(List<String> args) {
        final result = Process.runSync(
          'git',
          args,
          workingDirectory: repo.path,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return (result.stdout as String).trim();
      }

      void write(Map<String, ReadinessFile> files) {
        for (final entry in files.entries) {
          final file = File('${repo.path}/${entry.key}');
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(entry.value.contents);
        }
      }

      git(['init', '--quiet']);
      git(['config', 'user.name', 'Image export policy test']);
      git(['config', 'user.email', 'image-policy@example.invalid']);
      final files = imageFiles();
      write(files[baseSha]!);
      git(['add', '.']);
      git(['commit', '--quiet', '-m', 'base']);
      final base = git(['rev-parse', 'HEAD']);
      write(files[headSha]!);
      git(['add', '.']);
      git(['commit', '--quiet', '-m', 'head']);
      final head = git(['rev-parse', 'HEAD']);
      final evidence = imageEvidence()
        ..['expected_pr_head_sha'] = head
        ..['current_base_sha'] = base;
      evidence['independent_audit']['audit_head_sha'] = head;
      evidence['independent_audit']['audit_base_sha'] = base;
      Future<HighRiskReadinessResult> evaluate() =>
          const HighRiskReadinessEvaluator().evaluate(
            evidence: evidence,
            context: PullRequestContext(
              repository: context.repository,
              prNumber: context.prNumber,
              headSha: head,
              baseSha: base,
              author: context.author,
            ),
            workingDirectory: repo.path,
          );
      File('${repo.path}/$barrel').writeAsStringSync('forged local barrel');
      expect(
        (await evaluate()).decision,
        ReadinessDecision.unverifiedPrerequisites,
      );
      evidence['test_evidence'][imageTest]['production_refs'][0]['snippet'] =
          'forged local barrel';
      expectFailure(
        await evaluate(),
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
    });

    final barrelMutations = <String, String Function(String)>{
      'removed existing export': (s) =>
          s.replaceFirst("export 'src/core/exceptions.dart';\n", ''),
      'replaced existing export': (s) =>
          s.replaceFirst('exceptions.dart', 'other.dart'),
      'another shown name': (s) => s.replaceFirst(
        'ImageEditingRequest;',
        'ImageEditingRequest, validateImageEditingRecipe;',
      ),
      'changed show': (s) => s.replaceFirst(
        'show ImageEditingPixels, ImageEditingRequest',
        'hide validateImageEditingRecipe',
      ),
      'wildcard export': (s) => s.replaceFirst(
        '\n    show ImageEditingPixels, ImageEditingRequest',
        '',
      ),
      'changed URI': (s) => s.replaceFirst(
        'image_editing_request.dart',
        'another_image_request.dart',
      ),
      'conditional addition': (s) => s.replaceFirst(
        "'src/core/image/image_editing_request.dart'\n",
        "'src/core/image/image_editing_request.dart' if (dart.library.io) 'other.dart'\n",
      ),
      'commented forged addition': (s) =>
          s.replaceFirst(addition, '/*\n$addition*/\n'),
    };
    for (final mutation in barrelMutations.entries) {
      test(
        '${mutation.key} retains ordinary conservative requirements',
        () async {
          final files = imageFiles();
          files[headSha]![barrel] = (
            mode: '100644',
            contents: mutation.value(oldBarrel + addition),
          );
          final evidence = imageEvidence();
          for (final proof in [
            evidence['test_evidence'][imageTest],
            ...(evidence['structured_output_evidence']['impacts'] as Map)
                .values,
          ]) {
            proof['production_refs'][0]['snippet'] = 'library;';
          }
          final result = await evaluateImage(files: files, evidence: evidence);
          expectFailure(
            result,
            ReadinessFailureClassification.missingStructuredOutputEvidence,
          );
          expect(result.message, contains('cannot be excluded'));
        },
      );
    }

    for (final path in [barrel, target]) {
      for (final mode in ['100755', '120000']) {
        test('$path mode $mode cannot narrow impacts', () async {
          final files = imageFiles();
          final old = files[headSha]![path]!;
          files[headSha]![path] = (mode: mode, contents: old.contents);
          expectFailure(
            await evaluateImage(files: files),
            ReadinessFailureClassification.missingStructuredOutputEvidence,
          );
        });
      }
    }
    for (final mutation in <String, String Function(String)>{
      'extra local import': (s) => "import 'new_dependency.dart';\n$s",
      'nonlocal import': (s) =>
          s.replaceFirst("'dart:typed_data'", "'package:other/types.dart'"),
      'conditional import': (s) => s.replaceFirst(
        "'dart:typed_data'",
        "'dart:typed_data' if (dart.library.io) 'other.dart'",
      ),
      'new public declaration': (s) => '$s\nclass AnotherClass {}',
      'missing reviewed declaration': (s) =>
          s.replaceFirst('ImageEditingRequest extends', 'OtherRequest extends'),
      'exporting helper library': (s) => "export 'new_dependency.dart';\n$s",
      'extension with implicit effects': (s) =>
          '$s\nextension NewExtension on Object {}',
      'invalid syntax': (s) => '$s\nclass',
    }.entries) {
      test('target ${mutation.key} fails closed', () async {
        final files = imageFiles();
        files[headSha]![target] = (
          mode: '100644',
          contents: mutation.value(imageSource),
        );
        final result = await evaluateImage(files: files);
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains('cannot be excluded'));
      });
    }

    test('a deferred old import does not prove existing loading', () async {
      final files = imageFiles();
      final path = 'lib/src/core/image/generated_image.dart';
      files[baseSha]![path] = (
        mode: '100644',
        contents: files[baseSha]![path]!.contents.replaceFirst(
          "import 'image_generation_driver.dart';",
          "import 'image_generation_driver.dart' deferred as driver;",
        ),
      );
      final result = await evaluateImage(files: files);
      expectFailure(
        result,
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
      expect(result.message, contains('cannot be excluded'));
    });
    test(
      'an existing or renamed target never uses the additive route',
      () async {
        for (final kind in [
          RepositoryChangeKind.modified,
          RepositoryChangeKind.renamed,
        ]) {
          final files = imageFiles();
          final evidence = imageEvidence();
          const oldPath = 'lib/src/core/image/old.dart';
          if (kind == RepositoryChangeKind.renamed) {
            files[baseSha]![oldPath] = (
              mode: '100644',
              contents: 'productionCall();',
            );
            for (final proof in [
              evidence['test_evidence'][imageTest],
              ...(evidence['structured_output_evidence']['impacts'] as Map)
                  .values,
            ]) {
              (proof['production_refs'] as List).addAll(
                productionRefs(oldPath),
              );
            }
          }
          final result = await evaluateImage(
            files: files,
            evidence: evidence,
            changes: [
              imageChanges.first,
              RepositoryChange(
                path: target,
                kind: kind,
                previousPath: kind == RepositoryChangeKind.renamed
                    ? oldPath
                    : null,
              ),
            ],
          );
          expectFailure(
            result,
            ReadinessFailureClassification.missingStructuredOutputEvidence,
          );
          expect(result.message, contains('cannot be excluded'));
        }
      },
    );
    for (final conditional in [
      (
        'import',
        "import 'image_generation_driver.dart' if (dart.library.io) 'other_driver.dart';",
      ),
      (
        'import',
        "import 'other_driver.dart' if (dart.library.io) 'image_generation_driver.dart';",
      ),
      (
        'export',
        "export 'src/core/image/image_generation_driver.dart' if (dart.library.io) 'src/core/image/other_driver.dart';",
      ),
      (
        'export',
        "export 'src/core/image/other_driver.dart' if (dart.library.io) 'src/core/image/image_generation_driver.dart';",
      ),
    ]) {
      test(
        'conditional-only old dependency does not prove loading: ${conditional.$2}',
        () async {
          final files = imageFiles();
          for (final revision in [baseSha, headSha]) {
            files[revision]!['lib/src/core/image/generated_image.dart'] = (
              mode: '100644',
              contents:
                  "import 'dart:typed_data';\n"
                  '${conditional.$1 == 'import' ? conditional.$2 : ''}\n'
                  'class GeneratedImage {}',
            );
            files[revision]!['lib/src/core/image/other_driver.dart'] = (
              mode: '100644',
              contents: 'class OtherDriver {}',
            );
            if (conditional.$1 == 'export') {
              final original = files[revision]![barrel]!;
              files[revision]![barrel] = (
                mode: original.mode,
                contents: '${original.contents}${conditional.$2}\n',
              );
            }
          }
          final result = await evaluateImage(files: files);
          expectFailure(
            result,
            ReadinessFailureClassification.missingStructuredOutputEvidence,
          );
          expect(result.message, contains('cannot be excluded'));
        },
      );
    }
    test('target dependencies must already load at base', () async {
      final files = imageFiles();
      files[baseSha]!['lib/src/core/image/generated_image.dart'] = (
        mode: '100644',
        contents: 'class GeneratedImage {}',
      );
      final result = await evaluateImage(files: files);
      expectFailure(
        result,
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
      expect(result.message, contains('cannot be excluded'));
    });
    for (final revision in [baseSha, headSha]) {
      for (final declaration in [
        'class ImageEditingRequest {}',
        'typedef ImageEditingPixels = Object;',
        'final ImageEditingRequest = 0;',
        'void ImageEditingPixels() {}',
        'enum ImageEditingRequest { value }',
        'mixin ImageEditingPixels {}',
        'extension type ImageEditingRequest(int value) {}',
        'extension type const ImageEditingRequest(int value) {}',
        'typedef void ImageEditingPixels();',
        'class ImageEditingRequest = Object with ExistingMixin;',
        'int get ImageEditingRequest => 0;',
        'set ImageEditingPixels(int value) {}',

        '({int value}) ImageEditingRequest() => (value: 1);',
        'void Function({int value}) ImageEditingRequest() => ({int value = 0}) {};',
        'extension ImageEditingRequest on Object {}',
        "@Annotation({'key': 1}) class ImageEditingRequest {}",
        r"final text = '${Object()}', ImageEditingRequest = 0;",
      ]) {
        test(
          'existing namespace collision at $revision: $declaration',
          () async {
            final files = imageFiles();
            files[revision]!['lib/src/core/exceptions.dart'] = (
              mode: '100644',
              contents: declaration,
            );
            final result = await evaluateImage(files: files);
            expectFailure(
              result,
              ReadinessFailureClassification.missingStructuredOutputEvidence,
            );
            expect(result.message, contains('cannot be excluded'));
          },
        );
      }
    }
    for (final export in [
      "export 'missing.dart';",
      "export 'package:external/types.dart';",
      "part 'other.dart';",
      "export 'exceptions.dart';",
      'class',
    ]) {
      test('uncertain old namespace $export retains minima', () async {
        final files = imageFiles();
        files[headSha]!['lib/src/core/exceptions.dart'] = (
          mode: '100644',
          contents: 'class LlamaException {}\n$export',
        );
        final result = await evaluateImage(files: files);
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains('cannot be excluded'));
      });
    }
    test(
      'base comments and string segments are not identifier tokens',
      () async {
        final files = imageFiles();
        const source = r'''// ImageEditingRequest ImageEditingPixels
class LlamaException {}
const text = 'ImageEditingPixels';
final segment = '${Object()}ImageEditingRequest${Object()}';
''';
        for (final revision in [baseSha, headSha]) {
          files[revision]!['lib/src/core/exceptions.dart'] = (
            mode: '100644',
            contents: source,
          );
        }
        expect(
          (await evaluateImage(files: files)).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
      },
    );
    test(
      'base identifiers in nested scopes retain conservative minima',
      () async {
        final files = imageFiles();
        files[baseSha]!['lib/src/core/exceptions.dart'] = (
          mode: '100644',
          contents:
              'class LlamaException {} void example() { final ImageEditingRequest = 0; }',
        );
        final result = await evaluateImage(files: files);
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains('cannot be excluded'));
      },
    );
    test(
      'head type references do not introduce namespace declarations',
      () async {
        final files = imageFiles();
        files[headSha]!['lib/src/core/exceptions.dart'] = (
          mode: '100644',
          contents:
              "import 'image/image_editing_request.dart';\n"
              'ImageEditingRequest? unused;\n'
              'class LlamaException { Object use(ImageEditingRequest request) => request; }',
        );
        expect(
          (await evaluateImage(files: files)).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
      },
    );
    for (final edge in [
      "export 'src/core/image/image_editing_request.dart' show ImageEditingPixels;\n",
      "export 'src/core/exceptions.dart' if (dart.library.io) 'src/core/image/image_editing_request.dart';\n",
    ]) {
      test(
        'pre-existing missing target edge cannot be skipped: $edge',
        () async {
          final files = imageFiles();
          files[baseSha]![barrel] = (
            mode: '100644',
            contents: oldBarrel + edge,
          );
          files[headSha]![barrel] = (
            mode: '100644',
            contents: oldBarrel + edge + addition,
          );
          final result = await evaluateImage(files: files);
          expectFailure(
            result,
            ReadinessFailureClassification.missingStructuredOutputEvidence,
          );
          expect(result.message, contains('cannot be excluded'));
        },
      );
    }
    for (final revision in [baseSha, headSha]) {
      test('indirect target edge at $revision cannot be skipped', () async {
        final files = imageFiles();
        files[revision]!['lib/src/core/exceptions.dart'] = (
          mode: '100644',
          contents:
              "export 'image/image_editing_request.dart';\nclass LlamaException {}",
        );
        final result = await evaluateImage(files: files);
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains('cannot be excluded'));
      });
    }
    test('conditional export collision in any branch fails closed', () async {
      final files = imageFiles();
      files[headSha]!['lib/src/core/exceptions.dart'] = (
        mode: '100644',
        contents:
            "export 'safe.dart' if (dart.library.io) 'collision.dart';\nclass LlamaException {}",
      );
      files[headSha]!['lib/src/core/safe.dart'] = (
        mode: '100644',
        contents: 'class Safe {}',
      );
      files[headSha]!['lib/src/core/collision.dart'] = (
        mode: '100644',
        contents: 'class ImageEditingRequest {}',
      );
      final result = await evaluateImage(files: files);
      expectFailure(
        result,
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
      expect(result.message, contains('cannot be excluded'));
    });
    for (final source in [
      'lib/src/core/template/template_render_context.dart',
      'lib/src/core/template/peg_chat_parser.dart',
      'lib/src/core/grammar/gbnf_grammar_generator.dart',
      structuredSource,
      'lib/src/core/template/new_helper.dart',
    ]) {
      test('mixed $source retains every path contribution', () async {
        final files = imageFiles();
        files[headSha]![source] = (
          mode: '100644',
          contents: 'productionCall();',
        );
        final evidence = imageEvidence();
        for (final proof in [
          evidence['test_evidence'][imageTest],
          ...(evidence['structured_output_evidence']['impacts'] as Map).values,
        ]) {
          (proof['production_refs'] as List).addAll(productionRefs(source));
        }
        final result = await evaluateImage(
          files: files,
          evidence: evidence,
          changes: [
            ...imageChanges,
            RepositoryChange(path: source, kind: RepositoryChangeKind.modified),
          ],
        );
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains('cannot be excluded'));
      });
    }
    test(
      'renaming structured source into image path retains old impacts',
      () async {
        final files = imageFiles();
        const destination = 'lib/src/core/image/renamed_helper.dart';
        files[baseSha]![structuredSource] = (
          mode: '100644',
          contents: 'productionCall();',
        );
        files[headSha]![destination] = (
          mode: '100644',
          contents: 'productionCall();',
        );
        final evidence = imageEvidence();
        for (final proof in [
          evidence['test_evidence'][imageTest],
          ...(evidence['structured_output_evidence']['impacts'] as Map).values,
        ]) {
          (proof['production_refs'] as List).addAll(<Map<String, dynamic>>[
            ...productionRefs(structuredSource),
            ...productionRefs(destination),
          ]);
        }
        final result = await evaluateImage(
          files: files,
          evidence: evidence,
          changes: [
            ...imageChanges,
            const RepositoryChange(
              path: destination,
              previousPath: structuredSource,
              kind: RepositoryChangeKind.renamed,
            ),
          ],
        );
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains('cannot be excluded'));
      },
    );
    for (final missing in [barrel, target]) {
      test('missing causal $missing coverage is rejected', () async {
        final evidence = imageEvidence();
        (evidence['test_evidence'][imageTest]['production_refs'] as List)
            .removeWhere((ref) => ref['path'] == missing);
        expectFailure(
          await evaluateImage(evidence: evidence),
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
      });
    }
    test('self-approval and stale audit pairs remain rejected', () async {
      for (final field in [
        'auditor_identity',
        'audit_head_sha',
        'audit_base_sha',
      ]) {
        final evidence = imageEvidence();
        evidence['independent_audit'][field] = field == 'auditor_identity'
            ? context.author
            : otherSha;
        expect(
          (await evaluateImage(evidence: evidence)).decision,
          ReadinessDecision.rejected,
        );
      }
    });
  });

  test('raw-text-consumed sources all exist in the repository', () {
    for (final path in rawTextConsumedSources) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('raw-text-consumed sources include the Dart files the pin tooling '
      'reads', () {
    final syncScript = File(
      'tool/native/sync_native_release_pins.py',
    ).readAsStringSync();
    final syncedDartPaths = RegExp(
      r'^DEFAULT_\w+ = \(?\s*"((?:hook|lib)/[^"]+\.dart)"',
      multiLine: true,
    ).allMatches(syncScript).map((match) => match[1]!).toSet();
    expect(syncedDartPaths, contains('hook/build.dart'));
    expect(
      syncedDartPaths,
      contains('lib/src/backends/litert_lm/litert_lm_runtime.dart'),
    );

    final readByTooling = {
      ...syncedDartPaths,
      nativeLlamaCppTagPath,
      for (final pin in [
        ...bridgeTagPins,
        ...releaseNotesPins,
        ...bridgeLlamaCppParityPins,
        ...bridgeProvenancePins,
      ])
        if (pin.path.endsWith('.dart')) pin.path,
    };
    expect(rawTextConsumedSources, containsAll(readByTooling));
  });

  group('Git-proven comment-only production changes', () {
    const realSource = 'lib/src/backends/other_backend.dart';
    const commentBase =
        '/// Backend entry point.\n'
        'bool productionCall() => false; // Keep the default.\n'
        "const label = 'a // b /* c */';\n";
    const commentHead =
        '/// Backend entry point, documented further.\n'
        '///\n'
        '/// ```dart\n'
        '/// productionCall(); // returns true?\n'
        '/// ```\n'
        '/* Block comment\n   spanning lines. */\n'
        'bool productionCall() => false; // Keep the default value.\n'
        "const label = 'a // b /* c */';\n";

    Map<String, dynamic> commentEvidence(List<RepositoryChange> changes) {
      final evidence = backendEvidence()
        ..['affected_test_paths'] = <String>[]
        ..['test_evidence'] = <String, dynamic>{};
      final surfaces = assessHighRiskFiles([
        for (final change in changes) ...[
          change.path,
          if (change.previousPath != null) change.previousPath!,
        ],
      ]).surfaces;
      evidence['surfaces'] = [for (final surface in surfaces) surface.name];
      return evidence;
    }

    Future<HighRiskReadinessResult> evaluateComment({
      String? base = commentBase,
      String? head = commentHead,
      String path = backendSource,
      String baseMode = '100644',
      String headMode = '100644',
      List<RepositoryChange>? changes,
      Map<String, dynamic>? evidence,
      Map<String, ReadinessFile> extraHead = const {},
    }) {
      final inventory =
          changes ??
          [RepositoryChange(path: path, kind: RepositoryChangeKind.modified)];
      final testFile = (
        mode: '100644',
        contents: "test('regression case', () { productionCall(); });",
      );
      final files = {
        baseSha: <String, ReadinessFile>{
          if (base != null) path: (mode: baseMode, contents: base),
        },
        headSha: <String, ReadinessFile>{
          if (head != null) path: (mode: headMode, contents: head),
          backendTest: testFile,
          ...extraHead,
        },
      };
      return HighRiskReadinessEvaluator(
        repositoryState: FakeRepositoryState(
          changes: inventory,
          existingPaths: files[headSha]!.keys.toSet(),
          files: files,
        ),
      ).evaluate(
        evidence: evidence ?? commentEvidence(inventory),
        context: context,
      );
    }

    void expectAdmitted(HighRiskReadinessResult result) {
      expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
      expect(
        result.failureClassification,
        ReadinessFailureClassification.externalPrerequisitesUnavailable,
      );
      expect(result.isReady, isFalse);
    }

    test(
      'needs no causal test record but keeps high-risk audit gates',
      () async {
        final result = await evaluateComment();
        expectAdmitted(result);
        expect(result.changedFiles.single.path, backendSource);
        for (final mutate in <void Function(Map<String, dynamic>)>[
          (evidence) => evidence['independent_audit'] = null,
          (evidence) =>
              evidence['independent_audit']['audit_head_sha'] = otherSha,
          (evidence) => evidence['independent_audit']['auditor_identity'] =
              context.author,
          (evidence) =>
              evidence['independent_audit']['known_pr_caused_p1_regressions'] =
                  1,
          (evidence) =>
              evidence['independent_audit']['unresolved_review_threads'] = 1,
          (evidence) => evidence['classification'] = 'standard',
        ]) {
          final evidence = commentEvidence([
            const RepositoryChange(
              path: backendSource,
              kind: RepositoryChangeKind.modified,
            ),
          ]);
          mutate(evidence);
          expect(
            (await evaluateComment(evidence: evidence)).decision,
            ReadinessDecision.rejected,
          );
        }
      },
    );

    test(
      'an optional record for the comment-only path is still checked',
      () async {
        final evidence =
            commentEvidence([
                const RepositoryChange(
                  path: backendSource,
                  kind: RepositoryChangeKind.modified,
                ),
              ])
              ..['affected_test_paths'] = [backendTest]
              ..['test_evidence'] = {backendTest: testProof(backendSource)};
        expectAdmitted(await evaluateComment(evidence: evidence));
        evidence['test_evidence'][backendTest]['production_refs'] =
            productionRefs(realSource);
        expectFailure(
          await evaluateComment(
            evidence: evidence,
            extraHead: {
              realSource: (
                mode: '100644',
                contents: 'void run() { productionCall(); }\n',
              ),
            },
          ),
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
      },
    );

    test('tool and hook Dart sources use the same proof', () async {
      for (final path in [
        'tool/testing/high_risk_readiness.dart',
        'hook/link.dart',
      ]) {
        expectAdmitted(await evaluateComment(path: path));
        expectFailure(
          await evaluateComment(
            path: path,
            head: commentHead.replaceFirst('=> false', '=> true'),
          ),
          ReadinessFailureClassification.missingTestPath,
        );
      }
    });

    final executableChanges = <String, String>{
      'executable token': commentHead.replaceFirst('=> false', '=> true'),
      'string contents resembling a line comment': commentHead.replaceFirst(
        'a // b',
        'a // x',
      ),
      'string contents resembling a block comment': commentHead.replaceFirst(
        '/* c */',
        '/* x */',
      ),
      'comment turned into code':
          '${commentHead.replaceFirst('/// productionCall(); // returns true?\n', '')}'
          'final called = productionCall();\n',
      'block comment closed early': commentHead.replaceFirst(
        '/* Block comment\n   spanning lines. */\n',
        '/* Block comment */ void spanning() {}\n',
      ),
      'added import': "import 'dart:async';\n$commentHead",
      'added annotation': commentHead.replaceFirst(
        'bool productionCall',
        "@pragma('vm:prefer-inline')\nbool productionCall",
      ),
      'layout change without a comment change': commentHead.replaceFirst(
        '=> false;',
        '=>   false;',
      ),
      'tokens regrouped onto one line': commentBase.replaceFirst(
        'bool productionCall() => false; // Keep the default.\n'
            "const label",
        'bool productionCall() => false; const label',
      ),
      'malformed head': '$commentHead\nclass',
    };
    for (final change in executableChanges.entries) {
      test('${change.key} still demands a causal test record', () async {
        expectFailure(
          await evaluateComment(head: change.value),
          ReadinessFailureClassification.missingTestPath,
        );
      });
    }

    test('malformed source at both revisions fails closed', () async {
      expectFailure(
        await evaluateComment(
          base: 'bool productionCall( => false; // a\n',
          head: 'bool productionCall( => false; // b\n',
        ),
        ReadinessFailureClassification.missingTestPath,
      );
    });

    final activeComments = <String, String>{
      'language version': '// @dart=2.19\n',
      'analyzer suppression': '// ignore: unused_element\n',
      'file analyzer suppression': '// ignore_for_file: avoid_print\n',
      'coverage directive': '// coverage:ignore-line\n',
      'formatter directive': '// dart format off\n',
      'doc import': "/// @docImport 'dart:async';\n",
      'Dartdoc directive': '/// {@template backend.entry}\n',
      'Dartdoc nodoc': '/// @nodoc\n',
      'security suppression': '// nosemgrep: dart.lang.security\n',
      'doc excerpt region': '// #docregion backend\n',
      'bidirectional control': '// Note \u202Eevil\u202C text.\n',
      'control character': '// Bell \u0007 text.\n',
      'upper-case suppression': '// NOSONAR\n',
      'upper-case formatter directive': '// DART FORMAT OFF\n',
    };
    for (final comment in activeComments.entries) {
      test('${comment.key} comments are rejected when added, removed or '
          'moved', () async {
        final added = commentHead.replaceFirst(
          'bool productionCall',
          '${comment.value}bool productionCall',
        );
        for (final pair in [
          (commentBase, added),
          (added, commentBase),
          (
            added,
            commentHead.replaceFirst(
              "const label",
              '${comment.value}const label',
            ),
          ),
        ]) {
          expectFailure(
            await evaluateComment(base: pair.$1, head: pair.$2),
            ReadinessFailureClassification.missingTestPath,
          );
        }
      });
    }

    test('unchanged active comments do not block a prose edit', () async {
      const header =
          '// ignore_for_file: avoid_print\n// coverage:ignore-file\n';
      expectAdmitted(
        await evaluateComment(
          base: '$header$commentBase',
          head: '$header$commentHead',
        ),
      );
    });

    test('generated sources never qualify', () async {
      for (final header in [
        '// AUTO GENERATED FILE, DO NOT EDIT.\n',
        '// @generated\n',
        '// Copyright 2026.\n// This file is generated by tool/gen.dart.\n',
        '/* Produced by a script; do not hand-edit. */\n',
        '// Do not modify by hand.\n',
      ]) {
        expectFailure(
          await evaluateComment(
            base: '$header$commentBase',
            head: '$header$commentHead',
          ),
          ReadinessFailureClassification.missingTestPath,
        );
      }
      expectAdmitted(
        await evaluateComment(
          base: '$commentBase// Explains the generated grammar.\n',
          head: '$commentHead// Explains the generated grammar.\n',
        ),
      );
      expectFailure(
        await evaluateComment(path: 'lib/src/backends/example_backend.g.dart'),
        ReadinessFailureClassification.missingTestPath,
      );
    });

    test('a removed generated header is rejected whichever side holds it', () {
      const header = '// Copyright 2026.\n// Generated by tool/gen.dart.\n';
      const edited = 'bool productionCall() => false; // Keep the default.\n';
      const base = '${header}bool productionCall() => false;\n';
      const head = '// Copyright 2026.\n$edited';
      expect(isCommentOnlyDartChange(realSource, base, head), isFalse);
      expect(isCommentOnlyDartChange(realSource, head, base), isFalse);
    });

    test('a comment edit must end its line in both revisions', () {
      const inline = 'int a = 1; /* x */ int b = 2;\n';
      const lined = 'int a = 1; // y\nint b = 2;\n';
      expect(isCommentOnlyDartChange(realSource, inline, lined), isFalse);
      expect(isCommentOnlyDartChange(realSource, lined, inline), isFalse);
      expect(
        isCommentOnlyDartChange(
          realSource,
          lined,
          'int a = 1; // z\nint b = 2;\n',
        ),
        isTrue,
      );
    });

    test('sources whose raw text tooling reads never qualify', () async {
      for (final path in rawTextConsumedSources) {
        expect(
          isCommentOnlyDartChange(path, commentBase, commentHead),
          isFalse,
          reason: path,
        );
        if (assessHighRiskFiles([path]).isHighRisk) {
          expectFailure(
            await evaluateComment(path: path),
            ReadinessFailureClassification.missingTestPath,
          );
        }
      }
      const pins = 'lib/src/hook/native_release_pins.dart';
      const pinsBase = "const llamaCppTag = 'v0.9.0';\n";
      expectFailure(
        await evaluateComment(
          path: pins,
          base: pinsBase,
          head: "// const llamaCppTag = 'v0.8.0';\n$pinsBase",
        ),
        ReadinessFailureClassification.missingTestPath,
      );
      // Split so the bridge tag gate does not read this fixture as a pin.
      const bridgePin =
          'webBridge'
          "AssetsTag = 'v9.9.9'";
      expect(
        isCommentOnlyDartChange(
          'lib/src/web_setup/web_bridge_setup.dart',
          pinsBase,
          '/* const String $bridgePin; */\n$pinsBase',
        ),
        isFalse,
      );
    });

    test('an unreadable blob keeps the causal-test route', () async {
      const changes = [
        RepositoryChange(
          path: backendSource,
          kind: RepositoryChangeKind.modified,
        ),
      ];
      for (final sha in [baseSha, headSha]) {
        final result = await HighRiskReadinessEvaluator(
          repositoryState: _UnreadableBlobState(
            sha: sha,
            path: backendSource,
            changes: changes,
            existingPaths: {backendSource, backendTest},
            files: {
              baseSha: {backendSource: (mode: '100644', contents: commentBase)},
              headSha: {backendSource: (mode: '100644', contents: commentHead)},
            },
          ),
        ).evaluate(evidence: commentEvidence(changes), context: context);
        expectFailure(result, ReadinessFailureClassification.missingTestPath);
      }
    });

    test('non-Dart production paths never qualify', () async {
      expectFailure(
        await evaluateComment(
          path: '.github/workflows/ci.yml',
          base: '# Run CI.\non: push\n',
          head: '# Run CI on every push.\non: push\n',
        ),
        ReadinessFailureClassification.missingTestPath,
      );
    });

    for (final mode in [('100755', '100644'), ('100644', '100755')]) {
      test('mode ${mode.$1} to ${mode.$2} fails closed', () async {
        expectFailure(
          await evaluateComment(baseMode: mode.$1, headMode: mode.$2),
          ReadinessFailureClassification.missingTestPath,
        );
      });
    }

    test('unavailable base or head blobs fail closed', () async {
      for (final pair in [(null, commentHead), (commentBase, null)]) {
        expectFailure(
          await evaluateComment(base: pair.$1, head: pair.$2),
          ReadinessFailureClassification.missingTestPath,
        );
      }
    });

    for (final change in const [
      RepositoryChange(path: backendSource, kind: RepositoryChangeKind.added),
      RepositoryChange(path: backendSource, kind: RepositoryChangeKind.deleted),
      RepositoryChange(
        path: backendSource,
        kind: RepositoryChangeKind.typeChanged,
      ),
      RepositoryChange(
        path: backendSource,
        previousPath: realSource,
        kind: RepositoryChangeKind.renamed,
      ),
      RepositoryChange(
        path: backendSource,
        previousPath: realSource,
        kind: RepositoryChangeKind.copied,
      ),
    ]) {
      test('${change.kind.name} comment-only content fails closed', () async {
        expectFailure(
          await evaluateComment(changes: [change]),
          ReadinessFailureClassification.missingTestPath,
        );
      });
    }

    group('mixed with an executable change', () {
      const changes = [
        RepositoryChange(
          path: backendSource,
          kind: RepositoryChangeKind.modified,
        ),
        RepositoryChange(path: realSource, kind: RepositoryChangeKind.modified),
      ];
      final realFiles = <String, ReadinessFile>{
        realSource: (
          mode: '100644',
          contents: 'void run() { productionCall(); }\n',
        ),
      };
      Future<HighRiskReadinessResult> evaluateMixed(String refPath) {
        final evidence = commentEvidence(changes)
          ..['affected_test_paths'] = [backendTest]
          ..['test_evidence'] = {backendTest: testProof(refPath)};
        return evaluateComment(
          changes: changes,
          evidence: evidence,
          extraHead: realFiles,
        );
      }

      test('the executable path alone needs coverage', () async {
        expectAdmitted(await evaluateMixed(realSource));
      });

      test('evidence for only the comment-only path leaves the executable path '
          'uncovered', () async {
        final result = await evaluateMixed(backendSource);
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains('lack reviewed test reachability'));
      });

      test('no test record at all is rejected', () async {
        expectFailure(
          await evaluateComment(changes: changes, extraHead: realFiles),
          ReadinessFailureClassification.missingTestPath,
        );
      });
    });

    test('changes without a production path stay conservative', () async {
      const doc = 'doc/high_risk_pre_merge_readiness.md';
      expectFailure(
        await evaluateComment(
          path: doc,
          base: '# Contract\n',
          head: '# Contract\n\nClarified.\n',
        ),
        ReadinessFailureClassification.missingTestPath,
      );
    });

    test('structured-output impacts and coverage keep their minima', () async {
      const changes = [
        RepositoryChange(
          path: structuredSource,
          kind: RepositoryChangeKind.modified,
        ),
      ];
      final files = {
        baseSha: <String, ReadinessFile>{
          structuredSource: (mode: '100644', contents: commentBase),
        },
        headSha: <String, ReadinessFile>{
          structuredSource: (mode: '100644', contents: commentHead),
          compiledTest: (
            mode: '100644',
            contents: "test('regression case', () { productionCall(); });",
          ),
          realSource: (
            mode: '100644',
            contents: 'void run() { productionCall(); }\n',
          ),
        },
      };
      Future<HighRiskReadinessResult> evaluate(Map<String, dynamic> evidence) =>
          HighRiskReadinessEvaluator(
            repositoryState: FakeRepositoryState(
              changes: changes,
              existingPaths: files[headSha]!.keys.toSet(),
              files: files,
            ),
          ).evaluate(evidence: evidence, context: context);

      expectAdmitted(await evaluate(structuredEvidence()));
      final excluded = structuredEvidence();
      excluded['structured_output_evidence']['impacts']['grammarSchema']['applicable'] =
          false;
      final result = await evaluate(excluded);
      expectFailure(
        result,
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
      expect(result.message, contains('cannot be excluded'));
      final unreviewed = structuredEvidence();
      for (final impact in StructuredImpact.values) {
        unreviewed['structured_output_evidence']['impacts'][impact
            .name]['production_refs'] = productionRefs(
          realSource,
        );
      }
      expectFailure(
        await evaluate(unreviewed),
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
    });

    test('token proof edge cases', () {
      bool proven(String base, String head) =>
          isCommentOnlyDartChange('lib/a.dart', base, head);
      for (final pair in [
        ('/** Old. */\nvoid f() {}\n', '/** New\n * prose. */\nvoid f() {}\n'),
        (
          '/* a /* nested */ b */\nvoid f() {}\n',
          '/* a /* x */ b */\nvoid f() {}\n',
        ),
        ('void f() {}\r\n// a\r\n', 'void f() {}\r\n// b\r\n'),
        (
          '#!/usr/bin/env dart\n// a\nvoid main() {}\n',
          '#!/usr/bin/env dart\n// b\nvoid main() {}\n',
        ),
        (
          '// ignore_for_file: x\n// a\nvoid f() {}\n',
          '// ignore_for_file: x\n// b\nvoid f() {}\n',
        ),
        ('void f() {} // a\n', 'void f() {}\n'),
        ('void f() {}', 'void f() {}'),
        ('void f() {}\r// a\r', 'void f() {}\r// b\r'),
      ]) {
        expect(proven(pair.$1, pair.$2), isTrue, reason: pair.$2);
      }
      for (final pair in [
        ("var s = r'// a';", "var s = r'// b';"),
        ("var s = '''\n// a\n''';", "var s = '''\n// b\n''';"),
        ("var s = 'a' '// b';", "var s = 'a' '// c';"),
        (r"var s = '${1 /* a */}';", r"var s = '${2 /* a */}';"),
        (
          '#!/usr/bin/env dart\nvoid main() {}\n',
          '#!/usr/bin/env -S dart\nvoid main() {}\n',
        ),
        (
          '// ignore: x\n// a\nvoid f() {}\n',
          '// ignore: x\n// b\nvoid f() {}\n',
        ),
        ('// a\nvoid f() {}\n', '// GENERATED CODE - b\nvoid f() {}\n'),
        ('void f() {}\n', 'void f() {}\n// @dart=2.19\n'),
        ('void f() {}\n// a\n', 'void f() {}\n// a\u200B\n'),
        ('/* a */\nvoid f() {}\n', '/* a\nvoid f() {}\n'),
        ('void f() {}\n', '// a\nvoid f() { }\n'),
        ('void f() {} // a\rvoid g() {}\r', 'void f() {} void g() {}\r'),
        (r"var s = '${1 /* a */}';", r"var s = '${1 /* b */}';"),
        ("import 'dart:io';\n", "/* a */ import 'dart:io';\n"),
        (
          "import 'a.dart';\nimport 'b.dart';\n",
          "import 'a.dart';\n/* a */ import 'b.dart';\n",
        ),
        (
          'void f() {}\n// GENERATED CODE below.\n// a\nvoid g() {}\n',
          'void f() {}\n// GENERATED CODE below.\n// b\nvoid g() {}\n',
        ),
        ("import 'dart:io';\n", "import /* a */ 'dart:io';\n"),
        ('void f() {}', 'void f() {} // a'),
      ]) {
        expect(proven(pair.$1, pair.$2), isFalse, reason: pair.$2);
      }
      expect(isCommentOnlyDartChange('lib/a.sh', '# a\n', '# b\n'), isFalse);
      // Deep unary nesting overflows the analyzer parser's stack.
      final overflowing = 'var x = ${'-' * 200000}1;';
      expect(proven(overflowing, overflowing), isFalse);
    });

    test('reads exact Git blobs, not the working tree', () async {
      final repo = Directory.systemTemp.createTempSync('comment-only-git-');
      addTearDown(() => repo.deleteSync(recursive: true));
      String git(List<String> args) {
        final result = Process.runSync(
          'git',
          args,
          workingDirectory: repo.path,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return (result.stdout as String).trim();
      }

      final sourceFile = File('${repo.path}/$backendSource');
      String commit(String contents, String message) {
        sourceFile.writeAsStringSync(contents);
        git(['add', '.']);
        git(['commit', '--quiet', '-m', message]);
        return git(['rev-parse', 'HEAD']);
      }

      git(['init', '--quiet']);
      git(['config', 'user.name', 'Comment-only policy test']);
      git(['config', 'user.email', 'comment-only@example.invalid']);
      sourceFile.parent.createSync(recursive: true);
      final base = commit(commentBase, 'base');
      final commentOnly = commit(commentHead, 'comment-only');
      final executable = commit(
        commentHead.replaceFirst('=> false', '=> true'),
        'executable',
      );
      git(['checkout', '--quiet', base]);
      sourceFile.writeAsBytesSync([
        ...utf8.encode(commentHead),
        ...utf8.encode('// invalid '),
        0xff,
        0x0a,
      ]);
      git(['commit', '--quiet', '-am', 'invalid UTF-8 comment']);
      final invalidUtf8 = git(['rev-parse', 'HEAD']);
      Future<HighRiskReadinessResult> evaluate(String head) {
        final evidence =
            commentEvidence(const [
                RepositoryChange(
                  path: backendSource,
                  kind: RepositoryChangeKind.modified,
                ),
              ])
              ..['expected_pr_head_sha'] = head
              ..['current_base_sha'] = base;
        evidence['independent_audit']['audit_head_sha'] = head;
        evidence['independent_audit']['audit_base_sha'] = base;
        return const HighRiskReadinessEvaluator().evaluate(
          evidence: evidence,
          context: PullRequestContext(
            repository: context.repository,
            prNumber: context.prNumber,
            headSha: head,
            baseSha: base,
            author: context.author,
          ),
          workingDirectory: repo.path,
        );
      }

      sourceFile.writeAsStringSync(
        commentHead.replaceFirst('=> false', '=> true'),
      );
      expectAdmitted(await evaluate(commentOnly));
      sourceFile.writeAsStringSync(commentHead);
      expectFailure(
        await evaluate(executable),
        ReadinessFailureClassification.missingTestPath,
      );
      expectFailure(
        await evaluate(invalidUtf8),
        ReadinessFailureClassification.missingTestPath,
      );
    });
  });

  test(
    'readiness AST supports explicitly requested allowed analyzer versions',
    () async {
      final requested =
          Platform.environment['LLAMADART_ANALYZER_COMPATIBILITY_VERSIONS'];
      if (requested == null || requested.isEmpty) {
        markTestSkipped(
          'Set LLAMADART_ANALYZER_COMPATIBILITY_VERSIONS for offline compatibility qualification.',
        );
        return;
      }
      final versions = requested.split(',');
      expect(versions, everyElement(matches(r'^\d+\.\d+\.\d+$')));
      final root = Directory.current;
      const paths = [
        'tool/testing/classify_high_risk_changes.dart',
        'tool/testing/high_risk_readiness.dart',
        'tool/testing/release_metadata_readiness.dart',
        'test/unit/tooling/support/bounded_process.dart',
        'test/unit/tooling/high_risk_readiness_test.dart',
      ];
      final source = File('${root.path}/pubspec.yaml').readAsStringSync();
      for (final version in versions) {
        final scratch = Directory.systemTemp.createTempSync(
          'readiness-analyzer-compat-',
        );
        addTearDown(() => scratch.deleteSync(recursive: true));
        File('${scratch.path}/pubspec.yaml').writeAsStringSync(
          source
              .replaceFirst(
                'name: llamadart',
                'name: readiness_analyzer_compat',
              )
              .replaceFirst(
                RegExp(r'^  analyzer:.*$', multiLine: true),
                "  analyzer: '$version'",
              ),
        );
        for (final path in paths) {
          final file = File('${scratch.path}/$path');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(File('${root.path}/$path').readAsBytesSync());
        }
        Future<ProcessResult> run(List<String> args) => Process.run(
          Platform.resolvedExecutable,
          args,
          workingDirectory: scratch.path,
        );
        final resolved = await run(['pub', 'get', '--offline']);
        expect(
          resolved.exitCode,
          0,
          reason:
              'Full root dependency graph analyzer $version: ${resolved.stdout} ${resolved.stderr}',
        );
        final lock = File('${scratch.path}/pubspec.lock').readAsStringSync();
        expect(
          RegExp(
            r'  analyzer:.*?version: "([^"\n]+)"',
            dotAll: true,
          ).firstMatch(lock)?.group(1),
          version,
        );
        final help = await run([
          'run',
          'tool/testing/high_risk_readiness.dart',
          '--help',
        ]);
        expect(
          help.exitCode,
          0,
          reason: 'CLI analyzer $version: ${help.stdout} ${help.stderr}',
        );
        expect(help.stdout, contains('never accepts App credentials'));
        final probe = await run([
          'test',
          '-p',
          'vm',
          '-j',
          '1',
          paths.last,
          '--name',
          'Git-bound additive image export impacts|'
              'Git-proven comment-only production changes',
          '--exclude-tags',
          'local-only',
          '--reporter',
          'expanded',
        ]);
        expect(
          probe.exitCode,
          0,
          reason:
              'Namespace proof analyzer $version: ${probe.stdout} ${probe.stderr}',
        );
        expect(probe.stdout, contains('All tests passed!'));
        print(
          'Qualified analyzer $version: full root offline resolution, CLI help, namespace and comment-only cases passed.',
        );
      }
    },
    tags: 'local-only',
    timeout: const Timeout(Duration(minutes: 4)),
  );

  group('bounded metadata-only release evidence', () {
    test(
      'new release prefix cannot duplicate or invent historical sections',
      () async {
        for (final heading in ['## 0.8.22', '## 9.0.0', '## Migration']) {
          final files = metadataFiles();
          final old = files[headSha]!['CHANGELOG.md']!;
          files[headSha]!['CHANGELOG.md'] = (
            mode: old.mode,
            contents: old.contents.replaceFirst(
              '* Update.',
              '* Update.\n\n$heading\n\n* Duplicate.',
            ),
          );
          expectFailure(
            await evaluateMetadata(files: files),
            ReadinessFailureClassification.invalidReleaseMetadata,
          );
        }
      },
    );
    test(
      'existing active JSX template attributes and script bodies cannot use exception',
      () async {
        for (final pair in [
          (
            before: '<div title={`safe`} />',
            after: r'<div title={`${dangerous()}`} />',
          ),
          (
            before: '<script>safe()</script>',
            after: '<script>dangerous()</script>',
          ),
          (
            before: '<style>body{color:red}</style>',
            after: '<style>body{display:none}</style>',
          ),
        ]) {
          final files = metadataFiles();
          final base = files[baseSha]!['README.md']!;
          final head = files[headSha]!['README.md']!;
          files[baseSha]!['README.md'] = (
            mode: base.mode,
            contents: '${base.contents}\n${pair.before}\n',
          );
          files[headSha]!['README.md'] = (
            mode: head.mode,
            contents: '${head.contents}\n${pair.after}\n',
          );
          expectFailure(
            await evaluateMetadata(files: files),
            ReadinessFailureClassification.invalidReleaseMetadata,
          );
        }
      },
    );
    for (final omitted in releaseMetadataPaths) {
      test('omitting required $omitted rejects stale metadata', () async {
        final changes = [
          for (final path in releaseMetadataPaths)
            if (path != omitted)
              RepositoryChange(path: path, kind: RepositoryChangeKind.modified),
        ];
        expectFailure(
          await evaluateMetadata(changes: changes),
          ReadinessFailureClassification.invalidReleaseMetadata,
        );
      });
    }
    test(
      'real Git blobs authorize only the committed metadata candidate',
      () async {
        final repo = Directory.systemTemp.createTempSync(
          'release-metadata-git-',
        );
        addTearDown(() => repo.deleteSync(recursive: true));
        String git(List<String> args) {
          final result = Process.runSync(
            'git',
            args,
            workingDirectory: repo.path,
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
          return (result.stdout as String).trim();
        }

        git(['init', '--quiet']);
        git(['config', 'user.name', 'Metadata test']);
        git(['config', 'user.email', 'metadata@example.invalid']);
        git(['config', 'core.autocrlf', 'false']);
        final files = metadataFiles();
        void write(Map<String, ReadinessFile> tree) {
          for (final entry in tree.entries) {
            File('${repo.path}/${entry.key}')
              ..parent.createSync(recursive: true)
              ..writeAsStringSync(entry.value.contents);
          }
        }

        write(files[baseSha]!);
        git(['add', '.']);
        git(['commit', '--quiet', '-m', 'base']);
        final base = git(['rev-parse', 'HEAD']);
        write(files[headSha]!);
        git(['add', '.']);
        git(['commit', '--quiet', '-m', 'release']);
        final head = git(['rev-parse', 'HEAD']);
        final evidence = metadataEvidence()
          ..['expected_pr_head_sha'] = head
          ..['current_base_sha'] = base;
        evidence['independent_audit']['audit_head_sha'] = head;
        evidence['independent_audit']['audit_base_sha'] = base;
        Future<HighRiskReadinessResult> evaluate(
          String candidate,
          Map<String, dynamic> input,
        ) => const HighRiskReadinessEvaluator().evaluate(
          evidence: input,
          context: PullRequestContext(
            repository: context.repository,
            prNumber: context.prNumber,
            headSha: candidate,
            baseSha: base,
            author: context.author,
          ),
          workingDirectory: repo.path,
        );
        // Mutable working-tree content cannot substitute for committed blobs.
        File('${repo.path}/README.md').writeAsStringSync('{unsafe()}');
        expect(
          (await evaluate(head, evidence)).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
        git(['add', 'README.md']);
        git(['commit', '--quiet', '-m', 'unsafe MDX']);
        final unsafe = git(['rev-parse', 'HEAD']);
        expectFailure(
          await evaluate(unsafe, evidence),
          ReadinessFailureClassification.headMismatch,
        );
        evidence['expected_pr_head_sha'] = unsafe;
        evidence['independent_audit']['audit_head_sha'] = unsafe;
        expectFailure(
          await evaluate(unsafe, evidence),
          ReadinessFailureClassification.invalidReleaseMetadata,
        );
      },
    );
    test(
      'documented grammar and repeated existing runtime identity are inert',
      () async {
        final files = metadataFiles();
        for (final sha in [baseSha, headSha]) {
          final old = files[sha]!['README.md']!;
          files[sha]!['README.md'] = (
            mode: old.mode,
            contents: '${old.contents}\nNative v0.4.0.\n',
          );
        }
        final candidate = files[headSha]!['README.md']!;
        files[headSha]!['README.md'] = (
          mode: candidate.mode,
          contents:
              '${candidate.contents}\nKnown v0.4.0 limitation: `root ::= "a"{2000}`.\n',
        );
        expect(
          (await evaluateMetadata(files: files)).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
      },
    );
    test(
      'fence and inline context cannot convert existing fragments to MDX',
      () async {
        for (final snippet in [
          '{dangerous()}',
          'export const bad = 1;',
          '<script src="bad"/>',
        ]) {
          for (final fence in ['```', '````', '~~~', '`']) {
            final files = metadataFiles();
            final before = files[baseSha]!['README.md']!;
            final after = files[headSha]!['README.md']!;
            final inert = fence.length == 1
                ? '$fence$snippet$fence'
                : '$fence\n$snippet\n$fence';
            files[baseSha]!['README.md'] = (
              mode: before.mode,
              contents: '${before.contents}\n$inert\n',
            );
            files[headSha]!['README.md'] = (
              mode: after.mode,
              contents: '${after.contents}\n$snippet\n',
            );
            expectFailure(
              await evaluateMetadata(files: files),
              ReadinessFailureClassification.invalidReleaseMetadata,
            );
          }
        }
      },
    );
    test('Docusaurus executable fences and unclosed fences reject', () async {
      for (final snippet in [
        '```mdx-code-block\n{dangerous()}\n```',
        '````mdx-code-block\n{dangerous()}\n````',
        '```js\n{dangerous()}',
      ]) {
        final files = metadataFiles();
        final old = files[headSha]!['README.md']!;
        files[headSha]!['README.md'] = (
          mode: old.mode,
          contents: '${old.contents}\n$snippet\n',
        );
        expectFailure(
          await evaluateMetadata(files: files),
          ReadinessFailureClassification.invalidReleaseMetadata,
        );
      }
    });
    test(
      'complete three-lock release remains high risk and externally unverified',
      () async {
        final result = await evaluateMetadata();
        expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
        expect(
          result.failureClassification,
          ReadinessFailureClassification.externalPrerequisitesUnavailable,
        );
        expect(result.isReady, isFalse);
        expect(result.toJson()['classification'], 'high-risk');
      },
    );

    for (final path in [
      'lib/src/backends/native.dart',
      'hook/build.dart',
      'scripts/fetch_webgpu_bridge_assets.sh',
      'packages/llamadart_llama_cpp_flutter/darwin/llamadart_llama_cpp_flutter/Package.swift',
      '.github/workflows/release_on_prep_merge.yml',
      'tool/testing/high_risk_readiness.dart',
      'AGENTS.md',
      'website/versioned_docs/version-0.8.22/intro.md',
      'website/docs/new.mdx',
      'packages/llamadart_llama_cpp_flutter/pubspec.yaml',
    ]) {
      test('mixed $path cannot claim release exception', () async {
        final changes = [
          for (final name in releaseMetadataPaths)
            RepositoryChange(path: name, kind: RepositoryChangeKind.modified),
          RepositoryChange(path: path, kind: RepositoryChangeKind.modified),
        ];
        final evidence = metadataEvidence();
        evidence['surfaces'] = assessHighRiskFiles(
          changes.map((c) => c.path),
        ).surfaces.map((s) => s.name).toList();
        expect(
          (await evaluateMetadata(
            evidence: evidence,
            changes: changes,
          )).decision,
          ReadinessDecision.rejected,
        );
      });
    }

    for (final mutation in <String, String Function(String)>{
      'dependency': (s) => s.replaceFirst('yaml: ^3.1.3', 'yaml: ^9.0.0'),
      'SDK': (s) =>
          '$s'
          'environment:\n  sdk: ^9.0.0\n',
      'override': (s) =>
          '$s'
          'dependency_overrides:\n  yaml: any\n',
      'native pin': (s) =>
          '$s'
          'hooks:\n  user_defines:\n    llamadart_native_tag: v9.0.0\n',
      'duplicate version': (s) =>
          '$s'
          'version: 0.8.23\n',
      'rollback': (s) => s.replaceFirst('0.8.23', '0.8.21'),
      'minor jump': (s) => s.replaceFirst('0.8.23', '0.9.0'),
      'leading zero': (s) => s.replaceFirst('0.8.23', '0.8.023'),
    }.entries) {
      test(
        'pubspec ${mutation.key} rejects even claimed verifier PASS',
        () async {
          final files = metadataFiles();
          files[headSha]!['pubspec.yaml'] = (
            mode: '100644',
            contents: mutation.value(files[headSha]!['pubspec.yaml']!.contents),
          );
          expectFailure(
            await evaluateMetadata(files: files),
            ReadinessFailureClassification.invalidReleaseMetadata,
          );
        },
      );
    }

    for (final lock in metadataLockPaths.entries) {
      for (final mutation in <String, String Function(String)>{
        'source': (s) => s.replaceFirst('source: path', 'source: hosted'),
        'path': (s) => s.replaceFirst(lock.value, '../evil'),
        'relative': (s) => s.replaceFirst('relative: true', 'relative: false'),
        'SDK': (s) => s.replaceFirst('3.13.0', '3.14.0'),
        'dependency': (s) => s.replaceFirst('"3.1.3"', '"9.0.0"'),
        'extra package': (s) =>
            s.replaceFirst('sdks:', '  evil:\n    version: "1.0.0"\nsdks:'),
        'wrong version': (s) => s.replaceFirst('0.8.23', '0.8.24'),
        'hash': (s) => s.replaceFirst('abc123', 'wronghash'),
        'duplicate core': (s) => s.replaceFirst(
          '  yaml:',
          '  llamadart:\n    version: "0.8.23"\n  yaml:',
        ),
        'malformed core': (s) =>
            s.replaceFirst('  llamadart:\n', '  llamadart: [unterminated\n'),
      }.entries) {
        test('${lock.key} ${mutation.key} rejects independently', () async {
          final files = metadataFiles();
          final original = files[headSha]![lock.key]!;
          final mutated = mutation.value(original.contents);
          expect(mutated, isNot(original.contents));
          files[headSha]![lock.key] = (mode: original.mode, contents: mutated);
          expectFailure(
            await evaluateMetadata(files: files),
            ReadinessFailureClassification.invalidReleaseMetadata,
          );
        });
      }
      for (final identity in ['source', 'path', 'relative']) {
        test('${lock.key} rejects consistently wrong $identity', () async {
          final files = metadataFiles();
          for (final sha in [baseSha, headSha]) {
            final original = files[sha]![lock.key]!;
            final mutated = switch (identity) {
              'source' => original.contents.replaceFirst(
                'source: path',
                'source: hosted',
              ),
              'path' => original.contents.replaceFirst(lock.value, '../evil'),
              _ => original.contents.replaceFirst(
                'relative: true',
                'relative: false',
              ),
            };
            files[sha]![lock.key] = (mode: original.mode, contents: mutated);
          }
          expectFailure(
            await evaluateMetadata(files: files),
            ReadinessFailureClassification.invalidReleaseMetadata,
          );
        });
      }
      for (final mode in ['100755', '120000']) {
        test('${lock.key} rejects mode $mode', () async {
          final files = metadataFiles();
          final original = files[headSha]![lock.key]!;
          files[headSha]![lock.key] = (mode: mode, contents: original.contents);
          expectFailure(
            await evaluateMetadata(files: files),
            ReadinessFailureClassification.invalidReleaseMetadata,
          );
        });
      }
      for (final kind in [
        RepositoryChangeKind.added,
        RepositoryChangeKind.deleted,
        RepositoryChangeKind.renamed,
        RepositoryChangeKind.typeChanged,
      ]) {
        test('${lock.key} rejects ${kind.name}', () async {
          final changes = [
            for (final path in releaseMetadataPaths)
              RepositoryChange(
                path: path,
                kind: path == lock.key ? kind : RepositoryChangeKind.modified,
                previousPath:
                    path == lock.key && kind == RepositoryChangeKind.renamed
                    ? 'old/pubspec.lock'
                    : null,
              ),
          ];
          expectFailure(
            await evaluateMetadata(changes: changes),
            ReadinessFailureClassification.invalidReleaseMetadata,
          );
        });
      }
    }
    test('extra consumer lock cannot enter the finite inventory', () async {
      final files = metadataFiles();
      const extra = 'example/other/pubspec.lock';
      for (final sha in [baseSha, headSha]) {
        files[sha]![extra] = files[sha]![metadataLockPaths.keys.first]!;
      }
      expectFailure(
        await evaluateMetadata(
          files: files,
          changes: [
            for (final path in releaseMetadataPaths)
              RepositoryChange(path: path, kind: RepositoryChangeKind.modified),
            RepositoryChange(path: extra, kind: RepositoryChangeKind.modified),
          ],
        ),
        ReadinessFailureClassification.invalidReleaseMetadata,
      );
    });

    for (final path in [
      releaseMetadataVerifier,
      releaseMetadataTest,
      'pubspec.yaml',
    ]) {
      for (final mode in ['120000', '100755']) {
        test('$path mode $mode rejects', () async {
          final files = metadataFiles();
          files[headSha]![path] = (
            mode: mode,
            contents: files[headSha]![path]!.contents,
          );
          expectFailure(
            await evaluateMetadata(files: files),
            ReadinessFailureClassification.invalidReleaseMetadata,
          );
        });
      }
    }
    test('modified or missing existing verifier/test rejects', () async {
      for (final path in [releaseMetadataVerifier, releaseMetadataTest]) {
        final files = metadataFiles();
        files[headSha]![path] = (mode: '100644', contents: '// fake pass\n');
        expectFailure(
          await evaluateMetadata(files: files),
          ReadinessFailureClassification.invalidReleaseMetadata,
        );
        files[headSha]!.remove(path);
        expectFailure(
          await evaluateMetadata(files: files),
          ReadinessFailureClassification.invalidReleaseMetadata,
        );
      }
    });
    test(
      'changed history, stale snippets and executable docs reject',
      () async {
        for (final source in [
          '# Install\n  llamadart: ^0.8.22\n',
          '# Install\n  llamadart: ^0.8.23\n{dangerous()}\n',
          '# Install\n  llamadart: ^0.8.23\n<script src="evil"/>\n',
          '# Install\n  llamadart: ^0.8.23\nexport const x = 1;\n',
          '# Install\n  llamadart: ^0.8.23\nNew runtime v9.0.0\n',
        ]) {
          final files = metadataFiles();
          files[headSha]!['README.md'] = (mode: '100644', contents: source);
          expectFailure(
            await evaluateMetadata(files: files),
            ReadinessFailureClassification.invalidReleaseMetadata,
          );
        }
        final files = metadataFiles();
        files[headSha]!['CHANGELOG.md'] = (
          mode: '100644',
          contents: files[headSha]!['CHANGELOG.md']!.contents.replaceFirst(
            'History.',
            'Rewrite.',
          ),
        );
        expectFailure(
          await evaluateMetadata(files: files),
          ReadinessFailureClassification.invalidReleaseMetadata,
        );
      },
    );
    test(
      'renames/additions/removals cannot be disguised as metadata',
      () async {
        for (final kind in [
          RepositoryChangeKind.added,
          RepositoryChangeKind.deleted,
          RepositoryChangeKind.renamed,
          RepositoryChangeKind.typeChanged,
        ]) {
          final changes = [
            for (final path in releaseMetadataPaths)
              RepositoryChange(
                path: path,
                kind: path == 'README.md'
                    ? kind
                    : RepositoryChangeKind.modified,
                previousPath:
                    path == 'README.md' && kind == RepositoryChangeKind.renamed
                    ? 'old.md'
                    : null,
              ),
          ];
          expectFailure(
            await evaluateMetadata(changes: changes),
            ReadinessFailureClassification.invalidReleaseMetadata,
          );
        }
      },
    );
    test(
      'wrong command, nonpassing row and invented test cannot authorize',
      () async {
        final command = metadataEvidence();
        command['matrix_row_evidence'][releaseMetadataRow]['command'] =
            'echo pass';
        expectFailure(
          await evaluateMetadata(evidence: command),
          ReadinessFailureClassification.invalidReleaseMetadata,
        );
        final failed = metadataEvidence();
        failed['matrix_row_evidence'][releaseMetadataRow]['result'] =
            'notApplicable';
        expectFailure(
          await evaluateMetadata(evidence: failed),
          ReadinessFailureClassification.matrixRowFailed,
        );
        final path = metadataEvidence()
          ..['affected_test_paths'] = [backendTest];
        expectFailure(
          await evaluateMetadata(evidence: path),
          ReadinessFailureClassification.invalidReleaseMetadata,
        );
      },
    );
    test(
      'stale audits, selfapproval, P1s and unresolved threads stay blocked',
      () async {
        for (final entry in <String, Object>{
          'audit_head_sha': otherSha,
          'audit_base_sha': otherSha,
          'auditor_identity': context.author,
          'known_pr_caused_p1_regressions': 1,
          'unresolved_review_threads': 1,
        }.entries) {
          final evidence = metadataEvidence();
          evidence['independent_audit'][entry.key] = entry.value;
          expect(
            (await evaluateMetadata(evidence: evidence)).decision,
            ReadinessDecision.rejected,
          );
        }
      },
    );
  });
  group('strict JSON and schema shape', () {
    test('rejects duplicate root, nested, and escaped-equivalent keys', () {
      expect(
        () => decodeStrictJsonObject('{"a":1,"a":2}'),
        throwsFormatException,
      );
      expect(
        () => decodeStrictJsonObject('{"x":{"a":1,"a":2}}'),
        throwsFormatException,
      );
      expect(
        () => decodeStrictJsonObject('{"a":1,"\\u0061":2}'),
        throwsFormatException,
      );
    });

    test('accepts duplicate names in different JSON objects', () {
      expect(decodeStrictJsonObject('{"x":{"a":1},"y":{"a":2}}'), hasLength(2));
    });

    for (final mutation in <String, void Function(Map<String, dynamic>)>{
      'unknown root key': (value) => value['decision'] = 'ready',
      'wrong integer type': (value) => value['pr_number'] = '419',
      'wrong list member type': (value) => value['surfaces'] = [1],
      'wrong map type': (value) => value['matrix_row_evidence'] = <dynamic>[],
      'invalid classification enum': (value) =>
          value['classification'] = 'ready',
      'unknown surface enum': (value) => value['surfaces'] = ['parser'],
      'invalid timestamp': (value) =>
          value['timestamp'] = '2026-08-28T12:00:00-04:00',
      'invalid calendar timestamp': (value) =>
          value['timestamp'] = '2026-02-31T12:00:00Z',
      'invalid correlation identity': (value) =>
          value['correlation_id'] = '../escape',
      'uppercase SHA': (value) => value['expected_pr_head_sha'] =
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      'zero SHA': (value) => value['current_base_sha'] =
          '0000000000000000000000000000000000000000',
      'invalid GitHub author': (value) => value['pr_author'] = 'bad--author',
      'caller-declared evaluation': (value) =>
          value['evaluation'] = {'decision': 'ready'},
      'unknown nested audit key': (value) =>
          (value['independent_audit'] as Map<String, dynamic>)['trusted'] =
              true,
      'invalid audit kind enum': (value) =>
          (value['independent_audit'] as Map<String, dynamic>)['audit_kind'] =
              'qa',
      'negative audit count': (value) =>
          (value['independent_audit']
                  as Map<String, dynamic>)['unresolved_review_threads'] =
              -1,
      'invalid matrix result enum': (value) =>
          ((value['matrix_row_evidence']
                      as Map<String, dynamic>)['structured-output-adversarial']
                  as Map<String, dynamic>)['result'] =
              'passed',
      'invalid family status enum': (value) =>
          (((value['structured_output_evidence']
                              as Map<String, dynamic>)['families']
                          as List<dynamic>)
                      .single
                  as Map<String, dynamic>)['status'] =
              'skipped',
      'legacy boolean structured claim': (value) =>
          (value['structured_output_evidence']
                  as Map<String, dynamic>)['schema_exactness_covered'] =
              true,
      'duplicate declared row': (value) =>
          (value['required_matrix_row_ids'] as List<dynamic>).add(
            'structured-output-adversarial',
          ),
    }.entries) {
      test('rejects ${mutation.key}', () async {
        final evidence = structuredEvidence();
        mutation.value(evidence);
        expectFailure(
          await evaluateStructured(evidence),
          ReadinessFailureClassification.schemaViolation,
        );
      });
    }

    test(
      'malformed evidence still produces schema-safe rejection JSON',
      () async {
        final evidence = structuredEvidence()..['surfaces'] = [1];
        final result = await evaluateStructured(evidence);

        expectFailure(result, ReadinessFailureClassification.schemaViolation);
        final output = result.toJson();
        expect(() => jsonEncode(output), returnsNormally);
        expect(output['surfaces'], isEmpty);
        expect(
          (output['evaluation'] as Map<String, dynamic>)['decision'],
          ReadinessDecision.rejected.name,
        );
      },
    );

    test(
      'rejects row object type confusion and conflicting row identity',
      () async {
        final wrongType = structuredEvidence();
        final wrongRows = Map<String, dynamic>.from(
          wrongType['matrix_row_evidence'] as Map,
        );
        wrongRows['structured-output-adversarial'] = 'pass';
        wrongType['matrix_row_evidence'] = wrongRows;
        expectFailure(
          await evaluateStructured(wrongType),
          ReadinessFailureClassification.schemaViolation,
        );

        final conflict = structuredEvidence();
        ((conflict['matrix_row_evidence']
                    as Map<String, dynamic>)['structured-output-adversarial']
                as Map<String, dynamic>)['row_id'] =
            'high-risk-exact-head-independent-qa';
        expectFailure(
          await evaluateStructured(conflict),
          ReadinessFailureClassification.matrixRowFailed,
        );
      },
    );
  });

  group('exact PR and repository binding', () {
    for (final testCase
        in <
          (
            String,
            void Function(Map<String, dynamic>),
            ReadinessFailureClassification,
          )
        >[
          (
            'repository',
            (value) => value['repository'] = 'attacker/fork',
            ReadinessFailureClassification.repositoryMismatch,
          ),
          (
            'PR number',
            (value) => value['pr_number'] = 420,
            ReadinessFailureClassification.prMismatch,
          ),
          (
            'head',
            (value) => value['expected_pr_head_sha'] = otherSha,
            ReadinessFailureClassification.headMismatch,
          ),
          (
            'base',
            (value) => value['current_base_sha'] = otherSha,
            ReadinessFailureClassification.baseMismatch,
          ),
          (
            'author',
            (value) => value['pr_author'] = 'other-author',
            ReadinessFailureClassification.authorMismatch,
          ),
        ]) {
      test('rejects mismatched ${testCase.$1}', () async {
        final evidence = structuredEvidence();
        testCase.$2(evidence);
        final result = await evaluateStructured(evidence);
        expectFailure(result, testCase.$3);
        expectContextBoundIdentity(result);
      });
    }

    test(
      'emitted identity stays bound to the context for every identity field',
      () async {
        final mismatch = structuredEvidence();
        mutateIdentityToOtherValidValues(mismatch);
        final mismatchResult = await evaluateStructured(mismatch);
        expectFailure(
          mismatchResult,
          ReadinessFailureClassification.repositoryMismatch,
        );
        expectContextBoundIdentity(mismatchResult);

        final schemaViolation = structuredEvidence();
        mutateIdentityToOtherValidValues(schemaViolation);
        schemaViolation['surfaces'] = [1];
        final schemaResult = await evaluateStructured(schemaViolation);
        expectFailure(
          schemaResult,
          ReadinessFailureClassification.schemaViolation,
        );
        expectContextBoundIdentity(schemaResult);
      },
    );

    test('fails closed when commits or ancestry cannot be proven', () async {
      expectFailure(
        await evaluatorFor(
          structuredChanges,
          commitsExist: false,
        ).evaluate(evidence: structuredEvidence(), context: context),
        ReadinessFailureClassification.gitExecutionError,
      );
      expectFailure(
        await evaluatorFor(
          structuredChanges,
          baseIsAncestor: false,
        ).evaluate(evidence: structuredEvidence(), context: context),
        ReadinessFailureClassification.baseMismatch,
      );
    });

    test('rejects malformed context before any Git access', () async {
      for (final testCase
          in <(PullRequestContext, String, int, String, String, String)>[
            const (
              PullRequestContext(
                repository: '../../unsafe',
                prNumber: 419,
                headSha: headSha,
                baseSha: baseSha,
                author: 'contributor-dev',
              ),
              'invalid/invalid',
              419,
              headSha,
              baseSha,
              'contributor-dev',
            ),
            const (
              PullRequestContext(
                repository: 'leehack/llamadart',
                prNumber: 0,
                headSha: headSha,
                baseSha: baseSha,
                author: 'contributor-dev',
              ),
              'leehack/llamadart',
              1,
              headSha,
              baseSha,
              'contributor-dev',
            ),
            const (
              PullRequestContext(
                repository: 'leehack/llamadart',
                prNumber: 419,
                headSha: '--upload-pack=unsafe',
                baseSha: baseSha,
                author: 'contributor-dev',
              ),
              'leehack/llamadart',
              419,
              'ffffffffffffffffffffffffffffffffffffffff',
              baseSha,
              'contributor-dev',
            ),
            const (
              PullRequestContext(
                repository: 'leehack/llamadart',
                prNumber: 419,
                headSha: headSha,
                baseSha: '../unsafe',
                author: 'contributor-dev',
              ),
              'leehack/llamadart',
              419,
              headSha,
              'ffffffffffffffffffffffffffffffffffffffff',
              'contributor-dev',
            ),
            const (
              PullRequestContext(
                repository: 'leehack/llamadart',
                prNumber: 419,
                headSha: headSha,
                baseSha: baseSha,
                author: 'bad--author',
              ),
              'leehack/llamadart',
              419,
              headSha,
              baseSha,
              'invalid-author',
            ),
          ]) {
        final malformedContext = testCase.$1;
        final repositoryState = FakeRepositoryState(changes: structuredChanges);
        final evidence = structuredEvidence();
        mutateIdentityToOtherValidValues(evidence);
        final result = await HighRiskReadinessEvaluator(
          repositoryState: repositoryState,
          clock: () => DateTime.utc(2026, 8, 28, 13),
        ).evaluate(evidence: evidence, context: malformedContext);

        expectFailure(result, ReadinessFailureClassification.invalidInput);
        expect(repositoryState.repositoryCallCount, 0);
        expectEmittedIdentity(
          result,
          repository: testCase.$2,
          prNumber: testCase.$3,
          headSha: testCase.$4,
          baseSha: testCase.$5,
          author: testCase.$6,
        );
      }
    });

    test(
      'classifies rename source and destination from exact inventory',
      () async {
        final result = await evaluatorFor(const [
          RepositoryChange(
            path: 'website/docs/renamed.md',
            previousPath: 'lib/src/core/template/old_handler.dart',
            kind: RepositoryChangeKind.renamed,
          ),
        ]).evaluate(evidence: standardEvidence(), context: context);
        expectFailure(
          result,
          ReadinessFailureClassification.classificationMismatch,
        );
      },
    );

    test('rejects unknown and unmerged inventory statuses', () async {
      for (final kind in [
        RepositoryChangeKind.unknown,
        RepositoryChangeKind.unmerged,
      ]) {
        expectFailure(
          await evaluatorFor([
            RepositoryChange(
              path: 'lib/src/backends/example_backend.dart',
              kind: kind,
            ),
          ]).evaluate(evidence: backendEvidence(), context: context),
          ReadinessFailureClassification.changedFilesMismatch,
        );
      }
    });

    test(
      'rejects malformed and duplicate repository inventory entries',
      () async {
        for (final changes in <List<RepositoryChange>>[
          const [
            RepositoryChange(path: '', kind: RepositoryChangeKind.modified),
          ],
          const [
            RepositoryChange(
              path: backendTest,
              kind: RepositoryChangeKind.renamed,
            ),
          ],
          const [
            RepositoryChange(
              path: backendTest,
              previousPath: 'test/unit/backends/old_test.dart',
              kind: RepositoryChangeKind.modified,
            ),
          ],
          const [
            RepositoryChange(
              path: backendTest,
              kind: RepositoryChangeKind.added,
            ),
            RepositoryChange(
              path: backendTest,
              kind: RepositoryChangeKind.modified,
            ),
          ],
        ]) {
          final result = await evaluatorFor(
            changes,
          ).evaluate(evidence: backendEvidence(), context: context);
          expectFailure(
            result,
            ReadinessFailureClassification.changedFilesMismatch,
          );
          expect(() => jsonEncode(result.toJson()), returnsNormally);
        }
      },
    );
  });

  group('canonical PR author identities', () {
    PullRequestContext authorContext(String author) => PullRequestContext(
      repository: context.repository,
      prNumber: context.prNumber,
      headSha: context.headSha,
      baseSha: context.baseSha,
      author: author,
    );

    RegExp authorPattern() {
      final schema =
          jsonDecode(
                File(
                  'tool/testing/high_risk_readiness_evidence.schema.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      return RegExp(schema['properties']['pr_author']['pattern'] as String);
    }

    test(
      'canonical human and bot authors agree with schema and emitted identity',
      () async {
        final pattern = authorPattern();
        for (final author in [
          'leehack',
          'github-actions',
          'github-actions[bot]',
          'dependabot[bot]',
          'a',
          'a[bot]',
          List.filled(39, 'a').join(),
          '${List.filled(39, 'a').join()}[bot]',
        ]) {
          expect(pattern.hasMatch(author), isTrue, reason: author);
          final evidence = backendEvidence()..['pr_author'] = author;
          final result = await evaluatorFor(
            backendChanges,
          ).evaluate(evidence: evidence, context: authorContext(author));
          expect(
            result.decision,
            ReadinessDecision.unverifiedPrerequisites,
            reason: author,
          );
          expect(result.isReady, isFalse);
          expectEmittedIdentity(
            result,
            repository: context.repository,
            prNumber: context.prNumber,
            headSha: headSha,
            baseSha: baseSha,
            author: author,
          );
        }
      },
    );

    test(
      'canonical bot matching preserves context spelling without alias conversion',
      () async {
        final evidence = backendEvidence()
          ..['pr_author'] = 'GITHUB-ACTIONS[bot]';
        final result = await evaluatorFor(backendChanges).evaluate(
          evidence: evidence,
          context: authorContext('GitHub-Actions[bot]'),
        );
        expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
        expect(result.toJson()['pr_author'], 'GitHub-Actions[bot]');
        for (final pair in [
          ('github-actions', 'github-actions[bot]'),
          ('github-actions[bot]', 'github-actions'),
        ]) {
          final mismatch = backendEvidence()..['pr_author'] = pair.$1;
          final rejected = await evaluatorFor(
            backendChanges,
          ).evaluate(evidence: mismatch, context: authorContext(pair.$2));
          expectFailure(
            rejected,
            ReadinessFailureClassification.authorMismatch,
          );
          expect(rejected.toJson()['pr_author'], pair.$2);
        }
      },
    );

    test(
      'aliases and malformed bot logins fail schema and context before Git',
      () async {
        final pattern = authorPattern();
        for (final author in [
          '',
          'app/github-actions',
          'app/github-actions[bot]',
          '../github-actions',
          '[bot]',
          '-bot[bot]',
          'bot-[bot]',
          'bad--bot[bot]',
          'github-actions[BOT]',
          'github-actions[Bot]',
          'github-actions[bot]extra',
          'github-actions[bot][bot]',
          'github-actions[bot]/main',
          'github-actions [bot]',
          ' github-actions[bot]',
          'github-actions[bot] ',
          'github-actions[bot]\n',
          'github_actions[bot]',
          List.filled(40, 'a').join(),
          '${List.filled(40, 'a').join()}[bot]',
        ]) {
          expect(pattern.hasMatch(author), isFalse, reason: author);
          final repository = FakeRepositoryState(changes: backendChanges);
          final invalidContext =
              await HighRiskReadinessEvaluator(
                repositoryState: repository,
              ).evaluate(
                evidence: backendEvidence(),
                context: authorContext(author),
              );
          expectFailure(
            invalidContext,
            ReadinessFailureClassification.invalidInput,
          );
          expect(repository.repositoryCallCount, 0);
          expect(invalidContext.toJson()['pr_author'], 'invalid-author');
          final invalidEvidence = backendEvidence()..['pr_author'] = author;
          expectFailure(
            await evaluatorFor(
              backendChanges,
            ).evaluate(evidence: invalidEvidence, context: context),
            ReadinessFailureClassification.schemaViolation,
          );
        }
      },
    );

    test(
      'canonical author support preserves human and bot self-approval refusal',
      () async {
        final human = backendEvidence()..['pr_author'] = 'github-actions';
        human['independent_audit']['auditor_identity'] = 'GITHUB-ACTIONS';
        expectFailure(
          await evaluatorFor(
            backendChanges,
          ).evaluate(evidence: human, context: authorContext('github-actions')),
          ReadinessFailureClassification.selfApprovalProhibited,
        );
        final bot = backendEvidence()..['pr_author'] = 'github-actions[bot]';
        bot['independent_audit']['auditor_identity'] = 'github-actions[bot]';
        // Author admission does not widen the independent auditor identifier.
        expectFailure(
          await evaluatorFor(backendChanges).evaluate(
            evidence: bot,
            context: authorContext('github-actions[bot]'),
          ),
          ReadinessFailureClassification.schemaViolation,
        );
        final botLogin = backendEvidence()
          ..['pr_author'] = 'github-actions[bot]';
        botLogin['independent_audit']['auditor_identity'] = 'GitHub-Actions';
        expectFailure(
          await evaluatorFor(backendChanges).evaluate(
            evidence: botLogin,
            context: authorContext('github-actions[bot]'),
          ),
          ReadinessFailureClassification.selfApprovalProhibited,
        );
      },
    );
  });

  group('audit and matrix invariants', () {
    test('valid local evidence is never operationally ready', () async {
      final result = await evaluateStructured(structuredEvidence());
      expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
      expect(
        result.failureClassification,
        ReadinessFailureClassification.externalPrerequisitesUnavailable,
      );
      expect(result.isReady, isFalse);
      final prerequisites =
          ((result.toJson()['evaluation']
                  as Map<String, dynamic>)['external_prerequisites']
              as Map<String, dynamic>);
      expect(prerequisites.values.whereType<bool>(), everyElement(isFalse));
    });

    test('rejects self approval and retired qa identities', () async {
      final self = structuredEvidence();
      (self['independent_audit'] as Map<String, dynamic>)['auditor_identity'] =
          context.author;
      expectFailure(
        await evaluateStructured(self),
        ReadinessFailureClassification.selfApprovalProhibited,
      );

      for (final identity in ['qa', 'QA', 'qa-agent', 'qa_agent', 'qa-task']) {
        final retired = structuredEvidence();
        (retired['independent_audit']
                as Map<String, dynamic>)['auditor_identity'] =
            identity;
        expectFailure(
          await evaluateStructured(retired),
          ReadinessFailureClassification.retiredQaProfileProhibited,
        );
      }
    });

    for (final testCase
        in <(String, String, Object, ReadinessFailureClassification)>[
          (
            'audit head',
            'audit_head_sha',
            otherSha,
            ReadinessFailureClassification.headMismatch,
          ),
          (
            'audit base',
            'audit_base_sha',
            otherSha,
            ReadinessFailureClassification.baseMismatch,
          ),
          (
            'audit decision',
            'decision',
            'blocked',
            ReadinessFailureClassification.auditRejected,
          ),
          (
            'review threads',
            'unresolved_review_threads',
            1,
            ReadinessFailureClassification.unresolvedReviewThreads,
          ),
          (
            'P1 regressions',
            'known_pr_caused_p1_regressions',
            1,
            ReadinessFailureClassification.knownP1Regressions,
          ),
        ]) {
      test('rejects invalid ${testCase.$1}', () async {
        final evidence = structuredEvidence();
        (evidence['independent_audit'] as Map<String, dynamic>)[testCase.$2] =
            testCase.$3;
        expectFailure(await evaluateStructured(evidence), testCase.$4);
      });
    }

    test(
      'rejects missing, extra, failed, and mismatched matrix rows',
      () async {
        final missing = structuredEvidence();
        (missing['required_matrix_row_ids'] as List<dynamic>).remove(
          'structured-output-adversarial',
        );
        expectFailure(
          await evaluateStructured(missing),
          ReadinessFailureClassification.missingRequiredMatrixRow,
        );

        final extra = structuredEvidence();
        (extra['required_matrix_row_ids'] as List<dynamic>).add('phantom-row');
        expectFailure(
          await evaluateStructured(extra),
          ReadinessFailureClassification.schemaViolation,
        );

        final failed = structuredEvidence();
        ((failed['matrix_row_evidence']
                    as Map<String, dynamic>)['structured-output-adversarial']
                as Map<String, dynamic>)['result'] =
            'fail';
        expectFailure(
          await evaluateStructured(failed),
          ReadinessFailureClassification.matrixRowFailed,
        );
      },
    );
  });

  group('candidate-tree evidence paths', () {
    test(
      'only maintained compiled adapter suites can satisfy grammar axes',
      () async {
        const source =
            'packages/genkit_llamadart/lib/src/integration/genkit/converters/constrained_tools.dart';
        const compiled =
            'packages/genkit_llamadart/test/integration/genkit/plugin/real_model_constrained_grammar_test.dart';
        const ordinary =
            'packages/genkit_llamadart/test/integration/genkit/plugin/ordinary_test.dart';
        final evidence =
            jsonDecode(
                  jsonEncode(structuredEvidence())
                      .replaceAll(structuredSource, source)
                      .replaceAll(compiledTest, compiled),
                )
                as Map<String, dynamic>;
        evidence['surfaces'] = ['structuredOutput', 'backendRuntime'];
        final changes = [
          const RepositoryChange(
            path: source,
            kind: RepositoryChangeKind.modified,
          ),
          const RepositoryChange(
            path: compiled,
            kind: RepositoryChangeKind.modified,
          ),
          const RepositoryChange(
            path: ordinary,
            kind: RepositoryChangeKind.added,
          ),
        ];
        Future<HighRiskReadinessResult> evaluate() => evaluatorFor(
          changes,
        ).evaluate(evidence: evidence, context: context);
        expect(
          (await evaluate()).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
        evidence['affected_test_paths'].add(ordinary);
        evidence['test_evidence'][ordinary] = testProof(source);
        for (final axis in [
          'compiled_grammar_acceptance',
          'compiled_grammar_rejection',
        ]) {
          evidence['structured_output_evidence']['coverage'][axis] = [ordinary];
        }
        final result = await evaluate();
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains('compiled production grammar test'));
      },
    );

    test(
      'Genkit test and production paths bind exact-head evidence without bypasses',
      () async {
        const source =
            'packages/genkit_llamadart/lib/src/core/runtime/engine_registry.dart';
        const target =
            'packages/genkit_llamadart/test/core/runtime/engine_registry/reuse_test.dart';
        final evidence =
            jsonDecode(
                  jsonEncode(backendEvidence())
                      .replaceAll(backendSource, source)
                      .replaceAll(backendTest, target),
                )
                as Map<String, dynamic>;
        final changes = [
          const RepositoryChange(
            path: source,
            kind: RepositoryChangeKind.modified,
          ),
          const RepositoryChange(
            path: target,
            kind: RepositoryChangeKind.added,
          ),
        ];
        Future<HighRiskReadinessResult> evaluate() => evaluatorFor(
          changes,
          existingPaths: {source, target, backendSource},
        ).evaluate(evidence: evidence, context: context);
        expect(
          (await evaluate()).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
        evidence['test_evidence'][target]['production_refs'] = productionRefs(
          backendSource,
        );
        final disconnected = await evaluate();
        expect(disconnected.decision, ReadinessDecision.rejected);
        expect(disconnected.message, contains('disconnected'));
        evidence['test_evidence'][target]['production_refs'] = productionRefs(
          source,
        );
        evidence['test_evidence'][target]['control_result'] = 'pass';
        expect((await evaluate()).decision, ReadinessDecision.rejected);
      },
    );

    test(
      'workflow changes bind tooling tests to the changed workflow',
      () async {
        const workflow = '.github/workflows/ci.yml';
        const otherWorkflow = '.github/workflows/docs_pages.yml';
        const target = 'test/unit/tooling/ci_workflow_selection_test.dart';
        final evidence = backendEvidence()
          ..['surfaces'] = ['regressionPolicy']
          ..['affected_test_paths'] = [target];
        final proof = testProof(workflow);
        evidence['test_evidence'] = {target: proof};
        var changes = const [
          RepositoryChange(path: workflow, kind: RepositoryChangeKind.modified),
        ];
        Future<HighRiskReadinessResult> evaluate() => evaluatorFor(
          changes,
          existingPaths: {workflow, otherWorkflow, target, backendSource},
        ).evaluate(evidence: evidence, context: context);

        expect(
          (await evaluate()).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );

        for (final unrelated in [otherWorkflow, backendSource]) {
          proof['production_refs'] = productionRefs(unrelated);
          final result = await evaluate();
          expectFailure(
            result,
            ReadinessFailureClassification.missingStructuredOutputEvidence,
          );
          expect(result.message, contains('disconnected'), reason: unrelated);
        }

        changes = const [
          RepositoryChange(path: workflow, kind: RepositoryChangeKind.modified),
          RepositoryChange(
            path: backendSource,
            kind: RepositoryChangeKind.modified,
          ),
        ];
        evidence['surfaces'] = ['backendRuntime', 'regressionPolicy'];
        final result = await evaluate();
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains('lack reviewed test reachability'));
        proof['production_refs'] = [
          ...productionRefs(workflow),
          ...productionRefs(backendSource),
        ];
        expect(
          (await evaluate()).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
      },
    );

    test(
      'composite action changes bind tooling tests to the changed action',
      () async {
        const action = '.github/actions/companion-package/action.yml';
        const otherAction = '.github/actions/other/action.yml';
        const target = 'test/unit/tooling/ci_workflow_selection_test.dart';
        final evidence = backendEvidence()
          ..['surfaces'] = ['regressionPolicy']
          ..['affected_test_paths'] = [target];
        final proof = testProof(action);
        evidence['test_evidence'] = {target: proof};
        Future<HighRiskReadinessResult> evaluate() => evaluatorFor(
          const [
            RepositoryChange(path: action, kind: RepositoryChangeKind.modified),
          ],
          existingPaths: {action, otherAction, target, backendSource},
        ).evaluate(evidence: evidence, context: context);

        expect(
          (await evaluate()).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );

        for (final unrelated in [otherAction, backendSource]) {
          proof['production_refs'] = productionRefs(unrelated);
          final result = await evaluate();
          expectFailure(
            result,
            ReadinessFailureClassification.missingStructuredOutputEvidence,
          );
          expect(result.message, contains('disconnected'), reason: unrelated);
        }
      },
    );

    test('production refs admit no non-workflow policy paths', () async {
      for (final path in [
        '.github/CODEOWNERS',
        '.github/pull_request_template.md',
        '.github/workflows_backup/ci.yml',
        '.github/actions_backup/companion-package/action.yml',
        '.github/actions/../CODEOWNERS',
        '.github/workflows/../CODEOWNERS',
        'packages/genkit_llamadart/.github/check_docs.py',
        'scripts/release/publish.sh',
        'doc/high_risk_pre_merge_readiness.md',
        'AGENTS.md',
      ]) {
        final evidence = backendEvidence()..['surfaces'] = ['regressionPolicy'];
        evidence['test_evidence'][backendTest]['production_refs'] =
            productionRefs(path);
        final result = await evaluatorFor(
          [
            ...backendChanges,
            RepositoryChange(path: path, kind: RepositoryChangeKind.modified),
          ],
          existingPaths: {backendSource, backendTest, path},
        ).evaluate(evidence: evidence, context: context);
        expectFailure(result, ReadinessFailureClassification.schemaViolation);
        expect(result.message, 'Invalid production reference.', reason: path);
      }
    });

    test(
      'native-sync Python suites bind to their paired script and command',
      () async {
        const source = 'tool/native/sync_native_release_pins.py';
        const target = 'tool/native/test_sync_native_release_pins.py';
        const otherSource = 'tool/native/native_header_archive.py';
        const otherTarget = 'tool/native/test_native_header_archive.py';
        final evidence =
            jsonDecode(
                  jsonEncode(backendEvidence())
                      .replaceAll(backendSource, source)
                      .replaceAll(backendTest, target),
                )
                as Map<String, dynamic>;
        evidence['surfaces'] = ['artifactConsumer'];
        final proof = evidence['test_evidence'][target] as Map<String, dynamic>;
        var changes = const [
          RepositoryChange(path: source, kind: RepositoryChangeKind.modified),
        ];
        var existingPaths = {source, target, otherSource, otherTarget};
        Future<HighRiskReadinessResult> evaluate() => evaluatorFor(
          changes,
          existingPaths: existingPaths,
        ).evaluate(evidence: evidence, context: context);

        for (final command in [
          'python3 $target',
          'python3 -m unittest '
              'tool.native.test_sync_native_release_pins.SyncNativeReleasePinsTest',
        ]) {
          proof['command'] = command;
          expect(
            (await evaluate()).decision,
            ReadinessDecision.unverifiedPrerequisites,
            reason: command,
          );
        }

        proof['command'] = 'python3 $otherTarget';
        var result = await evaluate();
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains(target));

        proof['command'] = 'python3 $target';
        proof['control_result'] = 'pass';
        expect((await evaluate()).decision, ReadinessDecision.rejected);
        proof['control_result'] = 'fail';

        existingPaths = {source, otherSource, otherTarget};
        expectFailure(
          await evaluate(),
          ReadinessFailureClassification.missingTestPath,
        );
        existingPaths = {source, target, otherSource, otherTarget};

        changes = const [
          RepositoryChange(
            path: otherSource,
            kind: RepositoryChangeKind.modified,
          ),
        ];
        proof['production_refs'] = productionRefs(otherSource);
        result = await evaluate();
        expectFailure(
          result,
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
        expect(result.message, contains(target));
      },
    );

    const nativeSyncSuites = {
      'tool/native/test_native_header_archive.py':
          'tool/native/native_header_archive.py',
      'tool/native/test_sync_native_headers_and_bindings.py':
          'tool/native/sync_native_headers_and_bindings.sh',
      'tool/native/test_sync_native_release_pins.py':
          'tool/native/sync_native_release_pins.py',
      'tool/native/test_sync_stable_diffusion_bindings.py':
          'tool/native/sync_stable_diffusion_bindings.py',
    };
    for (final MapEntry(key: suite, value: script)
        in nativeSyncSuites.entries) {
      test('$suite binds only to $script, in any production_refs', () async {
        final others = nativeSyncSuites.values
            .where((other) => other != script)
            .toList();
        final evidence = backendEvidence()
          ..['surfaces'] = ['artifactConsumer']
          ..['affected_test_paths'] = [suite];
        final proof = testProof(script)..['command'] = 'python3 $suite';
        evidence['test_evidence'] = {suite: proof};
        Future<HighRiskReadinessResult> evaluate(
          List<String> changed,
        ) => evaluatorFor(
          [
            for (final path in changed)
              RepositoryChange(path: path, kind: RepositoryChangeKind.modified),
          ],
          existingPaths: {...nativeSyncSuites.keys, ...nativeSyncSuites.values},
        ).evaluate(evidence: evidence, context: context);

        expect(
          (await evaluate([script])).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
        proof['production_refs'] = [
          ...productionRefs(script),
          ...productionRefs(others[0]),
        ];
        expect(
          (await evaluate([script, others[0]])).decision,
          ReadinessDecision.unverifiedPrerequisites,
        );
        for (final refs in [
          [others[0]],
          [others[0], others[1]],
        ]) {
          proof['production_refs'] = [
            for (final path in refs) ...productionRefs(path),
          ];
          final result = await evaluate(refs);
          expectFailure(
            result,
            ReadinessFailureClassification.missingStructuredOutputEvidence,
          );
          expect(result.message, contains(script), reason: '$refs');
        }
      });
    }

    test('release-auth suite keeps helper and command pairing', () async {
      const source = 'tool/release/nonpublishing_auth_probe.py';
      const target = 'test/ci/test_nonpublishing_auth_probe.py';
      const unrelated = 'tool/native/native_header_archive.py';
      final evidence = backendEvidence()
        ..['surfaces'] = ['releaseAutomation']
        ..['affected_test_paths'] = [target];
      final proof = testProof(source);
      evidence['test_evidence'] = {target: proof};
      Future<HighRiskReadinessResult> evaluate() => evaluatorFor(
        const [
          RepositoryChange(path: source, kind: RepositoryChangeKind.modified),
        ],
        existingPaths: {source, target, unrelated},
      ).evaluate(evidence: evidence, context: context);

      for (final command in [
        'python3 -B $target',
        'python3 -B -m unittest test.ci.test_nonpublishing_auth_probe',
      ]) {
        proof['command'] = command;
        expect(
          (await evaluate()).decision,
          ReadinessDecision.unverifiedPrerequisites,
          reason: command,
        );
      }

      proof['command'] = 'python3 tool/native/test_native_header_archive.py';
      expectFailure(
        await evaluate(),
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
      proof['command'] = 'python3 -B $target';
      proof['production_refs'] = productionRefs(unrelated);
      expectFailure(
        await evaluate(),
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );
      proof['production_refs'] = productionRefs(source);
      proof['control_result'] = 'pass';
      expect((await evaluate()).decision, ReadinessDecision.rejected);
    });

    test('rejects Python paths outside the explicitly paired suites', () async {
      for (final path in [
        'tool/native/sync_native_release_pins.py',
        'tool/native/test_unlisted_suite.py',
        'tool/native/fixtures/test_sync_native_release_pins.py',
        'tool/testing/validation/test_npu_apk.py',
        'test/ci/test_workflow.py',
        'test/ci/test_nonpublishing_auth_probe_extra.py',
        'test/ci/fixtures/test_nonpublishing_auth_probe.py',
        'test/ci/../ci/test_nonpublishing_auth_probe.py',
        'test/unit/tooling/sync_native_release_pins_test.py',
      ]) {
        final evidence = backendEvidence()..['affected_test_paths'] = [path];
        evidence['test_evidence'] = {path: testProof(backendSource)};
        expectFailure(
          await evaluatorFor(
            [backendChanges.first],
            existingPaths: {backendSource, path},
          ).evaluate(evidence: evidence, context: context),
          ReadinessFailureClassification.nonTestPathCited,
        );
      }
    });

    test(
      'rejects traversal, absolute, non-test, and tool script paths',
      () async {
        for (final path in [
          '../test/escape_test.dart',
          'packages/other/test/escape_test.dart',
          'packages/genkit_llamadart/lib/not_a_test.dart',
          'packages/genkit_llamadart/test/../lib/escape_test.dart',
          'packages/genkit_llamadart/test/unit/*_test.dart',
          'packages/llamadart_validation/test/../lib/reuse_test.dart',
          'packages/llamadart_validation/test/unit/*_test.dart',
          '/test/absolute_test.dart',
          'test/../test/escape_test.dart',
          'lib/readme.dart',
          'tool/scripts/not_a_test.sh',
          'test/unit/not_a_test.dart.txt',
          'test/unit/backends/bad\u0000name_test.dart',
          'test/unit/backends/bad\nname_test.dart',
          'test/unit/backends/*_test.dart',
          'test/unit/backends/model?_test.dart',
          'test/unit/backends/[ab]_test.dart',
        ]) {
          final evidence = backendEvidence()..['affected_test_paths'] = [path];
          final changes = path.contains('\u0000')
              ? backendChanges
              : <RepositoryChange>[
                  backendChanges.first,
                  RepositoryChange(
                    path: path,
                    kind: RepositoryChangeKind.modified,
                  ),
                ];
          expectFailure(
            await evaluatorFor(
              changes,
            ).evaluate(evidence: evidence, context: context),
            ReadinessFailureClassification.nonTestPathCited,
          );
        }
      },
    );

    test('rejects absent, deleted, renamed-old, and phantom paths', () async {
      expectFailure(
        await evaluatorFor([
          backendChanges.first,
        ]).evaluate(evidence: backendEvidence(), context: context),
        ReadinessFailureClassification.missingTestPath,
      );

      expectFailure(
        await evaluatorFor(const [
          RepositoryChange(
            path: 'lib/src/backends/example_backend.dart',
            kind: RepositoryChangeKind.modified,
          ),
          RepositoryChange(
            path: backendTest,
            kind: RepositoryChangeKind.deleted,
          ),
        ]).evaluate(evidence: backendEvidence(), context: context),
        ReadinessFailureClassification.deletedEvidencePath,
      );

      final renamed = backendEvidence()
        ..['affected_test_paths'] = [
          'test/unit/backends/old_backend_test.dart',
        ];
      expectFailure(
        await evaluatorFor(const [
          RepositoryChange(
            path: 'lib/src/backends/example_backend.dart',
            kind: RepositoryChangeKind.modified,
          ),
          RepositoryChange(
            path: backendTest,
            previousPath: 'test/unit/backends/old_backend_test.dart',
            kind: RepositoryChangeKind.renamed,
          ),
        ]).evaluate(evidence: renamed, context: context),
        ReadinessFailureClassification.renamedEvidencePath,
      );

      expectFailure(
        await evaluatorFor(
          backendChanges,
          existingPaths: {'lib/src/backends/example_backend.dart'},
        ).evaluate(evidence: backendEvidence(), context: context),
        ReadinessFailureClassification.missingTestPath,
      );
    });

    test('does not treat a copy source as the old side of a rename', () async {
      final result = await evaluatorFor(const [
        RepositoryChange(
          path: 'lib/src/backends/example_backend.dart',
          kind: RepositoryChangeKind.modified,
        ),
        RepositoryChange(
          path: backendTest,
          kind: RepositoryChangeKind.modified,
        ),
        RepositoryChange(
          path: 'test/unit/backends/copied_backend_test.dart',
          previousPath: backendTest,
          kind: RepositoryChangeKind.copied,
        ),
      ]).evaluate(evidence: backendEvidence(), context: context);

      expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
    });

    test(
      'serializes a fail-closed result when the tree probe errors',
      () async {
        final result = await evaluatorFor(
          backendChanges,
          pathProbeThrows: true,
        ).evaluate(evidence: backendEvidence(), context: context);

        expectFailure(result, ReadinessFailureClassification.gitExecutionError);
        expect(() => jsonEncode(result.toJson()), returnsNormally);
      },
    );
  });

  group('exact root ffigen config evidence', () {
    const config = 'ffigen.yaml';
    const target =
        'test/unit/tooling/native_bindings_generator_policy_test.dart';
    const caseName =
        'repo policy keeps pointer-only libc FILE opaque and its alias usable';
    const callsite =
        "jsonDecode(jsonEncode(loadYaml(File('ffigen.yaml').readAsStringSync())))";
    const configSnippet = 'name: LlamaCpp';
    const changes = [
      RepositoryChange(path: config, kind: RepositoryChangeKind.modified),
      RepositoryChange(path: target, kind: RepositoryChangeKind.added),
    ];

    Map<String, dynamic> evidenceFor([String testPath = target]) {
      final evidence = backendEvidence()
        ..['surfaces'] = ['artifactConsumer']
        ..['affected_test_paths'] = [testPath];
      evidence['test_evidence'] = {
        testPath: testProof(config)
          ..['test_case'] = caseName
          ..['test_snippet'] = callsite
          ..['production_refs'] = [
            {'path': config, 'snippet': configSnippet},
          ]
          ..['command'] = 'dart test -p vm $testPath',
      };
      return evidence;
    }

    Future<HighRiskReadinessResult> evaluate(
      Map<String, dynamic> evidence, {
      List<RepositoryChange> inventory = changes,
      Map<String, ReadinessFile>? headFiles,
      Set<String> missingHeadPaths = const {},
    }) {
      final files = <String, ReadinessFile>{
        config: (mode: '100644', contents: '$configSnippet\n'),
        for (final path in [
          target,
          backendTest,
          'test/ci/test_nonpublishing_auth_probe.py',
        ])
          path: (mode: '100644', contents: '$caseName\n$callsite'),
        backendSource: (mode: '100644', contents: 'productionCall();'),
        'tool/native/sync_native_headers_and_bindings.sh': (
          mode: '100755',
          contents: 'productionCall();',
        ),
        ...?headFiles,
      };
      for (final path in missingHeadPaths) {
        files.remove(path);
      }
      return HighRiskReadinessEvaluator(
        repositoryState: FakeRepositoryState(
          changes: inventory,
          existingPaths: files.keys.toSet(),
          files: {
            baseSha: {config: (mode: '100644', contents: '$configSnippet\n')},
            headSha: files,
          },
        ),
        clock: () => DateTime.utc(2026, 8, 28, 13),
      ).evaluate(evidence: evidence, context: context);
    }

    test('paired ffigen config preserves causal and external gates', () async {
      final result = await evaluate(evidenceFor());
      expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
      expect(result.isReady, isFalse);
      final evaluation = result.toJson()['evaluation'] as Map;
      final external = evaluation['external_prerequisites'] as Map;
      for (final key in [
        'app_installed',
        'protected_environment_configured',
        'independent_auditor_authenticated',
        'ruleset_enforced',
      ]) {
        expect(external[key], isFalse);
      }
      final failedControl = evidenceFor();
      failedControl['test_evidence'][target]['control_result'] = 'pass';
      expectFailure(
        await evaluate(failedControl),
        ReadinessFailureClassification.schemaViolation,
      );
    });

    test('ffigen config rejects unpaired Dart and Python evidence', () async {
      for (final testPath in [
        backendTest,
        'test/ci/test_nonpublishing_auth_probe.py',
      ]) {
        final result = await evaluate(evidenceFor(testPath));
        expect(result.decision, ReadinessDecision.rejected);
        expect(result.message, contains('must pair only'), reason: testPath);
      }
    });

    test(
      'ffigen policy test cannot substitute or append an uncalled producer',
      () async {
        for (final refs in [
          productionRefs('tool/native/sync_native_headers_and_bindings.sh'),
          [
            {'path': config, 'snippet': configSnippet},
            ...productionRefs(backendSource),
          ],
        ]) {
          final evidence = evidenceFor();
          evidence['test_evidence'][target]['production_refs'] = refs;
          final result = await evaluate(evidence);
          expect(result.decision, ReadinessDecision.rejected);
          expect(result.message, contains('must pair only'));
        }
      },
    );

    test(
      'changed ffigen config cannot omit its paired causal record',
      () async {
        final evidence = evidenceFor(backendTest);
        evidence['test_evidence'][backendTest] = testProof(backendSource);
        final result = await evaluate(
          evidence,
          headFiles: {
            backendTest: (
              mode: '100644',
              contents: 'regression case\nproductionCall();',
            ),
          },
        );
        expect(result.decision, ReadinessDecision.rejected);
        expect(result.message, contains('disconnected'));
      },
    );

    test(
      'ffigen config and consumer snippets bind the exact candidate blobs',
      () async {
        for (final file in [config, target]) {
          final result = await evaluate(
            evidenceFor(),
            headFiles: {
              file: (mode: '100644', contents: 'unrelated head blob'),
            },
          );
          expect(result.decision, ReadinessDecision.rejected, reason: file);
        }
        final wrongSnippet = evidenceFor();
        wrongSnippet['test_evidence'][target]['production_refs'][0]['snippet'] =
            'invented config';
        expect(
          (await evaluate(wrongSnippet)).decision,
          ReadinessDecision.rejected,
        );
      },
    );

    test('ffigen config requires a current regular head blob', () async {
      expect(
        (await evaluate(evidenceFor(), missingHeadPaths: {config})).decision,
        ReadinessDecision.rejected,
      );
      for (final file in [
        (mode: '120000', contents: '$configSnippet\n'),
        (mode: '100644', contents: ''),
      ]) {
        expect(
          (await evaluate(evidenceFor(), headFiles: {config: file})).decision,
          ReadinessDecision.rejected,
        );
      }
      for (final change in [
        const RepositoryChange(
          path: config,
          kind: RepositoryChangeKind.deleted,
        ),
        const RepositoryChange(
          path: 'retired-ffigen.yaml',
          previousPath: config,
          kind: RepositoryChangeKind.renamed,
        ),
      ]) {
        final result = await evaluate(
          evidenceFor(),
          inventory: [change, changes.last],
        );
        expect(result.decision, ReadinessDecision.rejected);
        expect(result.message, contains('current root config'));
      }
    });

    test(
      'root config pairing admits no lookalikes or non-production policy refs',
      () async {
        for (final path in [
          'ffigen.yml',
          'ffigen.yaml.backup',
          'nested/ffigen.yaml',
          'analysis_options.yaml',
          'dart_test.yaml',
          '.github/CODEOWNERS',
        ]) {
          final evidence = evidenceFor();
          evidence['test_evidence'][target]['production_refs'] = [
            {'path': path, 'snippet': configSnippet},
          ];
          final result = await evaluate(evidence);
          expectFailure(result, ReadinessFailureClassification.schemaViolation);
          expect(result.message, 'Invalid production reference.', reason: path);
        }
      },
    );
  });

  group('private harness evidence admission', () {
    const source = 'packages/llamadart_validation/lib/src/tokenization.dart';
    const registry =
        'packages/llamadart_validation/assets/capability_coverage.json';
    const target = 'packages/llamadart_validation/test/tokenization_test.dart';
    const tooling = 'test/unit/tooling/validation_coverage_test.dart';
    const changes = [
      RepositoryChange(path: source, kind: RepositoryChangeKind.modified),
      RepositoryChange(path: registry, kind: RepositoryChangeKind.modified),
      RepositoryChange(path: target, kind: RepositoryChangeKind.added),
    ];

    Map<String, dynamic> evidenceFor(String testPath) {
      final evidence = backendEvidence()..['affected_test_paths'] = [testPath];
      evidence['test_evidence'] = {
        testPath: testProof(source)
          ..['production_refs'] = [
            ...productionRefs(source),
            {'path': registry, 'snippet': '"schema_version": 1'},
          ],
      };
      return evidence;
    }

    Future<HighRiskReadinessResult> evaluate(
      Map<String, dynamic> evidence, {
      List<RepositoryChange> inventory = changes,
      Set<String>? existingPaths,
      Map<String, ReadinessFile>? headFiles,
    }) {
      final files = <String, ReadinessFile>{
        source: (mode: '100644', contents: 'productionCall();'),
        registry: (mode: '100644', contents: '{"schema_version": 1}'),
        for (final path in [target, tooling, backendTest])
          path: (
            mode: '100644',
            contents: 'regression case\nproductionCall();',
          ),
        backendSource: (mode: '100644', contents: 'productionCall();'),
        'packages/genkit_llamadart/test/registry_test.dart': (
          mode: '100644',
          contents: 'regression case\nproductionCall();',
        ),
        ...?headFiles,
      };
      return HighRiskReadinessEvaluator(
        repositoryState: FakeRepositoryState(
          changes: inventory,
          existingPaths: existingPaths ?? files.keys.toSet(),
          files: {headSha: files},
        ),
        clock: () => DateTime.utc(2026, 8, 28, 13),
      ).evaluate(evidence: evidence, context: context);
    }

    for (final testPath in [target, tooling]) {
      test(
        'private harness paired $testPath keeps local prerequisites',
        () async {
          final result = await evaluate(evidenceFor(testPath));
          expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
        },
      );
    }

    test('private harness CLI reads exact Git blobs and exits 2', () async {
      final fixtureWatch = Stopwatch()..start();
      print('readiness CLI fixture: Git setup started');
      final repo = Directory.systemTemp.createTempSync(
        'harness-readiness-git-',
      );
      addTearDown(() => repo.deleteSync(recursive: true));
      String git(List<String> args) {
        final result = Process.runSync(
          'git',
          args,
          workingDirectory: repo.path,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return (result.stdout as String).trim();
      }

      void write(String path, String contents) {
        File('${repo.path}/$path')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(contents);
      }

      git(['init', '--quiet']);
      git(['config', 'user.name', 'Harness test']);
      git(['config', 'user.email', 'harness@example.invalid']);
      write(source, 'productionCall();');
      write(registry, '{"schema_version": 0}');
      write(target, 'regression case\nproductionCall();');
      git(['add', '.']);
      git(['commit', '--quiet', '-m', 'base']);
      final base = git(['rev-parse', 'HEAD']);
      write(registry, '{"schema_version": 1}');
      git(['add', '.']);
      git(['commit', '--quiet', '-m', 'registry']);
      final head = git(['rev-parse', 'HEAD']);
      final evidence = evidenceFor(target)
        ..['expected_pr_head_sha'] = head
        ..['current_base_sha'] = base;
      evidence['independent_audit']['audit_head_sha'] = head;
      evidence['independent_audit']['audit_base_sha'] = base;
      final evidenceFile = File('${repo.path}/evidence.json');
      final script = File(
        'tool/testing/high_risk_readiness.dart',
      ).absolute.path;
      print(
        'readiness CLI fixture: Git setup ${fixtureWatch.elapsedMilliseconds} ms',
      );
      Future<ProcessResult> stage(
        String name,
        List<String> arguments,
        Duration budget, {
        String? workingDirectory,
      }) async {
        final watch = Stopwatch()..start();
        print(
          'readiness CLI $name started (child budget ${budget.inSeconds} s)',
        );
        try {
          return await runBoundedProcess(
            Platform.resolvedExecutable,
            arguments,
            timeout: budget,
            workingDirectory: workingDirectory,
          );
        } finally {
          print('readiness CLI $name elapsed ${watch.elapsedMilliseconds} ms');
        }
      }

      // Compile the analyzer dependency once instead of paying for two cold
      // source launches. Each child has a deadline below this test's total cap.
      final kernel = '${repo.path}/readiness.dill';
      final compiled = await stage('compile', [
        'compile',
        'kernel',
        script,
        '-o',
        kernel,
      ], const Duration(seconds: 60));
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      Future<ProcessResult> run(String name, {String? author}) {
        evidenceFile.writeAsStringSync(jsonEncode(evidence));
        return stage(
          name,
          [
            kernel,
            '--evidence',
            evidenceFile.path,
            '--repository',
            context.repository,
            '--pr-number',
            '${context.prNumber}',
            '--head-sha',
            head,
            '--base-sha',
            base,
            '--pr-author',
            author ?? context.author,
          ],
          const Duration(seconds: 15),
          workingDirectory: repo.path,
        );
      }

      // Working-tree edits cannot replace either cited committed blob.
      write(registry, '{"schema_version": 2}');
      write(target, 'invented working-tree case');
      final accepted = await run('committed blobs');
      expect(
        accepted.exitCode,
        2,
        reason: '${accepted.stdout}\n${accepted.stderr}',
      );
      final output = jsonDecode(accepted.stdout as String) as Map;
      expect(output['evaluation']['decision'], 'unverifiedPrerequisites');
      evidence['pr_author'] = 'github-actions[bot]';
      final bot = await run(
        'canonical bot author',
        author: 'github-actions[bot]',
      );
      expect(bot.exitCode, 2, reason: '${bot.stdout}\n${bot.stderr}');
      final botOutput = jsonDecode(bot.stdout as String) as Map;
      expect(botOutput['pr_author'], 'github-actions[bot]');
      expect(botOutput['evaluation']['decision'], 'unverifiedPrerequisites');
      evidence['pr_author'] = context.author;
      final refs = evidence['test_evidence'][target]['production_refs'] as List;
      refs.last['snippet'] = '"schema_version": 2';
      final rejected = await run('forged snippet');
      expect(
        rejected.exitCode,
        1,
        reason: '${rejected.stdout}\n${rejected.stderr}',
      );
      expect(rejected.stdout, contains('disconnected'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'private harness registry requires exact candidate JSON snippet',
      () async {
        final evidence = evidenceFor(tooling);
        final refs =
            evidence['test_evidence'][tooling]['production_refs'] as List;
        refs.last['snippet'] = '"schema_version": 2';
        final result = await evaluate(evidence);
        expect(result.decision, ReadinessDecision.rejected);
        expect(result.message, contains('disconnected'));
      },
    );

    test('private harness source and test snippets bind exact head', () async {
      for (final path in [source, target]) {
        final result = await evaluate(
          evidenceFor(target),
          headFiles: {path: (mode: '100644', contents: 'different candidate')},
        );
        expect(result.decision, ReadinessDecision.rejected, reason: path);
      }
    });

    test(
      'private harness changed production requires complete coverage',
      () async {
        final evidence = evidenceFor(target);
        (evidence['test_evidence'][target]['production_refs'] as List)
            .removeLast();
        final result = await evaluate(evidence);
        expect(result.decision, ReadinessDecision.rejected);
        expect(result.message, contains('lack reviewed test reachability'));
      },
    );

    test(
      'private harness rejects core and cross-package test substitutions',
      () async {
        for (final testPath in [
          backendTest,
          'packages/genkit_llamadart/test/registry_test.dart',
        ]) {
          final result = await evaluate(evidenceFor(testPath));
          expect(result.decision, ReadinessDecision.rejected, reason: testPath);
          expect(result.message, contains('paired'));
        }
        final evidence = evidenceFor(target);
        (evidence['test_evidence'][target]['production_refs'] as List).addAll(
          productionRefs(backendSource),
        );
        final result = await evaluate(evidence);
        expect(result.decision, ReadinessDecision.rejected);
        expect(result.message, contains('paired'));
      },
    );

    test(
      'private harness admission excludes other packages and assets',
      () async {
        for (final path in [
          'packages/other/lib/runtime.dart',
          'packages/llamadart_validation_extra/lib/runtime.dart',
          'packages/llamadart_validation/assets/profiles.json',
          'packages/llamadart_validation/assets/capability_coverage.json.backup',
          'packages/llamadart_validation/lib/../assets/profiles.json',
        ]) {
          final evidence = evidenceFor(target);
          (evidence['test_evidence'][target]['production_refs'] as List).addAll(
            productionRefs(path),
          );
          final result = await evaluate(evidence);
          expectFailure(result, ReadinessFailureClassification.schemaViolation);
          expect(result.message, 'Invalid production reference.', reason: path);
        }
      },
    );

    test(
      'private harness rejects deleted renamed-old and phantom tests',
      () async {
        final evidence = evidenceFor(target);
        for (final (inventory, paths, failure) in [
          (
            [
              ...changes.take(2),
              const RepositoryChange(
                path: target,
                kind: RepositoryChangeKind.deleted,
              ),
            ],
            {source, registry, target},
            ReadinessFailureClassification.deletedEvidencePath,
          ),
          (
            [
              ...changes.take(2),
              const RepositoryChange(
                path: 'packages/llamadart_validation/test/renamed_test.dart',
                previousPath: target,
                kind: RepositoryChangeKind.renamed,
              ),
            ],
            {source, registry, target},
            ReadinessFailureClassification.renamedEvidencePath,
          ),
          (
            changes,
            {source, registry},
            ReadinessFailureClassification.missingTestPath,
          ),
        ]) {
          expectFailure(
            await evaluate(
              evidence,
              inventory: inventory,
              existingPaths: paths,
            ),
            failure,
          );
        }
      },
    );

    test(
      'private harness keeps causal audit and head binding requirements',
      () async {
        for (final mutate in <void Function(Map<String, dynamic>)>[
          (evidence) =>
              evidence['test_evidence'][target]['control_result'] = 'pass',
          (evidence) => evidence['independent_audit']['auditor_identity'] =
              context.author,
          (evidence) => evidence['expected_pr_head_sha'] = otherSha,
        ]) {
          final evidence = evidenceFor(target);
          mutate(evidence);
          expect(
            (await evaluate(evidence)).decision,
            ReadinessDecision.rejected,
          );
        }
      },
    );
  });

  group('structured-output production proof', () {
    test('requires every explicit coverage axis and family evidence', () async {
      final missingAxis = structuredEvidence();
      ((missingAxis['structured_output_evidence']
                  as Map<String, dynamic>)['coverage']
              as Map<String, dynamic>)
          .remove('streaming_rollback');
      expectFailure(
        await evaluateStructured(missingAxis),
        ReadinessFailureClassification.schemaViolation,
      );

      final emptyAxis = structuredEvidence();
      ((emptyAxis['structured_output_evidence']
                  as Map<String, dynamic>)['coverage']
              as Map<String, dynamic>)['tool_choice_thinking'] =
          <String>[];
      expectFailure(
        await evaluateStructured(emptyAxis),
        ReadinessFailureClassification.missingStructuredOutputEvidence,
      );

      final noFamilies = structuredEvidence();
      (noFamilies['structured_output_evidence']
              as Map<String, dynamic>)['families'] =
          <dynamic>[];
      expectFailure(
        await evaluateStructured(noFamilies),
        ReadinessFailureClassification.schemaViolation,
      );
    });

    test(
      'requires compiled acceptance and rejection production tests',
      () async {
        const ordinaryTest =
            'test/unit/core/template/example_handler_test.dart';
        final evidence = structuredEvidence();
        evidence['affected_test_paths'] = [ordinaryTest];
        evidence['test_evidence'] = {ordinaryTest: testProof(structuredSource)};
        final coverage =
            (evidence['structured_output_evidence']
                    as Map<String, dynamic>)['coverage']
                as Map<String, dynamic>;
        for (final key in coverage.keys) {
          coverage[key] = [ordinaryTest];
        }
        ((evidence['structured_output_evidence']
                    as Map<String, dynamic>)['families']
                as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .single['evidence_test_paths'] = [
          ordinaryTest,
        ];
        expectFailure(
          await evaluateStructured(
            evidence,
            changes: const [
              RepositoryChange(
                path: 'lib/src/core/template/chat_template_handler.dart',
                kind: RepositoryChangeKind.modified,
              ),
              RepositoryChange(
                path: ordinaryTest,
                kind: RepositoryChangeKind.modified,
              ),
            ],
          ),
          ReadinessFailureClassification.missingStructuredOutputEvidence,
        );
      },
    );

    test(
      'rejects coverage and family paths outside cited affected tests',
      () async {
        const otherTest = 'test/unit/core/template/other_handler_test.dart';
        final axis = structuredEvidence();
        (((axis['structured_output_evidence']
                        as Map<String, dynamic>)['coverage']
                    as Map<String, dynamic>)['streaming_rollback']
                as List<dynamic>)
            .add(otherTest);
        expectFailure(
          await evaluateStructured(axis),
          ReadinessFailureClassification.unchangedEvidencePath,
        );

        final family = structuredEvidence();
        ((((family['structured_output_evidence']
                                as Map<String, dynamic>)['families']
                            as List<dynamic>)
                        .single
                    as Map<String, dynamic>)['evidence_test_paths']
                as List<dynamic>)
            .add(otherTest);
        expectFailure(
          await evaluateStructured(family),
          ReadinessFailureClassification.unchangedEvidencePath,
        );
      },
    );

    test(
      'accepts explicit unavailable-family semantics but stays unverified',
      () async {
        final evidence = structuredEvidence();
        final family =
            ((evidence['structured_output_evidence']
                            as Map<String, dynamic>)['families']
                        as List<dynamic>)
                    .single
                as Map<String, dynamic>;
        family['status'] = 'unavailable';
        family['rationale'] =
            'Exact weights unavailable; primary upstream fixture is covered.';
        final result = await evaluateStructured(evidence);
        expect(result.decision, ReadinessDecision.unverifiedPrerequisites);
      },
    );

    test('rejects duplicate affected-family names', () async {
      final evidence = structuredEvidence();
      final families =
          (evidence['structured_output_evidence']
                  as Map<String, dynamic>)['families']
              as List<dynamic>;
      final duplicate = Map<String, Object>.from(
        families.single as Map,
      )..['rationale'] = 'A duplicate family cannot stand in for completeness.';
      families.add(duplicate);

      expectFailure(
        await evaluateStructured(evidence),
        ReadinessFailureClassification.schemaViolation,
      );
    });
  });

  group('standard-risk diagnostic and schema/serializer parity', () {
    test(
      'standard risk remains non-ready and needs no high-risk evidence',
      () async {
        final result = await evaluatorFor(const [
          RepositoryChange(
            path: 'website/docs/guides/example.md',
            kind: RepositoryChangeKind.modified,
          ),
        ]).evaluate(evidence: standardEvidence(), context: context);
        expect(result.decision, ReadinessDecision.standardRiskDiagnostic);
        expect(
          result.failureClassification,
          ReadinessFailureClassification.none,
        );
        expect(result.isReady, isFalse);
      },
    );

    test('standard diff rejects high-risk classification and claims', () async {
      expectFailure(
        await evaluatorFor(const [
          RepositoryChange(
            path: 'website/docs/guides/example.md',
            kind: RepositoryChangeKind.modified,
          ),
        ]).evaluate(evidence: backendEvidence(), context: context),
        ReadinessFailureClassification.classificationMismatch,
      );
    });

    test('standard classification rejects attached high-risk claims', () async {
      final evidence = standardEvidence()
        ..['independent_audit'] = structuredEvidence()['independent_audit'];
      final result = await evaluatorFor(const [
        RepositoryChange(
          path: 'website/docs/guides/example.md',
          kind: RepositoryChangeKind.modified,
        ),
      ]).evaluate(evidence: evidence, context: context);

      expectFailure(result, ReadinessFailureClassification.schemaViolation);
    });

    test('emitted keys and enum values match the canonical schema', () async {
      final output = (await evaluateStructured(structuredEvidence())).toJson();
      final schema =
          jsonDecode(
                File(
                  'tool/testing/high_risk_readiness_evidence.schema.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(output.keys.toSet(), (schema['required'] as List).toSet());
      expect(output.keys.toSet(), (schema['properties'] as Map).keys.toSet());

      final definitions = schema[r'$defs'] as Map<String, dynamic>;
      void expectExactKeys(Map<dynamic, dynamic> value, String definition) {
        final objectSchema = definitions[definition] as Map<String, dynamic>;
        expect(value.keys.toSet(), (objectSchema['required'] as List).toSet());
        expect(
          value.keys.toSet(),
          (objectSchema['properties'] as Map).keys.toSet(),
        );
      }

      expect(
        (schema['properties']
            as Map<String, dynamic>)['surfaces']['items']['enum'],
        HighRiskSurface.values.map((value) => value.name).toList(),
      );
      const matrixRows = <String>[
        'high-risk-exact-head-independent-qa',
        'structured-output-adversarial',
        'release-metadata-verification',
      ];
      expect(
        (schema['properties']
            as Map<
              String,
              dynamic
            >)['required_matrix_row_ids']['items']['enum'],
        matrixRows,
      );
      expect(
        (schema['properties']
            as Map<
              String,
              dynamic
            >)['matrix_row_evidence']['propertyNames']['enum'],
        matrixRows,
      );
      expect(
        (definitions['matrixRow']
            as Map<String, dynamic>)['properties']['row_id']['enum'],
        matrixRows,
      );

      final input = structuredEvidence();
      expectExactKeys(
        input['independent_audit'] as Map<String, dynamic>,
        'independentAudit',
      );
      expect(
        (definitions['independentAudit']
            as Map<String, dynamic>)['properties']['audit_kind']['enum'],
        const ['operator-owned', 'codex-adversarial'],
      );
      final matrixEvidence =
          input['matrix_row_evidence'] as Map<String, dynamic>;
      for (final row in matrixEvidence.values.cast<Map<String, dynamic>>()) {
        expectExactKeys(row, 'matrixRow');
      }
      final structured =
          input['structured_output_evidence'] as Map<String, dynamic>;
      expectExactKeys(structured, 'structuredOutputEvidence');
      final structuredSchema =
          definitions['structuredOutputEvidence'] as Map<String, dynamic>;
      final coverage = structured['coverage'] as Map<String, dynamic>;
      final coverageSchema =
          structuredSchema['properties']['coverage'] as Map<String, dynamic>;
      expect(
        coverage.keys.toSet(),
        (coverageSchema['required'] as List).toSet(),
      );
      expect(
        coverage.keys.toSet(),
        (coverageSchema['properties'] as Map).keys.toSet(),
      );
      final family =
          (structured['families'] as List<dynamic>).single
              as Map<String, dynamic>;
      final familySchema =
          (structuredSchema['properties']['families']['items']
              as Map<String, dynamic>);
      expect(family.keys.toSet(), (familySchema['required'] as List).toSet());
      expect(
        family.keys.toSet(),
        (familySchema['properties'] as Map).keys.toSet(),
      );
      expect(
        (familySchema['properties'] as Map<String, dynamic>)['status']['enum'],
        const ['tested', 'unavailable'],
      );

      final evaluationSchema =
          definitions['evaluation'] as Map<String, dynamic>;
      final evaluationProperties =
          evaluationSchema['properties'] as Map<String, dynamic>;
      final evaluation = output['evaluation'] as Map<String, dynamic>;
      expect(
        evaluation.keys.toSet(),
        (evaluationSchema['required'] as List).toSet(),
      );
      expect(evaluation.keys.toSet(), evaluationProperties.keys.toSet());
      expect(
        (evaluationProperties['decision'] as Map)['enum'],
        ReadinessDecision.values.map((value) => value.name).toList(),
      );
      expect(
        (evaluationProperties['failure_classification'] as Map)['enum'],
        ReadinessFailureClassification.values
            .map((value) => value.name)
            .toList(),
      );
      expect(evaluation['decision'], isNot('ready'));
      final changeSchema =
          definitions['repositoryChange'] as Map<String, dynamic>;
      final changedFiles = evaluation['changed_files'] as List<dynamic>;
      expect(changedFiles, isNotEmpty);
      for (final change in changedFiles.cast<Map<String, dynamic>>()) {
        expect(
          change.keys.toSet(),
          containsAll(changeSchema['required'] as List),
        );
        expect(
          change.keys,
          everyElement(
            isIn((changeSchema['properties'] as Map<String, dynamic>).keys),
          ),
        );
      }
      expect(
        ((changeSchema['properties'] as Map<String, dynamic>)['status']
            as Map<String, dynamic>)['enum'],
        RepositoryChangeKind.values.map((value) => value.name).toList(),
      );

      final prerequisites =
          evaluation['external_prerequisites'] as Map<String, dynamic>;
      expectExactKeys(prerequisites, 'externalPrerequisites');

      final testPathPattern = RegExp(
        (definitions['testPath'] as Map<String, dynamic>)['pattern'] as String,
      );
      expect(testPathPattern.hasMatch(backendTest), isTrue);
      expect(
        testPathPattern.hasMatch(
          'packages/llamadart_validation/test/tokenization_test.dart',
        ),
        isTrue,
      );
      expect(
        testPathPattern.hasMatch(
          'packages/genkit_llamadart/test/core/runtime/reuse_test.dart',
        ),
        isTrue,
      );
      for (final path in [
        'tool/native/test_native_header_archive.py',
        'tool/native/test_sync_native_headers_and_bindings.py',
        'tool/native/test_sync_native_release_pins.py',
        'tool/native/test_sync_stable_diffusion_bindings.py',
        'test/ci/test_nonpublishing_auth_probe.py',
      ]) {
        expect(testPathPattern.hasMatch(path), isTrue, reason: path);
      }
      for (final path in [
        'packages/other/test/reuse_test.dart',
        'packages/genkit_llamadart/test/../lib/reuse_test.dart',
        'packages/genkit_llamadart/test/unit/*_test.dart',
        'packages/llamadart_validation/test/../lib/reuse_test.dart',
        'packages/llamadart_validation/test/unit/*_test.dart',
        'tool/native/sync_native_release_pins.py',
        'tool/native/test_unlisted_suite.py',
        'tool/testing/validation/test_npu_apk.py',
        'test/ci/test_workflow.py',
        'test/ci/test_nonpublishing_auth_probe_extra.py',
        'test/ci/fixtures/test_nonpublishing_auth_probe.py',
        'test/ci/../ci/test_nonpublishing_auth_probe.py',
        'test/unit/tooling/sync_native_release_pins_test.py',
      ]) {
        expect(testPathPattern.hasMatch(path), isFalse, reason: path);
      }
      for (final unsafePath in [
        'test/../escape_test.dart',
        r'test\escape_test.dart',
        'test/bad\u0000name_test.dart',
        'test/bad\nname_test.dart',
        'test/double//slash_test.dart',
        'test/unit/*_test.dart',
        'test/unit/model?_test.dart',
        'test/unit/[ab]_test.dart',
      ]) {
        expect(testPathPattern.hasMatch(unsafePath), isFalse);
      }
    });
  });

  group('Git inventory parser', () {
    test('preserves added, deleted, and both sides of renames', () {
      final changes = parseGitNameStatus(
        'A\u0000test/new_test.dart\u0000'
        'D\u0000test/deleted_test.dart\u0000'
        'R100\u0000lib/src/core/template/old.dart\u0000website/docs/new.md\u0000',
      );
      expect(changes, hasLength(3));
      expect(changes[0].kind, RepositoryChangeKind.added);
      expect(changes[1].kind, RepositoryChangeKind.deleted);
      expect(changes[2].kind, RepositoryChangeKind.renamed);
      expect(changes[2].previousPath, 'lib/src/core/template/old.dart');
      expect(changes[2].path, 'website/docs/new.md');
    });

    test('rejects malformed name-status output', () {
      for (final output in [
        'R100\u0000only-one-path\u0000',
        'R101\u0000old\u0000new\u0000',
        'modified\u0000path\u0000',
        'M\u0000unterminated',
      ]) {
        expect(() => parseGitNameStatus(output), throwsFormatException);
      }
    });

    test(
      'candidate-tree probe rejects symlinks and accepts regular blobs',
      () async {
        final symlinkReader = GitRepositoryStateReader(
          gitRunner: (args, {workingDirectory}) async =>
              ProcessResult(1, 0, '120000 blob abcdef\t$backendTest\u0000', ''),
        );
        expect(
          await symlinkReader.pathIsRegularFileAt(headSha, backendTest),
          isFalse,
        );

        final fileReader = GitRepositoryStateReader(
          gitRunner: (args, {workingDirectory}) async =>
              ProcessResult(1, 0, '100644 blob abcdef\t$backendTest\u0000', ''),
        );
        expect(
          await fileReader.pathIsRegularFileAt(headSha, backendTest),
          isTrue,
        );

        const wildcardTest = 'test/unit/backends/*_test.dart';
        late List<String> observedArgs;
        final wildcardReader = GitRepositoryStateReader(
          gitRunner: (args, {workingDirectory}) async {
            observedArgs = args;
            return ProcessResult(
              1,
              0,
              '100644 blob abcdef\t$backendTest\u0000',
              '',
            );
          },
        );
        expect(
          await wildcardReader.pathIsRegularFileAt(headSha, wildcardTest),
          isFalse,
        );
        expect(observedArgs.last, ':(top,literal)$wildcardTest');
      },
    );
  });
}
