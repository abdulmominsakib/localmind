@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/isolate_shutdown_releases.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/ggml_graph_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/token_batch.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';

import '../../../support/synthetic_decision_head.dart';
import '../../../support/synthetic_embedding_gguf.dart';

// Runs the real llama.cpp runtime on the CPU in spawned isolates, which free
// what they leave loaded when they exit.
void main() {
  late _Paths paths;

  setUp(() {
    final directory = Directory.systemTemp.createTempSync('llama_shutdown_');
    addTearDown(() => directory.deleteSync(recursive: true));
    paths = _Paths(directory.path);
  });

  test('holds each object it creates with the runtime\'s tracked free and its '
      'stage, which the isolate exit frees', () async {
    final p = paths;
    final held = await Isolate.run(() {
      _load(LlamaCppService()..initializeBackend(), p);
      return _describeHeld();
    });

    expect(held, [
      'llama_dart_exit_free model',
      // Each context, then its sampler chain and token batch.
      'llama_dart_exit_free context',
      'llama_sampler_free session',
      'free session',
      'llama_dart_exit_free context',
      'llama_sampler_free session',
      'free session',
      'llama_dart_exit_free model',
      // The decision head: its encoder context, then its runtime.
      'llama_dart_exit_free context',
      'llama_dart_exit_free backend',
      'llama_dart_exit_free modelUser',
      'llama_dart_exit_free scheduler',
    ]);
  });

  test('holds each object with its upstream free function on a runtime '
      'without exit teardown', () async {
    final p = paths;
    final held = await Isolate.run(() {
      final service = LlamaCppService(objectCalls: LlamaCppObjectCalls.upstream)
        ..initializeBackend();
      _load(service, p);
      return _describeHeld();
    });

    expect(held, [
      'llama_model_free model',
      'llama_free context',
      'llama_sampler_free session',
      'free session',
      'llama_free context',
      'llama_sampler_free session',
      'free session',
      'llama_model_free model',
      'llama_free context',
      'ggml_backend_free backend',
      'ggml_backend_buffer_free modelUser',
      'ggml_backend_sched_free scheduler',
    ]);
  });

  test('computes the same decision and embedding through the tracked and the '
      'upstream calls', () async {
    final p = paths;
    Future<(List<double>, List<double>, List<double>)> run(bool upstream) =>
        Isolate.run(() {
          final service = LlamaCppService(
            objectCalls: upstream ? LlamaCppObjectCalls.upstream : null,
          )..initializeBackend();
          final loaded = _load(service, p);
          final decision = service.runDecision(loaded.head, [
            BackendDecisionSequence(
              tokens: Int32List.fromList([1, 5, 0, 6, 0, 2]),
              markers: Int32List.fromList([2, 4]),
              questionType: DecisionQuestionType.choice,
            ),
          ]).single;
          final embedding = service.embed(loaded.context, 'exit teardown');
          service.dispose();
          return (
            decision.logits.toList(),
            decision.actLogits.toList(),
            embedding,
          );
        });

    final tracked = await run(false);
    final upstream = await run(true);
    expect(tracked.$1, hasLength(2));
    expect(tracked.$3, isNotEmpty);
    expect(upstream.$1, tracked.$1);
    expect(upstream.$2, tracked.$2);
    expect(upstream.$3, tracked.$3);
  });

  test('releases each hold when its object is freed', () async {
    final p = paths;
    final counts = await Isolate.run(() {
      final releases = IsolateShutdownReleases.current;
      int held() => releases.debugHeldForTesting.length;
      final service = LlamaCppService()..initializeBackend();
      final loaded = _load(service, p);
      final counts = <int>[];
      service.freeDecisionHead(loaded.head);
      counts.add(held());
      service.freeContext(loaded.context);
      counts.add(held());
      service.freeModel(loaded.model);
      counts.add(held());
      service.freeModel(loaded.encoder);
      counts.add(held());
      return counts;
    });

    expect(counts, [8, 5, 1, 0]);
  });

  test('releases every hold when the service is disposed', () async {
    final p = paths;
    final held = await Isolate.run(() {
      final service = LlamaCppService()..initializeBackend();
      _load(service, p);
      service.dispose();
      return IsolateShutdownReleases.current.debugHeldForTesting.length;
    });

    expect(held, 0);
  });

  test('holds the sampler chain of a running generation until it '
      'ends', () async {
    final (:before, :during, :after) = await _samplerChainHolds(paths.model);

    expect(before, [
      'llama_dart_exit_free model',
      'llama_dart_exit_free context',
      'llama_sampler_free session',
      'free session',
    ]);
    expect(during, [...before, 'llama_sampler_free session']);
    expect(after, before);
  });

  test('sampler hold observation reports generation ending before its first '
      'token', () async {
    await expectLater(
      _samplerChainHolds(
        paths.model,
        params: const GenerationParams(
          maxTokens: 4,
          seed: 7,
          grammar: 'root ::= ""',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'readiness diagnostic',
          contains('Generation completed before its first token'),
        ),
      ),
    );
  });

  test('sampler hold observation propagates generation errors before its first '
      'token', () async {
    await expectLater(
      _samplerChainHolds(
        paths.model,
        params: const GenerationParams(maxTokens: 4, grammar: 'root ::= ('),
      ),
      throwsA(isA<LlamaInferenceException>()),
    );
  });

  test('releases the sampler chain of a generation whose sampler setup '
      'fails', () async {
    final model = paths.model;
    final (:before, :error, :after) = await Isolate.run(() async {
      final service = LlamaCppService()..initializeBackend();
      final context = service.createContext(
        service.loadModel(model, _params),
        _params,
      );
      final before = _describeHeld();
      final cancel = calloc<Int8>();
      Object? error;
      try {
        await service
            .generate(
              context,
              'a b',
              const GenerationParams(maxTokens: 1, grammar: 'root ::= ('),
              cancel.address,
            )
            .drain<void>();
      } on Object catch (e) {
        error = e;
      }
      calloc.free(cancel);
      final after = _describeHeld();
      service.dispose();
      return (before: before, error: '${error.runtimeType}', after: after);
    });

    expect(error, 'LlamaInferenceException');
    expect(after, before);
  });

  for (final generating in [false, true]) {
    test('frees what an isolate killed while '
        '${generating ? 'generating' : 'idle'} held at its exit', () async {
      final held = await _killAfterReadiness(
        paths.model,
        generating: generating,
      );

      expect(held, [
        'llama_dart_exit_free model',
        'llama_dart_exit_free context',
        'llama_sampler_free session',
        'free session',
        if (generating) 'llama_sampler_free session',
      ]);
      // A wrong free function or a double free at that exit ends the process.
      expect(await Isolate.run(() => 'alive'), 'alive');
    });
  }

  test('reports generation completing before its first token', () async {
    await expectLater(
      _killAfterReadiness(
        paths.model,
        params: const GenerationParams(
          maxTokens: 32,
          seed: 7,
          grammar: 'root ::= ""',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'readiness diagnostic',
          contains('completed before its first token (seed: 7)'),
        ),
      ),
    );
  });

  test('reports generation failing before its first token', () async {
    await expectLater(
      _killAfterReadiness(
        paths.model,
        params: const GenerationParams(
          maxTokens: 32,
          seed: 7,
          grammar: 'root ::= (',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'readiness diagnostic',
          allOf(
            contains('failed before its first token (seed: 7)'),
            contains('LlamaInferenceException'),
          ),
        ),
      ),
    );
  });
}

