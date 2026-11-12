#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

/// Decision reached while evaluating a PR head update.
enum PrHeadUpdateDecision { accepted, rejected, noOp, validated }

/// Stable failure classes emitted in PR head update evidence.
enum PrHeadUpdateFailureClassification {
  none,
  expectedHeadMismatch,
  nonDescendantHistory,
  staleAncestorRewind,
  invalidInput,
  invalidRemoteConfiguration,
  commitObjectMissing,
  remoteRefMissing,
  gitExecutionError,
  remoteMutationFailed,
  postMutationVerificationFailed,
  prePushHookRejected,
}

/// Structured, sanitized audit evidence for one update attempt.
class PrHeadUpdateResult {
  const PrHeadUpdateResult({
    required this.timestamp,
    required this.correlationId,
    required this.writer,
    required this.targetRef,
    required this.remote,
    required this.expectedHeadSha,
    required this.remoteHeadBefore,
    required this.proposedHeadSha,
    required this.remoteHeadAfter,
    required this.decision,
    required this.failureClassification,
    required this.message,
  });

  static const String schema = 'llamadart.pr-head-update-evidence';
  static const String schemaVersion = '1.0.0';

  final DateTime timestamp;
  final String correlationId;
  final String writer;
  final String targetRef;
  final String remote;
  final String? expectedHeadSha;
  final String? remoteHeadBefore;
  final String proposedHeadSha;
  final String? remoteHeadAfter;
  final PrHeadUpdateDecision decision;
  final PrHeadUpdateFailureClassification failureClassification;
  final String message;

  bool get isSuccess => decision != PrHeadUpdateDecision.rejected;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schema,
    'schema_version': schemaVersion,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'correlation_id': correlationId,
    'writer': writer,
    'target_ref': targetRef,
    'remote': remote,
    'expected_head_sha': expectedHeadSha,
    'remote_head_before': remoteHeadBefore,
    'proposed_head_sha': proposedHeadSha,
    'remote_head_after': remoteHeadAfter,
    'decision': decision.name,
    'failure_classification': failureClassification.name,
    'message': message,
  };

  String toFormattedJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Process abstraction used by deterministic tests.
typedef GitCommandRunner =
    Future<ProcessResult> Function(
      List<String> args, {
      String? workingDirectory,
    });

/// Runs Git without invoking a shell.
Future<ProcessResult> defaultGitCommandRunner(
  List<String> args, {
  String? workingDirectory,
}) {
  return Process.run('git', args, workingDirectory: workingDirectory);
}

const String _zeroOid = '0000000000000000000000000000000000000000';

bool _isValidIdentifier(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,127}$').hasMatch(value);

/// Returns whether [branch] is in the safe subset accepted by this tool.
bool isValidBranchName(String branch) {
  if (branch.isEmpty || branch.length > 255) return false;
  if (branch.startsWith('refs/') && !branch.startsWith('refs/heads/')) {
    return false;
  }
  final name = branch.startsWith('refs/heads/')
      ? branch.substring('refs/heads/'.length)
      : branch;
  final components = name.split('/');
  return name.isNotEmpty &&
      !name.startsWith('-') &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$').hasMatch(name) &&
      components.every(
        (component) =>
            component.isNotEmpty &&
            !component.startsWith('.') &&
            !component.endsWith('.lock'),
      ) &&
      !name.endsWith('/') &&
      !name.endsWith('.') &&
      !name.contains('..') &&
      !name.contains('//');
}

/// Returns whether [remote] is a safe configured remote name, never a URL.
bool isValidRemoteName(String remote) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$').hasMatch(remote) &&
    !remote.contains('//') &&
    !remote.contains('..');

/// Returns whether [sha] is a full hexadecimal object ID.
bool isValidCommitSha(String sha, {bool allowZero = false}) {
  final value = sha.trim().toLowerCase();
  return RegExp(r'^[0-9a-f]{40}$').hasMatch(value) &&
      (allowZero || value != _zeroOid);
}

