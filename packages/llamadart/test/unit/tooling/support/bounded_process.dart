import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

/// Runs [executable] like [Process.run], but kills it after [timeout] and
/// fails the test with whatever it printed.
///
/// A test timeout does not stop a [Process.run] child: it keeps running into
/// the next test after `tearDown` has deleted its files, and competes with that
/// test's own processes.
Future<ProcessResult> runBoundedProcess(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final started = Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  var exited = false;
  // An interrupted test must reap its child before earlier scratch cleanup.
  addTearDown(() async {
    final Process child;
    try {
      child = await started;
    } on Object {
      return;
    }
    if (exited) return;
    child.kill(ProcessSignal.sigkill);
    await child.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('Child ${child.pid} survived test teardown.'),
    );
  });
  final process = await started;
  final exit = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  await process.stdin.close();
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final subscriptions = [
    process.stdout.transform(systemEncoding.decoder).listen(stdout.write),
    process.stderr.transform(systemEncoding.decoder).listen(stderr.write),
  ];
  final outputDone = Future.wait([
    for (final subscription in subscriptions) subscription.asFuture<void>(),
  ]);
  try {
    final exitCode = await exit.timeout(
      timeout,
      onTimeout: () async {
        final state = _linuxProcessState(process.pid);
        process.kill();
        var cleanup = '';
        try {
          await exit.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          // Windows terminates directly; POSIX children can ignore SIGTERM.
          process.kill(ProcessSignal.sigkill);
          try {
            await exit.timeout(const Duration(seconds: 5));
          } on TimeoutException {
            cleanup =
                '\nChild ${process.pid} did not exit after forced termination.';
          }
        }
        // A grandchild that inherited the pipes can hold them open.
        await outputDone.timeout(
          const Duration(seconds: 5),
          onTimeout: () async {
            for (final subscription in subscriptions) {
              await subscription.cancel();
            }
            return const [];
          },
        );
        fail(
          '`$executable ${arguments.join(' ')}` did not exit within '
          '${timeout.inSeconds} s.$state$cleanup\nstdout:\n$stdout\nstderr:\n'
          '$stderr',
        );
      },
    );
    await outputDone;
    return ProcessResult(process.pid, exitCode, '$stdout', '$stderr');
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

/// Tells a child blocked in disk I/O (`D`, rising `read_bytes`), for example
/// paging in a cold executable, from one idling in its own event loop (`S`).
String _linuxProcessState(int pid) {
  if (!Platform.isLinux) return '';
  String read(String name) {
    try {
      return File('/proc/$pid/$name').readAsStringSync().trim();
    } on FileSystemException {
      return '';
    }
  }

  String field(String text, String name) => text
      .split('\n')
      .firstWhere((line) => line.startsWith('$name:'), orElse: () => '')
      .trim();

  final status = read('status');
  return '\nChild $pid at timeout: ${field(status, 'State')}; '
      'wchan: ${read('wchan')}; ${field(read('io'), 'read_bytes')}';
}
