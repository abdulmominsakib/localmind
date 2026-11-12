import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

/// Bounds and reaps a direct fixture child before earlier scratch cleanup.
Future<ProcessResult> runBoundedFixtureProcess(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  Future<Process>? started;
  var exited = false;
  Future<void> reap() async {
    final pending = started;
    if (pending == null) return;
    final Process child;
    try {
      child = await pending;
    } on Object {
      return;
    }
    if (exited) return;
    child.kill(ProcessSignal.sigkill);
    await child.exitCode.timeout(const Duration(seconds: 5));
    exited = true;
  }

  // A test timeout leaves its async body running. Register before spawning so
  // a late continuation cannot create a child after its test has closed.
  addTearDown(reap);
  started = Process.start(executable, arguments);
  final process = await started;
  final exit = process.exitCode.then((code) {
    exited = true;
    return code;
  });
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
    await process.stdin.close();
    final code = await exit.timeout(timeout);
    await outputDone.timeout(const Duration(seconds: 5));
    return ProcessResult(process.pid, code, '$stdout', '$stderr');
  } on TimeoutException {
    await reap();
    await outputDone.timeout(
      const Duration(seconds: 5),
      onTimeout: () => const [],
    );
    throw TimeoutException(
      'Fixture child did not complete within $timeout.\n'
      'stdout:\n$stdout\nstderr:\n$stderr',
      timeout,
    );
  } finally {
    try {
      await reap();
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }
}
