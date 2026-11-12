// Subprocess fixture: success requires natural VM exit, without exit().
import 'dart:async';
import 'dart:isolate';

import 'package:llamadart/src/backends/litert_lm/litert_lm_backend.dart';
import 'package:llamadart/src/backends/litert_lm/worker_messages.dart';
import 'package:llamadart/src/core/exceptions.dart';

Future<void> main() async {
  print('started');
  final port = ReceivePort();
  final received = Completer<void>();
  port.listen((message) {
    if (message is LiteRtLmTokenizeRequest) {
      received.complete();
    } else if (message is LiteRtLmWorkerRequest) {
      message.sendPort.send(LiteRtLmDoneResponse());
    }
  });
  final backend = LiteRtLmBackend(initialSendPort: port.sendPort);
  final pending = backend
      .tokenize(1, 'hello')
      .then<void>(
        (_) => throw StateError('Abandoned request unexpectedly succeeded'),
        onError: (Object error) {
          if (error is! LlamaStateException) throw error;
        },
      );
  await received.future;
  print('request received');
  try {
    await backend.dispose();
    throw StateError('Unverified cleanup unexpectedly succeeded');
  } on LlamaStateException {
    // The request port must close even when cleanup cannot be verified.
  } finally {
    port.close();
  }
  print('disposed');
  await pending;
  print('done; the VM must now exit on its own');
}
