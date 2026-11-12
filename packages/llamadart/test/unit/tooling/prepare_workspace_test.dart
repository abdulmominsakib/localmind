@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/prepare_workspace.dart';

Directory _workspaceFixture() {
  final root = Directory.systemTemp.createTempSync('prepare_workspace_test');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final package in workspacePackages) {
    final directory =
        package.path == '.' ? root : Directory('${root.path}/${package.path}')
          ..createSync(recursive: true);
    File('${directory.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
  }
  return root;
}

String _workspaceRelativePath(String rootPath, String workingDirectory) {
  if (workingDirectory == rootPath) {
    return '.';
  }
  return workingDirectory.substring(rootPath.length + 1).replaceAll('\\', '/');
}

void main() {
  test('checked-in package roots are fully classified', () {
    expect(validateWorkspaceManifest(Directory.current), isEmpty);
  });

  test('workspace manifest has one canonical entry for every owned lane', () {
    expect(workspacePackages.map((package) => package.path), <String>[
      '.',
      'example/basic_app',
      'example/chat_app',
      'example/laya_command_bar',
      'example/laya_tetris',
      'example/llamadart_cli',
      'example/llamadart_server',
      'example/tui_coding_agent',
      'packages/genkit_llamadart',
      'packages/llamadart_validation',
      'packages/llamadart_litert_lm_flutter',
      'packages/llamadart_model_store',
      'packages/llamadart_llama_cpp_flutter',
      'packages/llamadart_stable_diffusion_flutter',
    ]);
    expect(
      workspacePackages.map((package) => package.path).toSet(),
      hasLength(workspacePackages.length),
    );
    expect(
      workspacePackages.where((package) => package.path == '.'),
      hasLength(1),
    );
    expect(
      workspacePackages.map((package) => package.path),
      everyElement(
        anyOf(
          equals('.'),
          allOf(isNot(startsWith('/')), isNot(contains('\\'))),
        ),
      ),
    );
  });

  test(
    'prepares every root-gate package with its declared SDK in order',
    () async {
      final root = _workspaceFixture();
      final commands = <String>[];

      final result = await prepareWorkspace(
        root,
        commandRunner: (executable, arguments, workingDirectory) async {
          final relative = _workspaceRelativePath(root.path, workingDirectory);
          commands.add('$executable ${arguments.join(' ')} @ $relative');
          return 0;
        },
      );

      expect(result, 0);
      expect(commands, <String>[
        'flutter pub get @ .',
        'flutter pub get @ example/basic_app',
        'flutter pub get @ example/chat_app',
        'flutter pub get @ example/laya_command_bar',
        'flutter pub get @ example/laya_tetris',
        'dart pub get @ example/llamadart_cli',
        'dart pub get @ example/llamadart_server',
        'dart pub get @ example/tui_coding_agent',
      ]);
      expect(
        workspacePackages
            .where((package) => package.path.startsWith('example/'))
            .every((package) => package.prepareForRootQualityGates),
        isTrue,
        reason: 'Every maintained example belongs to the root quality lane.',
      );
      expect(
        workspacePackages
            .where((package) => package.path.startsWith('packages/'))
            .every((package) => !package.prepareForRootQualityGates),
        isTrue,
        reason: 'Companion packages own separate CI quality lanes.',
      );
    },
  );

  test('normalizes Windows workspace command paths for stable assertions', () {
    expect(
      _workspaceRelativePath(r'C:\repo', r'C:\repo\example\chat_app'),
      'example/chat_app',
    );
  });

  test('rejects a package that is not in the preparation manifest', () {
    final root = _workspaceFixture();
    final pubspec = File('${root.path}/example/new_example/pubspec.yaml');
    pubspec.parent.createSync(recursive: true);
    pubspec.writeAsStringSync('name: new_example\n');

    expect(
      validateWorkspaceManifest(root),
      contains(
        'Unclassified workspace package: example/new_example/pubspec.yaml',
      ),
    );
  });

  test('rejects a missing package from the preparation manifest', () {
    final root = _workspaceFixture();
    File('${root.path}/example/llamadart_server/pubspec.yaml').deleteSync();

    expect(
      validateWorkspaceManifest(root),
      contains(
        'Missing workspace package: '
        'example/llamadart_server/pubspec.yaml',
      ),
    );
  });

  test('rejects an invalid manifest before dependency preparation', () async {
    final root = _workspaceFixture();
    File('${root.path}/example/llamadart_server/pubspec.yaml').deleteSync();
    var commandStarted = false;

    final result = await prepareWorkspace(
      root,
      commandRunner: (executable, arguments, workingDirectory) async {
        commandStarted = true;
        return 0;
      },
    );

    expect(result, 64, reason: 'Manifest failures use EX_USAGE.');
    expect(commandStarted, isFalse);
  });

  test('ignores explicitly generated package trees', () {
    final root = _workspaceFixture();
    for (final path in <String>[
      'example/chat_app/.dart_tool/generated/pubspec.yaml',
      'example/chat_app/build/generated/pubspec.yaml',
      'example/chat_app/macos/Flutter/ephemeral/plugin/pubspec.yaml',
      'example/chat_app/ios/.symlinks/plugins/example/pubspec.yaml',
      'example/chat_app/ios/Pods/generated/pubspec.yaml',
      'example/chat_app/macos/Pods/generated/pubspec.yaml',
    ]) {
      final pubspec = File('${root.path}/$path');
      pubspec.parent.createSync(recursive: true);
      pubspec.writeAsStringSync('name: generated\n');
    }

    expect(validateWorkspaceManifest(root), isEmpty);
  });

  test('does not prune maintained packages with generated-looking names', () {
    final root = _workspaceFixture();
    for (final name in <String>[
      '.dart_tooling',
      'builder',
      '.symlinks_backup',
      'PodsApp',
      'ephemeralized',
    ]) {
      final pubspec = File('${root.path}/example/$name/pubspec.yaml');
      pubspec.parent.createSync(recursive: true);
      pubspec.writeAsStringSync('name: generated_lookalike\n');
    }

    expect(validateWorkspaceManifest(root), <String>[
      'Unclassified workspace package: '
          'example/.dart_tooling/pubspec.yaml',
      'Unclassified workspace package: '
          'example/.symlinks_backup/pubspec.yaml',
      'Unclassified workspace package: example/PodsApp/pubspec.yaml',
      'Unclassified workspace package: example/builder/pubspec.yaml',
      'Unclassified workspace package: '
          'example/ephemeralized/pubspec.yaml',
    ]);
  });

  test(
    'does not traverse symlinked package trees',
    () {
      final root = _workspaceFixture();
      final externalPackage = Directory('${root.path}/external_fixture')
        ..createSync();
      File(
        '${externalPackage.path}/pubspec.yaml',
      ).writeAsStringSync('name: external\n');
      Link(
        '${root.path}/example/symlinked_package',
      ).createSync(externalPackage.path);

      expect(validateWorkspaceManifest(root), isEmpty);
    },
    skip: Platform.isWindows ? 'Symlink creation needs elevated access.' : null,
  );

  test('stops without hiding a failed dependency resolution', () async {
    final root = _workspaceFixture();
    final calls = <String>[];

    final result = await prepareWorkspace(
      root,
      commandRunner: (executable, arguments, workingDirectory) async {
        calls.add(
          '$executable ${arguments.join(' ')} @ '
          '${_workspaceRelativePath(root.path, workingDirectory)}',
        );
        return calls.length == 3 ? 17 : 0;
      },
    );

    expect(result, 17);
    expect(calls, <String>[
      'flutter pub get @ .',
      'flutter pub get @ example/basic_app',
      'flutter pub get @ example/chat_app',
    ]);
  });

  test('launches SDK commands through a shell only on Windows', () async {
    final root = _workspaceFixture();
    for (final isWindows in <bool>[true, false]) {
      final launches = <String>[];
      final result = await runWorkspaceCommand(
        'flutter',
        const <String>['pub', 'get'],
        root.path,
        isWindows: isWindows,
        startProcess:
            (
              executable,
              arguments, {
              workingDirectory,
              mode = ProcessStartMode.normal,
              runInShell = false,
            }) async {
              launches.add(
                '$executable ${arguments.join(' ')} @ $workingDirectory '
                '${mode == ProcessStartMode.inheritStdio} $runInShell',
              );
              return _ExitedProcess(isWindows ? 3 : 0);
            },
      );

      expect(result, isWindows ? 3 : 0);
      expect(launches, <String>[
        'flutter pub get @ ${root.path} true $isWindows',
      ], reason: 'isWindows: $isWindows');
    }
  });

  test('starts the dart SDK command on this host', () async {
    final root = _workspaceFixture();

    final result = await runWorkspaceCommand('dart', const <String>[
      '--version',
    ], root.path);

    expect(result, 0);
  });

  test(
    'optional process receipt uses the returned ID without changing status',
    () async {
      final root = _workspaceFixture();
      final process = _RecordedProcess(421, 17);
      final receipts = <int>[];
      final result = await runWorkspaceCommand(
        'fixture',
        const <String>['unrecorded-argument'],
        root.path,
        startProcess:
            (
              executable,
              arguments, {
              workingDirectory,
              mode = ProcessStartMode.normal,
              runInShell = false,
            }) async => process,
        onProcessStarted: receipts.add,
      );

      expect(receipts, <int>[421]);
      expect(result, 17);
      expect(process.signals, isEmpty);
    },
  );

  test(
    'failed process receipt retires the returned process and stays failed',
    () async {
      final root = _workspaceFixture();
      final process = _RecordedProcess(422);
      final failure = FileSystemException('fixture publication failed');

      await expectLater(
        runWorkspaceCommand(
          'fixture',
          const <String>[],
          root.path,
          startProcess:
              (
                executable,
                arguments, {
                workingDirectory,
                mode = ProcessStartMode.normal,
                runInShell = false,
              }) async => process,
          onProcessStarted: (processId) {
            expect(processId, 422);
            throw failure;
          },
        ),
        throwsA(same(failure)),
      );

      expect(process.signals, <ProcessSignal>[ProcessSignal.sigterm]);
      expect(await process.exitCode, -15);
    },
  );

  test('a process that ignores SIGTERM is killed after five seconds', () async {
    final root = _workspaceFixture();
    final process = _TermIgnoringProcess();
    final failure = FileSystemException('fixture publication failed');
    final timers = <Duration>[];
    await expectLater(
      runZoned(
        () => runWorkspaceCommand(
          'fixture',
          const <String>[],
          root.path,
          startProcess:
              (
                executable,
                arguments, {
                workingDirectory,
                mode = ProcessStartMode.normal,
                runInShell = false,
              }) async => process,
          onProcessStarted: (_) => throw failure,
        ),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            timers.add(duration);
            return parent.createTimer(zone, Duration.zero, callback);
          },
        ),
      ),
      throwsA(same(failure)),
    );
    expect(timers, <Duration>[const Duration(seconds: 5)]);
    expect(process.signals, <ProcessSignal>[
      ProcessSignal.sigterm,
      ProcessSignal.sigkill,
    ]);
  });

  test(
    'an awaited process error keeps the existing launch-error status',
    () async {
      final root = _workspaceFixture();
      final process = _FailedExitProcess();
      final result = await runWorkspaceCommand(
        'fixture',
        const <String>[],
        root.path,
        startProcess:
            (
              executable,
              arguments, {
              workingDirectory,
              mode = ProcessStartMode.normal,
              runInShell = false,
            }) async => process,
      );
      expect(result, 127);
      expect(process.signals, <ProcessSignal>[ProcessSignal.sigterm]);
    },
  );

  test(
    'a receipt ProcessException is not reported as a launch failure',
    () async {
      final root = _workspaceFixture();
      final process = _RecordedProcess(423);
      final failure = ProcessException('fixture', const <String>[]);
      await expectLater(
        runWorkspaceCommand(
          'fixture',
          const <String>[],
          root.path,
          startProcess:
              (
                executable,
                arguments, {
                workingDirectory,
                mode = ProcessStartMode.normal,
                runInShell = false,
              }) async => process,
          onProcessStarted: (_) => throw failure,
        ),
        throwsA(same(failure)),
      );
      expect(process.signals, <ProcessSignal>[ProcessSignal.sigterm]);
    },
  );

  test('reports a stable exit code when an SDK command cannot start', () async {
    final root = _workspaceFixture();

    final result = await runWorkspaceCommand(
      'missing-workspace-sdk-command-for-test',
      const <String>['pub', 'get'],
      root.path,
      isWindows: false,
    );

    expect(result, 127);
  });
}

class _RecordedProcess implements Process {
  _RecordedProcess(this.pid, [int? code]) {
    if (code != null) {
      _exit.complete(code);
    }
  }

  @override
  final int pid;
  final _exit = Completer<int>();
  final signals = <ProcessSignal>[];

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (!_exit.isCompleted) {
      _exit.complete(-signal.signalNumber);
    }
    return true;
  }

  @override
  IOSink get stdin => throw UnsupportedError('stdio is inherited');

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();
}

class _TermIgnoringProcess extends _RecordedProcess {
  _TermIgnoringProcess() : super(425);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (signal == ProcessSignal.sigkill) {
      _exit.complete(-signal.signalNumber);
    }
    return true;
  }
}

class _FailedExitProcess extends _RecordedProcess {
  _FailedExitProcess() : super(424);

  @override
  Future<int> get exitCode async =>
      throw ProcessException('fixture', const <String>[]);
}

class _ExitedProcess implements Process {
  _ExitedProcess(this._exitCode);

  final int _exitCode;

  @override
  Future<int> get exitCode async => _exitCode;

  @override
  int get pid => 0;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => false;

  @override
  IOSink get stdin => throw UnsupportedError('stdio is inherited');

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();
}
