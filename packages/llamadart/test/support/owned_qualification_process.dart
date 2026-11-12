import 'dart:async';
import 'dart:io';

/// Captures exact bytes and kills only this owned child at its deadline.
Future<
  ({
    int exitCode,
    bool timedOut,
    bool outputComplete,
    List<int> stdout,
    List<int> stderr,
  })
>
runOwnedQualificationProcess(
  String executable,
  List<String> arguments, {
  required int seconds,
}) async {
  final process = await Process.start(executable, arguments);
  final stdout = <int>[], stderr = <int>[];
  final outDone = Completer<void>(), errDone = Completer<void>();
  var outputComplete = true;
  final out = process.stdout.listen(
    stdout.addAll,
    onDone: () {
      if (!outDone.isCompleted) outDone.complete();
    },
    onError: (Object _) {
      outputComplete = false;
      if (!outDone.isCompleted) outDone.complete();
    },
  );
  final err = process.stderr.listen(
    stderr.addAll,
    onDone: () {
      if (!errDone.isCompleted) errDone.complete();
    },
    onError: (Object _) {
      outputComplete = false;
      if (!errDone.isCompleted) errDone.complete();
    },
  );
  var finished = false, timedOut = false;
  late int code;
  try {
    try {
      code = await process.exitCode.timeout(Duration(seconds: seconds));
    } on TimeoutException {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      code = await process.exitCode;
    }
    finished = true;
  } finally {
    if (!finished) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    try {
      await Future.wait([
        outDone.future,
        errDone.future,
      ]).timeout(const Duration(seconds: 2));
    } on TimeoutException {
      outputComplete = false;
    }
    await out.cancel();
    await err.cancel();
  }
  return (
    exitCode: code,
    timedOut: timedOut,
    outputComplete: outputComplete,
    stdout: stdout,
    stderr: stderr,
  );
}
