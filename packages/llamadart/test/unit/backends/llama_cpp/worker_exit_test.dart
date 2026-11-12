@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

const _deadline = Duration(seconds: 2);

void main() {
  late _WorkerHarness harness;
  late NativeLlamaBackend backend;
  late _FlagAllocator allocator;

  setUp(() {
    harness = _WorkerHarness();
    allocator = _FlagAllocator();
    final events = harness.events.sendPort;
    backend = NativeLlamaBackend(
      workerEntrypoint: _entrypoint(events),
      cancelFlagAllocator: allocator,
    );
  });

  tearDown(() async {
    try {
      await backend.dispose().timeout(_deadline);
    } finally {
      await harness.close();
    }
  });

  Future<void> start() async {
    expect(
      await backend
          .modelLoad('fixture', const ModelParams())
          .timeout(_deadline),
      42,
    );
  }

  test(
    'worker exit fails concurrent unary requests and rejects stale handles',
    () async {
      await start();
      final tokenizing = expectLater(
        backend.tokenize(42, 'hold').timeout(_deadline),
        throwsA(isA<LlamaStateException>()),
      );
      final probing = expectLater(
        backend.getContextSize(22).timeout(_deadline),
        throwsA(isA<LlamaStateException>()),
      );
      await harness.waitFor('tokenize');
      await harness.waitFor('context-size');
      await harness.kill();
      await Future.wait([tokenizing, probing]);
      expect(backend.isReady, isFalse);
      await expectLater(
        backend.generationCapabilities().timeout(_deadline),
        throwsA(isA<LlamaStateException>()),
      );
      await expectLater(
        backend.tokenize(42, 'later').timeout(_deadline),
        throwsA(isA<LlamaStateException>()),
      );
      await expectLater(
        backend.embed(22, 'later').timeout(_deadline),
        throwsA(isA<LlamaStateException>()),
      );
      await expectLater(
        backend.modelLoad('later', const ModelParams()).timeout(_deadline),
        throwsA(isA<LlamaStateException>()),
      );
      await backend.dispose().timeout(_deadline);
    },
  );

  test(
    'worker exit fails generation and frees its flag exactly once',
    () async {
      await start();
      final completed = expectLater(
        backend
            .generate(22, 'hold', const GenerationParams())
            .timeout(_deadline),
        emitsInOrder([
          <int>[65],
          emitsError(isA<LlamaStateException>()),
          emitsDone,
        ]),
      );
      await harness.waitFor('generate');
      expect(allocator.frees, 0);
      await harness.kill();
      await completed;
      expect(allocator.frees, 1);
      await expectLater(
        backend.generate(22, 'later', const GenerationParams()),
        emitsInOrder([emitsError(isA<LlamaStateException>()), emitsDone]),
      );
      await backend.dispose().timeout(_deadline);
      expect(allocator.frees, 1);
    },
  );

  test(
    'cancelled generation and queued replacement settle after worker exit',
    () async {
      await start();
      final firstErrors = <Object>[];
      final first = backend
          .generate(22, 'hold', const GenerationParams())
          .listen((_) {}, onError: firstErrors.add);
      await harness.waitFor('generate');
      backend.cancelGeneration();
      final queued = expectLater(
        backend
            .generate(22, 'queued', const GenerationParams())
            .timeout(_deadline),
        emitsInOrder([emitsError(isA<LlamaStateException>()), emitsDone]),
      );
      expect(allocator.allocations, 1);
      await harness.kill();
      await queued;
      await first.cancel();
      expect(firstErrors, <Matcher>[isA<LlamaStateException>()]);
      expect(allocator.frees, 1);
      expect(allocator.allocations, 1);
    },
  );

  test(
    'worker exit fails synthesis after progress and cancel without leaking flag',
    () async {
      await start();
      final progress = Completer<void>();
      final synthesis = expectLater(
        backend
            .synthesizeTextToSpeech(
              22,
              33,
              const BackendTextToSpeechRequest(text: 'hold'),
              onProgress: (_) => progress.complete(),
            )
            .timeout(_deadline),
        throwsA(isA<LlamaStateException>()),
      );
      await progress.future.timeout(_deadline);
      backend.cancelTextToSpeech();
      expect(allocator.frees, 0);
      await harness.kill();
      await synthesis;
      expect(allocator.frees, 1);
      await backend.dispose().timeout(_deadline);
      expect(allocator.frees, 1);
    },
  );

  test(
    'worker exit while disposal awaits acknowledgement settles disposal',
    () async {
      await backend.modelLoad('hold-dispose', const ModelParams());
      final disposing = backend.dispose().timeout(_deadline);
      await harness.waitFor('dispose');
      await harness.kill();
      await disposing;
      expect(backend.isReady, isFalse);
      await backend.dispose().timeout(_deadline);
    },
  );

  test('uncaught Dart worker error fails the pending request', () async {
    await start();
    await expectLater(
      backend.tokenize(42, 'crash').timeout(_deadline),
      throwsA(isA<LlamaStateException>()),
    );
    expect(backend.isReady, isFalse);
    await backend.dispose().timeout(_deadline);
  });

  test('healthy worker replies still succeed', () async {
    await start();
    expect(await backend.tokenize(42, 'healthy').timeout(_deadline), <int>[
      1,
      2,
    ]);
    expect(backend.isReady, isTrue);
  });
}

