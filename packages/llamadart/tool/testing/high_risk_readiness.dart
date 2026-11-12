#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

import 'classify_high_risk_changes.dart';
import 'release_metadata_readiness.dart';

/// Overall decision reached by the repository-local evaluator.
enum ReadinessDecision {
  rejected,
  unverifiedPrerequisites,
  standardRiskDiagnostic,
}

/// Stable failure classification emitted by the evaluator.
enum ReadinessFailureClassification {
  none,
  schemaViolation,
  repositoryMismatch,
  prMismatch,
  headMismatch,
  baseMismatch,
  authorMismatch,
  classificationMismatch,
  changedFilesMismatch,
  selfApprovalProhibited,
  retiredQaProfileProhibited,
  unresolvedReviewThreads,
  knownP1Regressions,
  missingAudit,
  auditRejected,
  missingRequiredMatrixRow,
  matrixRowFailed,
  missingStructuredOutputEvidence,
  missingTestPath,
  nonTestPathCited,
  unchangedEvidencePath,
  deletedEvidencePath,
  renamedEvidencePath,
  invalidReleaseMetadata,
  externalPrerequisitesUnavailable,
  gitExecutionError,
  invalidInput,
}

/// Git change kind used to bind evidence to the exact candidate diff.
enum RepositoryChangeKind {
  added,
  modified,
  deleted,
  renamed,
  copied,
  typeChanged,
  unmerged,
  unknown,
}

/// One path in the exact base-to-head repository inventory.
class RepositoryChange {
  const RepositoryChange({
    required this.path,
    required this.kind,
    this.previousPath,
  });

  final String path;
  final RepositoryChangeKind kind;
  final String? previousPath;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'status': kind.name,
    if (previousPath != null) 'previous_path': previousPath,
  };
}

/// Exact pull-request state supplied independently from the evidence payload.
class PullRequestContext {
  const PullRequestContext({
    required this.repository,
    required this.prNumber,
    required this.headSha,
    required this.baseSha,
    required this.author,
  });

  final String repository;
  final int prNumber;
  final String headSha;
  final String baseSha;
  final String author;
}

/// Read-only repository operations needed by the evaluator.
abstract interface class RepositoryStateReader {
  Future<bool> commitExists(String sha, {String? workingDirectory});

  Future<bool> isAncestor(
    String ancestor,
    String descendant, {
    String? workingDirectory,
  });

  Future<List<RepositoryChange>> changedFiles(
    String baseSha,
    String headSha, {
    String? workingDirectory,
  });

  Future<bool> pathIsRegularFileAt(
    String headSha,
    String path, {
    String? workingDirectory,
  });

  Future<ReadinessFile?> fileAt(
    String sha,
    String path, {
    String? workingDirectory,
  });
}

/// Function signature for non-shell Git command execution.
typedef GitRunner =
    Future<ProcessResult> Function(
      List<String> args, {
      String? workingDirectory,
    });

Future<ProcessResult> _defaultGitRunner(
  List<String> args, {
  String? workingDirectory,
}) => Process.run(
  'git',
  args,
  workingDirectory: workingDirectory,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

/// Repository state reader backed by direct, non-shell Git invocations.
class GitRepositoryStateReader implements RepositoryStateReader {
  const GitRepositoryStateReader({this.gitRunner = _defaultGitRunner});

  final GitRunner gitRunner;

  @override
  Future<ReadinessFile?> fileAt(
    String sha,
    String path, {
    String? workingDirectory,
  }) async {
    final tree = await gitRunner(<String>[
      'ls-tree',
      '-z',
      '--full-tree',
      sha,
      '--',
      ':(top,literal)$path',
    ], workingDirectory: workingDirectory);
    if (tree.exitCode != 0 || tree.stdout is! String) {
      throw StateError('Could not read literal Git tree entry.');
    }
    final entry = RegExp(
      r'^(100644|100755) blob ([0-9a-f]{40})\t([^\u0000]+)\u0000$',
    ).firstMatch(tree.stdout as String);
    if (entry == null || entry.group(3) != path) return null;
    final blob = await gitRunner(<String>[
      'cat-file',
      'blob',
      entry.group(2)!,
    ], workingDirectory: workingDirectory);
    if (blob.exitCode != 0 || blob.stdout is! String) {
      throw StateError('Could not read exact Git blob.');
    }
    return (mode: entry.group(1)!, contents: blob.stdout as String);
  }

  @override
  Future<bool> commitExists(String sha, {String? workingDirectory}) async {
    final result = await gitRunner(<String>[
      'cat-file',
      '-e',
      '$sha^{commit}',
    ], workingDirectory: workingDirectory);
    return result.exitCode == 0;
  }

  @override
  Future<bool> isAncestor(
    String ancestor,
    String descendant, {
    String? workingDirectory,
  }) async {
    final result = await gitRunner(<String>[
      'merge-base',
      '--is-ancestor',
      ancestor,
      descendant,
    ], workingDirectory: workingDirectory);
    if (result.exitCode == 0) return true;
    if (result.exitCode == 1) return false;
    throw StateError('git merge-base failed with exit ${result.exitCode}');
  }

  @override
  Future<List<RepositoryChange>> changedFiles(
    String baseSha,
    String headSha, {
    String? workingDirectory,
  }) async {
    final result = await gitRunner(<String>[
      'diff',
      '--name-status',
      '-z',
      '--find-renames',
      '--no-ext-diff',
      '--no-textconv',
      '$baseSha...$headSha',
    ], workingDirectory: workingDirectory);
    if (result.exitCode != 0) {
      throw StateError('git diff failed with exit ${result.exitCode}');
    }
    if (result.stdout is! String) {
      throw StateError('git diff did not return text output');
    }
    return parseGitNameStatus(result.stdout as String);
  }

  @override
  Future<bool> pathIsRegularFileAt(
    String headSha,
    String path, {
    String? workingDirectory,
  }) async {
    final result = await gitRunner(<String>[
      'ls-tree',
      '-z',
      '--full-tree',
      headSha,
      '--',
      ':(top,literal)$path',
    ], workingDirectory: workingDirectory);
    if (result.exitCode != 0) {
      throw StateError('git ls-tree failed with exit ${result.exitCode}');
    }
    if (result.stdout is! String) {
      throw StateError('git ls-tree did not return text output');
    }
    final output = result.stdout as String;
    if (output.isEmpty) return false;
    if (!output.endsWith('\u0000')) {
      throw const FormatException('Malformed git ls-tree output.');
    }
    final records = output.substring(0, output.length - 1).split('\u0000');
    if (records.length != 1) return false;
    final separator = records.single.indexOf('\t');
    if (separator < 0) {
      throw const FormatException('Malformed git ls-tree record.');
    }
    final metadata = records.single.substring(0, separator);
    final actualPath = records.single.substring(separator + 1);
    return actualPath == path &&
        RegExp(r'^(100644|100755) blob [0-9a-f]+$').hasMatch(metadata);
  }
}

/// Parses NUL-delimited `git diff --name-status -z --find-renames` output.
List<RepositoryChange> parseGitNameStatus(String output) {
  if (output.isEmpty) return const <RepositoryChange>[];
  if (!output.endsWith('\u0000')) {
    throw const FormatException(
      'Git name-status output is not NUL-terminated.',
    );
  }
  final fields = output.substring(0, output.length - 1).split('\u0000');
  final changes = <RepositoryChange>[];
  var offset = 0;
  while (offset < fields.length) {
    final status = fields[offset++];
    final scoredStatus = RegExp(r'^([RC])(\d{1,3})$').firstMatch(status);
    final code = scoredStatus?.group(1) ?? status;
    if (scoredStatus != null && int.parse(scoredStatus.group(2)!) > 100) {
      throw FormatException('Invalid Git similarity score: $status');
    }
    if (scoredStatus == null && !RegExp(r'^[A-Z]$').hasMatch(status)) {
      throw FormatException('Malformed Git change status: $status');
    }
    if (code == 'R' || code == 'C') {
      if (offset + 1 >= fields.length ||
          fields[offset].isEmpty ||
          fields[offset + 1].isEmpty) {
        throw FormatException('Malformed Git $status name-status record.');
      }
      changes.add(
        RepositoryChange(
          path: fields[offset + 1],
          previousPath: fields[offset],
          kind: code == 'R'
              ? RepositoryChangeKind.renamed
              : RepositoryChangeKind.copied,
        ),
      );
      offset += 2;
      continue;
    }
    if (offset >= fields.length || fields[offset].isEmpty) {
      throw FormatException('Malformed Git $status name-status record.');
    }
    final kind = switch (code) {
      'A' => RepositoryChangeKind.added,
      'M' => RepositoryChangeKind.modified,
      'D' => RepositoryChangeKind.deleted,
      'T' => RepositoryChangeKind.typeChanged,
      'U' => RepositoryChangeKind.unmerged,
      _ => RepositoryChangeKind.unknown,
    };
    changes.add(RepositoryChange(path: fields[offset++], kind: kind));
  }
  return changes;
}

/// Whether a Dart source edit from [base] to [head] is provably comment-only.
///
/// Both revisions must parse without diagnostics and scan to identical tokens
/// (type and lexeme, so string contents, directives and annotations count).
/// Whitespace may change only where the comments between two tokens change,
/// and the later token must start its line in both revisions. A comment added,
/// removed or moved must not be a language-version, analyzer, coverage,
/// formatter, Dartdoc-directive, doc-import, suppression or excerpt marker,
/// nor contain control, invisible or bidirectional characters. Generated
/// sources and [rawTextConsumedSources] never qualify. Callers bind both texts
/// to exact Git blobs.
bool isCommentOnlyDartChange(String path, String base, String head) {
  if (!path.endsWith('.dart') ||
      _generatedDartPath.hasMatch(path) ||
      rawTextConsumedSources.contains(path)) {
    return false;
  }
  final baseUnit = _parseCleanly(base);
  final headUnit = _parseCleanly(head);
  if (baseUnit == null || headUnit == null) return false;
  var left = baseUnit.beginToken;
  var right = headUnit.beginToken;
  var leftEnd = 0;
  var rightEnd = 0;
  while (true) {
    if (left.type != right.type ||
        left.lexeme != right.lexeme ||
        left.offset < leftEnd ||
        right.offset < rightEnd) {
      return false;
    }
    final leftComments = _commentsBefore(left);
    final rightComments = _commentsBefore(right);
    final comments = [...leftComments, ...rightComments];
    if (comments.any(_generatedMarker.hasMatch) ||
        (leftEnd == 0 && comments.any(_generatedHeader.hasMatch))) {
      return false;
    }
    final leftGap = base.substring(leftEnd, left.offset);
    final rightGap = head.substring(rightEnd, right.offset);
    if (leftGap != rightGap &&
        !_isInertCommentEdit(leftComments, rightComments, leftGap, rightGap)) {
      return false;
    }
    if (left.isEof) return true;
    leftEnd = left.end;
    rightEnd = right.end;
    left = left.next!;
    right = right.next!;
  }
}

/// Production Dart sources whose raw text, comments included, repository
/// tooling reads with regular expressions (release pins, bridge tags,
/// template hashes). A comment there can change what a CI gate or sync
/// script sees, so these never use the comment-only route.
const rawTextConsumedSources = <String>{
  'hook/build.dart',
  'lib/src/backends/litert_lm/litert_lm_runtime.dart',
  'lib/src/hook/native_release_pins.dart',
  'lib/src/web_setup/web_bridge_setup.dart',
};

final _generatedDartPath = RegExp(
  r'\.(g|gr|freezed|mocks|pb|pbenum|pbgrpc|pbjson|pbserver)\.dart$',
);
final _generatedMarker = RegExp(
  r'^(//+|/\*+)\s*(auto[- ]?generated|generated\s+(file|code|by)|'
  r'code\s+generated|do\s+not\s+(edit|modify))',
  caseSensitive: false,
);
final _generatedHeader = RegExp(
  r'generated|do\s+not\s+(hand[- ])?(edit|modify)',
  caseSensitive: false,
);
// Comments that tools read: language version, doc imports and Dartdoc
// directives, analyzer/coverage/formatter/security suppressions, excerpts.
final _activeComment = RegExp(
  r'@[a-z]|\bignore(_for_file)?\s*:|\bcoverage\s*:|\bdart\s+format\b|#[a-z]|'
  r'\b(nosemgrep|nosec|nosonar|lgtm|codeql|noqa|nolint|expect_lint|eslint|'
  r'istanbul|c8|pragma)\b',
  caseSensitive: false,
);
// These apply to the whole file wherever they sit, so an unchanged one may
// precede an edited comment at the same token.
final _fileScopedDirective = RegExp(
  r'^//\s*(ignore_for_file\s*:|coverage:ignore-file\b|@dart\s*=)',
  caseSensitive: false,
);
final _unsafeCommentCharacter = RegExp(
  '[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u0085\u061C'
  '\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060-\u2069\uFEFF]',
);
final _lineBreak = RegExp(r'[\r\n]');

CompilationUnit? _parseCleanly(String source) {
  try {
    final parsed = parseString(content: source, throwIfDiagnostics: false);
    return parsed.errors.isEmpty ? parsed.unit : null;
  } on Object {
    return null;
  }
}

List<String> _commentsBefore(Token token) {
  final comments = <String>[];
  for (
    Token? comment = token.precedingComments;
    comment != null &&
        (comment.type == TokenType.SINGLE_LINE_COMMENT ||
            comment.type == TokenType.MULTI_LINE_COMMENT);
    comment = comment.next
  ) {
    comments.add(comment.lexeme);
  }
  return comments;
}

bool _isInertCommentEdit(
  List<String> left,
  List<String> right,
  String leftGap,
  String rightGap,
) {
  if (left.length == right.length &&
      Iterable<int>.generate(left.length).every((i) => left[i] == right[i])) {
    return false;
  }
  // Edited comments must end their line, so the next token still starts its
  // line in both revisions. Line-oriented source scanners then see the same
  // code at every line start, and no token joins or leaves another's line.
  for (final gap in [leftGap, rightGap]) {
    final lineStart = gap.lastIndexOf(_lineBreak) + 1;
    if (lineStart == 0 || gap.substring(lineStart).trim().isNotEmpty) {
      return false;
    }
  }
  var prefix = 0;
  while (prefix < left.length &&
      prefix < right.length &&
      left[prefix] == right[prefix]) {
    prefix++;
  }
  for (final comments in [left, right]) {
    for (var i = 0; i < comments.length; i++) {
      final comment = comments[i];
      if (_unsafeCommentCharacter.hasMatch(comment) ||
          (_activeComment.hasMatch(comment) &&
              !(i < prefix && _fileScopedDirective.hasMatch(comment)))) {
        return false;
      }
    }
  }
  return true;
}

/// Strictly decodes a JSON object, rejecting duplicate object keys.
Map<String, dynamic> decodeStrictJsonObject(String source) {
  _DuplicateKeyScanner(source).scan();
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Evidence JSON must be an object.');
  }
  return decoded;
}

