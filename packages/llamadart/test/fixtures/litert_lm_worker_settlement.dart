// Retained native families deliberately keep workers alive until process exit.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/worker.dart';

int count(DynamicLibrary library, String name) =>
    library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
void call(DynamicLibrary library, String name, int value) =>
    library.lookupFunction<Void Function(Int), void Function(int)>(
      'fixture_$name',
    )(value);

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  check(condition(), 'condition did not become true');
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Object?> request(
  SendPort worker,
  LiteRtLmWorkerRequest Function(SendPort) create,
) async {
  final port = ReceivePort();
  try {
    worker.send(create(port.sendPort));
    return await port
        .firstWhere((response) => response is! LiteRtLmNativeTeardownStarted)
        .timeout(const Duration(seconds: 2));
  } finally {
    port.close();
  }
}

class NativeService extends LiteRtLmService {
  NativeService(String path)
    : runtime = LiteRtLmV1Runtime(DynamicLibrary.open(path)) {
    runtime.load('/fixture/model.litertlm', cacheDir: '/fixture/cache');
  }

  final LiteRtLmV1Runtime runtime;
  LiteRtLmV1Conversation? conversation;
  LiteRtLmV1Turn? turn;
  bool failDispose = false;

  @override
  LiteRtLmNativeSettlement get nativeSettlement =>
      super.nativeSettlement == LiteRtLmNativeSettlement.quarantined
      ? LiteRtLmNativeSettlement.quarantined
      : runtime.nativeSettlement;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    conversation?.close();
    conversation = runtime.openConversation();
    final active = turn = conversation!.sendText(prompt);
    Object? failure;
    StackTrace? trace;
    final done = active.done.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
      },
    );
    await for (final chunk in active.chunks) {
      yield utf8.encode(chunk);
    }
    await done;
    if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  }

  @override
  void cancelGeneration() => turn?.cancel();

  @override
  void dispose() {
    if (failDispose) throw StateError('injected native cleanup failure');
    conversation?.close();
    runtime.dispose();
  }
}

void nativeEntry(SendPort port) {
  runLiteRtLmWorkerForTesting(
    port,
    NativeService(Platform.environment['LITERT_SETTLEMENT_LIBRARY']!),
  );
}

Future<void> backendQuarantine(DynamicLibrary library) async {
  final backend = LiteRtLmBackend(workerEntryPoint: nativeEntry);
  final firstChunk = Completer<void>();
  final subscription = backend
      .generate(1, 'first', const GenerationParams())
      .listen((_) {
        if (!firstChunk.isCompleted) firstChunk.complete();
      });
  await until(() => count(library, 'sends') == 1);
  call(library, 'emit', 0);
  await firstChunk.future;
  await subscription.cancel();
  final queued = backend
      .generate(1, 'queued', const GenerationParams())
      .toList();
  final queuedFailed = queued.then<void>(
    (_) => throw StateError('quarantined queued generation started'),
    onError: (Object error) {
      check(error is LlamaStateException, 'wrong queued failure');
    },
  );
  call(library, 'fail', 19);
  call(library, 'emit', 2);
  await queuedFailed.timeout(const Duration(seconds: 2));
  check(count(library, 'sends') == 1, 'queued generation dispatched');
  for (final operation in <Future<void> Function()>[
    backend.dispose,
    () => backend.contextFree(1),
    () => backend.modelFree(1),
  ]) {
    var refused = false;
    try {
      await operation();
    } on LlamaStateException {
      refused = true;
    }
    check(refused, 'quarantined backend accepted native operation');
  }
  // Killing the worker would invalidate its listener. A genuinely late native
  // callback must still find that listener and release both copied fields.
  call(library, 'emit', 4);
  await until(() => count(library, 'copies') == 0);
  check(
    count(library, 'live') == 2 && count(library, 'proxies') == 1,
    'quarantined native family was deleted',
  );
}

