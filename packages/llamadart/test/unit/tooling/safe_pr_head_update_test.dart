@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/git/safe_pr_head_update.dart';

const zeroOid = '0000000000000000000000000000000000000000';

const generatedDirectoryNames = {
  '.git',
  '.dart_tool',
  'node_modules',
  'build',
  '.docusaurus',
};

bool isMaintainedMarkdown(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  return parts.last.endsWith('.md') &&
      !parts.any(generatedDirectoryNames.contains);
}

bool isMaintainedWriterSource(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  if (parts.first == 'test' || parts.any(generatedDirectoryNames.contains)) {
    return false;
  }
  return RegExp(
        r'\.(dart|py|sh|bash|zsh|fish|ps1|cmd|bat|js|ts|ya?ml)$',
      ).hasMatch(normalized) ||
      parts.last == 'package.json' ||
      parts.last == 'Makefile';
}

// Prune generated trees before listing their contents: site builds may replace
// them concurrently. Errors in maintained directories and files still propagate.
Iterable<MapEntry<String, File>> maintainedFiles(
  Directory root, [
  String prefix = '',
]) sync* {
  for (final entity in root.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    final path = '$prefix$name';
    if (entity is Directory) {
      if (!generatedDirectoryNames.contains(name)) {
        yield* maintainedFiles(entity, '$path/');
      }
    } else if (entity is File) {
      yield MapEntry(path, entity);
    }
  }
}

Iterable<MapEntry<String, String>> maintainedWriterSources(
  Directory root,
) sync* {
  for (final entry in maintainedFiles(root)) {
    if (isMaintainedWriterSource(entry.key)) {
      yield MapEntry(
        entry.key,
        entry.value.readAsStringSync().replaceAll('\r\n', '\n'),
      );
    }
  }
}

Future<ProcessResult> git(List<String> args, Directory cwd) {
  return Process.run('git', args, workingDirectory: cwd.path);
}

Future<String> commitFile(
  Directory repo,
  String filename,
  String content,
  String message,
) async {
  final file = File('${repo.path}/$filename');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  expect((await git(<String>['add', filename], repo)).exitCode, 0);
  expect(
    (await git(<String>[
      '-c',
      'user.name=Test Writer',
      '-c',
      'user.email=test@example.com',
      'commit',
      '--quiet',
      '-m',
      message,
    ], repo)).exitCode,
    0,
  );
  return (await git(<String>[
    'rev-parse',
    'HEAD',
  ], repo)).stdout.toString().trim();
}

Future<String?> remoteHead(Directory repo, String branch) async {
  final result = await git(<String>[
    'ls-remote',
    '--refs',
    'origin',
    'refs/heads/$branch',
  ], repo);
  final output = result.stdout.toString().trim();
  return output.isEmpty ? null : output.split(RegExp(r'\s+')).first;
}