class _DuplicateKeyScanner {
  _DuplicateKeyScanner(this.source);

  final String source;
  var _offset = 0;

  void scan() {
    _skipWhitespace();
    _scanValue();
    _skipWhitespace();
    if (_offset != source.length) {
      throw FormatException(
        'Unexpected trailing JSON content.',
        source,
        _offset,
      );
    }
  }

  void _scanValue() {
    _skipWhitespace();
    if (_offset >= source.length) {
      throw FormatException('Unexpected end of JSON.', source, _offset);
    }
    switch (source.codeUnitAt(_offset)) {
      case 0x7b:
        _scanObject();
        return;
      case 0x5b:
        _scanArray();
        return;
      case 0x22:
        _scanString();
        return;
      default:
        _scanPrimitive();
        return;
    }
  }

  void _scanObject() {
    _offset++;
    _skipWhitespace();
    final keys = <String>{};
    if (_consume(0x7d)) return;
    while (true) {
      _skipWhitespace();
      if (_offset >= source.length || source.codeUnitAt(_offset) != 0x22) {
        throw FormatException('Expected JSON object key.', source, _offset);
      }
      final key = _scanString();
      if (!keys.add(key)) {
        throw FormatException(
          'Duplicate JSON object key "$key".',
          source,
          _offset,
        );
      }
      _skipWhitespace();
      if (!_consume(0x3a)) {
        throw FormatException(
          'Expected colon after object key.',
          source,
          _offset,
        );
      }
      _scanValue();
      _skipWhitespace();
      if (_consume(0x7d)) return;
      if (!_consume(0x2c)) {
        throw FormatException(
          'Expected comma in JSON object.',
          source,
          _offset,
        );
      }
    }
  }

  void _scanArray() {
    _offset++;
    _skipWhitespace();
    if (_consume(0x5d)) return;
    while (true) {
      _scanValue();
      _skipWhitespace();
      if (_consume(0x5d)) return;
      if (!_consume(0x2c)) {
        throw FormatException('Expected comma in JSON array.', source, _offset);
      }
    }
  }

  String _scanString() {
    final start = _offset;
    _offset++;
    var escaped = false;
    while (_offset < source.length) {
      final unit = source.codeUnitAt(_offset++);
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5c) {
        escaped = true;
      } else if (unit == 0x22) {
        return jsonDecode(source.substring(start, _offset)) as String;
      }
    }
    throw FormatException('Unterminated JSON string.', source, start);
  }

  void _scanPrimitive() {
    final start = _offset;
    while (_offset < source.length) {
      final unit = source.codeUnitAt(_offset);
      if (unit == 0x2c || unit == 0x5d || unit == 0x7d || _isWhitespace(unit)) {
        break;
      }
      _offset++;
    }
    if (_offset == start) {
      throw FormatException('Expected JSON value.', source, _offset);
    }
  }

  bool _consume(int unit) {
    if (_offset < source.length && source.codeUnitAt(_offset) == unit) {
      _offset++;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (_offset < source.length &&
        _isWhitespace(source.codeUnitAt(_offset))) {
      _offset++;
    }
  }

  static bool _isWhitespace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;
}

/// Structured evaluation result. Its JSON shape is the canonical schema root.
class HighRiskReadinessResult {
  const HighRiskReadinessResult({
    required this.evidence,
    required this.evaluatedAt,
    required this.changedFiles,
    required this.decision,
    required this.failureClassification,
    required this.message,
  });

  static const schema = 'llamadart.high-risk-readiness-evidence';
  static const schemaVersion = '2.0.0';

  final Map<String, Object?> evidence;
  final DateTime evaluatedAt;
  final List<RepositoryChange> changedFiles;
  final ReadinessDecision decision;
  final ReadinessFailureClassification failureClassification;
  final String message;

  /// Repository-local evaluation never represents operational merge readiness.
  bool get isReady => false;

  Map<String, Object?> toJson() => <String, Object?>{
    ...evidence,
    'evaluation': <String, Object?>{
      'evaluated_at': evaluatedAt.toUtc().toIso8601String(),
      'changed_files': changedFiles.map((change) => change.toJson()).toList(),
      'decision': decision.name,
      'failure_classification': failureClassification.name,
      'message': message,
      'external_prerequisites': const <String, Object?>{
        'app_installed': false,
        'protected_environment_configured': false,
        'independent_auditor_authenticated': false,
        'ruleset_enforced': false,
        'diagnostic_message':
            'No repository-local input can authenticate the dedicated GitHub App, protected environment, independent auditor, or conditional ruleset. See doc/high_risk_pre_merge_readiness.md.',
      },
    },
  };

