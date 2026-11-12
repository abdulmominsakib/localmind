#!/usr/bin/env dart

import 'dart:async';
import 'dart:io';

/// Standard command-line usage error (`EX_USAGE`).
const int _usageErrorExitCode = 64;

/// The dependency resolver used for a package in this repository.
enum WorkspacePackageManager {
  /// Resolve with the Dart SDK.
  dart,

  /// Resolve with the Flutter SDK.
  flutter,
}

/// A maintained Dart or Flutter package in the workspace manifest.
class WorkspacePackage {
  /// Creates a package entry relative to the repository root.
  const WorkspacePackage(
    this.path,
    this.packageManager, {
    this.prepareForRootQualityGates = true,
  });

  /// The package directory relative to the repository root.
  final String path;

  /// The SDK command that resolves this package's dependencies.
  final WorkspacePackageManager packageManager;

  /// Whether the root format/analyze lane resolves this package directly.
  final bool prepareForRootQualityGates;
}

/// Every maintained package that must be classified by the root quality gates.
///
/// Keep this list explicit so lane ownership and SDK selection are reviewable.
/// The layout check below fails when a package is added or removed without
/// updating the list.
const List<WorkspacePackage> workspacePackages = <WorkspacePackage>[
  WorkspacePackage('.', WorkspacePackageManager.flutter),
  WorkspacePackage('example/basic_app', WorkspacePackageManager.flutter),
  WorkspacePackage('example/chat_app', WorkspacePackageManager.flutter),
  WorkspacePackage('example/laya_command_bar', WorkspacePackageManager.flutter),
  WorkspacePackage('example/laya_tetris', WorkspacePackageManager.flutter),
  WorkspacePackage('example/llamadart_cli', WorkspacePackageManager.dart),
  WorkspacePackage('example/llamadart_server', WorkspacePackageManager.dart),
  WorkspacePackage('example/tui_coding_agent', WorkspacePackageManager.dart),
  WorkspacePackage(
    'packages/genkit_llamadart',
    WorkspacePackageManager.dart,
    prepareForRootQualityGates: false,
  ),
  WorkspacePackage(
    'packages/llamadart_validation',
    WorkspacePackageManager.dart,
    prepareForRootQualityGates: false,
  ),
  WorkspacePackage(
    'packages/llamadart_litert_lm_flutter',
    WorkspacePackageManager.flutter,
    prepareForRootQualityGates: false,
  ),
  WorkspacePackage(
    'packages/llamadart_model_store',
    WorkspacePackageManager.flutter,
    prepareForRootQualityGates: false,
  ),
  WorkspacePackage(
    'packages/llamadart_llama_cpp_flutter',
    WorkspacePackageManager.flutter,
    prepareForRootQualityGates: false,
  ),
  WorkspacePackage(
    'packages/llamadart_stable_diffusion_flutter',
    WorkspacePackageManager.flutter,
    prepareForRootQualityGates: false,
  ),
];

/// Runs one dependency-resolution command.
typedef WorkspaceCommandRunner =
    Future<int> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

/// Returns maintained `pubspec.yaml` paths found in the repository.
///
/// Generated `.dart_tool`, `build`, Flutter platform `ephemeral`, and plugin
/// `.symlinks` trees are never package roots. The root, `example/`, and
/// `packages/` directories are the repository-owned package boundary; vendored
/// or local-only trees outside it are not workspace members.
Set<String> discoverWorkspacePubspecs(Directory repositoryRoot) {
  final paths = <String>{};
  final rootPubspec = File('${repositoryRoot.path}/pubspec.yaml');
  if (rootPubspec.existsSync()) {
    paths.add('pubspec.yaml');
  }

  for (final topLevel in const <String>['example', 'packages']) {
    final directory = Directory('${repositoryRoot.path}/$topLevel');
    if (!directory.existsSync()) {
      continue;
    }
    _discoverPubspecs(repositoryRoot, directory, paths);
  }
  return paths;
}

