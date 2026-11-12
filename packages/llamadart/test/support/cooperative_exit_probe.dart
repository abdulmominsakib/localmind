import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Requests disposal after generation starts and rejects any stream error.
Future<void> disposeAfterProbeGenerationStarts<T>(
  Stream<T> generation,
  Future<void> Function() dispose,
) async {
  final first = Completer<void>();
  Object? failure;
  StackTrace? failureStack;
  final subscription = generation.listen(
    (_) {
      if (!first.isCompleted) first.complete();
    },
    onError: (Object error, StackTrace stack) {
      if (!first.isCompleted) {
        first.completeError(error, stack);
      } else {
        failure = error;
        failureStack = stack;
      }
    },
    onDone: () {
      if (!first.isCompleted) {
        first.completeError(StateError('Generation produced no token.'));
      }
    },
  );
  try {
    await first.future;
    await dispose();
  } finally {
    await subscription.cancel();
  }
  final error = failure;
  if (error != null) {
    Error.throwWithStackTrace(error, failureStack!);
  }
}

/// Runs a probe's model-owning isolate and waits for its actual VM exit.
///
/// The entry point sends `true` after disposing its engines. That notice alone
/// is insufficient: native finalizers may still run before the VM sends null.
Future<void> runCooperativeExitProbe(
  void Function((SendPort, List<String>)) entryPoint,
  List<String> arguments, {
  required String completedMarker,
}) async {
  final events = ReceivePort();
  final messages = StreamIterator<Object?>(events);
  var disposed = false;
  Object? failure;
  try {
    await Isolate.spawn(
      entryPoint,
      (events.sendPort, arguments),
      onExit: events.sendPort,
      onError: events.sendPort,
      errorsAreFatal: true,
    );
    while (await messages.moveNext()) {
      final message = messages.current;
      if (message == null) {
        if (failure != null) throw failure;
        if (!disposed) {
          throw StateError('Probe worker exited without completing disposal.');
        }
        stdout.writeln(completedMarker);
        return;
      }
      if (message == true) {
        disposed = true;
      } else if (message is List && message.length == 2) {
        failure = RemoteError('${message[0]}', '${message[1]}');
      } else {
        failure = StateError('Unexpected probe worker message: $message');
      }
    }
    throw StateError('Probe worker exit notification was lost.');
  } finally {
    await messages.cancel();
    events.close();
  }
}