  String toFormattedJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Evaluates evidence against an independently supplied PR context and Git tree.
class HighRiskReadinessEvaluator {
  const HighRiskReadinessEvaluator({
    this.repositoryState = const GitRepositoryStateReader(),
    this.clock = _defaultClock,
  });

  final RepositoryStateReader repositoryState;
  final DateTime Function() clock;

  static DateTime _defaultClock() => DateTime.now();
  static const _zeroSha = '0000000000000000000000000000000000000000';
  static const _rootKeys = <String>{
    'schema',
    'schema_version',
    'timestamp',
    'correlation_id',
    'repository',
    'pr_number',
    'expected_pr_head_sha',
    'current_base_sha',
    'pr_author',
    'classification',
    'surfaces',
    'required_matrix_row_ids',
    'matrix_row_evidence',
    'independent_audit',
    'structured_output_evidence',
    'affected_test_paths',
    'test_evidence',
    'evaluation',
  };
  static const _auditKeys = <String>{
    'auditor_identity',
    'audit_kind',
    'audit_head_sha',
    'audit_base_sha',
    'decision',
    'unresolved_review_threads',
    'known_pr_caused_p1_regressions',
    'summary',
  };
  static const _matrixKeys = <String>{
    'row_id',
    'result',
    'command',
    'evidence_notes',
  };
  static const _knownMatrixRows = <String>{
    'high-risk-exact-head-independent-qa',
    'structured-output-adversarial',
    releaseMetadataRow,
  };
  static const _structuredKeys = <String>{'coverage', 'families', 'impacts'};
  static const _coverageAxes = <String>{
    'input_rendering_history',
    'compiled_grammar_acceptance',
    'compiled_grammar_rejection',
    'schema_reconstruction',
    'streaming_rollback',
    'tool_choice_thinking',
    'upstream_parity',
  };
  static const _familyKeys = <String>{
    'family',
    'status',
    'evidence_test_paths',
    'rationale',
  };
  static const _knownCompiledGrammarTests = <String>{
    'test/integration/core/grammar/generated_tool_schema_grammar_test.dart',
    'test/e2e/template/specialized_tool_grammar_validation_e2e_test.dart',
    'packages/genkit_llamadart/test/integration/genkit/plugin/real_model_constrained_grammar_test.dart',
    'packages/genkit_llamadart/test/integration/genkit/plugin/real_model_rich_tool_schemas_test.dart',
  };
  static const _ffigenConfig = 'ffigen.yaml';
  static const _ffigenPolicyTest =
      'test/unit/tooling/native_bindings_generator_policy_test.dart';

  // Python suites CI runs directly, each bound to the one script it drives.
  static const _nativeSyncPythonTests = <String, String>{
    'tool/native/test_native_header_archive.py':
        'tool/native/native_header_archive.py',
    'tool/native/test_sync_native_headers_and_bindings.py':
        'tool/native/sync_native_headers_and_bindings.sh',
    'tool/native/test_sync_native_release_pins.py':
        'tool/native/sync_native_release_pins.py',
    'tool/native/test_sync_stable_diffusion_bindings.py':
        'tool/native/sync_stable_diffusion_bindings.py',
    'test/ci/test_nonpublishing_auth_probe.py':
        'tool/release/nonpublishing_auth_probe.py',
  };