void _discoverPubspecs(
  Directory repositoryRoot,
  Directory directory,
  Set<String> paths,
) {
  for (final entity in directory.listSync(followLinks: false)) {
    final relative = entity.path
        .substring(repositoryRoot.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final segments = relative.split('/');
    if (entity is Directory) {
      if (_isGeneratedDirectory(segments)) {
        continue;
      }
      _discoverPubspecs(repositoryRoot, entity, paths);
    } else if (entity is File && segments.last == 'pubspec.yaml') {
      paths.add(relative);
    }
  }
}

bool _isGeneratedDirectory(List<String> segments) {
  final name = segments.last;
  final lowerName = name.toLowerCase();
  return lowerName == '.dart_tool' ||
      lowerName == 'build' ||
      lowerName == '.symlinks' ||
      lowerName == 'pods' ||
      _isFlutterEphemeral(segments);
}

bool _isFlutterEphemeral(List<String> segments) {
  for (var index = 0; index < segments.length - 1; index++) {
    if (segments[index].toLowerCase() == 'flutter' &&
        segments[index + 1] == 'ephemeral') {
      return true;
    }
  }
  return false;
}

/// Returns package-layout errors that would make preparation incomplete.
List<String> validateWorkspaceManifest(Directory repositoryRoot) {
  final expected = workspacePackages
      .map(
        (package) => package.path == '.'
            ? 'pubspec.yaml'
            : '${package.path}/pubspec.yaml',
      )
      .toSet();
  final discovered = discoverWorkspacePubspecs(repositoryRoot);
  final errors = <String>[];

  for (final missing in expected.difference(discovered).toList()..sort()) {
    errors.add('Missing workspace package: $missing');
  }
  for (final unclassified in discovered.difference(expected).toList()..sort()) {
    errors.add('Unclassified workspace package: $unclassified');
  }
  return errors;
}

/// Resolves every root-quality-gate package, stopping at the first failure.
Future<int> prepareWorkspace(
  Directory repositoryRoot, {
  WorkspaceCommandRunner commandRunner = runWorkspaceCommand,
}) async {
  final layoutErrors = validateWorkspaceManifest(repositoryRoot);
  if (layoutErrors.isNotEmpty) {
    for (final error in layoutErrors) {
      stderr.writeln(error);
    }
    return _usageErrorExitCode;
  }

  for (final package in workspacePackages.where(
    (package) => package.prepareForRootQualityGates,
  )) {
    final executable = package.packageManager.name;
    final arguments = <String>['pub', 'get'];
    stdout.writeln(
      'Preparing ${package.path} with $executable ${arguments.join(' ')}',
    );
    final result = await commandRunner(
      executable,
      arguments,
      package.path == '.'
          ? repositoryRoot.path
          : '${repositoryRoot.path}/${package.path}',
    );
    if (result != 0) {
      stderr.writeln(
        'Dependency preparation failed for ${package.path} (exit $result).',
      );
      return result;
    }
  }
  return 0;
}

/// Starts one workspace process; [Process.start] outside tests.
typedef WorkspaceProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      ProcessStartMode mode,
      bool runInShell,
    });

/// Runs a workspace command with output attached to the current terminal.
///
/// On Windows, Flutter's `flutter` and `dart` are `.bat` scripts, which
/// [Process.start] launches only with `runInShell`.
///
/// [onProcessStarted] optionally records the returned process ID. It receives
/// no command arguments and does not establish descendant ownership. The
/// synchronous callback must return promptly.
Future<int> runWorkspaceCommand(
  String executable,
  List<String> arguments,
  String workingDirectory, {
  bool? isWindows,
  WorkspaceProcessStarter startProcess = Process.start,
  void Function(int processId)? onProcessStarted,
}) async {
  final Process process;
  try {
    process = await startProcess(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.inheritStdio,
      runInShell: isWindows ?? Platform.isWindows,
    );
  } on ProcessException catch (error) {
    stderr.writeln(
      'Could not start $executable in $workingDirectory: ${error.message}',
    );
    return 127;
  }
  var completed = false;
  try {
    onProcessStarted?.call(process.pid);
    try {
      final result = await process.exitCode;
      completed = true;
      return result;
    } on ProcessException catch (error) {
      stderr.writeln(
        'Could not start $executable in $workingDirectory: ${error.message}',
      );
      return 127;
    }
  } finally {
    if (!completed) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      } on ProcessException {
        // Preserve an exit-future failure without replacing its result.
      }
    }
  }
}

Future<void> main() async {
  final repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final result = await prepareWorkspace(repositoryRoot);
  if (result != 0) {
    exitCode = result;
  }
}
