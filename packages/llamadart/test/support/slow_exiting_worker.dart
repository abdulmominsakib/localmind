import 'dart:ffi';
import 'dart:isolate';

import 'package:llamadart/src/backends/llama_cpp/worker.dart';

/// A worker that acknowledges disposal before a blocking POSIX C call.
void slowExitingWorkerEntry(SendPort initialSendPort) {
  final receivePort = ReceivePort();
  initialSendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    switch (message) {
      case WorkerHandshake():
        message.sendPort.send(DoneResponse());
      case ModelLoadRequest():
        message.sendPort.send(HandleResponse(42));
      case DisposeRequest():
        message.sendPort.send(null);
        // A kill cannot interrupt this synchronous native call. Disposal
        // must wait for onExit before reporting that native work has stopped.
        DynamicLibrary.process()
            .lookupFunction<Int32 Function(Uint32), int Function(int)>(
              'usleep',
            )(300000);
        receivePort.close();
        Isolate.exit();
    }
  });
}