  Future<HighRiskReadinessResult> evaluate({
    required Map<String, dynamic> evidence,
    required PullRequestContext context,
    String? workingDirectory,
  }) async {
    final evaluatedAt = clock().toUtc();
    final shapeError = _validateShape(evidence);
    final contextError = _validateContext(context);
    final outputEvidence = _safeOutputEvidence(
      evidence,
      context,
      evaluatedAt,
      preserveEvidence: shapeError == null && contextError == null,
    );

    HighRiskReadinessResult reject(
      ReadinessFailureClassification failure,
      String message, {
      List<RepositoryChange> changedFiles = const <RepositoryChange>[],
    }) => HighRiskReadinessResult(
      evidence: outputEvidence,
      evaluatedAt: evaluatedAt,
      changedFiles: changedFiles,
      decision: ReadinessDecision.rejected,
      failureClassification: failure,
      message: message,
    );

    if (shapeError != null) {
      return reject(ReadinessFailureClassification.schemaViolation, shapeError);
    }
    if (contextError != null) {
      return reject(ReadinessFailureClassification.invalidInput, contextError);
    }
    if (evidence['repository'] != context.repository) {
      return reject(
        ReadinessFailureClassification.repositoryMismatch,
        'Evidence repository does not match the independently supplied repository.',
      );
    }
    if (evidence['pr_number'] != context.prNumber) {
      return reject(
        ReadinessFailureClassification.prMismatch,
        'Evidence PR number does not match the independently supplied PR number.',
      );
    }
    if (evidence['expected_pr_head_sha'] != context.headSha) {
      return reject(
        ReadinessFailureClassification.headMismatch,
        'Evidence head SHA does not match the independently observed PR head.',
      );
    }
    if (evidence['current_base_sha'] != context.baseSha) {
      return reject(
        ReadinessFailureClassification.baseMismatch,
        'Evidence base SHA does not match the independently observed PR base.',
      );
    }
    if ((evidence['pr_author'] as String).toLowerCase() !=
        context.author.toLowerCase()) {
      return reject(
        ReadinessFailureClassification.authorMismatch,
        'Evidence PR author does not match the independently observed PR author.',
      );
    }

    late final List<RepositoryChange> changedFiles;
    try {
      if (!await repositoryState.commitExists(
            context.baseSha,
            workingDirectory: workingDirectory,
          ) ||
          !await repositoryState.commitExists(
            context.headSha,
            workingDirectory: workingDirectory,
          )) {
        return reject(
          ReadinessFailureClassification.gitExecutionError,
          'The exact base and head commits must both exist in the local object database.',
        );
      }
      if (!await repositoryState.isAncestor(
        context.baseSha,
        context.headSha,
        workingDirectory: workingDirectory,
      )) {
        return reject(
          ReadinessFailureClassification.baseMismatch,
          'The independently observed base is not an ancestor of the PR head.',
        );
      }
      changedFiles = await repositoryState.changedFiles(
        context.baseSha,
        context.headSha,
        workingDirectory: workingDirectory,
      );
    } on Object {
      return reject(
        ReadinessFailureClassification.gitExecutionError,
        'Git could not build the exact base-to-head changed-file inventory.',
      );
    }
    if (changedFiles.isEmpty) {
      return reject(
        ReadinessFailureClassification.changedFilesMismatch,
        'The exact base-to-head changed-file inventory is empty.',
      );
    }
    if (changedFiles.any((change) => !_isValidRepositoryChange(change)) ||
        changedFiles.map((change) => change.path).toSet().length !=
            changedFiles.length) {
      return reject(
        ReadinessFailureClassification.changedFilesMismatch,
        'The exact inventory contains a malformed or duplicate repository change.',
      );
    }
    if (changedFiles.any(
      (change) =>
          change.kind == RepositoryChangeKind.unknown ||
          change.kind == RepositoryChangeKind.unmerged,
    )) {
      return reject(
        ReadinessFailureClassification.changedFilesMismatch,
        'The exact inventory contains an unsupported or unmerged change status.',
        changedFiles: changedFiles,
      );
    }

    final classificationPaths = <String>[
      for (final change in changedFiles) ...<String>[
        change.path,
        if (change.previousPath != null) change.previousPath!,
      ],
    ];
    final assessment = assessHighRiskFiles(classificationPaths);
    final declaredClassification = evidence['classification'] as String;
    if (assessment.isHighRisk != (declaredClassification == 'high-risk')) {
      return reject(
        ReadinessFailureClassification.classificationMismatch,
        'Declared classification does not match the exact changed-file inventory.',
        changedFiles: changedFiles,
      );
    }
    if (!assessment.isHighRisk) {
      final standardError = _validateStandardEvidence(evidence);
      if (standardError != null) {
        return reject(
          ReadinessFailureClassification.schemaViolation,
          standardError,
          changedFiles: changedFiles,
        );
      }
      return HighRiskReadinessResult(
        evidence: outputEvidence,
        evaluatedAt: evaluatedAt,
        changedFiles: changedFiles,
        decision: ReadinessDecision.standardRiskDiagnostic,
        failureClassification: ReadinessFailureClassification.none,
        message:
            'The exact diff is standard risk. This diagnostic is not an operational required-check qualification.',
      );
    }

    final declaredSurfaces = (evidence['surfaces'] as List<dynamic>)
        .cast<String>()
        .toSet();
    final actualSurfaces = assessment.surfaces
        .map((surface) => surface.name)
        .toSet();
    if (!_sameSet(declaredSurfaces, actualSurfaces)) {
      return reject(
        ReadinessFailureClassification.classificationMismatch,
        'Declared surfaces must exactly match classified surfaces: ${_sorted(actualSurfaces).join(', ')}.',
        changedFiles: changedFiles,
      );
    }

    const baselineRow = 'high-risk-exact-head-independent-qa';
    const structuredRow = 'structured-output-adversarial';
    final requiredRows = <String>{baselineRow};
    final metadataClaim = (evidence['required_matrix_row_ids'] as List<dynamic>)
        .contains(releaseMetadataRow);
    if (metadataClaim) requiredRows.add(releaseMetadataRow);
    if (actualSurfaces.contains(HighRiskSurface.structuredOutput.name)) {
      requiredRows.add(structuredRow);
    }
    final declaredRows = (evidence['required_matrix_row_ids'] as List<dynamic>)
        .cast<String>()
        .toSet();
    if (!_sameSet(declaredRows, requiredRows)) {
      return reject(
        ReadinessFailureClassification.missingRequiredMatrixRow,
        'Required matrix rows must exactly match: ${_sorted(requiredRows).join(', ')}.',
        changedFiles: changedFiles,
      );
    }
    final matrixEvidence =
        evidence['matrix_row_evidence'] as Map<String, dynamic>;
    if (!_sameSet(matrixEvidence.keys.toSet(), requiredRows)) {
      return reject(
        ReadinessFailureClassification.missingRequiredMatrixRow,
        'Matrix evidence keys must exactly match required matrix row IDs.',
        changedFiles: changedFiles,
      );
    }
    for (final rowId in requiredRows) {
      final row = matrixEvidence[rowId] as Map<String, dynamic>;
      if (row['row_id'] != rowId || row['result'] != 'pass') {
        return reject(
          ReadinessFailureClassification.matrixRowFailed,
          'Required matrix row "$rowId" must identify itself and report pass.',
          changedFiles: changedFiles,
        );
      }
    }

    final audit = evidence['independent_audit'] as Map<String, dynamic>?;
    if (audit == null) {
      return reject(
        ReadinessFailureClassification.missingAudit,
        'High-risk changes require an independent audit object.',
        changedFiles: changedFiles,
      );
    }
    final auditor = audit['auditor_identity'] as String;
    final authorLogin = context.author.toLowerCase().replaceFirst(
      RegExp(r'\[bot\]$'),
      '',
    );
    if (auditor.toLowerCase() == authorLogin) {
      return reject(
        ReadinessFailureClassification.selfApprovalProhibited,
        'The independent auditor cannot be the PR author.',
        changedFiles: changedFiles,
      );
    }
    if (_isRetiredQaIdentity(auditor)) {
      return reject(
        ReadinessFailureClassification.retiredQaProfileProhibited,
        'The standalone qa identity is retired and cannot supply an audit.',
        changedFiles: changedFiles,
      );
    }
    if (audit['audit_head_sha'] != context.headSha) {
      return reject(
        ReadinessFailureClassification.headMismatch,
        'The audit is not bound to the exact PR head.',
        changedFiles: changedFiles,
      );
    }
    if (audit['audit_base_sha'] != context.baseSha) {
      return reject(
        ReadinessFailureClassification.baseMismatch,
        'The audit is not bound to the exact PR base.',
        changedFiles: changedFiles,
      );
    }
    if (audit['decision'] != 'accepted') {
      return reject(
        ReadinessFailureClassification.auditRejected,
        'The independent audit decision is not accepted.',
        changedFiles: changedFiles,
      );
    }
    if ((audit['unresolved_review_threads'] as int) != 0) {
      return reject(
        ReadinessFailureClassification.unresolvedReviewThreads,
        'Unresolved review threads remain.',
        changedFiles: changedFiles,
      );
    }
    if ((audit['known_pr_caused_p1_regressions'] as int) != 0) {
      return reject(
        ReadinessFailureClassification.knownP1Regressions,
        'Known PR-caused P1 regressions remain.',
        changedFiles: changedFiles,
      );
    }

    final changedByPath = <String, RepositoryChange>{
      for (final change in changedFiles) change.path: change,
    };
    final renamedPreviousPaths = <String>{
      for (final change in changedFiles)
        if (change.kind == RepositoryChangeKind.renamed) change.previousPath!,
    };
    final affectedPaths = (evidence['affected_test_paths'] as List<dynamic>)
        .cast<String>();
    final commentOnlyProduction = metadataClaim
        ? const <String>{}
        : await _commentOnlyProductionPaths(
            context,
            changedFiles,
            workingDirectory,
          );
    final changedProduction = {
      for (final path in classificationPaths)
        if (_isProductionPath(path)) path,
    };
    if (metadataClaim) {
      if (actualSurfaces.length != 1 ||
          !actualSurfaces.contains(HighRiskSurface.artifactConsumer.name) ||
          affectedPaths.length != 1 ||
          affectedPaths.single != releaseMetadataTest ||
          (matrixEvidence[releaseMetadataRow]
                  as Map<String, dynamic>)['command'] !=
              releaseMetadataCommand) {
        return reject(
          ReadinessFailureClassification.invalidReleaseMetadata,
          'Metadata release evidence requires only artifactConsumer, the fixed '
          'existing release test and its exact strict-verifier/test command.',
          changedFiles: changedFiles,
        );
      }
      try {
        final files = <String, ReadinessFilePair>{};
        for (final change in changedFiles) {
          if (change.kind != RepositoryChangeKind.modified ||
              !releaseMetadataPaths.contains(change.path)) {
            return reject(
              ReadinessFailureClassification.invalidReleaseMetadata,
              'Metadata releases cannot add, remove, rename or change paths '
              'outside the fixed release inventory.',
              changedFiles: changedFiles,
            );
          }
          final base = await repositoryState.fileAt(
            context.baseSha,
            change.path,
            workingDirectory: workingDirectory,
          );
          final head = await repositoryState.fileAt(
            context.headSha,
            change.path,
            workingDirectory: workingDirectory,
          );
          if (base == null || head == null) {
            return reject(
              ReadinessFailureClassification.invalidReleaseMetadata,
              'Metadata release paths must be regular files at both revisions.',
              changedFiles: changedFiles,
            );
          }
          files[change.path] = (base: base, head: head);
        }
        final metadataError = validateReleaseMetadata(files);
        if (metadataError != null) {
          return reject(
            ReadinessFailureClassification.invalidReleaseMetadata,
            metadataError,
            changedFiles: changedFiles,
          );
        }
        for (final path in [releaseMetadataVerifier, releaseMetadataTest]) {
          final base = await repositoryState.fileAt(
            context.baseSha,
            path,
            workingDirectory: workingDirectory,
          );
          final head = await repositoryState.fileAt(
            context.headSha,
            path,
            workingDirectory: workingDirectory,
          );
          if (base == null ||
              head == null ||
              base != head ||
              base.mode != '100644') {
            return reject(
              ReadinessFailureClassification.invalidReleaseMetadata,
              'Existing release verifier and test must be unchanged regular '
              'blobs at the exact base and head.',
              changedFiles: changedFiles,
            );
          }
        }
      } on Object {
        return reject(
          ReadinessFailureClassification.gitExecutionError,
          'Could not verify exact release metadata blobs.',
          changedFiles: changedFiles,
        );
      }
    } else if (affectedPaths.isEmpty &&
        (changedProduction.isEmpty ||
            !commentOnlyProduction.containsAll(changedProduction))) {
      return reject(
        ReadinessFailureClassification.missingTestPath,
        'High-risk evidence must cite at least one relevant production test.',
        changedFiles: changedFiles,
      );
    }
    for (final path in metadataClaim ? const <String>[] : affectedPaths) {
      late final (ReadinessFailureClassification, String)? pathFailure;
      try {
        pathFailure = await _validateEvidencePath(
          path,
          context.headSha,
          changedByPath,
          renamedPreviousPaths,
          workingDirectory: workingDirectory,
        );
      } on Object {
        return reject(
          ReadinessFailureClassification.gitExecutionError,
          'Git could not verify an evidence path in the exact candidate tree.',
          changedFiles: changedFiles,
        );
      }
      if (pathFailure != null) {
        return reject(
          pathFailure.$1,
          pathFailure.$2,
          changedFiles: changedFiles,
        );
      }
    }

    try {
      final error = await _validateImpactEvidence(
        evidence,
        context,
        changedByPath,
        metadataClaim,
        commentOnlyProduction,
        workingDirectory,
      );
      if (error != null) {
        return reject(
          ReadinessFailureClassification.missingStructuredOutputEvidence,
          error,
          changedFiles: changedFiles,
        );
      }
    } on Object {
      return reject(
        ReadinessFailureClassification.gitExecutionError,
        'Could not inspect impact evidence blobs.',
        changedFiles: changedFiles,
      );
    }

    if (actualSurfaces.contains(HighRiskSurface.structuredOutput.name)) {
      final structured =
          evidence['structured_output_evidence'] as Map<String, dynamic>?;
      if (structured == null) {
        return reject(
          ReadinessFailureClassification.missingStructuredOutputEvidence,
          'Structured-output changes require structured evidence.',
          changedFiles: changedFiles,
        );
      }
      final coverage = structured['coverage'] as Map<String, dynamic>;
      for (final axis in _coverageAxes) {
        final paths = (coverage[axis] as List<dynamic>).cast<String>();
        for (final path in paths) {
          if (!affectedPaths.contains(path)) {
            return reject(
              ReadinessFailureClassification.unchangedEvidencePath,
              'Structured-output axis "$axis" cites a path outside affected_test_paths: $path.',
              changedFiles: changedFiles,
            );
          }
        }
      }
      for (final axis in const <String>{
        'compiled_grammar_acceptance',
        'compiled_grammar_rejection',
      }) {
        final paths = (coverage[axis] as List<dynamic>).cast<String>().toSet();
        if (paths.isNotEmpty &&
            paths.intersection(_knownCompiledGrammarTests).isEmpty) {
          return reject(
            ReadinessFailureClassification.missingStructuredOutputEvidence,
            'Structured-output axis "$axis" must cite a compiled production grammar test.',
            changedFiles: changedFiles,
          );
        }
      }
      final families = (structured['families'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final family in families) {
        for (final path
            in (family['evidence_test_paths'] as List<dynamic>)
                .cast<String>()) {
          if (!affectedPaths.contains(path)) {
            return reject(
              ReadinessFailureClassification.unchangedEvidencePath,
              'Family evidence cites a path outside affected_test_paths: $path.',
              changedFiles: changedFiles,
            );
          }
        }
      }
    } else if (evidence['structured_output_evidence'] != null) {
      return reject(
        ReadinessFailureClassification.schemaViolation,
        'Non-structured changes must not declare structured_output_evidence.',
        changedFiles: changedFiles,
      );
    }

    return HighRiskReadinessResult(
      evidence: outputEvidence,
      evaluatedAt: evaluatedAt,
      changedFiles: changedFiles,
      decision: ReadinessDecision.unverifiedPrerequisites,
      failureClassification:
          ReadinessFailureClassification.externalPrerequisitesUnavailable,
      message:
          'Repository-local evidence is internally consistent, but auditor authentication, GitHub App publication, protected-environment provenance, and ruleset enforcement are not available. This is not operational merge readiness.',
    );
  }

  static const _impactAxes = <String, Set<String>>{
    'inputRenderingHistory': {'input_rendering_history', 'upstream_parity'},
    'outputParsingStreaming': {
      'schema_reconstruction',
      'streaming_rollback',
      'tool_choice_thinking',
      'upstream_parity',
    },
    'grammarSchema': {
      'compiled_grammar_acceptance',
      'compiled_grammar_rejection',
      'schema_reconstruction',
      'tool_choice_thinking',
      'upstream_parity',
    },
  };

  // These are reviewed observations, not authenticated execution receipts.
  // The local evaluator checks exact-tree references and consistency only.
  static String? _validateImpactShape(Map<String, dynamic> evidence) {
    final tests = evidence['test_evidence'];
    if (tests is! Map<String, dynamic>) {
      return 'test_evidence must be an object.';
    }
    for (final entry in tests.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) {
        return 'Test evidence must be an object.';
      }
      final error = _exactKeys(value, {
        'test_case',
        'test_snippet',
        'production_refs',
        'command',
        'head_result',
        'control_result',
        'control_kind',
        'control_description',
        'evidence_notes',
      }, 'test evidence');
      if (error != null) return error;
      for (final key in [
        'test_case',
        'test_snippet',
        'command',
        'control_description',
        'evidence_notes',
      ]) {
        if (!_isNonEmptyString(value[key])) {
          return 'Test evidence $key must be nonempty.';
        }
      }
      if (value['head_result'] != 'pass' ||
          value['control_result'] != 'fail' ||
          !{'before-fix', 'mutation'}.contains(value['control_kind'])) {
        return 'Test evidence requires head pass and causal control failure.';
      }
      final refsError = _validateRefsShape(value['production_refs']);
      if (refsError != null) return refsError;
    }
    final structured = evidence['structured_output_evidence'];
    if (structured == null) return null;
    if (structured is! Map<String, dynamic>) {
      return 'Structured evidence must be an object.';
    }
    final impacts = structured['impacts'];
    if (impacts is! Map<String, dynamic>) {
      return 'Structured impacts must be an object.';
    }
    final error = _exactKeys(impacts, _impactAxes.keys.toSet(), 'impacts');
    if (error != null) return error;
    for (final value in impacts.values) {
      if (value is! Map<String, dynamic>) {
        return 'Each impact must be an object.';
      }
      final error = _exactKeys(value, {
        'applicable',
        'rationale',
        'production_refs',
      }, 'impact');
      if (error != null) return error;
      if (value['applicable'] is! bool ||
          !_isNonEmptyString(value['rationale'])) {
        return 'Impact applicability and independent rationale are required.';
      }
      final refsError = _validateRefsShape(value['production_refs']);
      if (refsError != null) return refsError;
    }
    return null;
  }

