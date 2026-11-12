@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/worker_messages.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native transport snapshots documents and retains cancellation flag until reply',
    () async {
      final port = ReceivePort();
      final started = Completer<RerankRequest>();
      port.listen((message) {
        if (message is RerankRequest) started.complete(message);
        if (message is DisposeRequest) message.sendPort.send(null);
      });
      final backend = NativeLlamaBackend(initialSendPort: port.sendPort);
      addTearDown(() async {
        await backend.dispose();
        port.close();
      });
      final documents = ['doc'];
      final pending = backend.rerank(1, 'query', documents);
      documents.clear();
      final request = await started.future;
      expect(request.documents, ['doc']);
      final flag = Pointer<Int8>.fromAddress(request.cancelTokenAddress);
      expect(flag.value, 0);
      backend.cancelGeneration();
      expect(flag.value, 1);
      var settled = false;
      unawaited(pending.then((_) => settled = true));
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      request.sendPort.send(
        RerankResponse(
          BackendRerankingOutput(
            scores: [
              [2],
            ],
            classifierLabels: [null],
          ),
        ),
      );
      expect((await pending).scores, [
        [2],
      ]);
    },
  );
  test('probe and typed unsupported errors cross worker transport', () async {
    final port = ReceivePort();
    port.listen((message) {
      if (message is RerankingCapabilitiesRequest) {
        message.sendPort.send(
          RerankingCapabilitiesResponse(
            LlamaRerankingCapabilities(
              isSupported: false,
              unsupportedReason: 'not rank pooled',
            ),
          ),
        );
      }
      if (message is RerankRequest) {
        message.sendPort.send(
          ErrorResponse('not rank pooled', kind: WorkerErrorKind.unsupported),
        );
      }
      if (message is DisposeRequest) message.sendPort.send(null);
    });
    final backend = NativeLlamaBackend(initialSendPort: port.sendPort);
    addTearDown(() async {
      await backend.dispose();
      port.close();
    });
    expect((await backend.getRerankingCapabilities(1)).isSupported, isFalse);
    await expectLater(
      backend.rerank(1, 'q', ['d']),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });
}
