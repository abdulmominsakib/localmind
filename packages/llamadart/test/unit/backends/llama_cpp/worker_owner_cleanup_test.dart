@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/embedding.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';

const _deadline = Duration(seconds: 5);
typedef _Failure = ({Object error, StackTrace stack});

void main() {
  for (final (name, failure) in [
    (
      'cleanup isolate',
      IsolateSpawnException('fixture cleanup isolate failure'),
    ),
    ('owner API', LlamaStateException('fixture owner API failure')),
  ]) {
    for (final startupFailure in [true, false]) {
      test(
        '$name failure after startup failure $startupFailure is retained without an unhandled future',
        () async {
          final releases = <Future<void> Function()>[];
          final cleanupStarted = Completer<void>();
          var cleanupCalls = 0;
          final stack = StackTrace.fromString('fixture-owner-cleanup-stack');
          final ports = <RawReceivePort>[];
          late final NativeLlamaBackend backend;
          backend = NativeLlamaBackend(
            workerEntrypoint: _entrypoint(startupFailure),
            workerExitCleanup: (release) {
              releases.add(release);
              ports.addAll(_capturePorts(backend));
              cleanupCalls++;
              if (!cleanupStarted.isCompleted) cleanupStarted.complete();
              return Future<void>.error(failure, stack);
            },
          );
          _Failure? startup;
          _Failure? first;
          _Failure? second;
          _Failure? reload;
          final uncaught = await _observeUncaught(() async {
            try {
              startup = await _capture(
                backend
                    .modelLoad('fixture', const ModelParams())
                    .timeout(_deadline),
              );
              if (startupFailure) {
                await cleanupStarted.future.timeout(_deadline);
                await Future<void>.delayed(Duration.zero);
              }
              first = await _capture(backend.dispose().timeout(_deadline));
              second = await _capture(backend.dispose().timeout(_deadline));
              reload = await _capture(
                backend
                    .modelLoad('later', const ModelParams())
                    .timeout(_deadline),
              );
              await Future<void>.delayed(Duration.zero);
            } finally {
              // Injection intentionally bypasses the real native release. Run it
              // after onExit to reclaim any empty bootstrap token the test owns.
              for (final release in releases) {
                await release();
              }
            }
          });
          expect(uncaught, isEmpty);
          if (startupFailure) {
            expect(startup?.error, isA<LlamaBackendInitializationException>());
          } else {
            expect(startup, isNull);
          }
          expect(first?.error, isA<LlamaStateException>());
          final retained = first!.error as LlamaStateException;
          if (failure is LlamaStateException) {
            expect(retained, same(failure));
          } else {
            expect(retained.details, same(failure));
          }
          expect(second?.error, same(retained));
          expect(reload?.error, same(retained));
          expect(
            second?.stack.toString(),
            contains('fixture-owner-cleanup-stack'),
          );
          expect(
            cleanupCalls,
            1,
            reason: 'A failed cleanup must prevent worker restart.',
          );
          expect(backend.isReady, isFalse);
          _expectPortsClosed(backend, ports);
        },
      );
    }
  }

  for (final operation in ['rerank', 'content embedding']) {
    test('$operation frees its shared flag when owner cleanup fails', () async {
      final allocator = _FlagAllocator();
      final releases = <Future<void> Function()>[];
      final cleanupStarted = Completer<void>();
      late Completer<void> cleanup;
      final failure = LlamaStateException(
        'fixture delayed owner cleanup failure',
      );
      final ports = <RawReceivePort>[];
      late final NativeLlamaBackend backend;
      backend = NativeLlamaBackend(
        workerEntrypoint: _entrypoint(false),
        cancelFlagAllocator: allocator,
        workerExitCleanup: (release) {
          releases.add(release);
          ports.addAll(_capturePorts(backend));
          // RawReceivePort invokes its handler in the root zone. Create the
          // failing future there too, so the fixture does not introduce a
          // cross-error-zone future that can never deliver its error.
          cleanup = Completer<void>();
          cleanupStarted.complete();
          return cleanup.future;
        },
      );
      _Failure? requestError;
      _Failure? disposalError;
      _Failure? retryError;
      final uncaught = await _observeUncaught(() async {
        try {
          await backend.modelLoad('fixture', const ModelParams());
          final request = operation == 'rerank'
              ? _capture(backend.rerank(22, 'query', ['document']))
              : _capture(
                  backend.embedContentBatch(22, [
                    LlamaEmbeddingInput([const LlamaTextContent('text')]),
                  ]),
                );
          await cleanupStarted.future.timeout(_deadline);
          // onExit has failed the RPC; allow its finally block to start
          // awaiting the still-pending native cleanup before failing it.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          cleanup.completeError(
            failure,
            StackTrace.fromString('fixture-owner-cleanup-stack'),
          );
          requestError = await request.timeout(_deadline);
          disposalError = await _capture(backend.dispose().timeout(_deadline));
          retryError = operation == 'rerank'
              ? await _capture(backend.rerank(22, 'later', ['document']))
              : await _capture(
                  backend.embedContentBatch(22, [
                    LlamaEmbeddingInput([const LlamaTextContent('later')]),
                  ]),
                );
        } finally {
          for (final release in releases) {
            await release();
          }
        }
      });
      final frees = allocator.frees;
      allocator.releaseRemaining();
      expect(uncaught, isEmpty);
      expect(allocator.allocations, 1);
      expect(
        frees,
        1,
        reason:
            'Actual worker exit makes the shared flag safe to free even if owner cleanup failed.',
      );
      expect(requestError?.error, same(failure));
      expect(disposalError?.error, same(failure));
      expect(retryError?.error, same(failure));
      _expectPortsClosed(backend, ports);
    });
  }
}