bool _isSafePushUrl(String value) {
  if (value.isEmpty || value.contains('\n') || value.contains('\r')) {
    return false;
  }
  if (value.startsWith('/') ||
      value.startsWith('./') ||
      value.startsWith('../')) {
    return true;
  }
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) return true;
  if (RegExp(
    r'^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[A-Za-z0-9._/~+-]+$',
  ).hasMatch(value)) {
    return true;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty || uri.hasQuery || uri.hasFragment) {
    return false;
  }
  if (uri.scheme == 'https') {
    return uri.userInfo.isEmpty;
  }
  if (uri.scheme == 'ssh') {
    return uri.userInfo.isEmpty ||
        RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(uri.userInfo);
  }
  return false;
}

String? _parseExactRemoteHead(String output, String targetRef) {
  String? found;
  for (final line in const LineSplitter().convert(output.trim())) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length != 2 || fields[1] != targetRef) continue;
    final sha = fields[0].toLowerCase();
    if (!isValidCommitSha(sha) || found != null) return null;
    found = sha;
  }
  return found;
}

PrHeadUpdateResult _evidence({
  required DateTime timestamp,
  required String correlationId,
  required String writer,
  required String targetRef,
  required String remote,
  required String? expected,
  required String? before,
  required String proposed,
  required String? after,
  required PrHeadUpdateDecision decision,
  required PrHeadUpdateFailureClassification classification,
  required String message,
}) {
  return PrHeadUpdateResult(
    timestamp: timestamp,
    correlationId: correlationId,
    writer: writer,
    targetRef: targetRef,
    remote: remote,
    expectedHeadSha: expected,
    remoteHeadBefore: before,
    proposedHeadSha: proposed,
    remoteHeadAfter: after,
    decision: decision,
    failureClassification: classification,
    message: message,
  );
}

/// Enforces expected-head CAS and strict fast-forward ancestry for a PR ref.
class SafePrHeadUpdate {
  const SafePrHeadUpdate({this.gitRunner = defaultGitCommandRunner});

  final GitCommandRunner gitRunner;

