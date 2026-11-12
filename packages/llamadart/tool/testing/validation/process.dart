import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Captured subprocess output; authentication results are never journaled.
class CommandResult {
  const CommandResult(this.code, this.output, this.error);
  final int code;
  final String output;
  final String error;
}

/// Injectable command boundary for remote lifecycle regression tests.
typedef CommandExecutor =
    Future<CommandResult> Function(
      String executable,
      List<String> arguments, {
      String? directory,
      Duration? timeout,
      Map<String, String>? environment,
    });

/// Executes without a shell, bounds retained output and kills timed-out children.
///
/// [environment] adds to or overrides the inherited environment.
///
/// [onProcessStarted] optionally records the returned host process ID, without
/// command arguments. This ID alone does not establish descendant ownership.
/// The synchronous callback must return promptly; deadlines cannot preempt it.
///
/// [processHostEntryPath] optionally selects a literal private host entry. The
/// caller owns its exact identity and must preserve the maintained host contract.
Future<CommandResult> executeCommand(
  String executable,
  List<String> arguments, {
  String? directory,
  Duration? timeout,
  Map<String, String>? environment,
  void Function(int processId)? onProcessStarted,
  String? processHostEntryPath,
}) async {
  final duration = timeout ?? const Duration(minutes: 5);
  final process = await Process.start(
    Platform.isWindows ? 'python' : 'python3',
    [
      processHostEntryPath ?? _checkedInProcessHostEntry(),
      (duration.inMilliseconds / 1000).toString(),
      executable,
      ...arguments,
    ],
    workingDirectory: directory,
    environment: environment,
  );
  final elapsed = Stopwatch()..start();
  final deadline = duration + const Duration(seconds: 10);
  final output = StringBuffer();
  final error = StringBuffer();
  final streams = <StreamSubscription<String>>[];
  final drains = <Future<void>>[];
  try {
    for (final pair in [(process.stdout, output), (process.stderr, error)]) {
      final done = Completer<void>();
      streams.add(
        pair.$1
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(
              pair.$2.write,
              onDone: done.complete,
              onError: done.completeError,
            ),
      );
      drains.add(done.future);
    }
    onProcessStarted?.call(process.pid);
    final code = await (() async {
      final code = await process.exitCode;
      await Future.wait(drains);
      return code;
    })().timeout(deadline - elapsed.elapsed);
    if (elapsed.elapsed >= deadline) {
      throw TimeoutException('Subprocess deadline exceeded', duration);
    }
    if (code == 124) {
      throw TimeoutException('Subprocess deadline exceeded', duration);
    }
    if (code == 125) {
      throw StateError('Subprocess containment or output limit failed');
    }
    return CommandResult(code, output.toString(), error.toString());
  } finally {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
    for (final stream in streams) {
      await stream.cancel();
    }
  }
}

String _checkedInProcessHostEntry() {
  // Find the checked-in host from the current repository, including package cwd.
  var root = Directory.current.absolute;
  while (!File(
    p.join(root.path, 'tool/testing/validation/process_host.py'),
  ).existsSync()) {
    if (root.parent.path == root.path) {
      throw StateError('Cannot locate subprocess host');
    }
    root = root.parent;
  }
  return p.join(root.path, 'tool/testing/validation/process_host.py');
}

/// Validates a successful JSON response without logging credentials/errors.
Map<String, dynamic> jsonObject(CommandResult result) {
  if (result.code != 0) {
    throw StateError('Provider command failed (${result.code})');
  }
  return jsonDecode(result.output) as Map<String, dynamic>;
}

/// Literal POSIX argument quoting for the remote shell boundary.
String shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

/// Literal PowerShell string quoting for the remote Windows boundary.
String powershellQuote(String value) => "'${value.replaceAll("'", "''")}'";