Future<_Failure?> _capture<T>(Future<T> operation) async {
  try {
    await operation;
  } catch (error, stack) {
    return (error: error, stack: stack);
  }
  return null;
}

Future<List<Object>> _observeUncaught(Future<void> Function() exercise) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(
    () {
      unawaited(
        Future<void>.sync(exercise).then(
          (_) {
            done.complete();
          },
          onError: (Object error, StackTrace stack) {
            errors.add(error);
            done.complete();
          },
        ),
      );
    },
    (error, _) {
      errors.add(error);
    },
  );
  await done.future.timeout(const Duration(seconds: 30));
  await Future<void>.delayed(Duration.zero);
  return errors;
}

LlamaWorkerEntrypoint _entrypoint(bool startupFailure) =>
    (initial) => _worker(initial, startupFailure);
void _worker(SendPort initial, bool startupFailure) {
  final port = ReceivePort();
  initial.send(port.sendPort);
  port.listen((request) {
    switch (request) {
      case WorkerHandshake():
        if (startupFailure) {
          port.close();
          Isolate.exit();
        }
        request.sendPort.send(DoneResponse());
      case ModelLoadRequest():
        request.sendPort.send(HandleResponse(42));
      case RerankRequest() || EmbedContentBatchRequest():
        port.close();
        Isolate.exit();
      case DisposeRequest():
        request.sendPort.send(null);
        port.close();
        Isolate.exit();
    }
  });
}

final class _FlagAllocator implements Allocator {
  int allocations = 0;
  int frees = 0;
  final Set<int> _live = {};
  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final pointer = malloc.allocate<T>(byteCount, alignment: alignment);
    allocations++;
    _live.add(pointer.address);
    return pointer;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    if (!_live.remove(pointer.address)) throw StateError('Duplicate flag free');
    frees++;
    malloc.free(pointer);
  }

  void releaseRemaining() {
    for (final address in _live) {
      malloc.free(Pointer<Void>.fromAddress(address));
    }
    _live.clear();
  }
}

List<RawReceivePort> _capturePorts(NativeLlamaBackend backend) {
  final owner = reflectClass(NativeLlamaBackend).owner as LibraryMirror;
  final ports = <RawReceivePort>[];
  for (final name in ['_workerLogPort', '_workerLifecyclePort']) {
    final port = reflect(
      backend,
    ).getField(MirrorSystem.getSymbol(name, owner)).reflectee;
    if (port is RawReceivePort) {
      // Closing a RawReceivePort clears this property. Setting it first makes
      // a skipped close observable; finally below still cleans failing controls.
      port.keepIsolateAlive = true;
      ports.add(port);
    }
  }
  return ports;
}

void _expectPortsClosed(
  NativeLlamaBackend backend,
  List<RawReceivePort> ports,
) {
  final owner = reflectClass(NativeLlamaBackend).owner as LibraryMirror;
  Object? field(String name) =>
      reflect(backend).getField(MirrorSystem.getSymbol(name, owner)).reflectee;
  try {
    expect(field('_responsePorts'), isEmpty);
    expect(field('_workerExits'), isEmpty);
    expect(field('_workerLogPort'), isNull);
    expect(field('_workerLifecyclePort'), isNull);
    expect(ports, isNotEmpty);
    for (final port in ports) {
      expect(
        port.keepIsolateAlive,
        isFalse,
        reason: 'Actual raw ports must close on cleanup failure.',
      );
    }
  } finally {
    for (final port in ports) {
      port.close();
    }
  }
}