  Future<PrHeadUpdateResult> updatePrHead({
    required String remote,
    required String branch,
    required String expectedHeadSha,
    required String proposedHeadSha,
    required String writer,
    String? correlationId,
    bool dryRun = false,
    String? workingDirectory,
  }) async {
    final timestamp = DateTime.now();
    final safeRemote = remote.trim();
    final safeBranch = branch.trim();
    final expected = expectedHeadSha.trim().toLowerCase();
    final proposed = proposedHeadSha.trim().toLowerCase();
    final safeWriter = writer.trim();
    final safeCorrelation =
        correlationId?.trim() ??
        'pr-head-update-${timestamp.microsecondsSinceEpoch}';
    final writerIsValid = _isValidIdentifier(safeWriter);
    final correlationIsValid = _isValidIdentifier(safeCorrelation);
    final remoteIsValid = isValidRemoteName(safeRemote);
    final branchIsValid = isValidBranchName(safeBranch);
    final expectedIsValid = isValidCommitSha(expected, allowZero: true);
    final proposedIsValid = isValidCommitSha(proposed);
    final targetRef = branchIsValid
        ? (safeBranch.startsWith('refs/heads/')
              ? safeBranch
              : 'refs/heads/$safeBranch')
        : '<invalid>';
    final evidenceWriter = writerIsValid ? safeWriter : '<invalid>';
    final evidenceCorrelation = correlationIsValid
        ? safeCorrelation
        : '<invalid>';
    final evidenceRemote = remoteIsValid ? safeRemote : '<invalid>';
    final evidenceExpected = expectedIsValid ? expected : _zeroOid;
    final evidenceProposed = proposedIsValid ? proposed : _zeroOid;

    PrHeadUpdateResult reject(
      PrHeadUpdateFailureClassification classification,
      String message, {
      String? before,
      String? after,
      String? overrideRemote,
      String? overrideWriter,
      String? overrideCorrelation,
      String? overrideTarget,
      String? overrideExpected,
      String? overrideProposed,
    }) => _evidence(
      timestamp: timestamp,
      correlationId: overrideCorrelation ?? evidenceCorrelation,
      writer: overrideWriter ?? evidenceWriter,
      targetRef: overrideTarget ?? targetRef,
      remote: overrideRemote ?? evidenceRemote,
      expected: overrideExpected ?? evidenceExpected,
      before: before,
      proposed: overrideProposed ?? evidenceProposed,
      after: after,
      decision: PrHeadUpdateDecision.rejected,
      classification: classification,
      message: message,
    );

    if (!writerIsValid) {
      return reject(
        PrHeadUpdateFailureClassification.invalidInput,
        'Writer identity must use the supported identifier character set.',
      );
    }
    if (!correlationIsValid) {
      return reject(
        PrHeadUpdateFailureClassification.invalidInput,
        'Correlation ID must use the supported identifier character set.',
      );
    }
    if (!remoteIsValid) {
      return reject(
        PrHeadUpdateFailureClassification.invalidInput,
        'Remote must be a configured remote name, not a URL or option.',
      );
    }
    if (!branchIsValid) {
      return reject(
        PrHeadUpdateFailureClassification.invalidInput,
        'Branch must be a safe branch name under refs/heads.',
      );
    }
    if (!expectedIsValid) {
      return reject(
        PrHeadUpdateFailureClassification.invalidInput,
        'Expected head must be a full hexadecimal object ID.',
      );
    }
    if (!proposedIsValid) {
      return reject(
        PrHeadUpdateFailureClassification.invalidInput,
        'Proposed head must be a nonzero full hexadecimal object ID.',
      );
    }

    String? initialRemoteHead;
    String? postMutationRemoteHead;
    var mutationAttempted = false;
    try {
      final remoteResult = await gitRunner(<String>[
        'remote',
        'get-url',
        '--push',
        '--all',
        safeRemote,
      ], workingDirectory: workingDirectory);
      final pushUrls = const LineSplitter()
          .convert(remoteResult.stdout.toString().trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      if (remoteResult.exitCode != 0 ||
          pushUrls.length != 1 ||
          !_isSafePushUrl(pushUrls.single)) {
        return reject(
          PrHeadUpdateFailureClassification.invalidRemoteConfiguration,
          'Remote must resolve to exactly one credential-free HTTPS, SSH, or local push URL.',
        );
      }

      final proposedObject = await gitRunner(<String>[
        'cat-file',
        '-t',
        proposed,
      ], workingDirectory: workingDirectory);
      if (proposedObject.exitCode != 0 ||
          proposedObject.stdout.toString().trim() != 'commit') {
        return reject(
          PrHeadUpdateFailureClassification.commitObjectMissing,
          'The proposed object is not an exact local commit object.',
        );
      }

      final observed = await _readRemoteHead(
        safeRemote,
        targetRef,
        workingDirectory,
      );
      initialRemoteHead = observed.sha;
      if (observed.commandFailed) {
        return reject(
          PrHeadUpdateFailureClassification.gitExecutionError,
          'Git could not query the exact remote ref.',
        );
      }
      final before = observed.sha ?? _zeroOid;
      if (before != expected) {
        return reject(
          observed.sha == null
              ? PrHeadUpdateFailureClassification.remoteRefMissing
              : PrHeadUpdateFailureClassification.expectedHeadMismatch,
          observed.sha == null
              ? 'The target ref does not exist at the expected head.'
              : 'The exact remote head does not match the expected head.',
          before: observed.sha,
          after: observed.sha,
        );
      }

      if (expected != _zeroOid) {
        final expectedObject = await gitRunner(<String>[
          'cat-file',
          '-t',
          expected,
        ], workingDirectory: workingDirectory);
        if (expectedObject.exitCode != 0 ||
            expectedObject.stdout.toString().trim() != 'commit') {
          return reject(
            PrHeadUpdateFailureClassification.commitObjectMissing,
            'The expected remote object is not an exact local commit object.',
            before: before,
            after: before,
          );
        }
        if (proposed == expected) {
          return _evidence(
            timestamp: timestamp,
            correlationId: safeCorrelation,
            writer: safeWriter,
            targetRef: targetRef,
            remote: safeRemote,
            expected: expected,
            before: before,
            proposed: proposed,
            after: before,
            decision: PrHeadUpdateDecision.noOp,
            classification: PrHeadUpdateFailureClassification.none,
            message: 'The exact remote ref is already at the proposed head.',
          );
        }

        final stale = await gitRunner(<String>[
          '--no-replace-objects',
          'merge-base',
          '--is-ancestor',
          proposed,
          expected,
        ], workingDirectory: workingDirectory);
        if (stale.exitCode == 0) {
          return reject(
            PrHeadUpdateFailureClassification.staleAncestorRewind,
            'The proposed head is an ancestor of the expected head.',
            before: before,
            after: before,
          );
        }
        if (stale.exitCode > 1) {
          return reject(
            PrHeadUpdateFailureClassification.gitExecutionError,
            'Git could not evaluate stale-ancestor ancestry.',
            before: before,
            after: before,
          );
        }
        final forward = await gitRunner(<String>[
          '--no-replace-objects',
          'merge-base',
          '--is-ancestor',
          expected,
          proposed,
        ], workingDirectory: workingDirectory);
        if (forward.exitCode == 1) {
          return reject(
            PrHeadUpdateFailureClassification.nonDescendantHistory,
            'The proposed head does not descend from the expected head.',
            before: before,
            after: before,
          );
        }
        if (forward.exitCode != 0) {
          return reject(
            PrHeadUpdateFailureClassification.gitExecutionError,
            'Git could not evaluate fast-forward ancestry.',
            before: before,
            after: before,
          );
        }
      }

      if (dryRun) {
        return _evidence(
          timestamp: timestamp,
          correlationId: safeCorrelation,
          writer: safeWriter,
          targetRef: targetRef,
          remote: safeRemote,
          expected: expected,
          before: observed.sha,
          proposed: proposed,
          after: observed.sha,
          decision: PrHeadUpdateDecision.validated,
          classification: PrHeadUpdateFailureClassification.none,
          message:
              'Expected-head and fast-forward checks passed without mutation.',
        );
      }

      final configuredHook = await gitRunner(<String>[
        'rev-parse',
        '--git-path',
        'hooks/pre-push',
      ], workingDirectory: workingDirectory);
      final configuredHookOutput = configuredHook.stdout.toString().trim();
      if (configuredHook.exitCode != 0 ||
          configuredHookOutput.isEmpty ||
          configuredHookOutput.contains('\n') ||
          configuredHookOutput.contains('\r')) {
        return reject(
          PrHeadUpdateFailureClassification.gitExecutionError,
          'Git could not resolve the configured pre-push hook path.',
          before: observed.sha,
          after: observed.sha,
        );
      }
      final configuredHookPath = File(configuredHookOutput).isAbsolute
          ? configuredHookOutput
          : '${workingDirectory ?? Directory.current.path}/$configuredHookOutput';

      final hookDirectory = await Directory.systemTemp.createTemp(
        'llamadart_pr_head_cas_',
      );
      final mismatchMarker = File(
        '${hookDirectory.path}/expected-head-mismatch',
      );
      final configuredHookRejectedMarker = File(
        '${hookDirectory.path}/configured-hook-rejected',
      );
      final hookInput = File('${hookDirectory.path}/pre-push-input');
      final hook = File('${hookDirectory.path}/pre-push');
      try {
        await hook.writeAsString(
          _prePushHook(
            targetRef: targetRef,
            expectedHead: expected,
            markerPath: mismatchMarker.path,
            configuredHookRejectedMarkerPath: configuredHookRejectedMarker.path,
            inputPath: hookInput.path,
            configuredHookPath: configuredHookPath,
          ),
        );
        if (!Platform.isWindows) {
          final chmod = await Process.run('chmod', <String>['700', hook.path]);
          if (chmod.exitCode != 0) {
            return reject(
              PrHeadUpdateFailureClassification.gitExecutionError,
              'The one-shot expected-head guard could not be prepared.',
              before: observed.sha,
              after: observed.sha,
            );
          }
        }
        mutationAttempted = true;
        final push = await gitRunner(<String>[
          '-c',
          'core.hooksPath=${hookDirectory.path}',
          if (!safeRemote.contains('/')) ...<String>[
            '-c',
            'remote.$safeRemote.mirror=false',
          ],
          'push',
          '--porcelain',
          '--no-mirror',
          '--no-tags',
          '--no-follow-tags',
          '--verify',
          safeRemote,
          '$proposed:$targetRef',
        ], workingDirectory: workingDirectory);
        if (push.exitCode != 0) {
          final afterFailure = await _readRemoteHead(
            safeRemote,
            targetRef,
            workingDirectory,
          );
          if (!afterFailure.commandFailed) {
            postMutationRemoteHead = afterFailure.sha;
          }
          final raced =
              await mismatchMarker.exists() ||
              (!afterFailure.commandFailed && afterFailure.sha != observed.sha);
          final configuredHookRejected = await configuredHookRejectedMarker
              .exists();
          return reject(
            raced
                ? PrHeadUpdateFailureClassification.expectedHeadMismatch
                : configuredHookRejected
                ? PrHeadUpdateFailureClassification.prePushHookRejected
                : PrHeadUpdateFailureClassification.remoteMutationFailed,
            raced
                ? 'The remote head changed after validation; the guarded push rejected the stale writer.'
                : configuredHookRejected
                ? 'The configured pre-push hook rejected the update.'
                : 'The server rejected the normal fast-forward-only push.',
            before: observed.sha,
            after: afterFailure.sha,
          );
        }
      } finally {
        try {
          await hookDirectory.delete(recursive: true);
        } on FileSystemException {
          // Cleanup is best-effort. The directory contains no credentials, and
          // read-back still determines whether the remote mutation succeeded.
        }
      }

      final verified = await _readRemoteHead(
        safeRemote,
        targetRef,
        workingDirectory,
      );
      if (!verified.commandFailed) {
        postMutationRemoteHead = verified.sha;
      }
      if (verified.commandFailed || verified.sha != proposed) {
        return reject(
          PrHeadUpdateFailureClassification.postMutationVerificationFailed,
          'The exact remote ref did not read back at the proposed head.',
          before: observed.sha,
          after: verified.sha,
        );
      }
      return _evidence(
        timestamp: timestamp,
        correlationId: safeCorrelation,
        writer: safeWriter,
        targetRef: targetRef,
        remote: safeRemote,
        expected: expected,
        before: observed.sha,
        proposed: proposed,
        after: verified.sha,
        decision: PrHeadUpdateDecision.accepted,
        classification: PrHeadUpdateFailureClassification.none,
        message:
            'The exact remote ref was advanced and read back successfully.',
      );
    } on ProcessException {
      return reject(
        PrHeadUpdateFailureClassification.gitExecutionError,
        'A local process could not execute the guarded update.',
        before: initialRemoteHead,
        after: mutationAttempted ? postMutationRemoteHead : initialRemoteHead,
      );
    } on FileSystemException {
      return reject(
        PrHeadUpdateFailureClassification.gitExecutionError,
        'A local filesystem operation could not prepare the guarded update.',
        before: initialRemoteHead,
        after: mutationAttempted ? postMutationRemoteHead : initialRemoteHead,
      );
    }
  }

  Future<_RemoteHead> _readRemoteHead(
    String remote,
    String targetRef,
    String? workingDirectory,
  ) async {
    final result = await gitRunner(<String>[
      'ls-remote',
      '--quiet',
      '--refs',
      remote,
      targetRef,
    ], workingDirectory: workingDirectory);
    if (result.exitCode != 0) return const _RemoteHead(commandFailed: true);
    final output = result.stdout.toString().trim();
    if (output.isEmpty) return const _RemoteHead();
    final sha = _parseExactRemoteHead(output, targetRef);
    return _RemoteHead(sha: sha, commandFailed: sha == null);
  }
}

class _RemoteHead {
  const _RemoteHead({this.sha, this.commandFailed = false});
  final String? sha;
  final bool commandFailed;
}

String _quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

String _prePushHook({
  required String targetRef,
  required String expectedHead,
  required String markerPath,
  required String configuredHookRejectedMarkerPath,
  required String inputPath,
  required String configuredHookPath,
}) =>
    '''#!/bin/sh
target_ref=${_quote(targetRef)}
expected_head=${_quote(expectedHead)}
mismatch_marker=${_quote(markerPath)}
configured_hook_rejected_marker=${_quote(configuredHookRejectedMarkerPath)}
input_file=${_quote(inputPath)}
configured_hook=${_quote(configuredHookPath)}
matched=0
cat > "\$input_file"
while read -r local_ref local_oid remote_ref remote_oid
do
  if [ "\$remote_ref" = "\$target_ref" ]; then
    matched=\$((matched + 1))
    if [ "\$remote_oid" != "\$expected_head" ]; then
      : > "\$mismatch_marker"
      exit 1
    fi
  fi
done < "\$input_file"
if [ "\$matched" -ne 1 ]; then
  : > "\$mismatch_marker"
  exit 1
fi
if [ -x "\$configured_hook" ]; then
  "\$configured_hook" "\$@" < "\$input_file" || {
    status=\$?
    : > "\$configured_hook_rejected_marker"
    exit "\$status"
  }
fi
exit 0
''';

void _printUsage() {
  stdout.writeln('''
Usage: dart run tool/git/safe_pr_head_update.dart
  --branch <branch> --expected-sha <sha> --proposed-sha <sha>
  --writer <principal> [--remote origin] [--correlation-id <id>] [--dry-run]

Use the all-zero expected SHA to create an absent branch. Update attempts and
invalid-argument invocations emit JSON evidence on stdout.
''');
}

void _emitInvalidCliArguments() {
  final timestamp = DateTime.now();
  final result = PrHeadUpdateResult(
    timestamp: timestamp,
    correlationId: 'invalid-cli-${timestamp.microsecondsSinceEpoch}',
    writer: '<invalid>',
    targetRef: '<invalid>',
    remote: '<invalid>',
    expectedHeadSha: _zeroOid,
    remoteHeadBefore: null,
    proposedHeadSha: _zeroOid,
    remoteHeadAfter: null,
    decision: PrHeadUpdateDecision.rejected,
    failureClassification: PrHeadUpdateFailureClassification.invalidInput,
    message: 'Command-line arguments are invalid or incomplete.',
  );
  stdout.writeln(result.toFormattedJson());
  exitCode = 64;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }
  final values = <String, String>{};
  var dryRun = false;
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--dry-run') {
      dryRun = true;
      continue;
    }
    final names = <String, String>{
      '--branch': 'branch',
      '-b': 'branch',
      '--expected-sha': 'expected',
      '-e': 'expected',
      '--proposed-sha': 'proposed',
      '-p': 'proposed',
      '--writer': 'writer',
      '-w': 'writer',
      '--remote': 'remote',
      '-r': 'remote',
      '--correlation-id': 'correlation',
      '-c': 'correlation',
    };
    final key = names[argument];
    if (key == null || index + 1 >= args.length) {
      _emitInvalidCliArguments();
      return;
    }
    values[key] = args[++index];
  }
  if (!<String>{
    'branch',
    'expected',
    'proposed',
    'writer',
  }.every(values.containsKey)) {
    _emitInvalidCliArguments();
    return;
  }
  final result = await const SafePrHeadUpdate().updatePrHead(
    remote: values['remote'] ?? 'origin',
    branch: values['branch']!,
    expectedHeadSha: values['expected']!,
    proposedHeadSha: values['proposed']!,
    writer: values['writer']!,
    correlationId: values['correlation'],
    dryRun: dryRun,
  );
  stdout.writeln(result.toFormattedJson());
  exitCode = result.isSuccess ? 0 : 1;
}