Future<void> main(List<String> args) async {
  final mode = args[0];
  final library = DynamicLibrary.open(args[1]);
  if (mode == 'backend-quarantine') {
    await backendQuarantine(library);
  } else {
    final service = NativeService(args[1]);
    final handshake = ReceivePort();
    runLiteRtLmWorkerForTesting(
      handshake.sendPort,
      service,
      exitOnDispose: false,
      disposeTimeout: const Duration(milliseconds: 25),
    );
    final worker = await handshake.first as SendPort;
    handshake.close();
    final generation = request(
      worker,
      (port) =>
          LiteRtLmGenerateRequest(1, 'first', const GenerationParams(), port),
    );
    await until(() => count(library, 'sends') == 1);
    if (mode == 'dispose-cancel-failure') {
      call(library, 'fail', 18);
      final disposal = request(worker, LiteRtLmDisposeRequest.new);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      call(library, 'emit', 3);
      check(
        await generation is LiteRtLmDoneResponse,
        'cancelled generation failed',
      );
      check(
        await disposal is LiteRtLmDoneResponse,
        'drained cleanup was not acknowledged',
      );
      check(
        count(library, 'live') == 0 && count(library, 'proxies') == 0,
        'drained cleanup left native handles',
      );
      stdout.writeln('case $mode passed');
      return;
    } else if (mode == 'pending') {
      final response = await request(worker, LiteRtLmDisposeRequest.new);
      check(
        response is LiteRtLmErrorResponse &&
            response.nativeSettlement == LiteRtLmNativeSettlement.quarantined,
        'pending dispose reported success',
      );
    } else {
      if (mode == 'cancel-failure') {
        call(library, 'fail', 18);
        final response = await request(
          worker,
          LiteRtLmCancelGenerationRequest.new,
        );
        check(
          response is LiteRtLmErrorResponse &&
              response.nativeSettlement == LiteRtLmNativeSettlement.pending,
          'cancel failure lost native lifetime',
        );
        check(
          count(library, 'live') == 2 && count(library, 'proxies') == 1,
          'cancel failure prematurely deleted resources',
        );
        call(library, 'emit', 3);
      } else {
        if (mode == 'quarantine') call(library, 'fail', 19);
        if (mode == 'safe-error') call(library, 'emit', 1);
        call(library, 'emit', 2);
      }
      final result = await generation;
      if (mode == 'quarantine') {
        check(
          result is LiteRtLmErrorResponse &&
              result.nativeSettlement == LiteRtLmNativeSettlement.quarantined,
          'failed drain lost quarantine',
        );
      } else {
        check(
          mode == 'safe-error'
              ? result is LiteRtLmErrorResponse &&
                    result.nativeSettlement == LiteRtLmNativeSettlement.settled
              : result is LiteRtLmDoneResponse,
          'safe request did not settle correctly',
        );
        if (mode == 'safe-error') {
          check(
            count(library, 'live') == 1 && count(library, 'proxies') == 0,
            'safe failed child leaked',
          );
          final next = request(
            worker,
            (port) => LiteRtLmGenerateRequest(
              1,
              'next',
              const GenerationParams(),
              port,
            ),
          );
          await until(() => count(library, 'sends') == 2);
          call(library, 'emit', 2);
          check(await next is LiteRtLmDoneResponse, 'safe error blocked reuse');
        }
        service.failDispose = mode == 'cleanup-failure';
        final response = await request(worker, LiteRtLmDisposeRequest.new);
        if (mode == 'cleanup-failure') {
          check(
            response is LiteRtLmErrorResponse &&
                response.nativeSettlement ==
                    LiteRtLmNativeSettlement.quarantined,
            'cleanup failure reported success',
          );
        } else {
          check(response is LiteRtLmDoneResponse, 'safe disposal failed');
          check(
            count(library, 'live') == 0 && count(library, 'proxies') == 0,
            'safe disposal left native resources',
          );
          stdout.writeln('case $mode passed');
          return;
        }
      }
    }
    final rejected = await request(
      worker,
      (port) => LiteRtLmMetadataRequest(1, port),
    );
    check(
      rejected is LiteRtLmErrorResponse &&
          rejected.nativeSettlement == LiteRtLmNativeSettlement.quarantined,
      'quarantined worker accepted request',
    );
    if (mode == 'quarantine' || mode == 'pending') {
      check(
        count(library, 'live') == 2 && count(library, 'proxies') == 1,
        'unsettled native resources freed',
      );
      call(library, 'emit', 4);
      await until(() => count(library, 'copies') == 0);
    }
  }
  stdout.writeln('case $mode passed');
  exit(
    0,
  ); // Process exit is the only permitted teardown of quarantined families.
}