  static String? _validateRefsShape(dynamic refs) {
    if (refs is! List || refs.isEmpty) {
      return 'Production references must be nonempty.';
    }
    final paths = <String>{};
    for (final ref in refs) {
      if (ref is! Map<String, dynamic>) {
        return 'Production reference must be an object.';
      }
      final error = _exactKeys(ref, {
        'path',
        'snippet',
      }, 'production reference');
      if (error != null) return error;
      final path = ref['path'];
      if (path is! String ||
          !paths.add(path) ||
          !_isProductionPath(path) ||
          path.contains('..') ||
          path.contains('\\') ||
          RegExp(r'[\x00-\x20\x7f*?\[\]]').hasMatch(path) ||
          !_isNonEmptyString(ref['snippet'])) {
        return 'Invalid production reference.';
      }
    }
    return null;
  }

  Future<String?> _validateImpactEvidence(
    Map<String, dynamic> evidence,
    PullRequestContext context,
    Map<String, RepositoryChange> changes,
    bool metadataClaim,
    Set<String> commentOnlyProduction,
    String? workingDirectory,
  ) async {
    final tests = evidence['test_evidence'] as Map<String, dynamic>;
    final paths = (evidence['affected_test_paths'] as List)
        .cast<String>()
        .toSet();
    if (metadataClaim) {
      return tests.isEmpty
          ? null
          : 'Release metadata uses its existing bounded evidence route.';
    }
    if (!_sameSet(tests.keys.toSet(), paths)) {
      return 'Every cited test needs exactly one relevance and causal evidence record.';
    }
    final renamedSources = {
      for (final change in changes.values)
        if (change.kind == RepositoryChangeKind.renamed &&
            change.previousPath != null)
          change.previousPath!,
    };
    final inspectedPaths = {...changes.keys, ...renamedSources};
    final changedProduction = inspectedPaths.where(_isProductionPath).toSet();
    final testedProduction = changedProduction.difference(
      commentOnlyProduction,
    );
    Future<bool> refsExist(List<dynamic> refs) async {
      for (final ref in refs.cast<Map<String, dynamic>>()) {
        final path = ref['path'] as String;
        // Deleted code is inspectable at the base, never at an invented head.
        final sha =
            changes[path]?.kind == RepositoryChangeKind.deleted ||
                renamedSources.contains(path)
            ? context.baseSha
            : context.headSha;
        final file = await repositoryState.fileAt(
          sha,
          path,
          workingDirectory: workingDirectory,
        );
        if (file == null ||
            !{'100644', '100755'}.contains(file.mode) ||
            !file.contents.contains(ref['snippet'] as String)) {
          return false;
        }
      }
      return true;
    }

    final coveredProduction = <String>{};
    for (final entry in tests.entries) {
      final proof = entry.value as Map<String, dynamic>;
      final file = await repositoryState.fileAt(
        context.headSha,
        entry.key,
        workingDirectory: workingDirectory,
      );
      if (file == null ||
          !file.contents.contains(proof['test_snippet'] as String) ||
          !file.contents.contains(proof['test_case'] as String)) {
        return 'Named test case or callsite snippet is missing from the exact head: ${entry.key}.';
      }
      final refs = proof['production_refs'] as List<dynamic>;
      final referenced = refs
          .map((ref) => (ref as Map)['path'] as String)
          .toSet();
      final ffigenTest = entry.key == _ffigenPolicyTest;
      if ((ffigenTest || referenced.contains(_ffigenConfig)) &&
          (!ffigenTest ||
              referenced.length != 1 ||
              !referenced.contains(_ffigenConfig))) {
        return 'Ffigen config evidence must pair only $_ffigenPolicyTest with $_ffigenConfig.';
      }
      if (referenced.contains(_ffigenConfig) &&
          (changes[_ffigenConfig]?.kind == RepositoryChangeKind.deleted ||
              renamedSources.contains(_ffigenConfig))) {
        return 'Ffigen config evidence requires the current root config at the head.';
      }
      final harnessTest = entry.key.startsWith(
        'packages/llamadart_validation/test/',
      );
      final harnessRefs = referenced.where(_isValidationHarnessProductionPath);
      if ((harnessTest && harnessRefs.length != referenced.length) ||
          (harnessRefs.isNotEmpty &&
              !harnessTest &&
              !entry.key.startsWith('test/unit/tooling/'))) {
        return 'Private harness evidence must use paired harness or root tooling tests: ${entry.key}.';
      }
      final pairedScript = _nativeSyncPythonTests[entry.key];
      if (pairedScript != null) {
        final command = proof['command'] as String;
        final module = entry.key
            .substring(0, entry.key.length - '.py'.length)
            .replaceAll('/', '.');
        if (!referenced.contains(pairedScript) ||
            !(command.contains(entry.key) || command.contains(module))) {
          return 'Python evidence must run its own suite and reference $pairedScript: ${entry.key}.';
        }
      }
      if (!await refsExist(refs) ||
          (changedProduction.isNotEmpty &&
              referenced.intersection(changedProduction).isEmpty)) {
        return 'Test evidence is disconnected from the changed production path: ${entry.key}.';
      }
      coveredProduction.addAll(referenced);
    }
    if (!coveredProduction.containsAll(testedProduction)) {
      return 'Some changed production paths lack reviewed test reachability.';
    }
    final structured =
        evidence['structured_output_evidence'] as Map<String, dynamic>?;
    if (structured == null) return null;
    final impacts = structured['impacts'] as Map<String, dynamic>;
    final minimumImpacts = <StructuredImpact>{};
    var hasProductionContribution = false;
    for (final path in inspectedPaths) {
      final contribution = structuredProductionImpactHints(path);
      if (contribution == null) continue;
      hasProductionContribution = true;
      if (path == 'lib/llamadart.dart' &&
          await _isAdditiveImageExport(context, changes, workingDirectory)) {
        continue;
      }
      minimumImpacts.addAll(contribution);
    }
    if (!hasProductionContribution) {
      minimumImpacts.addAll(StructuredImpact.values);
    }
    final minimum = minimumImpacts.map((impact) => impact.name).toSet();
    final requiredAxes = <String>{};
    for (final entry in impacts.entries) {
      final impact = entry.value as Map<String, dynamic>;
      final refs = impact['production_refs'] as List<dynamic>;
      final referenced = refs
          .map((ref) => (ref as Map)['path'] as String)
          .toSet();
      if (!await refsExist(refs) ||
          !referenced.containsAll(changedProduction)) {
        return 'Impact review must inspect the changed production paths and their callsites.';
      }
      if (minimum.contains(entry.key) && impact['applicable'] != true) {
        return 'Known or unknown/mixed production effects cannot be excluded: ${entry.key}.';
      }
      if (impact['applicable'] == true) {
        requiredAxes.addAll(_impactAxes[entry.key]!);
      }
    }
    final coverage = structured['coverage'] as Map<String, dynamic>;
    for (final axis in requiredAxes) {
      if ((coverage[axis] as List).isEmpty) {
        return 'Applicable impact requires coverage.$axis.';
      }
    }
    return null;
  }