void expectEvidenceMatchesLocalSchema(PrHeadUpdateResult result) {
  final schema =
      jsonDecode(
            File(
              'tool/git/pr_head_update_evidence.schema.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final properties = schema['properties'] as Map<String, dynamic>;
  final required = (schema['required'] as List<dynamic>).cast<String>().toSet();
  final evidence = result.toJson();

  expect(schema[r'$id'], 'urn:llamadart:pr-head-update-evidence:1.0.0');
  expect(schema['additionalProperties'], isFalse);
  expect(required, properties.keys.toSet());
  expect(evidence.keys.toSet(), properties.keys.toSet());
  expect(evidence['schema'], PrHeadUpdateResult.schema);
  expect(evidence['schema_version'], PrHeadUpdateResult.schemaVersion);
  expect(DateTime.tryParse(evidence['timestamp']! as String), isNotNull);
  expect(evidence['correlation_id'], isA<String>());
  expect(evidence['writer'], isA<String>());
  expect(evidence['target_ref'], isA<String>());
  expect(evidence['remote'], isA<String>());
  for (final key in <String>[
    'expected_head_sha',
    'remote_head_before',
    'remote_head_after',
  ]) {
    final value = evidence[key];
    expect(
      value == null || RegExp(r'^[0-9a-f]{40}$').hasMatch(value as String),
      isTrue,
    );
  }
  expect(evidence['proposed_head_sha'], matches(RegExp(r'^[0-9a-f]{40}$')));
  expect(
    ((properties['decision'] as Map<String, dynamic>)['enum'] as List<dynamic>)
        .toSet(),
    PrHeadUpdateDecision.values.map((value) => value.name).toSet(),
  );
  expect(
    ((properties['failure_classification'] as Map<String, dynamic>)['enum']
            as List<dynamic>)
        .toSet(),
    PrHeadUpdateFailureClassification.values.map((value) => value.name).toSet(),
  );
  expect(evidence['decision'], result.decision.name);
  expect(evidence['failure_classification'], result.failureClassification.name);
  expect(evidence['message'], isA<String>());
}

List<String> workflowWriterContractViolations(String workflow) {
  final violations = <String>[];
  final guardedInvocation = RegExp(
    r'''^\s+dart run tool/git/safe_pr_head_update\.dart \\\s*\n'''
    r'''\s+--remote origin \\\s*\n'''
    r'''\s+--branch "\$\{BRANCH\}" \\\s*\n'''
    r'''\s+--expected-sha "\$\{EXPECTED_SHA\}" \\\s*\n'''
    r'''\s+--proposed-sha "\$\{PROPOSED_SHA\}" \\\s*\n'''
    r'''\s+--writer github-actions-native-sync \\\s*\n'''
    r'''\s+--correlation-id "native-sync-\$\{GITHUB_RUN_ID\}-\$\{GITHUB_RUN_ATTEMPT\}" \\\s*\n'''
    r'''\s+\| tee "\$\{RUNNER_TEMP\}/pr-head-update-evidence\.json"\s*$''',
    multiLine: true,
  );
  final guardedInvocationCount = guardedInvocation.allMatches(workflow).length;
  if (guardedInvocationCount != 1) {
    violations.add('expected exactly one executable guarded-helper invocation');
  }
  for (final argument in <String>[
    '--remote origin',
    '--branch "\${BRANCH}"',
    '--expected-sha "\${EXPECTED_SHA}"',
    '--proposed-sha "\${PROPOSED_SHA}"',
    '--writer github-actions-native-sync',
    '--correlation-id "native-sync-\${GITHUB_RUN_ID}-\${GITHUB_RUN_ATTEMPT}"',
  ]) {
    if (!workflow.contains(argument)) {
      violations.add('guarded helper is missing $argument');
    }
  }
  for (final bypass in <RegExp>[
    RegExp(r'peter-evans/create-pull-request'),
    RegExp(r'^\s*git\b[^\n]*\bpush\b', multiLine: true),
    RegExp(r'\b(?:createRef|updateRef|deleteRef)\s*\('),
    RegExp(r'\bgithub\.rest\.git\.(?:createRef|updateRef|deleteRef)\b'),
    RegExp(r'\b(?:gh\s+api|curl\b)[^\n]*git/refs/heads'),
  ]) {
    if (bypass.hasMatch(workflow)) {
      violations.add('workflow contains a direct PR-ref mutation bypass');
    }
  }
  final guardIndex = workflow.indexOf(
    'dart run tool/git/safe_pr_head_update.dart',
  );
  for (final command in <String>['gh pr close', 'gh pr edit', 'gh pr create']) {
    final commandIndex = workflow.indexOf(command);
    if (guardIndex < 0 || commandIndex < 0 || guardIndex >= commandIndex) {
      violations.add('$command must follow the guarded ref update');
    }
  }
  return violations;
}

void main() {
  group('input and evidence contracts', () {
    test('validates branch, remote, and full object IDs', () {
      expect(isValidBranchName('feature/fix-434'), isTrue);
      expect(
        isValidBranchName('refs/heads/automation/native-sync-v0.3.0'),
        isTrue,
      );
      for (final value in <String>[
        '',
        '--force',
        '+refs/heads/main',
        'refs/tags/v1',
        'feature/../main',
        'feature//main',
        '.hidden',
        'feature/.hidden',
        'feature/topic.lock/next',
        'feature name',
        'feature.lock',
      ]) {
        expect(isValidBranchName(value), isFalse, reason: value);
      }

      expect(isValidRemoteName('origin'), isTrue);
      expect(isValidRemoteName('maintainer/upstream'), isTrue);
      for (final value in <String>[
        '--upload-pack=evil',
        'https://example.test/repo.git',
        'origin?token=secret',
        '../origin',
      ]) {
        expect(isValidRemoteName(value), isFalse, reason: value);
      }

      expect(
        isValidCommitSha('388dbc289abdb19b75225bcd3cee47cf72d83cd5'),
        isTrue,
      );
      expect(isValidCommitSha(zeroOid), isFalse);
      expect(isValidCommitSha(zeroOid, allowZero: true), isTrue);
      expect(isValidCommitSha('HEAD'), isFalse);
    });

    test('all invalid inputs are sanitized before any rejection', () async {
      final result = await const SafePrHeadUpdate().updatePrHead(
        remote:
            'https://user:remoteSecret@example.test/repo.git?token=remoteSecret',
        branch: 'feature?branchSecret',
        expectedHeadSha: 'expectedSecret',
        proposedHeadSha: 'proposedSecret',
        writer: 'writer?writerSecret',
        correlationId: 'correlation?correlationSecret',
      );
      final encoded = result.toFormattedJson();
      expect(
        result.failureClassification,
        PrHeadUpdateFailureClassification.invalidInput,
      );
      for (final secret in <String>[
        'remoteSecret',
        'branchSecret',
        'expectedSecret',
        'proposedSecret',
        'writerSecret',
        'correlationSecret',
      ]) {
        expect(encoded, isNot(contains(secret)));
      }
      expect(result.remote, '<invalid>');
      expect(result.targetRef, '<invalid>');
      expect(result.writer, '<invalid>');
      expect(result.correlationId, '<invalid>');
      expect(result.expectedHeadSha, zeroOid);
      expect(result.proposedHeadSha, zeroOid);
      expectEvidenceMatchesLocalSchema(result);
    });

    test(
      'local schema exactly accepts every emitted field and stable enum',
      () {
        expectEvidenceMatchesLocalSchema(
          PrHeadUpdateResult(
            timestamp: DateTime.utc(2026, 8, 28),
            correlationId: 'schema-check',
            writer: 'schema-writer',
            targetRef: 'refs/heads/schema-check',
            remote: 'origin',
            expectedHeadSha: zeroOid,
            remoteHeadBefore: null,
            proposedHeadSha: '388dbc289abdb19b75225bcd3cee47cf72d83cd5',
            remoteHeadAfter: '388dbc289abdb19b75225bcd3cee47cf72d83cd5',
            decision: PrHeadUpdateDecision.accepted,
            failureClassification: PrHeadUpdateFailureClassification.none,
            message: 'Schema validation fixture.',
          ),
        );
      },
    );

    test(
      'injected runner accepts valid SSH URI push remote and sanitizes credential-bearing SSH push remote',
      () async {
        const commitA = '388dbc289abdb19b75225bcd3cee47cf72d83cd5';
        const commitB = '25ef554283a667e3cf7e37a5cfd31605caafbd08';

        ProcessResult mockGit(String pushUrl, List<String> args) {
          if (args.length >= 2 && args[0] == 'remote' && args[1] == 'get-url') {
            return ProcessResult(0, 0, '$pushUrl\n', '');
          }
          if (args.length >= 2 && args[0] == 'cat-file' && args[1] == '-t') {
            return ProcessResult(0, 0, 'commit\n', '');
          }
          if (args.isNotEmpty && args[0] == 'ls-remote') {
            return ProcessResult(
              0,
              0,
              '$commitA\trefs/heads/feature/ssh-remote\n',
              '',
            );
          }
          if (args.contains('merge-base') && args.contains('--is-ancestor')) {
            final isForward = args.indexOf(commitA) < args.indexOf(commitB);
            return ProcessResult(0, isForward ? 0 : 1, '', '');
          }
          return ProcessResult(0, 0, '', '');
        }

        for (final validUrl in <String>[
          'ssh://git@github.com/owner/repo.git',
          'ssh://github.com/owner/repo.git',
          'git@github.com:owner/repo.git',
          'https://github.com/owner/repo.git',
        ]) {
          final accepted =
              await SafePrHeadUpdate(
                gitRunner: (args, {workingDirectory}) async =>
                    mockGit(validUrl, args),
              ).updatePrHead(
                remote: 'origin',
                branch: 'feature/ssh-remote',
                expectedHeadSha: commitA,
                proposedHeadSha: commitB,
                writer: 'ssh-writer',
                dryRun: true,
              );
          expect(
            accepted.decision,
            PrHeadUpdateDecision.validated,
            reason: validUrl,
          );
          expect(
            accepted.failureClassification,
            PrHeadUpdateFailureClassification.none,
            reason: validUrl,
          );
          expectEvidenceMatchesLocalSchema(accepted);
        }

        for (final (invalidUrl, secret) in <(String, String)>[
          (
            'ssh://git:sshSecretPass@github.com/owner/repo.git',
            'sshSecretPass',
          ),
          ('ssh://:sshSecretPass@github.com/owner/repo.git', 'sshSecretPass'),
          (
            'ssh://git@github.com/owner/repo.git?token=sshSecretQuery',
            'sshSecretQuery',
          ),
          (
            'ssh://git@github.com/owner/repo.git#sshSecretFrag',
            'sshSecretFrag',
          ),
          (
            'https://user:httpsSecretPass@github.com/owner/repo.git',
            'httpsSecretPass',
          ),
          (
            'https://httpsSecretUser@github.com/owner/repo.git',
            'httpsSecretUser',
          ),
        ]) {
          final rejected =
              await SafePrHeadUpdate(
                gitRunner: (args, {workingDirectory}) async =>
                    mockGit(invalidUrl, args),
              ).updatePrHead(
                remote: 'origin',
                branch: 'feature/ssh-remote',
                expectedHeadSha: commitA,
                proposedHeadSha: commitB,
                writer: 'ssh-writer',
                dryRun: true,
              );
          expect(
            rejected.decision,
            PrHeadUpdateDecision.rejected,
            reason: invalidUrl,
          );
          expect(
            rejected.failureClassification,
            PrHeadUpdateFailureClassification.invalidRemoteConfiguration,
            reason: invalidUrl,
          );
          expect(
            rejected.toFormattedJson(),
            isNot(contains(secret)),
            reason: invalidUrl,
          );
          expectEvidenceMatchesLocalSchema(rejected);
        }
      },
    );

    test('process exceptions become sanitized structured evidence', () async {
      final result =
          await SafePrHeadUpdate(
            gitRunner: (args, {workingDirectory}) {
              throw ProcessException('git', <String>['sensitive-argument']);
            },
          ).updatePrHead(
            remote: 'origin',
            branch: 'feature/process-failure',
            expectedHeadSha: zeroOid,
            proposedHeadSha: '388dbc289abdb19b75225bcd3cee47cf72d83cd5',
            writer: 'process-writer',
          );
      expect(result.decision, PrHeadUpdateDecision.rejected);
      expect(
        result.failureClassification,
        PrHeadUpdateFailureClassification.gitExecutionError,
      );
      expect(result.toFormattedJson(), isNot(contains('sensitive-argument')));
      expectEvidenceMatchesLocalSchema(result);
    });

    test('malformed CLI input emits sanitized schema evidence', () async {
      final process = await Process.run(Platform.resolvedExecutable, <String>[
        'tool/git/safe_pr_head_update.dart',
        '--unknown=cliSecret',
      ]);
      expect(process.exitCode, 64);
      expect(process.stderr.toString(), isEmpty);
      expect(process.stdout.toString(), isNot(contains('cliSecret')));
      final evidence =
          jsonDecode(process.stdout.toString()) as Map<String, dynamic>;
      expect(evidence['schema'], PrHeadUpdateResult.schema);
      expect(evidence['writer'], '<invalid>');
      expect(evidence['target_ref'], '<invalid>');
      expect(evidence['remote'], '<invalid>');
      expect(evidence['expected_head_sha'], zeroOid);
      expect(evidence['proposed_head_sha'], zeroOid);
      expect(evidence['decision'], PrHeadUpdateDecision.rejected.name);
      expect(
        evidence['failure_classification'],
        PrHeadUpdateFailureClassification.invalidInput.name,
      );
    });

    test('help and no-argument CLI invocations print usage block', () async {
      for (final args in <List<String>>[
        <String>[],
        <String>['--help'],
        <String>['-h'],
      ]) {
        final process = await Process.run(Platform.resolvedExecutable, <String>[
          'tool/git/safe_pr_head_update.dart',
          ...args,
        ]);
        expect(process.exitCode, 0, reason: '$args');
        expect(process.stderr.toString(), isEmpty, reason: '$args');
        expect(
          process.stdout.toString(),
          contains('Usage: dart run tool/git/safe_pr_head_update.dart'),
          reason: '$args',
        );
        expect(
          process.stdout.toString(),
          contains(
            'Update attempts and\ninvalid-argument invocations emit JSON evidence on stdout.',
          ),
          reason: '$args',
        );
      }
    });
  });

  group('bare remote integration', () {
    late Directory root;
    late Directory remote;
    late Directory work;
    late String commitA;
    late String commitB;
    late String commitC;
    late String commitD;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('safe_pr_head_update_test_');
      remote = Directory('${root.path}/remote.git')..createSync();
      work = Directory('${root.path}/work')..createSync();
      expect(
        (await git(<String>['init', '--bare', '--quiet'], remote)).exitCode,
        0,
      );
      expect((await git(<String>['init', '--quiet'], work)).exitCode, 0);
      expect(
        (await git(<String>[
          'remote',
          'add',
          'origin',
          remote.path,
        ], work)).exitCode,
        0,
      );
      commitA = await commitFile(work, 'base.txt', 'A\n', 'A');
      expect(
        (await git(<String>[
          'push',
          '--quiet',
          'origin',
          '$commitA:refs/heads/pr-test',
        ], work)).exitCode,
        0,
      );
      commitB = await commitFile(work, 'feature.txt', 'B\n', 'B');
      commitC = await commitFile(work, 'feature.txt', 'C\n', 'C');
      expect(
        (await git(<String>[
          'checkout',
          '--quiet',
          '--detach',
          commitA,
        ], work)).exitCode,
        0,
      );
      commitD = await commitFile(work, 'diverged.txt', 'D\n', 'D');
      expect(
        (await git(<String>[
          'checkout',
          '--quiet',
          '--detach',
          commitC,
        ], work)).exitCode,
        0,
      );
    });

    tearDown(() => root.delete(recursive: true));

    test(
      'normal fast-forward succeeds with no force option and exact read-back',
      () async {
        expect(
          (await git(<String>[
            '-c',
            'user.name=Test Writer',
            '-c',
            'user.email=test@example.com',
            'tag',
            '-a',
            'must-not-follow',
            '-m',
            'must not follow',
            commitB,
          ], work)).exitCode,
          0,
        );
        expect(
          (await git(<String>[
            'config',
            'push.followTags',
            'true',
          ], work)).exitCode,
          0,
        );
        expect(
          (await git(<String>[
            'config',
            'remote.origin.mirror',
            'true',
          ], work)).exitCode,
          0,
        );
        final contributorHookMarker = File('${root.path}/contributor-hook-ran');
        final contributorHookDirectory = Directory(
          '${work.path}/.custom-hooks',
        );
        await contributorHookDirectory.create();
        expect(
          (await git(<String>[
            'config',
            'core.hooksPath',
            '.custom-hooks',
          ], work)).exitCode,
          0,
        );
        final contributorHook = File(
          '${contributorHookDirectory.path}/pre-push',
        );
        await contributorHook.writeAsString(
          '#!/bin/sh\n: > "${contributorHookMarker.path}"\n',
        );
        expect(
          (await Process.run('chmod', <String>[
            '700',
            contributorHook.path,
          ])).exitCode,
          0,
        );
        final invocations = <List<String>>[];
        final updater = SafePrHeadUpdate(
          gitRunner: (args, {workingDirectory}) {
            invocations.add(List<String>.of(args));
            return defaultGitCommandRunner(
              args,
              workingDirectory: workingDirectory,
            );
          },
        );
        final result = await updater.updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitA,
          proposedHeadSha: commitB,
          writer: 'test-writer',
          correlationId: 'normal-forward',
          workingDirectory: work.path,
        );
        expect(
          result.decision,
          PrHeadUpdateDecision.accepted,
          reason: result.toFormattedJson(),
        );
        expect(result.remoteHeadBefore, commitA);
        expect(result.remoteHeadAfter, commitB);
        expectEvidenceMatchesLocalSchema(result);
        expect(await remoteHead(work, 'pr-test'), commitB);
        expect(
          (await git(<String>[
            'ls-remote',
            '--tags',
            'origin',
          ], work)).stdout.toString().trim(),
          isEmpty,
        );
        expect(await contributorHookMarker.exists(), isTrue);
        final push = invocations.singleWhere((args) => args.contains('push'));
        expect(push, contains('--porcelain'));
        expect(push, contains('remote.origin.mirror=false'));
        expect(
          push,
          containsAll(<String>[
            '--no-mirror',
            '--no-tags',
            '--no-follow-tags',
            '--verify',
          ]),
        );
        expect(push.any((arg) => arg.startsWith('--force')), isFalse);
        expect(push.any((arg) => arg.startsWith('+')), isFalse);
        final oneShotHookConfig = push.singleWhere(
          (argument) => argument.startsWith('core.hooksPath='),
        );
        final oneShotHookDirectory = Directory(
          oneShotHookConfig.substring('core.hooksPath='.length),
        );
        expect(oneShotHookDirectory.existsSync(), isFalse);
      },
    );

    test(
      'slash-containing remote name executes guarded update without invalid config keys',
      () async {
        expect(
          (await git(<String>[
            'remote',
            'add',
            'maintainer/upstream',
            remote.path,
          ], work)).exitCode,
          0,
        );
        final invocations = <List<String>>[];
        final updater = SafePrHeadUpdate(
          gitRunner: (args, {workingDirectory}) {
            invocations.add(List<String>.of(args));
            return defaultGitCommandRunner(
              args,
              workingDirectory: workingDirectory,
            );
          },
        );
        final result = await updater.updatePrHead(
          remote: 'maintainer/upstream',
          branch: 'pr-test',
          expectedHeadSha: commitA,
          proposedHeadSha: commitB,
          writer: 'slash-remote-writer',
          workingDirectory: work.path,
        );
        expect(
          result.decision,
          PrHeadUpdateDecision.accepted,
          reason: result.toFormattedJson(),
        );
        expect(result.remote, 'maintainer/upstream');
        expect(result.remoteHeadBefore, commitA);
        expect(result.remoteHeadAfter, commitB);
        expectEvidenceMatchesLocalSchema(result);

        final push = invocations.singleWhere((args) => args.contains('push'));
        expect(push, contains('--porcelain'));
        expect(push, contains('--no-mirror'));
        expect(push, contains('--no-tags'));
        expect(push, contains('--no-follow-tags'));
        expect(push, contains('--verify'));
        expect(push, contains('maintainer/upstream'));
        expect(
          push.any((arg) => arg.contains('maintainer/upstream.mirror')),
          isFalse,
        );
        expect(push.any((arg) => arg.startsWith('--force')), isFalse);
        expect(push.any((arg) => arg.startsWith('+')), isFalse);
        expect(
          (await git(<String>[
            '--git-dir=${remote.path}',
            'rev-parse',
            'refs/heads/pr-test',
          ], root)).stdout.toString().trim(),
          commitB,
        );
      },
    );

    test('configured pre-push rejection is preserved and classified', () async {
      final contributorHook = File('${work.path}/.git/hooks/pre-push');
      const hookContents = '#!/bin/sh\nexit 23\n';
      await contributorHook.writeAsString(hookContents);
      expect(
        (await Process.run('chmod', <String>[
          '700',
          contributorHook.path,
        ])).exitCode,
        0,
      );
      final result = await const SafePrHeadUpdate().updatePrHead(
        remote: 'origin',
        branch: 'pr-test',
        expectedHeadSha: commitA,
        proposedHeadSha: commitB,
        writer: 'hook-policy-writer',
        workingDirectory: work.path,
      );
      expect(result.decision, PrHeadUpdateDecision.rejected);
      expect(
        result.failureClassification,
        PrHeadUpdateFailureClassification.prePushHookRejected,
      );
      expect(await remoteHead(work, 'pr-test'), commitA);
      expect(await contributorHook.readAsString(), hookContents);
    });

    test(
      'expected-head mismatch rejects and leaves the exact ref untouched',
      () async {
        final result = await const SafePrHeadUpdate().updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitB,
          proposedHeadSha: commitC,
          writer: 'stale-writer',
          workingDirectory: work.path,
        );
        expect(
          result.failureClassification,
          PrHeadUpdateFailureClassification.expectedHeadMismatch,
        );
        expect(await remoteHead(work, 'pr-test'), commitA);
      },
    );

    test('force-style refspec input is rejected without mutation', () async {
      final result = await const SafePrHeadUpdate().updatePrHead(
        remote: 'origin',
        branch: '+refs/heads/pr-test',
        expectedHeadSha: commitA,
        proposedHeadSha: commitB,
        writer: 'force-refspec-writer',
        workingDirectory: work.path,
      );
      expect(
        result.failureClassification,
        PrHeadUpdateFailureClassification.invalidInput,
      );
      expect(await remoteHead(work, 'pr-test'), commitA);
    });

    test(
      'credential-bearing configured push URL is rejected and redacted',
      () async {
        expect(
          (await git(<String>[
            'config',
            'remote.origin.pushurl',
            'https://user:pushSecret@example.test/repo.git',
          ], work)).exitCode,
          0,
        );
        final result = await const SafePrHeadUpdate().updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitA,
          proposedHeadSha: commitB,
          writer: 'redacted-url-writer',
          workingDirectory: work.path,
        );
        expect(
          result.failureClassification,
          PrHeadUpdateFailureClassification.invalidRemoteConfiguration,
        );
        expect(result.toFormattedJson(), isNot(contains('pushSecret')));
        expect(
          (await git(<String>[
            '--git-dir=${remote.path}',
            'rev-parse',
            'refs/heads/pr-test',
          ], root)).stdout.toString().trim(),
          commitA,
        );
      },
    );

    test('non-descendant history is rejected', () async {
      expect(
        (await git(<String>[
          'push',
          'origin',
          '$commitB:refs/heads/pr-test',
        ], work)).exitCode,
        0,
      );
      final result = await const SafePrHeadUpdate().updatePrHead(
        remote: 'origin',
        branch: 'pr-test',
        expectedHeadSha: commitB,
        proposedHeadSha: commitD,
        writer: 'diverged-writer',
        workingDirectory: work.path,
      );
      expect(
        result.failureClassification,
        PrHeadUpdateFailureClassification.nonDescendantHistory,
      );
      expect(await remoteHead(work, 'pr-test'), commitB);
    });

    test('local replacement refs cannot bypass ancestry rejection', () async {
      expect(
        (await git(<String>[
          'push',
          'origin',
          '$commitB:refs/heads/pr-test',
        ], work)).exitCode,
        0,
      );
      expect(
        (await git(<String>['replace', commitD, commitC], work)).exitCode,
        0,
      );
      expect(
        (await git(<String>[
          'merge-base',
          '--is-ancestor',
          commitB,
          commitD,
        ], work)).exitCode,
        0,
        reason:
            'the fixture replacement must make the divergent head look safe',
      );
      final result = await const SafePrHeadUpdate().updatePrHead(
        remote: 'origin',
        branch: 'pr-test',
        expectedHeadSha: commitB,
        proposedHeadSha: commitD,
        writer: 'replace-ref-writer',
        workingDirectory: work.path,
      );
      expect(
        result.failureClassification,
        PrHeadUpdateFailureClassification.nonDescendantHistory,
      );
      expect(await remoteHead(work, 'pr-test'), commitB);
    });

    test('stale ancestor rewind is rejected', () async {
      expect(
        (await git(<String>[
          'push',
          'origin',
          '$commitC:refs/heads/pr-test',
        ], work)).exitCode,
        0,
      );
      final result = await const SafePrHeadUpdate().updatePrHead(
        remote: 'origin',
        branch: 'pr-test',
        expectedHeadSha: commitC,
        proposedHeadSha: commitA,
        writer: 'rewind-writer',
        workingDirectory: work.path,
      );
      expect(
        result.failureClassification,
        PrHeadUpdateFailureClassification.staleAncestorRewind,
      );
      expect(await remoteHead(work, 'pr-test'), commitC);
    });

    test(
      'retry is idempotent when expected and proposed equal the remote',
      () async {
        const updater = SafePrHeadUpdate();
        final first = await updater.updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitA,
          proposedHeadSha: commitB,
          writer: 'retry-writer',
          workingDirectory: work.path,
        );
        expect(first.decision, PrHeadUpdateDecision.accepted);
        final result = await updater.updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitB,
          proposedHeadSha: commitB,
          writer: 'retry-writer',
          workingDirectory: work.path,
        );
        expect(result.decision, PrHeadUpdateDecision.noOp);
        expect(result.remoteHeadAfter, commitB);
      },
    );

    test('all-zero expectation creates only an absent branch', () async {
      final result = await const SafePrHeadUpdate().updatePrHead(
        remote: 'origin',
        branch: 'new-pr',
        expectedHeadSha: zeroOid,
        proposedHeadSha: commitB,
        writer: 'automation-writer',
        workingDirectory: work.path,
      );
      expect(result.decision, PrHeadUpdateDecision.accepted);
      expect(result.remoteHeadBefore, isNull);
      expect(result.remoteHeadAfter, commitB);
      expect(await remoteHead(work, 'new-pr'), commitB);
    });

    test(
      'an annotated tag object cannot be used as a proposed branch head',
      () async {
        expect(
          (await git(<String>[
            '-c',
            'user.name=Test Writer',
            '-c',
            'user.email=test@example.com',
            'tag',
            '-a',
            'tag-object-proposal',
            '-m',
            'tag object proposal',
            commitB,
          ], work)).exitCode,
          0,
        );
        final tagObject = (await git(<String>[
          'rev-parse',
          'tag-object-proposal^{tag}',
        ], work)).stdout.toString().trim();
        final result = await const SafePrHeadUpdate().updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitA,
          proposedHeadSha: tagObject,
          writer: 'tag-object-writer',
          workingDirectory: work.path,
        );
        expect(
          result.failureClassification,
          PrHeadUpdateFailureClassification.commitObjectMissing,
        );
        expect(await remoteHead(work, 'pr-test'), commitA);
      },
    );

    test(
      'dry-run reports the observed ref rather than an optimistic after SHA',
      () async {
        final result = await const SafePrHeadUpdate().updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitA,
          proposedHeadSha: commitB,
          writer: 'dry-runner',
          dryRun: true,
          workingDirectory: work.path,
        );
        expect(result.decision, PrHeadUpdateDecision.validated);
        expect(result.remoteHeadAfter, commitA);
        expect(await remoteHead(work, 'pr-test'), commitA);
      },
    );

    test(
      'concurrent winner advances after precheck and stale writer is rejected by in-push CAS',
      () async {
        var injectedWinner = false;
        final updater = SafePrHeadUpdate(
          gitRunner: (args, {workingDirectory}) async {
            if (!injectedWinner && args.contains('push')) {
              injectedWinner = true;
              final winner = await git(<String>[
                'push',
                'origin',
                '$commitB:refs/heads/pr-test',
              ], work);
              expect(winner.exitCode, 0);
            }
            return defaultGitCommandRunner(
              args,
              workingDirectory: workingDirectory,
            );
          },
        );
        final stale = await updater.updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitA,
          proposedHeadSha: commitC,
          writer: 'stale-concurrent-writer',
          correlationId: 'deterministic-race',
          workingDirectory: work.path,
        );
        expect(injectedWinner, isTrue);
        expect(stale.decision, PrHeadUpdateDecision.rejected);
        expect(
          stale.failureClassification,
          PrHeadUpdateFailureClassification.expectedHeadMismatch,
        );
        expect(stale.remoteHeadAfter, commitB);
        expect(await remoteHead(work, 'pr-test'), commitB);
      },
    );

    test(
      'receive-pack rejects a post-advertisement race even when the stale proposal descends from the winner',
      () async {
        expect(
          (await git(<String>[
            'merge-base',
            '--is-ancestor',
            commitB,
            commitC,
          ], work)).exitCode,
          0,
        );
        expect(
          (await git(<String>[
            'push',
            '--quiet',
            'origin',
            '$commitC:refs/race-fixtures/commit-c',
          ], work)).exitCode,
          0,
        );
        final contributorHook = File('${work.path}/.git/hooks/pre-push');
        await contributorHook.writeAsString(
          '#!/bin/sh\n'
          "git --git-dir='${remote.path}' update-ref "
          "refs/heads/pr-test '$commitB' '$commitA'\n",
        );
        expect(
          (await Process.run('chmod', <String>[
            '700',
            contributorHook.path,
          ])).exitCode,
          0,
        );
        final result = await const SafePrHeadUpdate().updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitA,
          proposedHeadSha: commitC,
          writer: 'post-advertisement-writer',
          correlationId: 'receive-pack-old-oid-race',
          workingDirectory: work.path,
        );
        expect(result.decision, PrHeadUpdateDecision.rejected);
        expect(
          result.failureClassification,
          PrHeadUpdateFailureClassification.expectedHeadMismatch,
        );
        expect(result.remoteHeadBefore, commitA);
        expect(result.remoteHeadAfter, commitB);
        expect(await remoteHead(work, 'pr-test'), commitB);
      },
    );

    test(
      'success is rejected if the exact ref read-back moved again',
      () async {
        var remoteReads = 0;
        final updater = SafePrHeadUpdate(
          gitRunner: (args, {workingDirectory}) async {
            if (args.contains('ls-remote')) {
              remoteReads++;
              if (remoteReads == 2) {
                final next = await git(<String>[
                  'push',
                  'origin',
                  '$commitC:refs/heads/pr-test',
                ], work);
                expect(next.exitCode, 0);
              }
            }
            return defaultGitCommandRunner(
              args,
              workingDirectory: workingDirectory,
            );
          },
        );
        final result = await updater.updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitA,
          proposedHeadSha: commitB,
          writer: 'readback-writer',
          workingDirectory: work.path,
        );
        expect(
          result.failureClassification,
          PrHeadUpdateFailureClassification.postMutationVerificationFailed,
        );
        expect(result.remoteHeadAfter, commitC);
      },
    );

    test(
      'read-back exception never reports an optimistic after head',
      () async {
        var remoteReads = 0;
        final updater = SafePrHeadUpdate(
          gitRunner: (args, {workingDirectory}) {
            if (args.contains('ls-remote') && ++remoteReads == 2) {
              throw ProcessException('git', <String>['secret-readback-arg']);
            }
            return defaultGitCommandRunner(
              args,
              workingDirectory: workingDirectory,
            );
          },
        );
        final result = await updater.updatePrHead(
          remote: 'origin',
          branch: 'pr-test',
          expectedHeadSha: commitA,
          proposedHeadSha: commitB,
          writer: 'readback-exception-writer',
          workingDirectory: work.path,
        );
        expect(
          result.failureClassification,
          PrHeadUpdateFailureClassification.gitExecutionError,
        );
        expect(result.remoteHeadBefore, commitA);
        expect(result.remoteHeadAfter, isNull);
        expect(
          result.toFormattedJson(),
          isNot(contains('secret-readback-arg')),
        );
        expect(await remoteHead(work, 'pr-test'), commitB);
      },
    );

    test(
      'workflow reconciliation merges both lines without dropping newer content',
      () async {
        expect(
          (await git(<String>[
            'checkout',
            '--quiet',
            '--detach',
            commitD,
          ], work)).exitCode,
          0,
        );
        final reconciledResult = await git(<String>[
          '-c',
          'user.name=Test Writer',
          '-c',
          'user.email=test@example.com',
          'merge',
          '--no-ff',
          '--no-edit',
          commitC,
        ], work);
        expect(reconciledResult.exitCode, 0);
        final reconciled = (await git(<String>[
          'rev-parse',
          'HEAD',
        ], work)).stdout.toString().trim();
        final parents = (await git(<String>[
          'rev-list',
          '--parents',
          '-n',
          '1',
          reconciled,
        ], work)).stdout.toString().trim().split(' ');
        expect(parents, <String>[reconciled, commitD, commitC]);
        expect(
          File(
            '${work.path}/diverged.txt',
          ).readAsStringSync().replaceAll('\r\n', '\n'),
          'D\n',
        );
        expect(
          File(
            '${work.path}/feature.txt',
          ).readAsStringSync().replaceAll('\r\n', '\n'),
          'C\n',
        );
        for (final parent in <String>[commitD, commitC]) {
          expect(
            (await git(<String>[
              'merge-base',
              '--is-ancestor',
              parent,
              reconciled,
            ], work)).exitCode,
            0,
          );
        }
      },
    );
  });

  group('static repository writer contracts', () {
    test(
      'Markdown ownership excludes dependencies but retains maintained docs',
      () {
        for (final path in [
          'README.md',
          'doc/pr_branch_writer_inventory.md',
          'website/docs/maintainers/release-workflow.md',
          'website/versioned_docs/version-0.8.22/maintainers/release-workflow.md',
        ]) {
          expect(isMaintainedMarkdown(path), isTrue, reason: path);
        }
        for (final path in [
          'website/node_modules/dependency/README.md',
          r'website\node_modules\dependency\README.md',
          'node_modules/dependency/README.md',
          'example/chat_app/build/README.md',
          'website/.docusaurus/README.md',
          '.dart_tool/README.md',
          '.git/README.md',
        ]) {
          expect(isMaintainedMarkdown(path), isFalse, reason: path);
        }
      },
    );
    test('writer ownership retains maintained executables and tasks', () {
      for (final path in [
        '.github/workflows/sync_native_bindings.yml',
        '.github/actions/check/action.yaml',
        'tool/git/safe_pr_head_update.dart',
        'scripts/build_chat_app_web.sh',
        'website/src/writer.ts',
        'website/package.json',
        'example/chat_app/Makefile',
        'website/build_tools/check.js',
      ]) {
        expect(isMaintainedWriterSource(path), isTrue, reason: path);
        expect(
          isMaintainedWriterSource(path.replaceAll('/', r'\')),
          isTrue,
          reason: path,
        );
      }
      for (final path in [
        'website/build/__server/assets/js/bundle.js',
        'website/.docusaurus/generated.js',
        'example/chat_app/build/web/main.dart.js',
        'website/node_modules/package/index.js',
        '.dart_tool/generated.dart',
        'test/fixtures/writer.sh',
      ]) {
        expect(isMaintainedWriterSource(path), isFalse, reason: path);
        expect(
          isMaintainedWriterSource(path.replaceAll('/', r'\')),
          isFalse,
          reason: path,
        );
      }
    });

    test(
      'writer traversal prunes generated bytes and retains writer content',
      () {
        final root = Directory.systemTemp.createTempSync('writer-source-scan-');
        addTearDown(() => root.deleteSync(recursive: true));
        for (final path in [
          'website/build/__server/assets/js/bundle.js',
          'website/.docusaurus/generated.js',
          'example/chat_app/build/web/main.dart.js',
        ]) {
          File('${root.path}/$path')
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync([0xff]);
        }
        const paths = [
          '.github/workflows/writer.yml',
          'tool/git/writer.dart',
          'website/src/writer.ts',
          'website/package.json',
          'Makefile',
        ];
        for (final path in paths) {
          File('${root.path}/$path')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('git push origin HEAD');
        }
        // Assert traversal itself, before the writer path filter: deleting the
        // directory-pruning guard must expose the generated entries here.
        expect(
          maintainedFiles(root).map((entry) => entry.key),
          unorderedEquals(paths),
        );
        final sources = Map.fromEntries(maintainedWriterSources(root));
        expect(sources.keys, unorderedEquals(paths));
        expect(sources.values, everyElement(contains('git push origin HEAD')));
      },
    );

    test('writer traversal propagates maintained file read errors', () {
      final root = Directory.systemTemp.createTempSync('writer-source-error-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/writer.dart').writeAsBytesSync([0xff]);
      expect(
        () => maintainedWriterSources(root).toList(),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('all executable and task sources exclude bypass writers', () {
      for (final source in maintainedWriterSources(Directory('.'))) {
        final path = source.key;
        final content = source.value;
        expect(
          content,
          isNot(contains('peter-evans/create-pull-request')),
          reason: path,
        );
        expect(
          content,
          isNot(
            matches(
              RegExp(
                r'(git\s*\.\s*(createRef|updateRef|deleteRef)|git/refs/heads|\b(createRef|updateRef|deleteRef)\s*\(|git\s+push\s+[^\n]*(--force|\+refs/heads))',
                caseSensitive: false,
              ),
            ),
          ),
          reason: path,
        );
        if (path == '.github/workflows/docs_version_cut.yml') {
          expect(content, contains('git push origin HEAD:main'));
          expect(RegExp(r'\bgit\s+push\b').allMatches(content).length, 1);
        } else {
          expect(
            content,
            isNot(matches(RegExp(r'\bgit\s+push\b'))),
            reason: '$path contains an unregistered direct push',
          );
        }
        if (path != 'tool/git/safe_pr_head_update.dart') {
          expect(
            content,
            isNot(
              matches(
                RegExp(
                  r'''['"]git['"][\s\S]{0,160}['"]push['"]|['"]push['"]\s*,[\s\S]{0,160}refs/heads/''',
                ),
              ),
            ),
            reason: path,
          );
        }
        if (path == '.github/workflows/release_on_prep_merge.yml') {
          expect(content, contains('"ref=refs/tags/\$tag"'));
          expect(RegExp(r'git/refs').allMatches(content).length, 1);
        } else if (path ==
            '.github/workflows/release_genkit_on_prep_merge.yml') {
          expect(content, contains(r'"ref=refs/tags/$TAG"'));
          expect(content, contains(r'tag="genkit_llamadart-v$version"'));
          expect(RegExp(r'git/refs').allMatches(content).length, 1);
        } else if (path == 'tool/release/nonpublishing_auth_probe.py') {
          // Keep this registration tied to the diagnostic namespace, operation
          // gate and invocation ownership; additional ref APIs require review.
          expect(RegExp(r'git/refs').allMatches(content).length, 4);
          expect(
            RegExp(
              r'method == "([A-Z]+)"',
            ).allMatches(content).map((match) => match[1]).toList(),
            ['GET', 'POST', 'DELETE'],
          );
          for (final contract in [
            r'TAG = re.compile(r"ci-auth-probe-([1-9][0-9]*)-([0-9a-f]{32})\Z")',
            r'''require(path.startswith(ROOT) and (
            (method == "GET" and allowed_read and body is None)
            or (method == "POST" and suffix == "/git/refs" and isinstance(body, dict)
                and set(body) == {"ref", "sha"} and body["ref"].startswith("refs/tags/")
                and TAG.fullmatch(body["ref"][10:]) and commit(body["sha"]))
            or (method == "DELETE" and re.fullmatch(r"/git/refs/tags/ci-auth-probe-[1-9][0-9]*-[0-9a-f]{32}", suffix)
                and body is None)), "invalid-api-operation")''',
            '''def ref_path(self, tag, plural=False):
        require(TAG.fullmatch(tag) and TAG.fullmatch(tag)[1] == self.c["run_id"]
                and tag in self.owned_tags, "owned-ref-guard")
        return ROOT + ("/git/refs/tags/" if plural else "/git/ref/tags/") + tag''',
            '''def create(self, tag, token):
        self.ref_path(tag)
        return self.call("POST", ROOT + "/git/refs", token,
                         {"ref": "refs/tags/" + tag, "sha": self.c["sha"]})''',
            '''self.identity(self.get(self.ref_path(tag)), tag)
        status = None
        try:
            status, _, _ = self.call("DELETE", self.ref_path(tag, True), token)
        finally:
            observed = self.inspect(tag)''',
            '"atomicCompareAndSwap": False',
            'require(status == 204 and observed == "absent", "cleanup-incomplete")',
            'negative, positive = ["ci-auth-probe-" + self.c["run_id"] + "-" + n for n in nonces]',
            'self.owned_tags = (negative, positive)',
            'self.absent(negative)',
            'self.absent(positive)',
          ]) {
            expect(content, contains(contract), reason: path);
          }
        } else {
          expect(
            content,
            isNot(matches(RegExp(r'git/refs'))),
            reason: '$path contains an unregistered GitHub ref API',
          );
        }
      }

      final markdownFiles = maintainedFiles(
        Directory('.'),
      ).where((entry) => isMaintainedMarkdown(entry.key));
      for (final entry in markdownFiles) {
        final path = entry.key;
        final content = entry.value.readAsStringSync();
        for (final line in content.split('\n')) {
          if (!RegExp(r'\bgit\s+push\b').hasMatch(line)) continue;
          if (path == 'doc/pr_branch_writer_inventory.md') {
            expect(
              line,
              contains(
                'ordinary blind `git push` is not an authorized open-PR update path',
              ),
            );
            continue;
          }
          expect(
            path,
            matches(
              RegExp(
                r'^website/versioned_docs/version-[^/]+/maintainers/release-workflow\.md$',
              ),
            ),
            reason: '$path documents an unregistered push',
          );
          expect(
            line.trim(),
            matches(
              RegExp(
                r'^git push origin llamadart_[a-z0-9_]+-v[0-9]+\.[0-9]+\.[0-9]+$',
              ),
            ),
            reason: '$path must remain a tag-only push example',
          );
        }
      }
    });

    test('the only workflow open-PR writer invokes the guarded helper', () {
      final workflow = File(
        '.github/workflows/sync_native_bindings.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(workflowWriterContractViolations(workflow), isEmpty);
      expect(workflow, contains('tool/git/safe_pr_head_update.dart'));
      expect(workflow, contains('ref: main'));
      expect(workflow, contains('target_ref="refs/heads/\${branch}"'));
      expect(workflow, contains('--expected-sha'));
      expect(workflow, contains('--proposed-sha'));
      expect(workflow, contains('--writer github-actions-native-sync'));
      expect(workflow, contains('git fetch --quiet --no-tags origin'));
      expect(workflow, contains('if [[ "\${fetched}" != "\${expected}" ]]'));
      expect(
        workflow,
        contains('git merge-base --is-ancestor "\${candidate}" "\${expected}"'),
      );
      expect(workflow, contains('git merge --no-ff --no-edit "\${candidate}"'));
      expect(workflow, contains('git rev-list --parents -n 1 "\${proposed}"'));
      expect(
        workflow,
        contains('git merge-base --is-ancestor "\${expected}" "\${proposed}"'),
      );
      expect(
        workflow,
        contains('git merge-base --is-ancestor "\${candidate}" "\${proposed}"'),
      );
      expect(workflow, contains('should_update="\${has_changes}"'));
      expect(workflow, contains('if [[ "\${HAS_CHANGES}" != "true" ]]'));
      expect(workflow, contains('gh pr close'));
      expect(workflow, contains('gh pr edit'));
      expect(workflow, contains('gh pr create'));
      expect(
        workflow.indexOf('tool/git/safe_pr_head_update.dart'),
        lessThan(workflow.indexOf('gh pr close')),
      );
      expect(
        workflow.indexOf('tool/git/safe_pr_head_update.dart'),
        lessThan(workflow.indexOf('gh pr edit')),
      );
      expect(
        workflow.indexOf('tool/git/safe_pr_head_update.dart'),
        lessThan(workflow.indexOf('gh pr create')),
      );
      expect(workflow, isNot(contains('create-pull-request')));
    });

    test('workflow contract rejects guard deletion and mutation bypasses', () {
      final workflow = File(
        '.github/workflows/sync_native_bindings.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(workflowWriterContractViolations(workflow), isEmpty);

      final deletedGuard = workflow.replaceFirst(
        '          dart run tool/git/safe_pr_head_update.dart \\\n',
        '',
      );
      expect(workflowWriterContractViolations(deletedGuard), isNotEmpty);

      final mentionedButNotExecuted = workflow.replaceFirst(
        '          dart run tool/git/safe_pr_head_update.dart \\\n',
        '          echo tool/git/safe_pr_head_update.dart \\\n',
      );
      expect(
        workflowWriterContractViolations(mentionedButNotExecuted),
        isNotEmpty,
      );

      for (final bypass in <String>[
        '          git push --force origin HEAD:refs/heads/bypass\n',
        "          gh api graphql -f query='mutation { updateRef(input: {}) }'\n",
        '          gh api -X PATCH repos/example/repo/git/refs/heads/bypass\n',
      ]) {
        final bypassed = workflow.replaceFirst(
          '          set -euo pipefail\n',
          '          set -euo pipefail\n$bypass',
        );
        expect(
          workflowWriterContractViolations(bypassed),
          isNotEmpty,
          reason: bypass.trim(),
        );
      }

      final missingExpected = workflow.replaceFirst(
        '            --expected-sha "\${EXPECTED_SHA}" \\\n',
        '',
      );
      expect(workflowWriterContractViolations(missingExpected), isNotEmpty);
    });

    test('docs bind contributors to the inventory and residual boundary', () {
      final agents = File('AGENTS.md').readAsStringSync();
      final contributing = File('CONTRIBUTING.md').readAsStringSync();
      final testingMatrix = File('doc/testing_matrix.md').readAsStringSync();
      final inventory = File(
        'doc/pr_branch_writer_inventory.md',
      ).readAsStringSync();
      expect(agents, contains('doc/pr_branch_writer_inventory.md'));
      expect(agents, contains('tool/git/safe_pr_head_update.dart'));
      expect(contributing, contains('tool/git/safe_pr_head_update.dart'));
      expect(contributing, contains('exact observed fork-branch head'));
      expect(testingMatrix, contains('tool/git/safe_pr_head_update.dart'));
      expect(inventory, contains('GitHub web UI'));
      expect(inventory, contains('third-party'));
      expect(inventory, contains('protection or rulesets'));
      expect(inventory, contains('b6af5a8b5d1973bc72d4e5283f1c7d728a679cb7'));
      expect(inventory, contains('facts'));
      expect(inventory, contains('Inference'));
      expect(inventory, contains('.github/dependabot.yml'));
      expect(inventory, contains('CONTRIBUTING.md'));
    });
  });
}