const _params = ModelParams(gpuLayers: 0, contextSize: 64);

// The grammar guarantees a visible token before EOG on every platform.
const _heldGenerationParams = GenerationParams(
  maxTokens: 32,
  temp: 0,
  seed: 0,
  grammar: 'root ::= "a"',
);

Future<({List<String> before, List<String> during, List<String> after})>
_samplerChainHolds(
  String model, {
  GenerationParams params = _heldGenerationParams,
}) => Isolate.run(() async {
  final service = LlamaCppService()..initializeBackend();
  final context = service.createContext(
    service.loadModel(model, _params),
    _params,
  );
  final before = _describeHeld();
  final cancel = calloc<Int8>();
  final tokens = StreamIterator(
    service.generate(context, 'a b', params, cancel.address),
  );
  try {
    if (!await tokens.moveNext()) {
      throw StateError('Generation completed before its first token.');
    }
    // The iterator pauses generation until its next moveNext call.
    final during = _describeHeld();
    while (await tokens.moveNext()) {}
    final after = _describeHeld();
    return (before: before, during: during, after: after);
  } finally {
    await tokens.cancel();
    calloc.free(cancel);
    service.dispose();
  }
});

Future<List<String>> _killAfterReadiness(
  String model, {
  bool generating = true,
  GenerationParams params = _heldGenerationParams,
}) async {
  final ready = ReceivePort();
  final exited = ReceivePort();
  Isolate? isolate;
  try {
    printOnFailure('Awaiting shutdown readiness (seed: ${params.seed}).');
    isolate = await Isolate.spawn(_runUntilKilled, (
      ready.sendPort,
      model,
      generating,
      params,
    ), onExit: exited.sendPort);
    final (held, error) = await ready.first as (List<String>?, String?);
    if (error != null) throw StateError(error);
    return held!;
  } finally {
    if (isolate != null) {
      printOnFailure(
        'Killing shutdown worker; awaiting onExit '
        '(seed: ${params.seed}).',
      );
      isolate.kill(priority: Isolate.immediate);
      await exited.first;
    }
    ready.close();
    exited.close();
  }
}