  // Only in-place edits of regular Dart blobs qualify. An unreadable blob
  // keeps the ordinary causal-test route instead of failing the evaluation.
  Future<Set<String>> _commentOnlyProductionPaths(
    PullRequestContext context,
    List<RepositoryChange> changes,
    String? workingDirectory,
  ) async {
    final proven = <String>{};
    for (final change in changes) {
      if (change.kind != RepositoryChangeKind.modified ||
          change.previousPath != null ||
          !_isProductionPath(change.path) ||
          !change.path.endsWith('.dart')) {
        continue;
      }
      try {
        final base = await repositoryState.fileAt(
          context.baseSha,
          change.path,
          workingDirectory: workingDirectory,
        );
        final head = await repositoryState.fileAt(
          context.headSha,
          change.path,
          workingDirectory: workingDirectory,
        );
        if (base?.mode == '100644' &&
            head?.mode == '100644' &&
            isCommentOnlyDartChange(
              change.path,
              base!.contents,
              head!.contents,
            )) {
          proven.add(change.path);
        }
      } on Object {
        continue;
      }
    }
    return proven;
  }

  // This recognizes one reviewed export shape, not arbitrary "image paths".
  // It proves additive namespace/loading properties; the independent review
  // still owns the behavioral impact decisions and transitive callsite review.
  Future<bool> _isAdditiveImageExport(
    PullRequestContext context,
    Map<String, RepositoryChange> changes,
    String? workingDirectory,
  ) async {
    const barrel = 'lib/llamadart.dart';
    const target = 'lib/src/core/image/image_editing_request.dart';
    const addition =
        "export 'src/core/image/image_editing_request.dart'\n"
        '    show ImageEditingPixels, ImageEditingRequest;\n';
    const imports = {
      'dart:typed_data',
      'lib/src/core/exceptions.dart',
      'lib/src/core/image/image_generation_driver.dart',
      'lib/src/core/image/image_generation_request.dart',
    };
    if (changes[barrel]?.kind != RepositoryChangeKind.modified ||
        changes[barrel]?.previousPath != null ||
        changes[target]?.kind != RepositoryChangeKind.added ||
        changes[target]?.previousPath != null) {
      return false;
    }
    Future<ReadinessFile?> read(String sha, String path) =>
        repositoryState.fileAt(sha, path, workingDirectory: workingDirectory);
    final base = await read(context.baseSha, barrel);
    final head = await read(context.headSha, barrel);
    final image = await read(context.headSha, target);
    if (base?.mode != '100644' ||
        head?.mode != '100644' ||
        image?.mode != '100644' ||
        await read(context.baseSha, target) != null) {
      return false;
    }
    final offset = head!.contents.indexOf(addition);
    if (offset < 0 ||
        (offset != 0 && head.contents[offset - 1] != '\n') ||
        head.contents.indexOf(addition, offset + addition.length) >= 0 ||
        head.contents.replaceRange(offset, offset + addition.length, '') !=
            base!.contents) {
      return false;
    }
    CompilationUnit? parse(String source) {
      final parsed = parseString(content: source, throwIfDiagnostics: false);
      return parsed.errors.isEmpty ? parsed.unit : null;
    }

    final headUnit = parse(head.contents);
    final additions = headUnit?.directives.whereType<ExportDirective>().where(
      (directive) =>
          directive.offset == offset &&
          directive.end == offset + addition.trimRight().length,
    );
    if (additions == null || additions.length != 1) return false;
    final imageUnit = parse(image!.contents);
    if (imageUnit == null || imageUnit.directives.length != imports.length) {
      return false;
    }
    final actualImports = <String>{};
    for (final directive in imageUnit.directives) {
      if (directive is! ImportDirective ||
          directive.metadata.isNotEmpty ||
          directive.configurations.isNotEmpty ||
          directive.combinators.isNotEmpty ||
          directive.prefix != null ||
          directive.deferredKeyword != null) {
        return false;
      }
      final uri = directive.uri.stringValue;
      final resolved = uri == 'dart:typed_data'
          ? uri
          : _localExportPath(target, uri);
      if (resolved == null || !actualImports.add(resolved)) return false;
    }
    if (!_sameSet(actualImports, imports)) return false;
    final declarations = imageUnit.declarations;
    if (declarations.length != 3) return false;
    final classes = declarations.whereType<ClassDeclaration>().toList();
    final helper = declarations.whereType<FunctionDeclaration>().toList();
    if (classes.length != 2 ||
        helper.length != 1 ||
        helper.single.name.lexeme != 'validateImageEditingRecipe' ||
        declarations.any((node) => node.metadata.isNotEmpty)) {
      return false;
    }
    final expectedParents = {
      'ImageEditingPixels': null,
      'ImageEditingRequest': 'extends ImageGenerationRequest',
    };
    for (final declaration in classes) {
      final name = declaration.classKeyword.next;
      if (name == null ||
          !expectedParents.containsKey(name.lexeme) ||
          declaration.finalKeyword == null ||
          declaration.extendsClause?.toSource() !=
              expectedParents.remove(name.lexeme) ||
          declaration.withClause != null ||
          declaration.implementsClause != null ||
          !{'{', 'extends'}.contains(name.next?.lexeme)) {
        return false;
      }
    }
    if (expectedParents.isNotEmpty) return false;

    // Over-approximate the old namespace at both revisions: inspect every
    // conditional export branch and ignore show/hide filters. Uncertain graphs
    // retain the ordinary minima instead of claiming absence of collisions.
    // The byte proof above makes base.contents exactly the head barrel with
    // the one proven addition removed. All other export edges remain visible.
    for (final sha in [context.baseSha, context.headSha]) {
      final visiting = <String>{};
      final units = <String, CompilationUnit>{};
      final loaded = <String>{};
      final inspected = <(String, bool)>{};
      Future<bool> inspect(String path, bool guaranteed) async {
        if (visiting.contains(path)) return false;
        if (inspected.contains((path, guaranteed))) return true;
        visiting.add(path);
        final file = await read(sha, path);
        final unit =
            units[path] ??
            (file?.mode == '100644'
                ? parse(path == barrel ? base.contents : file!.contents)
                : null);
        if (unit == null) return false;
        units[path] = unit;
        if (_hasImageExportName(unit, tokensOnly: sha == context.baseSha)) {
          return false;
        }
        if (guaranteed) loaded.add(path);
        for (final directive in unit.directives) {
          if (directive is LibraryDirective || directive is ImportDirective) {
            if (guaranteed &&
                directive is ImportDirective &&
                directive.configurations.isEmpty &&
                directive.deferredKeyword == null) {
              final uri = directive.uri.stringValue;
              final dependency = uri?.startsWith('dart:') == true
                  ? uri
                  : _localExportPath(path, uri);
              if (dependency != null) loaded.add(dependency);
            }
            continue;
          }
          if (directive is! ExportDirective) return false;
          final uris = [
            directive.uri.stringValue,
            for (final branch in directive.configurations)
              branch.uri.stringValue,
          ];
          for (final uri in uris) {
            final child = _localExportPath(path, uri);
            if (child == null ||
                !await inspect(
                  child,
                  guaranteed && directive.configurations.isEmpty,
                )) {
              return false;
            }
          }
        }
        visiting.remove(path);
        inspected.add((path, guaranteed));
        return true;
      }

      if (!await inspect(barrel, true) || !loaded.containsAll(imports)) {
        return false;
      }
      for (final dependency in imports.where((uri) => uri.startsWith('lib/'))) {
        if ((await read(sha, dependency))?.mode != '100644') return false;
      }
    }
    return true;
  }

  static String? _localExportPath(String source, String? value) {
    if (value == null ||
        value.isEmpty ||
        value.contains('%') ||
        value.contains('\\') ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.startsWith('/')) {
      return null;
    }
    final resolved = Uri(path: source).resolveUri(uri).path;
    return resolved.startsWith('lib/') && resolved.endsWith('.dart')
        ? resolved
        : null;
  }

  static bool _hasImageExportName(
    CompilationUnit unit, {
    required bool tokensOnly,
  }) {
    const names = {'ImageEditingPixels', 'ImageEditingRequest'};
    if (tokensOnly) {
      // These new identifiers must be absent before the addition. Tokens avoid
      // mistaking comments or string contents for declarations or references.
      for (var token = unit.beginToken; !token.isEof; token = token.next!) {
        if (token.type == TokenType.IDENTIFIER &&
            names.contains(token.lexeme)) {
          return true;
        }
      }
      return false;
    }
    Token? nameAfter(Token keyword, {bool optionalConst = false}) {
      var token = keyword.next;
      if (optionalConst && token != null && token.lexeme == 'const') {
        token = token.next;
      }
      return token?.type == TokenType.IDENTIFIER ? token : null;
    }

    // Existing head image code may reference the new types inside methods.
    // Inspect actual namespace declarations, never a guessed header boundary:
    // record and function return types can contain braces before the name.
    for (final declaration in unit.declarations) {
      final declared = switch (declaration) {
        // Keyword-anchored name tokens span analyzer 8 through 14. The newer
        // namePart API is absent, nullable or gated in allowed older versions.
        ClassDeclaration() => [nameAfter(declaration.classKeyword)],
        ClassTypeAlias() => [declaration.name],
        EnumDeclaration() => [nameAfter(declaration.enumKeyword)],
        MixinDeclaration() => [declaration.name],
        ExtensionDeclaration() => [
          if (declaration.name != null) declaration.name!,
        ],
        ExtensionTypeDeclaration() => [
          nameAfter(declaration.typeKeyword, optionalConst: true),
        ],
        FunctionDeclaration() => [declaration.name],
        FunctionTypeAlias() => [declaration.name],
        GenericTypeAlias() => [declaration.name],
        TopLevelVariableDeclaration() => [
          for (final variable in declaration.variables.variables) variable.name,
        ],
        _ => null,
      };
      if (declared == null ||
          declared.any(
            (token) =>
                token == null || token.isSynthetic || token.lexeme.isEmpty,
          ) ||
          declared.any((token) => names.contains(token?.lexeme))) {
        return true;
      }
    }
    return false;
  }

