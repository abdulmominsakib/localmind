@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';

import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

import '../../../support/synthetic_decision_head.dart';
import '../../../support/synthetic_embedding_gguf.dart';

Object? _private(Object receiver, String name) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  return reflect(
    receiver,
  ).getField(MirrorSystem.getSymbol(name, owner)).reflectee;
}

// Reads the counts back from llama.cpp, so these cover what the runtime
// received and not only what the service computed.
void main() {
  late Directory dir;
  late LlamaCppService service;

  void start(int cores) {
    service = LlamaCppService(
      objectCalls: LlamaCppObjectCalls.upstream,
      availableCores: cores,
    )..initializeBackend();
  }

  List<int> contextThreads(int handle) {
    final contexts = _private(service, '_contexts') as Map;
    final pointer = _private(contexts[handle] as Object, 'pointer');
    final context = pointer as Pointer<llama_context>;
    return [llama_n_threads(context), llama_n_threads_batch(context)];
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_default_threads_');
    writeSyntheticLlamaGguf('${dir.path}/model.gguf');
  });

  tearDown(() {
    service.dispose();
    dir.deleteSync(recursive: true);
  });

  const params = ModelParams(gpuLayers: 0, contextSize: 64);

  for (final (cores, threads) in const [
    (1, 1),
    (2, 2),
    (3, 3),
    (4, 4),
    (16, 4),
  ]) {
    test('a context on $cores cores gets $threads threads by default', () {
      start(cores);
      final model = service.loadModel('${dir.path}/model.gguf', params);

      expect(contextThreads(service.createContext(model, params)), [
        threads,
        threads,
      ]);
    });

    test('a projector on $cores cores gets $threads threads', () {
      start(cores);
      final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
      final projector =
          reflect(service).invoke(
                MirrorSystem.getSymbol('_mtmdContextParamsFor', owner),
                [-1],
              ).reflectee
              as mtmd_context_params;

      expect(projector.n_threads, threads);
    });

    test('a decision encoder on $cores cores gets $threads threads', () {
      start(cores);
      writeSyntheticModernBertGguf(
        '${dir.path}/encoder.gguf',
        decisionTokens: true,
      );
      SyntheticDecisionHead(
        d: 16,
        layers: 1,
        seed: 1,
      ).write('${dir.path}/head.safetensors');
      File(
        '${dir.path}/config.json',
      ).writeAsStringSync('{"max_len": 64, "head_layers": 1}');
      final encoder = service.loadModel('${dir.path}/encoder.gguf', params);

      final head = service.loadDecisionHead(
        encoder,
        '${dir.path}/head.safetensors',
        '${dir.path}/config.json',
      );
      addTearDown(() => service.freeDecisionHead(head.handle));

      final heads = _private(service, '_decisionHeads') as Map;
      final context =
          _private(heads[head.handle] as Object, 'context')
              as Pointer<llama_context>;
      expect(llama_n_threads(context), threads);
      expect(llama_n_threads_batch(context), threads);
    });
  }

  test('reads the core count from the host by default', () {
    service = LlamaCppService(objectCalls: LlamaCppObjectCalls.upstream);

    expect(_private(service, '_availableCores'), Platform.numberOfProcessors);
  });

  test('a reranking context takes the same default', () {
    start(2);
    final model = service.loadModel('${dir.path}/model.gguf', params);

    expect(
      contextThreads(service.createContext(model, params, reranking: true)),
      [2, 2],
    );
  });

  test('an explicit count reaches llama.cpp unchanged on any host', () {
    for (final cores in const [2, 16]) {
      start(cores);
      final model = service.loadModel('${dir.path}/model.gguf', params);
      final context = service.createContext(
        model,
        params.copyWith(numberOfThreads: 7, numberOfThreadsBatch: 9),
      );

      expect(contextThreads(context), [7, 9]);
      service.dispose();
    }
    start(1);
  });
}
