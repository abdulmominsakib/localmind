@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';

import 'package:ffi/ffi.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:test/test.dart';

import '../../support/synthetic_embedding_gguf.dart';

const _params = ModelParams(
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
  device: ComputeDevice.cpu,
  gpuLayers: 0,
  contextSize: 64,
);
const _generation = GenerationParams(maxTokens: 3, temp: 0, topK: 1);

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  for (final phase in ['setup', 'step', 'reference']) {
    for (final operation in [
      'embed',
      'batch',
      'content',
      'score',
      'generate',
      'chat',
      'lora',
      'save',
      'load',
      'tts',
    ]) {
      test(
        '$operation rejects during TTS $phase without changing counters',
        () async {
          await h.service
              .generate(h.context, 'ab', _generation, h.flag.address)
              .drain<void>();
          if (operation == 'load') {
            final path = '${h.directory.path}/state';
            expect(h.service.stateSaveFile(h.context, path, [4, 5]), isTrue);
            expect(h.service.stateLoadFile(h.context, path, 64), [4, 5]);
          }
          final progress = Completer<void>();
          final synthesis = h.start(
            reference: phase == 'reference',
            onProgress: (_) => progress.complete(),
          );
          final terminal = expectLater(
            synthesis,
            throwsA(isA<LlamaInferenceException>()),
          );
          addTearDown(() => terminal);
          if (phase == 'step') await progress.future;
          final before = h.service.getPerformanceContext(h.context);
          if (phase == 'step') {
            expect(before, isNotNull);
            expect(before!.promptEvalTokens, greaterThan(0));
          } else {
            expect(before, isNull);
          }
          final initCalls = h.initCalls;
          await expectLater(
            Future.sync(() => h.run(operation)),
            throwsA(
              isA<LlamaStateException>().having(
                (error) => error.message.toLowerCase(),
                'message',
                contains('text-to-speech'),
              ),
            ),
          );
          final after = h.service.getPerformanceContext(h.context);
          if (phase == 'step') {
            expect(after, isNotNull);
            expect(after!.promptEvalTokens, before!.promptEvalTokens);
            expect(after.evalTokens, before.evalTokens);
            expect(after.sampleCount, before.sampleCount);
          } else {
            expect(after, isNull);
          }
          expect(h.initCalls, initCalls);
          await terminal;
          // Failure releases the reservation; the context can be used again.
          expect(h.service.embed(h.context, 'abc'), isNotEmpty);
        },
      );
    }
  }

  for (final reference in [false, true]) {
    test(
      'second-context TTS rejects before init (reference: $reference)',
      () async {
        final other = h.service.createContext(h.model, _params);
        final original = expectLater(
          h.start(reference: reference),
          throwsA(isA<LlamaInferenceException>()),
        );
        addTearDown(() => original);
        await expectLater(
          h.service.synthesizeTextToSpeech(
            other,
            999,
            const BackendTextToSpeechRequest(text: 'second'),
            h.flag.address,
          ),
          throwsA(isA<LlamaStateException>()),
        );
        await original;
        expect(h.initCalls, 1);
      },
    );
  }

  for (final operation in ['save', 'load']) {
    test(
      '$operation names generation when generation holds the context',
      () async {
        final iterator = StreamIterator(
          h.service.generate(h.context, 'ab', _generation, h.flag.address),
        );
        try {
          expect(await iterator.moveNext(), isTrue);
          await expectLater(
            Future.sync(() => h.run(operation)),
            throwsA(
              isA<LlamaStateException>().having(
                (error) => error.message,
                'message',
                contains('while generation is active'),
              ),
            ),
          );
        } finally {
          await iterator.cancel();
        }
      },
    );
  }

  test('another context remains usable during TTS', () async {
    final other = h.service.createContext(h.model, _params);
    final synthesis = expectLater(
      h.start(),
      throwsA(isA<LlamaInferenceException>()),
    );
    expect(h.service.embed(other, 'abc'), isNotEmpty);
    expect(h.service.getContextSize(h.context), greaterThanOrEqualTo(64));
    expect(h.service.getEmbeddingCapabilities(h.context).text, isTrue);
    await synthesis;
  });

  test(
    'TTS rejects while generation is suspended and leaves it usable',
    () async {
      final iterator = StreamIterator(
        h.service.generate(h.context, 'ab', _generation, h.flag.address),
      );
      try {
        expect(await iterator.moveNext(), isTrue);
        final before = h.service.getPerformanceContext(h.context);
        await expectLater(h.start(), throwsA(isA<LlamaStateException>()));
        expect(
          h.service.getPerformanceContext(h.context)?.evalTokens,
          before?.evalTokens,
        );
        expect(h.initCalls, 0);
      } finally {
        await iterator.cancel();
      }
      await expectLater(h.start(), throwsA(isA<LlamaInferenceException>()));
    },
  );

  test(
    'successful synthesis releases the reservation and returns PCM',
    () async {
      h.complete = true;
      final result = await h.start();
      expect(result.samples, [0.5, -0.5]);
      expect(result.framesGenerated, 1);
      expect(result.sampleRateHz, 24000);
      expect(result.channelCount, 1);
      expect(h.service.embed(h.context, 'abc'), isNotEmpty);
      expect((await h.start()).samples, [0.5, -0.5]);
      expect(h.initCalls, 2);
    },
  );

  test('reference read failure releases the TTS reservation', () async {
    await expectLater(
      h.service.synthesizeTextToSpeech(
        h.context,
        999,
        BackendTextToSpeechRequest(
          text: 'hello',
          speakerAudioPath: '${h.directory.path}/missing.wav',
        ),
        h.flag.address,
      ),
      throwsA(isA<LlamaAudioFormatException>()),
    );
    expect(h.service.embed(h.context, 'abc'), isNotEmpty);
    await expectLater(h.start(), throwsA(isA<LlamaInferenceException>()));
  });

  test('cancellation before init releases the TTS reservation', () async {
    final result = h.start();
    h.service.cancelTextToSpeech();
    await expectLater(result, throwsA(isA<LlamaTextToSpeechException>()));
    expect(h.initCalls, 0);
    expect(h.service.embed(h.context, 'abc'), isNotEmpty);
    await expectLater(h.start(), throwsA(isA<LlamaInferenceException>()));
  });
}