  Future<(ReadinessFailureClassification, String)?> _validateEvidencePath(
    String path,
    String headSha,
    Map<String, RepositoryChange> changedByPath,
    Set<String> previousPaths, {
    String? workingDirectory,
  }) async {
    if (!_isProductionTestPath(path)) {
      return (
        ReadinessFailureClassification.nonTestPathCited,
        'Evidence path is not a repository-relative production test: $path.',
      );
    }
    if (previousPaths.contains(path)) {
      return (
        ReadinessFailureClassification.renamedEvidencePath,
        'Evidence cites the old side of a rename: $path.',
      );
    }
    final change = changedByPath[path];
    if (change?.kind == RepositoryChangeKind.deleted) {
      return (
        ReadinessFailureClassification.deletedEvidencePath,
        'Evidence path is deleted in the candidate: $path.',
      );
    }
    if (!await repositoryState.pathIsRegularFileAt(
      headSha,
      path,
      workingDirectory: workingDirectory,
    )) {
      return (
        ReadinessFailureClassification.missingTestPath,
        'Evidence path is not a regular file in the exact candidate tree: $path.',
      );
    }
    return null;
  }

  static String? _validateContext(PullRequestContext context) {
    if (!_isRepository(context.repository)) {
      return 'Independently supplied repository must use owner/repository form.';
    }
    if (context.prNumber < 1) {
      return 'Independently supplied PR number must be positive.';
    }
    if (!_isSha(context.headSha) || !_isSha(context.baseSha)) {
      return 'Independently supplied head and base must be nonzero lowercase SHA-1 values.';
    }
    if (!_isGitHubLogin(context.author)) {
      return 'Independently supplied PR author is invalid.';
    }
    return null;
  }

  static String? _validateShape(Map<String, dynamic> evidence) {
    if (evidence['schema'] != HighRiskReadinessResult.schema ||
        evidence['schema_version'] != HighRiskReadinessResult.schemaVersion) {
      return 'Unsupported evidence schema or schema_version; historical v1 evidence must be reviewed and reissued as v2.';
    }
    final rootError = _exactKeys(evidence, _rootKeys, 'evidence');
    if (rootError != null) return rootError;
    if (!_isUtcTimestamp(evidence['timestamp'])) {
      return 'timestamp must be a valid RFC 3339 UTC string.';
    }
    if (!_isIdentifier(evidence['correlation_id'])) {
      return 'correlation_id has an invalid type or form.';
    }
    if (!_isRepository(evidence['repository'])) {
      return 'repository must use owner/repository form.';
    }
    if (evidence['pr_number'] is! int || (evidence['pr_number'] as int) < 1) {
      return 'pr_number must be a positive integer.';
    }
    for (final field in ['expected_pr_head_sha', 'current_base_sha']) {
      if (!_isSha(evidence[field])) {
        return '$field must be a nonzero lowercase SHA-1.';
      }
    }
    if (!_isGitHubLogin(evidence['pr_author'])) return 'pr_author is invalid.';
    if (evidence['classification'] != 'standard' &&
        evidence['classification'] != 'high-risk') {
      return 'classification must be standard or high-risk.';
    }
    if (evidence['evaluation'] != null) {
      return 'Input evidence must set evaluation to null; decisions are evaluator-owned.';
    }
    final surfacesError = _stringList(
      evidence['surfaces'],
      'surfaces',
      allowed: HighRiskSurface.values.map((surface) => surface.name).toSet(),
    );
    if (surfacesError != null) return surfacesError;
    final rowsError = _stringList(
      evidence['required_matrix_row_ids'],
      'required_matrix_row_ids',
      allowed: _knownMatrixRows,
    );
    if (rowsError != null) return rowsError;
    final testsError = _stringList(
      evidence['affected_test_paths'],
      'affected_test_paths',
    );
    if (testsError != null) return testsError;

    final matrix = evidence['matrix_row_evidence'];
    if (matrix is! Map<String, dynamic>) {
      return 'matrix_row_evidence must be an object.';
    }
    for (final entry in matrix.entries) {
      if (!_knownMatrixRows.contains(entry.key)) {
        return 'matrix_row_evidence contains unknown row "${entry.key}".';
      }
      final row = entry.value;
      if (row is! Map<String, dynamic>) {
        return 'Matrix row ${entry.key} must be an object.';
      }
      final error = _exactKeys(row, _matrixKeys, 'matrix row ${entry.key}');
      if (error != null) return error;
      if (!_knownMatrixRows.contains(row['row_id']) ||
          !const {'pass', 'fail', 'notApplicable'}.contains(row['result']) ||
          !_isNonEmptyString(row['command']) ||
          !_isNonEmptyString(row['evidence_notes'])) {
        return 'Matrix row ${entry.key} has invalid field types or values.';
      }
    }

    final audit = evidence['independent_audit'];
    if (audit != null) {
      if (audit is! Map<String, dynamic>) {
        return 'independent_audit must be an object or null.';
      }
      final error = _exactKeys(audit, _auditKeys, 'independent_audit');
      if (error != null) return error;
      if (!_isIdentifier(audit['auditor_identity']) ||
          !const {
            'operator-owned',
            'codex-adversarial',
          }.contains(audit['audit_kind']) ||
          !_isSha(audit['audit_head_sha']) ||
          !_isSha(audit['audit_base_sha']) ||
          !const {
            'accepted',
            'rejected',
            'blocked',
          }.contains(audit['decision']) ||
          audit['unresolved_review_threads'] is! int ||
          (audit['unresolved_review_threads'] as int) < 0 ||
          audit['known_pr_caused_p1_regressions'] is! int ||
          (audit['known_pr_caused_p1_regressions'] as int) < 0 ||
          !_isNonEmptyString(audit['summary'])) {
        return 'independent_audit has invalid field types or values.';
      }
    }

    final impactError = _validateImpactShape(evidence);
    if (impactError != null) return impactError;
    final structured = evidence['structured_output_evidence'];
    if (structured != null) {
      if (structured is! Map<String, dynamic>) {
        return 'structured_output_evidence must be an object or null.';
      }
      final error = _exactKeys(
        structured,
        _structuredKeys,
        'structured_output_evidence',
      );
      if (error != null) return error;
      final coverage = structured['coverage'];
      if (coverage is! Map<String, dynamic>) {
        return 'structured coverage must be an object.';
      }
      final coverageError = _exactKeys(
        coverage,
        _coverageAxes,
        'structured coverage',
      );
      if (coverageError != null) return coverageError;
      for (final axis in _coverageAxes) {
        final axisError = _stringList(coverage[axis], 'coverage.$axis');
        if (axisError != null) return axisError;
      }
      final families = structured['families'];
      if (families is! List || families.isEmpty) {
        return 'structured families must be a non-empty list.';
      }
      final familyNames = <String>{};
      for (final value in families) {
        if (value is! Map<String, dynamic>) {
          return 'Each structured family must be an object.';
        }
        final familyError = _exactKeys(value, _familyKeys, 'structured family');
        if (familyError != null) return familyError;
        final family = value['family'];
        if (!_isIdentifier(family) || !familyNames.add(family as String)) {
          return 'Structured family names must be valid and unique.';
        }
        if (!const {'tested', 'unavailable'}.contains(value['status']) ||
            !_isNonEmptyString(value['rationale'])) {
          return 'Structured family status or rationale is invalid.';
        }
        final pathsError = _stringList(
          value['evidence_test_paths'],
          'family.evidence_test_paths',
          requireNonEmpty: true,
        );
        if (pathsError != null) return pathsError;
      }
    }
    return null;
  }

  static String? _validateStandardEvidence(Map<String, dynamic> evidence) {
    if ((evidence['surfaces'] as List<dynamic>).isNotEmpty ||
        (evidence['required_matrix_row_ids'] as List<dynamic>).isNotEmpty ||
        (evidence['matrix_row_evidence'] as Map<String, dynamic>).isNotEmpty ||
        evidence['independent_audit'] != null ||
        evidence['structured_output_evidence'] != null ||
        (evidence['affected_test_paths'] as List<dynamic>).isNotEmpty ||
        (evidence['test_evidence'] is Map &&
            (evidence['test_evidence'] as Map).isNotEmpty)) {
      return 'Standard-risk evidence must not contain high-risk claims.';
    }
    return null;
  }