LlamaWorkerEntrypoint _entrypoint(SendPort events) =>
    (initial) => _worker(initial, events);

void _worker(SendPort initial, SendPort events) {
  events.send(Isolate.current);
  final requests = ReceivePort();
  var holdDispose = false;
  initial.send(requests.sendPort);
  requests.listen((Object? request) {
    switch (request) {
      case WorkerHandshake():
        request.sendPort.send(DoneResponse());
      case ModelLoadRequest():
        holdDispose = request.modelPath == 'hold-dispose';
        request.sendPort.send(HandleResponse(42));
      case TokenizeRequest():
        if (request.text == 'crash') {
          throw StateError('synthetic Dart worker error');
        }
        if (request.text == 'healthy') {
          request.sendPort.send(TokenizeResponse(<int>[1, 2]));
        } else {
          events.send('tokenize');
        }
      case GetContextSizeRequest():
        events.send('context-size');
      case GenerateRequest():
        request.sendPort.send(TokenResponse(<int>[65]));
        events.send('generate');
      case TextToSpeechSynthesizeRequest():
        request.sendPort.send(
          TextToSpeechProgressResponse(
            const BackendTextToSpeechProgress(
              phase: BackendTextToSpeechPhase.generating,
              promptTokensRemaining: 0,
              framesGenerated: 1,
              truncated: false,
            ),
          ),
        );
      case DisposeRequest():
        events.send('dispose');
        // Hold the acknowledgement so disposal is tested across actual exit.
        if (!holdDispose) {
          request.sendPort.send(null);
          requests.close();
          Isolate.exit();
        }
    }
  });
}

class _WorkerHarness {
  final ReceivePort events = ReceivePort();
  final Map<String, Completer<void>> _received = {};
  final Completer<Isolate> _isolate = Completer<Isolate>();

  _WorkerHarness() {
    events.listen((Object? event) {
      if (event is Isolate) _isolate.complete(event);
      if (event is String) {
        _received.putIfAbsent(event, Completer<void>.new).complete();
      }
    });
  }

  Future<void> waitFor(String event) => _received
      .putIfAbsent(event, Completer<void>.new)
      .future
      .timeout(_deadline);

  Future<void> kill() async {
    final worker = await _isolate.future.timeout(_deadline);
    final exit = ReceivePort();
    try {
      worker.addOnExitListener(exit.sendPort);
      worker.kill(priority: Isolate.immediate);
      await exit.first.timeout(_deadline);
    } finally {
      exit.close();
    }
  }

  Future<void> close() async {
    if (_isolate.isCompleted) {
      (await _isolate.future).kill(priority: Isolate.immediate);
    }
    events.close();
  }
}

class _FlagAllocator implements Allocator {
  int allocations = 0;
  int frees = 0;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    allocations++;
    return malloc.allocate<T>(byteCount, alignment: alignment);
  }

  @override
  void free(Pointer<NativeType> pointer) {
    frees++;
    malloc.free(pointer);
  }
}