/// Pauses after the first token so its sampler is still held when killed.
Future<void> _runUntilKilled(
  (SendPort, String, bool, GenerationParams) message,
) async {
  final (ready, model, generating, params) = message;
  try {
    final service = LlamaCppService()..initializeBackend();
    final context = service.createContext(
      service.loadModel(model, _params),
      _params,
    );
    if (generating) {
      late final StreamSubscription<List<int>> subscription;
      subscription = service
          .generate(context, 'a b', params, calloc<Int8>().address)
          .listen(
            (_) {
              subscription.pause();
              ready.send((_describeHeld(), null));
            },
            onDone: () => ready.send((
              null,
              'Generation completed before its first token '
                  '(seed: ${params.seed}).',
            )),
            onError: (Object error) => ready.send((
              null,
              'Generation failed before its first token '
                  '(seed: ${params.seed}): ${error.runtimeType}: $error',
            )),
          );
    } else {
      ready.send((_describeHeld(), null));
    }
  } on Object catch (error) {
    ready.send((null, 'Shutdown worker setup failed: $error'));
  }
  await Completer<void>().future;
}

final class _Paths {
  _Paths(String directory)
    : model = '$directory/model.gguf',
      encoder = '$directory/encoder.gguf',
      head = '$directory/head.safetensors',
      config = '$directory/config.json' {
    writeSyntheticLlamaGguf(model);
    writeSyntheticModernBertGguf(encoder, decisionTokens: true);
    SyntheticDecisionHead(d: 16, layers: 1, seed: 1).write(head);
    File(config).writeAsStringSync('{"max_len": 64, "head_layers": 1}');
  }

  final String model;
  final String encoder;
  final String head;
  final String config;
}

({int model, int context, int encoder, int head}) _load(
  LlamaCppService service,
  _Paths paths,
) {
  final model = service.loadModel(paths.model, _params);
  final context = service.createContext(model, _params);
  service.createContext(model, _params);
  final encoder = service.loadModel(paths.encoder, _params);
  final head = service
      .loadDecisionHead(encoder, paths.head, paths.config)
      .handle;
  return (model: model, context: context, encoder: encoder, head: head);
}

List<String> _describeHeld() {
  final names = {
    ExitTeardownApi.tryResolve(
      isWindows: Platform.isWindows,
    )!.freeAddress.address: 'llama_dart_exit_free',
    Native.addressOf<NativeFunction<Void Function(Pointer<llama_model>)>>(
      llama_model_free,
    ).address: 'llama_model_free',
    Native.addressOf<NativeFunction<Void Function(Pointer<llama_context>)>>(
      llama_free,
    ).address: 'llama_free',
    ggmlFreeAddresses.backendFree.address: 'ggml_backend_free',
    ggmlFreeAddresses.bufferFree.address: 'ggml_backend_buffer_free',
    ggmlFreeAddresses.schedFree.address: 'ggml_backend_sched_free',
    Native.addressOf<NativeFunction<Void Function(Pointer<llama_sampler>)>>(
      llama_sampler_free,
    ).address: 'llama_sampler_free',
    TokenBatch.freeAddress.address: 'free',
  };
  return [
    for (final (:free, :stage)
        in IsolateShutdownReleases.current.debugHeldForTesting)
      '${names[free.address] ?? free.address} ${stage.name}',
  ];
}
