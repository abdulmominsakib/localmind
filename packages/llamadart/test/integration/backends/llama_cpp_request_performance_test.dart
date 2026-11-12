@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';

import 'package:ffi/ffi.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:test/test.dart';

import '../../support/synthetic_embedding_gguf.dart';

const _modelParams = ModelParams(
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
  gpuLayers: 0,
  contextSize: 64,
);
const _generation = GenerationParams(maxTokens: 3, temp: 0, topK: 1, seed: 1);

void main() {
  late Directory directory;
  late String path;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('request_perf_');
    path = '${directory.path}/model.gguf';
    writeSyntheticLlamaGguf(path);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  for (final operation in ['embed', 'embedBatch', 'content', 'score']) {
    test(
      '$operation replaces generation counters after early cancellation',
      () async {
        final engine = LlamaEngine(NativeLlamaBackend());
        addTearDown(engine.dispose);
        await engine.loadModel(path, modelParams: _modelParams);
        await engine.generate('ab', params: _generation).drain<void>();
        expect(
          (await engine.getPerformanceContext())!.evalTokens,
          greaterThan(0),
        );
        final cancelled = engine.generate('cancelled').drain<void>();
        engine.cancelGeneration();
        await cancelled;
        expect(await engine.getPerformanceContext(), isNull);
        switch (operation) {
          case 'embed':
            expect(await engine.embed('abc'), isNotEmpty);
          case 'embedBatch':
            expect(await engine.embedBatch(['abc', 'abcd']), hasLength(2));
          case 'content':
            expect(
              await engine.embedContentBatch([
                LlamaEmbeddingInput([LlamaTextContent('abc')]),
                LlamaEmbeddingInput([LlamaTextContent('abcd')]),
              ]),
              hasLength(2),
            );
          case 'score':
            await engine.scoreNextToken(
              'abc',
              candidates: [4],
              topK: 1,
              reusePromptPrefix: false,
            );
        }
        final perf = (await engine.getPerformanceContext())!;
        // llama.cpp clamps native n_eval to at least one, even without decoding.
        expect(perf.evalTokens, 1);
        expect(perf.evalMs, 0);
        expect(perf.sampleCount, 0);
        expect(perf.sampleMs, 0);
        expect(perf.decodeMs, isNull);
        final prompts = operation == 'embedBatch' || operation == 'content'
            ? ['abc', 'abcd']
            : ['abc'];
        var expected = 0;
        for (final prompt in prompts) {
          expected += (await engine.tokenize(prompt, addSpecial: true)).length;
        }
        expect(perf.promptEvalTokens, expected);
        expect(perf.promptEvalMs, greaterThanOrEqualTo(0));
        await engine.generate('xy', params: _generation).drain<void>();
        expect(
          (await engine.getPerformanceContext())!.evalTokens,
          greaterThan(0),
        );
      },
    );
  }

  test(
    'pooled batch counters include grouped and oversized fallback inputs',
    () async {
      writeSyntheticLlamaGguf(path, poolingType: 3);
      final engine = LlamaEngine(NativeLlamaBackend());
      addTearDown(engine.dispose);
      await engine.loadModel(
        path,
        modelParams: const ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          gpuLayers: 0,
          contextSize: 128,
          batchSize: 16,
          microBatchSize: 16,
          maxParallelSequences: 2,
        ),
      );
      await engine.generate('ab', params: _generation).drain<void>();
      final texts = ['abc', 'abcd', 'ab ' * 8, 'abc'];
      expect(await engine.embedBatch(texts), hasLength(texts.length));
      var expected = 0;
      for (final text in texts) {
        expected += (await engine.tokenize(text, addSpecial: true)).length;
      }
      final perf = (await engine.getPerformanceContext())!;
      expect(perf.promptEvalTokens, expected);
      expect(perf.evalTokens, 1);
      expect(perf.evalMs, 0);
      expect(perf.sampleCount, 0);
      expect(perf.decodeMs, isNull);
    },
  );

  test(
    'content cancellation after preflight leaves diagnostics unavailable',
    () async {
      final flag = calloc<Int8>();
      addTearDown(() => calloc.free(flag));
      var cancelAtSync = false;
      final service = LlamaCppService(
        objectCalls: LlamaCppObjectCalls.untracked(
          synchronize: (context) {
            llama_synchronize(context);
            if (cancelAtSync) flag.value = 1;
          },
        ),
      )..initializeBackend();
      addTearDown(service.dispose);
      final model = service.loadModel(path, _modelParams);
      final context = service.createContext(model, _modelParams);
      await service
          .generate(context, 'ab', _generation, flag.address)
          .drain<void>();
      cancelAtSync = true;
      expect(
        () => service.embedContentBatch(context, [
          LlamaEmbeddingInput([const LlamaTextContent('abc')]),
        ], cancelToken: flag),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(service.getPerformanceContext(context), isNull);
    },
  );

  test('embedding resets retained native sampler diagnostics', () async {
    final service = LlamaCppService()..initializeBackend();
    addTearDown(service.dispose);
    final model = service.loadModel(path, _modelParams);
    final context = service.createContext(model, _modelParams);
    final library = reflectClass(LlamaCppService).owner as LibraryMirror;
    final samplers =
        reflect(
              service,
            ).getField(MirrorSystem.getSymbol('_samplers', library)).reflectee
            as Map;
    final sampler = samplers[context] as Pointer<llama_sampler>;
    llama_sampler_accept(sampler, 4);
    llama_sampler_accept(sampler, 5);
    expect(llama_perf_sampler(sampler).n_sample, 2);
    service.embed(context, 'abc');
    expect(service.getPerformanceContext(context)!.sampleCount, 0);
  });

  test('TTS native setup starts with fresh counters', () async {
    final service = LlamaCppService()..initializeBackend();
    addTearDown(service.dispose);
    final model = service.loadModel(path, _modelParams);
    final context = service.createContext(model, _modelParams);
    final flag = calloc<Int8>();
    addTearDown(() => calloc.free(flag));
    await service
        .generate(context, 'ab', _generation, flag.address)
        .drain<void>();
    final library = reflectClass(LlamaCppService).owner as LibraryMirror;
    Symbol symbol(String name) => MirrorSystem.getSymbol(name, library);
    final mirror = reflect(service);
    final projectors =
        mirror.getField(symbol('_mtmdContexts')).reflectee as Map;
    final modelProjectors =
        mirror.getField(symbol('_modelToMtmd')).reflectee as Map;
    // No native projector call is made: the injected init stops at that boundary.
    projectors[999] = Pointer<mtmd_context>.fromAddress(1);
    modelProjectors[model] = 999;
    addTearDown(() {
      projectors.clear();
      modelProjectors.clear();
    });
    final original = mirror.invoke(symbol('_resolveTtsApi'), []);
    final fields = <Symbol, dynamic>{
      for (final field
          in original.type.declarations.values.whereType<VariableMirror>())
        if (!field.isStatic)
          field.simpleName: original.getField(field.simpleName).reflectee,
    };
    fields[#init] =
        (
          Pointer<llama_context> ctx,
          Pointer<mtmd_context> projector,
          Pointer<Int32> status,
        ) {
          final perf = service.getPerformanceContext(context)!;
          expect(perf.evalTokens, 1);
          expect(perf.evalMs, 0);
          expect(perf.sampleCount, 0);
          expect(perf.decodeMs, isNull);
          throw LlamaInferenceException(
            'test stops before speech model execution',
          );
        };
    // Keep the legacy init this fake replaces on runtimes with the opt-in.
    fields[#initExt] = null;
    mirror.setField(
      symbol('_ttsApi'),
      original.type.newInstance(Symbol.empty, [], fields).reflectee,
    );
    await expectLater(
      service.synthesizeTextToSpeech(
        context,
        999,
        const BackendTextToSpeechRequest(text: 'hello'),
        flag.address,
      ),
      throwsA(isA<LlamaInferenceException>()),
    );
    expect(service.getPerformanceContext(context), isNotNull);
  });

  for (final operation in ['embed', 'embedBatch', 'content', 'score', 'tts']) {
    test(
      '$operation validation cannot expose previous service counters',
      () async {
        final service = LlamaCppService()..initializeBackend();
        addTearDown(service.dispose);
        final model = service.loadModel(path, _modelParams);
        final context = service.createContext(model, _modelParams);
        final flag = calloc<Int8>();
        addTearDown(() => calloc.free(flag));
        await service
            .generate(context, 'ab', _generation, flag.address)
            .drain<void>();
        expect(
          service.getPerformanceContext(context)!.evalTokens,
          greaterThan(0),
        );
        switch (operation) {
          case 'embed':
            expect(
              () => service.embed(context, 'ab ' * 100),
              throwsA(isA<LlamaException>()),
            );
          case 'embedBatch':
            expect(
              () => service.embedBatch(context, ['abc', 'ab ' * 100]),
              throwsA(isA<LlamaException>()),
            );
          case 'content':
            expect(
              () => service.embedContentBatch(context, [
                LlamaEmbeddingInput([LlamaTextContent('ab ' * 100)]),
              ]),
              throwsA(isA<LlamaException>()),
            );
          case 'score':
            expect(
              () => service.scoreNextToken(
                context,
                'abc',
                candidates: [-1],
                topK: 1,
                reusePromptPrefix: false,
              ),
              throwsRangeError,
            );
          case 'tts':
            // The tiny text model has no matching speech projector.
            await expectLater(
              service.synthesizeTextToSpeech(
                context,
                -1,
                const BackendTextToSpeechRequest(text: 'hello'),
                flag.address,
              ),
              throwsA(isA<LlamaStateException>()),
            );
        }
        expect(service.getPerformanceContext(context), isNull);
        service.embed(context, 'abc');
        expect(service.getPerformanceContext(context)!.evalTokens, 1);
        expect(service.getPerformanceContext(context)!.evalMs, 0);
      },
    );
  }
}