class _Harness {
  final directory = Directory.systemTemp.createTempSync('tts_exclusivity_');
  final service = LlamaCppService()..initializeBackend();
  final flag = calloc<Int8>();
  late final int model;
  late final int context;
  late final InstanceMirror mirror;
  late final LibraryMirror library;
  late final Map projectors;
  late final Map modelProjectors;
  int initCalls = 0;
  int steps = 0;
  bool complete = false;

  Symbol symbol(String name) => MirrorSystem.getSymbol(name, library);

  _Harness() {
    final path = '${directory.path}/model.gguf';
    writeSyntheticLlamaGguf(path);
    File('${directory.path}/speaker.wav').writeAsBytesSync([1, 2, 3]);
    model = service.loadModel(path, _params);
    context = service.createContext(model, _params);
    library = reflectClass(LlamaCppService).owner as LibraryMirror;
    mirror = reflect(service);
    projectors = mirror.getField(symbol('_mtmdContexts')).reflectee as Map;
    modelProjectors = mirror.getField(symbol('_modelToMtmd')).reflectee as Map;
    projectors[999] = Pointer<mtmd_context>.fromAddress(1);
    modelProjectors[model] = 999;
    final original = mirror.invoke(symbol('_resolveTtsApi'), []);
    final fields = <Symbol, dynamic>{
      for (final field
          in original.type.declarations.values.whereType<VariableMirror>())
        if (!field.isStatic)
          field.simpleName: original.getField(field.simpleName).reflectee,
    };
    // Keep the real service and context; replace only the native speech boundary.
    fields[#init] =
        (
          Pointer<llama_context> ctx,
          Pointer<mtmd_context> mm,
          Pointer<Int32> status,
        ) {
          initCalls++;
          steps = 0;
          return Pointer<llama_dart_tts>.fromAddress(123);
        };
    fields[#start] =
        (
          Pointer<llama_dart_tts> task,
          Pointer<llama_dart_tts_request> request,
        ) => 0;
    fields[#step] =
        (
          Pointer<llama_dart_tts> task,
          Pointer<llama_dart_tts_progress> progress,
        ) {
          if (steps++ > 0) {
            throw LlamaInferenceException('Injected TTS boundary stop');
          }
          progress.ref.state = complete
              ? llama_dart_tts_state.LLAMA_DART_TTS_STATE_COMPLETED.value
              : llama_dart_tts_state.LLAMA_DART_TTS_STATE_GENERATING.value;
          progress.ref.frames_generated = 1;
          progress.ref.prompt_tokens_remaining = 0;
          progress.ref.truncated = false;
          return 0;
        };
    fields[#getOutputInfo] =
        (
          Pointer<llama_dart_tts> task,
          Pointer<llama_dart_tts_output_info> info,
        ) {
          info.ref.sample_count = 2;
          info.ref.sample_rate = 24000;
          info.ref.channels = 1;
          return 0;
        };
    fields[#readPcm] =
        (
          Pointer<llama_dart_tts> task,
          int offset,
          Pointer<Float> pcm,
          int capacity,
          Pointer<Size> count,
        ) {
          pcm[0] = 0.5;
          pcm[1] = -0.5;
          count.value = 2;
          return 0;
        };
    fields[#reset] = (Pointer<llama_dart_tts> task) => 0;
    fields[#free] = (Pointer<llama_dart_tts> task) {};
    fields[#cancel] = (Pointer<llama_dart_tts> task) {};
    fields[#setCancelFlag] = null;
    fields[#initExt] = null;
    mirror.setField(
      symbol('_ttsApi'),
      original.type.newInstance(Symbol.empty, [], fields).reflectee,
    );
  }

  Future<BackendTextToSpeechResult> start({
    bool reference = false,
    void Function(BackendTextToSpeechProgress)? onProgress,
  }) {
    return service.synthesizeTextToSpeech(
      context,
      999,
      BackendTextToSpeechRequest(
        text: 'hello',
        speakerAudioPath: reference ? '${directory.path}/speaker.wav' : null,
      ),
      flag.address,
      onProgress: onProgress,
    );
  }

  FutureOr<void> run(String operation) {
    switch (operation) {
      case 'embed':
        service.embed(context, 'abc');
      case 'batch':
        service.embedBatch(context, ['abc', 'abcd']);
      case 'content':
        service.embedContentBatch(context, [
          LlamaEmbeddingInput([LlamaTextContent('abc')]),
        ]);
      case 'score':
        service.scoreNextToken(
          context,
          'abc',
          candidates: [4],
          topK: 1,
          reusePromptPrefix: false,
        );
      case 'generate':
        return service
            .generate(context, 'abc', _generation, flag.address)
            .drain<void>();
      case 'chat':
        return service
            .generateChatPrompt(
              context,
              'abc',
              _generation,
              flag.address,
              mediaMarker: '<media>',
            )
            .drain<void>();
      case 'lora':
        service.handleLora(context, null, null, 'clear');
      case 'save':
        service.stateSaveFile(context, '${directory.path}/state', []);
      case 'load':
        service.stateLoadFile(context, '${directory.path}/state', 64);
      case 'tts':
        return start().then<void>((_) {});
    }
  }

  void dispose() {
    projectors.clear();
    modelProjectors.clear();
    service.dispose();
    calloc.free(flag);
    directory.deleteSync(recursive: true);
  }
}