  static Map<String, Object?> _safeOutputEvidence(
    Map<String, dynamic> evidence,
    PullRequestContext context,
    DateTime now, {
    required bool preserveEvidence,
  }) {
    if (!preserveEvidence) {
      return <String, Object?>{
        'schema': HighRiskReadinessResult.schema,
        'schema_version': HighRiskReadinessResult.schemaVersion,
        'timestamp': now.toIso8601String(),
        'test_evidence': const <String, Object?>{},
        'correlation_id': 'invalid-input',
        ..._boundIdentity(context),
        'classification': 'standard',
        'surfaces': const <String>[],
        'required_matrix_row_ids': const <String>[],
        'matrix_row_evidence': const <String, Object?>{},
        'independent_audit': null,
        'structured_output_evidence': null,
        'affected_test_paths': const <String>[],
      };
    }
    Object? safe(String key, Object? fallback) => evidence[key] ?? fallback;
    return <String, Object?>{
      'schema': HighRiskReadinessResult.schema,
      'schema_version': HighRiskReadinessResult.schemaVersion,
      'test_evidence': evidence['test_evidence'],
      'timestamp': _isUtcTimestamp(evidence['timestamp'])
          ? evidence['timestamp']
          : now.toIso8601String(),
      'correlation_id': _isIdentifier(evidence['correlation_id'])
          ? evidence['correlation_id']
          : 'invalid-input',
      ..._boundIdentity(context),
      'classification':
          const {'standard', 'high-risk'}.contains(evidence['classification'])
          ? evidence['classification']
          : 'standard',
      'surfaces': safe('surfaces', const <String>[]),
      'required_matrix_row_ids': safe(
        'required_matrix_row_ids',
        const <String>[],
      ),
      'matrix_row_evidence': safe(
        'matrix_row_evidence',
        const <String, Object?>{},
      ),
      'independent_audit': evidence['independent_audit'],
      'structured_output_evidence': evidence['structured_output_evidence'],
      'affected_test_paths': safe('affected_test_paths', const <String>[]),
    };
  }

  /// Emitted identity always comes from the independently supplied context, so
  /// a rejected result can never claim a different repository, PR, head, base,
  /// or author than the one that was actually evaluated.
  static Map<String, Object?> _boundIdentity(PullRequestContext context) =>
      <String, Object?>{
        'repository': _isRepository(context.repository)
            ? context.repository
            : 'invalid/invalid',
        'pr_number': context.prNumber > 0 ? context.prNumber : 1,
        'expected_pr_head_sha': _isSha(context.headSha)
            ? context.headSha
            : 'ffffffffffffffffffffffffffffffffffffffff',
        'current_base_sha': _isSha(context.baseSha)
            ? context.baseSha
            : 'ffffffffffffffffffffffffffffffffffffffff',
        'pr_author': _isGitHubLogin(context.author)
            ? context.author
            : 'invalid-author',
      };

  static String? _exactKeys(
    Map<String, dynamic> value,
    Set<String> expected,
    String label,
  ) {
    final actual = value.keys.toSet();
    final missing = expected.difference(actual);
    final unknown = actual.difference(expected);
    if (missing.isNotEmpty) {
      return '$label is missing keys: ${_sorted(missing).join(', ')}.';
    }
    if (unknown.isNotEmpty) {
      return '$label has unknown keys: ${_sorted(unknown).join(', ')}.';
    }
    return null;
  }

  static String? _stringList(
    Object? value,
    String label, {
    Set<String>? allowed,
    bool requireNonEmpty = false,
  }) {
    if (value is! List) return '$label must be a list.';
    if (requireNonEmpty && value.isEmpty) return '$label must not be empty.';
    final strings = <String>[];
    for (final item in value) {
      if (!_isNonEmptyString(item)) {
        return '$label must contain only non-empty strings.';
      }
      strings.add(item as String);
      if (allowed != null && !allowed.contains(item)) {
        return '$label contains unknown value "$item".';
      }
    }
    if (strings.toSet().length != strings.length) {
      return '$label must not contain duplicates.';
    }
    return null;
  }

  static bool _isSha(Object? value) =>
      value is String &&
      value != _zeroSha &&
      RegExp(r'^[0-9a-f]{40}$').hasMatch(value);

  static bool _isRepository(Object? value) =>
      value is String &&
      RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(value);

  static bool _isGitHubLogin(Object? value) =>
      value is String &&
      RegExp(
        r'^(?!.*--)[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?(?:\[bot\])?(?![\s\S])',
      ).hasMatch(value);

  static bool _isIdentifier(Object? value) =>
      value is String &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:@-]{0,127}$').hasMatch(value);

  static bool _isNonEmptyString(Object? value) =>
      value is String && value.trim().isNotEmpty && value == value.trim();

  static bool _isUtcTimestamp(Object? value) {
    if (value is! String) {
      return false;
    }
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?Z$',
    ).firstMatch(value);
    final parsed = DateTime.tryParse(value);
    if (match == null || parsed == null || !parsed.isUtc) return false;
    return parsed.year == int.parse(match.group(1)!) &&
        parsed.month == int.parse(match.group(2)!) &&
        parsed.day == int.parse(match.group(3)!) &&
        parsed.hour == int.parse(match.group(4)!) &&
        parsed.minute == int.parse(match.group(5)!) &&
        parsed.second == int.parse(match.group(6)!);
  }

  static bool _isProductionPath(String path) =>
      path == _ffigenConfig ||
      path.startsWith('lib/') ||
      path.startsWith('tool/') ||
      path.startsWith('hook/') ||
      path.startsWith('packages/genkit_llamadart/lib/') ||
      _isValidationHarnessProductionPath(path) ||
      isWorkflowPath(path);

  static bool _isValidationHarnessProductionPath(String path) =>
      path.startsWith('packages/llamadart_validation/lib/') ||
      path == 'packages/llamadart_validation/assets/capability_coverage.json';

  static bool _isProductionTestPath(String path) {
    if (path.startsWith('/') ||
        path.contains('\\') ||
        path.contains('*') ||
        path.contains('?') ||
        path.contains('[') ||
        path.contains(']') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
        path
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      return false;
    }
    if (_nativeSyncPythonTests.containsKey(path)) return true;
    return (path.startsWith('test/') ||
            path.startsWith('packages/genkit_llamadart/test/') ||
            path.startsWith('packages/llamadart_validation/test/')) &&
        path.endsWith('_test.dart');
  }

  static bool _isValidRepositoryChange(RepositoryChange change) {
    if (change.path.isEmpty || change.path.contains('\u0000')) return false;
    final hasSource = change.previousPath != null;
    if (change.kind == RepositoryChangeKind.renamed ||
        change.kind == RepositoryChangeKind.copied) {
      return hasSource &&
          change.previousPath!.isNotEmpty &&
          !change.previousPath!.contains('\u0000') &&
          change.previousPath != change.path;
    }
    return !hasSource;
  }

  static bool _isRetiredQaIdentity(String identity) => RegExp(
    r'^(qa|qa[-_]agent|qa[-_]profile|qa[-_]task)$',
    caseSensitive: false,
  ).hasMatch(identity);

  static bool _sameSet<T>(Set<T> left, Set<T> right) =>
      left.length == right.length && left.containsAll(right);

  static List<String> _sorted(Iterable<String> values) =>
      values.toList()..sort();
}

String _usage() =>
    '''Usage: dart run tool/testing/high_risk_readiness.dart [options]

Required:
  --evidence <path>       Evidence JSON file, or - for stdin.
  --repository <owner/repo>
  --pr-number <number>
  --head-sha <sha>        Independently observed exact PR head.
  --base-sha <sha>        Independently observed exact PR base.
  --pr-author <login>     Independently observed PR author.

Other:
  --schema                Print the canonical schema.
  -h, --help              Show this help.

The CLI derives changed files and candidate-tree path existence from Git. It
never accepts App credentials or emits operational readiness.
''';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage());
    return;
  }
  if (args.length == 1 && args.single == '--schema') {
    final file = File('tool/testing/high_risk_readiness_evidence.schema.json');
    if (!file.existsSync()) {
      stderr.writeln('Schema file not found.');
      exitCode = 66;
      return;
    }
    stdout.write(file.readAsStringSync());
    return;
  }

  final values = <String, String>{};
  const valuedOptions = <String>{
    '--evidence',
    '--repository',
    '--pr-number',
    '--head-sha',
    '--base-sha',
    '--pr-author',
  };
  for (var i = 0; i < args.length; i++) {
    final option = args[i];
    if (!valuedOptions.contains(option) ||
        i + 1 >= args.length ||
        values.containsKey(option)) {
      stderr.writeln('Unknown, duplicate, or valueless option: $option');
      stdout.write(_usage());
      exitCode = 64;
      return;
    }
    values[option] = args[++i];
  }
  if (!values.keys.toSet().containsAll(valuedOptions)) {
    stderr.writeln('All required options must be supplied.');
    stdout.write(_usage());
    exitCode = 64;
    return;
  }

  final prNumber = int.tryParse(values['--pr-number']!);
  if (prNumber == null || prNumber < 1) {
    stderr.writeln('--pr-number must be a positive integer.');
    exitCode = 64;
    return;
  }
  late final String source;
  try {
    source = values['--evidence'] == '-'
        ? await stdin.transform(utf8.decoder).join()
        : await File(values['--evidence']!).readAsString();
  } on Object catch (error) {
    stderr.writeln('Could not read evidence: $error');
    exitCode = 66;
    return;
  }
  late final Map<String, dynamic> evidence;
  try {
    evidence = decodeStrictJsonObject(source);
  } on Object catch (error) {
    stderr.writeln('Invalid evidence JSON: $error');
    exitCode = 65;
    return;
  }

  final result = await const HighRiskReadinessEvaluator().evaluate(
    evidence: evidence,
    context: PullRequestContext(
      repository: values['--repository']!,
      prNumber: prNumber,
      headSha: values['--head-sha']!,
      baseSha: values['--base-sha']!,
      author: values['--pr-author']!,
    ),
  );
  stdout.writeln(result.toFormattedJson());
  exitCode = switch (result.decision) {
    ReadinessDecision.standardRiskDiagnostic => 0,
    ReadinessDecision.rejected => 1,
    ReadinessDecision.unverifiedPrerequisites => 2,
  };
}
