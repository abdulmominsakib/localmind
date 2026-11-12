@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/native_barrier_api.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

import '../../../support/fake_mtmd.dart';
import '../../../support/fake_native_barrier.dart';
import '../../../support/recording_exit_teardown.dart';
import '../../../support/synthetic_decision_head.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _params = ModelParams(
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
  gpuLayers: 0,
  contextSize: 64,
);
const _greedy = GenerationParams(maxTokens: 4, temp: 0, topK: 1, seed: 1);

const _load = 'llama_dart_model_load_from_file';
const _create = 'llama_dart_init_from_model';
const _decode = 'llama_dart_decode';
const _encode = 'llama_dart_encode';
const _sample = 'llama_dart_sampler_sample';
const _synchronize = 'llama_dart_synchronize';

// A state file llamadart 0.11.1 wrote with llamadart-native v0.5.0-2
// (llama.cpp v0.5.0, session version 10) for an empty context of the
// synthetic model.
const _v050StateFile = <int>[
  0x6e, 0x73, 0x67, 0x67, 0x0a, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, //
  0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00,
  0x05, 0x00, 0x00, 0x00, 0x6c, 0x6c, 0x61, 0x6d, 0x61, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00,
];

TypeMatcher<T> _caught<T extends LlamaException>(
  String call, [
  Object details = 'boom',
]) => isA<T>()
    .having(
      (e) => e.message,
      'message',
      'llama.cpp raised an exception in $call.',
    )
    .having((e) => e.details, 'details', details);

Matcher _unusable(String what, String call) =>
    isA<LlamaStateException>().having(
      (e) => e.message,
      'message',
      '$what is unusable after a llama.cpp exception in $call. Unload the '
          'model and load it again.',
    );

// Runs the real llama.cpp runtime on the CPU. The exit API and the exception
// barrier fail the calls a test names, the first as a recorder around the
// real functions; everything else is the pinned runtime.
void main() {
  late Directory dir;
  late RecordingExitTeardown recorder;
  late FakeNativeBarrier barrier;
  late LlamaCppService service;
  late int model;
  late int context;
  FakeMtmd? mtmd;

  // The exit-API calls that catch an exception, and the ones that fail
  // without one.
  final throwing = <String>{};
  final failing = <String>{};

  void start({bool isWindows = false}) {
    recorder =
        RecordingExitTeardown(
            ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
            evalMedia: (context, nPast, nBatch, newNPast) =>
                mtmd!.evalMedia(context, nPast, nBatch, newNPast),
          )
          // A function with a barrier clears the last error on entry; the
          // exit registry functions have none.
          ..onCall = (name) {
            if (!name.startsWith('llama_dart_exit_')) barrier.clear();
          }
          ..fail = (name) {
            if (throwing.contains(name)) {
              barrier.catchException('boom');
              return true;
            }
            return failing.contains(name);
          };
    service = LlamaCppService(
      objectCalls: LlamaCppObjectCalls.tracked(
        recorder.api,
        barrier: barrier.api,
        isWindows: isWindows,
      ),
    )..initializeBackend();
    model = service.loadModel('${dir.path}/model.gguf', _params);
    context = service.createContext(model, _params);
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_native_failure_');
    writeSyntheticLlamaGguf('${dir.path}/model.gguf');
    mtmd = null;
    throwing.clear();
    failing.clear();
    barrier = FakeNativeBarrier(
      real: NativeBarrierApi.tryResolve(isWindows: Platform.isWindows)!,
    );
  });

  tearDown(() {
    throwing.clear();
    failing.clear();
    barrier.throwing.clear();
    barrier.failing.clear();
    service.dispose();
    final unfreed = recorder.unfreed;
    for (final address in unfreed) {
      recorder.real.untrack(Pointer.fromAddress(address));
    }
    barrier.dispose();
    dir.deleteSync(recursive: true);
    expect(
      unfreed,
      isEmpty,
      reason: 'a failed call leaves nothing behind that dispose does not free',
    );
  });

  test('a prompt decode that throws is a typed error, and its context is '
      'unusable until it is freed', () async {
    start();
    throwing.add(_decode);

    await expectLater(
      _generate(service, context, 'ab', _greedy),
      throwsA(_caught<LlamaInferenceException>('llama_decode')),
    );

    throwing.clear();
    final unusable = _unusable('This context', 'llama_decode');
    await expectLater(
      _generate(service, context, 'ab', _greedy),
      throwsA(unusable),
    );
    expect(() => service.embed(context, 'ab'), throwsA(unusable));
    expect(
      () => service.stateSaveFile(context, '${dir.path}/state.bin', const []),
      throwsA(unusable),
    );
    expect(
      () => service.stateLoadFile(context, '${dir.path}/state.bin', 8),
      throwsA(unusable),
    );
    expect(() => service.stateIdentity(context), throwsA(unusable));
    expect(
      () => service.scoreNextToken(
        context,
        'ab',
        candidates: const [],
        topK: 1,
        reusePromptPrefix: false,
      ),
      throwsA(unusable),
    );

    // The model is untouched: a new context of it generates.
    service.freeContext(context);
    context = service.createContext(model, _params);
    expect(
      await _generate(service, context, 'ab', _greedy),
      BackendGenerationLimit.maxTokens,
    );
  });

  test('a decode that throws during generation ends the stream with the '
      'typed error', () async {
    start();
    var decodes = 0;
    final fail = recorder.fail!;
    recorder.fail = (name) {
      if (name == _decode && ++decodes == 2) {
        barrier.catchException('boom');
        return true;
      }
      return fail(name);
    };

    await expectLater(
      _generate(service, context, 'ab', _greedy),
      throwsA(_caught<LlamaInferenceException>('llama_decode')),
    );
    await expectLater(
      _generate(service, context, 'ab', _greedy),
      throwsA(_unusable('This context', 'llama_decode')),
    );
  });

  test('a failed decode that caught nothing fails as before and leaves '
      'the context usable', () async {
    start();
    failing.add(_decode);

    await expectLater(
      _generate(service, context, 'ab', _greedy),
      throwsA(
        isA<Exception>().having(
          (e) => '$e',
          'text',
          contains('Initial decode failed'),
        ),
      ),
    );

    failing.clear();
    expect(
      await _generate(service, context, 'ab', _greedy),
      BackendGenerationLimit.maxTokens,
    );
  });

  for (final isWindows in [false, true]) {
    test('a sample that throws is a typed error; the context stays usable '
        'except under the Windows rule ($isWindows)', () async {
      start(isWindows: isWindows);
      throwing.add(_sample);

      await expectLater(
        _generate(service, context, 'ab', _greedy),
        throwsA(_caught<LlamaInferenceException>('llama_sampler_sample')),
      );

      throwing.clear();
      if (isWindows) {
        await expectLater(
          _generate(service, context, 'ab', _greedy),
          throwsA(_unusable('This context', 'llama_sampler_sample')),
        );
      } else {
        expect(
          await _generate(service, context, 'ab', _greedy),
          BackendGenerationLimit.maxTokens,
        );
      }
    });

    test('a tokenize that throws is a typed error; the model stays usable '
        'except under the Windows rule ($isWindows)', () async {
      start(isWindows: isWindows);
      barrier.throwing.add('llama_dart_tokenize');
      barrier.message = 'boom';

      expect(
        () => service.tokenize(model, 'ab', true),
        throwsA(_caught<LlamaInferenceException>('llama_tokenize')),
      );
      await expectLater(
        _generate(service, context, 'ab', _greedy),
        throwsA(
          isWindows
              ? _unusable('This model', 'llama_tokenize')
              : _caught<LlamaInferenceException>('llama_tokenize'),
        ),
      );

      barrier.throwing.clear();
      if (isWindows) {
        final unusable = _unusable('This model', 'llama_tokenize');
        expect(() => service.tokenize(model, 'ab', true), throwsA(unusable));
        expect(
          () => service.detokenize(model, const [1], false),
          throwsA(unusable),
        );
        expect(() => service.createContext(model, _params), throwsA(unusable));
        // Loading the model again gives a usable one.
        service.freeModel(model);
        model = service.loadModel('${dir.path}/model.gguf', _params);
        context = service.createContext(model, _params);
      }
      expect(service.tokenize(model, 'ab', true), isNotEmpty);
      expect(
        await _generate(service, context, 'ab', _greedy),
        BackendGenerationLimit.maxTokens,
      );
    });
  }

  test('a token outside the vocabulary is a typed error from detokenize, '
      'where llama.cpp used to end the process', () {
    start();

    expect(
      () => service.detokenize(model, const [LLAMA_TOKEN_NULL], false),
      throwsA(
        _caught<LlamaInferenceException>(
          'llama_token_to_piece',
          isA<String>().having((s) => s, 'message', isNotEmpty),
        ),
      ),
    );
    if (!Platform.isWindows) {
      expect(service.tokenize(model, 'ab', true), isNotEmpty);
    }
  });

  test('a lazy-grammar trigger pattern that is not a regular expression is '
      'a typed error, and the next generation runs', () async {
    start();

    await expectLater(
      _generate(
        service,
        context,
        'ab',
        _greedy.copyWith(
          grammar: 'root ::= "a"',
          grammarLazy: true,
          grammarTriggers: const [
            GenerationGrammarTrigger.typed(
              type: GrammarTriggerType.pattern,
              value: '(',
            ),
          ],
        ),
      ),
      throwsA(
        _caught<LlamaInferenceException>(
          'llama_sampler_init_grammar_lazy_patterns',
          isA<String>(),
        ),
      ),
    );

    if (!Platform.isWindows) {
      expect(
        await _generate(service, context, 'ab', _greedy),
        BackendGenerationLimit.maxTokens,
      );
    }
  });

  test('an exception while the sampler accepts the prompt is a typed error, '
      'and the next generation runs', () async {
    start();
    barrier.throwing.add('llama_dart_sampler_accept');
    barrier.message = 'boom';

    await expectLater(
      _generate(service, context, 'ab', _greedy),
      throwsA(_caught<LlamaInferenceException>('llama_sampler_accept')),
    );

    barrier.throwing.clear();
    expect(
      await _generate(service, context, 'ab', _greedy),
      BackendGenerationLimit.maxTokens,
    );
  });

  test('an exception while the context memory clears is a typed error, and '
      'the context is unusable', () async {
    start();
    barrier.throwing.add('llama_dart_memory_clear');
    barrier.message = 'boom';

    await expectLater(
      _generate(service, context, 'ab', _greedy),
      throwsA(_caught<LlamaInferenceException>('llama_memory_clear')),
    );

    barrier.throwing.clear();
    await expectLater(
      _generate(service, context, 'ab', _greedy),
      throwsA(_unusable('This context', 'llama_memory_clear')),
    );
  });

  test('a synchronize that throws is a typed error, and the context is '
      'unusable', () async {
    start();
    throwing.add(_synchronize);

    await expectLater(
      _generate(service, context, 'ab', _greedy),
      throwsA(_caught<LlamaInferenceException>('llama_synchronize')),
    );

    throwing.clear();
    await expectLater(
      _generate(service, context, 'ab', _greedy),
      throwsA(_unusable('This context', 'llama_synchronize')),
    );
  });

  test('invalid state token capacity makes no guarded state-load calls '
      'and does not poison its context', () {
    start();
    final path = '${dir.path}/capacity.bin';
    recorder.calls.clear();
    final contextCapacity = service.getContextSize(context);
    for (final capacity in [0, -1, contextCapacity + 1]) {
      expect(
        () => service.stateLoadFile(context, path, capacity),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('tokenCapacity'),
              contains(
                capacity > contextCapacity ? 'context size' : 'positive',
              ),
            ),
          ),
        ),
      );
      expect(recorder.calls, isEmpty);
    }
    expect(
      () => service.stateLoadFile(-1, path, 0),
      throwsA(isA<LlamaStateException>()),
    );
    expect(recorder.calls, isEmpty);
    expect(service.stateSaveFile(context, path, const []), isTrue);
    expect(service.stateLoadFile(context, path, 8), isEmpty);
  });

  test('a state save or load that throws is a typed state error, and the '
      'context is unusable', () {
    start();
    final path = '${dir.path}/state.bin';
    expect(service.stateSaveFile(context, path, const [1, 2]), isTrue);

    throwing.add('llama_dart_state_load_file');
    expect(
      () => service.stateLoadFile(context, path, 8),
      throwsA(_caught<LlamaStateException>('llama_state_load_file')),
    );
    throwing.clear();
    expect(
      () => service.stateLoadFile(context, path, 8),
      throwsA(_unusable('This context', 'llama_state_load_file')),
    );

    service.freeContext(context);
    context = service.createContext(model, _params);
    throwing.add('llama_dart_state_save_file');
    expect(
      () => service.stateSaveFile(context, path, const [1, 2]),
      throwsA(_caught<LlamaStateException>('llama_state_save_file')),
    );
  });

  test('a state file of llama.cpp v0.5.0 is refused with both session '
      'versions, and the context still loads a current one', () {
    start();
    final oldPath = '${dir.path}/v0.5.0.bin';
    File(oldPath).writeAsBytesSync(_v050StateFile);
    final currentPath = '${dir.path}/current.bin';
    expect(service.stateSaveFile(context, currentPath, const [1, 2]), isTrue);

    expect(LlamaCppService.readSessionFileVersion(oldPath), 10);
    expect(
      LlamaCppService.readSessionFileVersion(currentPath),
      LLAMA_SESSION_VERSION,
    );
    expect(
      () => service.stateLoadFile(context, oldPath, 8),
      throwsA(
        isA<LlamaStateException>().having(
          (e) => e.message,
          'message',
          'The state file "$oldPath" has llama.cpp session version 10, and '
              'this runtime reads version $LLAMA_SESSION_VERSION. A state '
              'file does not carry over to a llama.cpp release that changed '
              'the format: evaluate the prompt again and save a new one.',
        ),
      ),
    );
    expect(service.stateLoadFile(context, currentPath, 8), [1, 2]);
  });

  test('a state file that is not a session file fails without a version', () {
    start();
    final path = '${dir.path}/not-a-session.bin';
    File(path).writeAsStringSync('not a llama.cpp session file');
    final short = '${dir.path}/short.bin';
    File(short).writeAsBytesSync(const [0x6e, 0x73, 0x67, 0x67]);

    expect(LlamaCppService.readSessionFileVersion(path), isNull);
    expect(LlamaCppService.readSessionFileVersion(short), isNull);
    expect(
      LlamaCppService.readSessionFileVersion('${dir.path}/missing.bin'),
      isNull,
    );
    expect(
      () => service.stateLoadFile(context, path, 8),
      throwsA(
        isA<LlamaStateException>().having(
          (e) => e.message,
          'message',
          contains('llama_state_load_file failed for'),
        ),
      ),
    );
  });

  for (final isWindows in [false, true]) {
    test('a context creation that throws is a typed context error; the model '
        'stays usable except under the Windows rule ($isWindows)', () {
      start(isWindows: isWindows);
      throwing.add(_create);

      expect(
        () => service.createContext(model, _params),
        throwsA(_caught<LlamaContextException>('llama_init_from_model')),
      );

      throwing.clear();
      if (isWindows) {
        expect(
          () => service.createContext(model, _params),
          throwsA(_unusable('This model', 'llama_init_from_model')),
        );
      } else {
        service.freeContext(service.createContext(model, _params));
      }
    });
  }

  test('a model load that throws is a typed model error', () {
    start();
    throwing.add(_load);

    expect(
      () => service.loadModel('${dir.path}/model.gguf', _params),
      throwsA(_caught<LlamaModelException>('llama_model_load_from_file')),
    );
  });

  test('a LoRA load that throws is a typed model error, and the model is '
      'unusable until it is loaded again', () {
    start();
    final path = '${dir.path}/adapter.gguf';
    File(path).writeAsStringSync('not an adapter');
    throwing.add('llama_dart_adapter_lora_init');

    expect(
      () => service.handleLora(context, path, 1, 'set'),
      throwsA(_caught<LlamaModelException>('llama_adapter_lora_init')),
    );

    throwing.clear();
    final unusable = _unusable('This model', 'llama_adapter_lora_init');
    expect(() => service.tokenize(model, 'ab', true), throwsA(unusable));
    expect(
      () => service.handleLora(context, path, 1, 'set'),
      throwsA(unusable),
    );
    service.freeModel(model);
    model = service.loadModel('${dir.path}/model.gguf', _params);
    expect(service.tokenize(model, 'ab', true), isNotEmpty);
  });

  group('with a projector', () {
    late int projector;

    Future<BackendGenerationLimit?> describe() =>
        _generate(service, context, '<__media__>', _greedy, parts: mtmd!.parts);

    void attach({bool chunkEval = false}) {
      start();
      final projectorPath = '${dir.path}/mmproj.gguf';
      File(projectorPath).writeAsStringSync('GGUF');
      final fake = mtmd = FakeMtmd.install(
        service,
        tokens: service.tokenize(model, 'ab', true),
        chunkEval: chunkEval,
        decode: recorder.api.decode,
      );
      addTearDown(fake.dispose);
      projector = service.createMultimodalContext(model, projectorPath);
    }

    test('a projector load that throws is a typed model error', () {
      start();
      final projectorPath = '${dir.path}/mmproj.gguf';
      File(projectorPath).writeAsStringSync('GGUF');
      final fake = mtmd = FakeMtmd.install(service, tokens: const []);
      addTearDown(fake.dispose);
      throwing.add('llama_dart_mtmd_init_from_file');

      expect(
        () => service.createMultimodalContext(model, projectorPath),
        throwsA(_caught<LlamaModelException>('mtmd_init_from_file')),
      );
    });

    test('builds media bitmaps through the barrier, and a constructor that '
        'throws is a typed error', () async {
      attach();

      expect(await describe(), BackendGenerationLimit.maxTokens);
      expect(barrier.calls, contains('llama_dart_mtmd_bitmap_init_from_audio'));
      expect(mtmd!.freedBitmaps, [FakeNativeBarrier.object.address]);

      barrier.throwing.add('llama_dart_mtmd_bitmap_init_from_audio');
      barrier.message = 'boom';
      await expectLater(
        describe(),
        throwsA(
          _caught<LlamaInferenceException>('the mtmd bitmap constructor'),
        ),
      );

      barrier.throwing.clear();
      expect(await describe(), BackendGenerationLimit.maxTokens);
    });

    test('a media tokenize that throws is a typed error, and the projector '
        'is unusable until it is freed', () async {
      attach();
      throwing.add('llama_dart_mtmd_tokenize');

      await expectLater(
        describe(),
        throwsA(_caught<LlamaInferenceException>('mtmd_tokenize')),
      );

      throwing.clear();
      await expectLater(
        describe(),
        throwsA(_unusable('This multimodal projector', 'mtmd_tokenize')),
      );
      // Text generation on the context is unaffected.
      expect(
        await _generate(service, context, 'ab', _greedy),
        BackendGenerationLimit.maxTokens,
      );
      // A projector loaded afterwards is usable, at the same address too.
      service.freeMultimodalContext(projector);
      projector = service.createMultimodalContext(
        model,
        '${dir.path}/mmproj.gguf',
      );
      expect(await describe(), BackendGenerationLimit.maxTokens);
    });

    test('builds a bitmap of each media source through its own barrier '
        'constructor', () async {
      attach();
      final audioPath = '${dir.path}/clip.wav';
      File(audioPath).writeAsBytesSync(const [1, 2, 3]);

      for (final (part, constructor) in [
        (
          LlamaAudioContent(path: audioPath),
          'llama_dart_mtmd_bitmap_init_from_file',
        ),
        (
          LlamaAudioContent(bytes: Uint8List.fromList(const [1, 2, 3])),
          'llama_dart_mtmd_bitmap_init_from_buf',
        ),
        (
          LlamaAudioContent(samples: Float32List(1)),
          'llama_dart_mtmd_bitmap_init_from_audio',
        ),
      ]) {
        barrier.calls.clear();

        expect(
          await _generate(
            service,
            context,
            '<__media__>',
            _greedy,
            parts: [part],
          ),
          BackendGenerationLimit.maxTokens,
        );

        expect(barrier.calls.where((call) => call.contains('_mtmd_bitmap_')), [
          constructor,
        ]);
      }
    });

    test('a media evaluation that throws is a typed error, and the context '
        'and the projector are unusable', () async {
      attach();
      throwing.add('llama_dart_mtmd_helper_eval_chunks');

      await expectLater(
        describe(),
        throwsA(_caught<LlamaInferenceException>('mtmd_helper_eval_chunks')),
      );

      throwing.clear();
      await expectLater(
        _generate(service, context, 'ab', _greedy),
        throwsA(_unusable('This context', 'mtmd_helper_eval_chunks')),
      );
      service.freeContext(context);
      context = service.createContext(model, _params);
      await expectLater(
        describe(),
        throwsA(
          _unusable('This multimodal projector', 'mtmd_helper_eval_chunks'),
        ),
      );
    });

    test('a chunk evaluation that throws is a typed error naming the '
        'chunk', () async {
      attach(chunkEval: true);
      throwing.add('llama_dart_mtmd_helper_eval_chunk_single');

      await expectLater(
        describe(),
        throwsA(
          _caught<LlamaInferenceException>(
            'the mtmd chunk evaluation (failed to eval chunk 0)',
          ),
        ),
      );

      throwing.clear();
      await expectLater(
        _generate(service, context, 'ab', _greedy),
        throwsA(
          _unusable(
            'This context',
            'the mtmd chunk evaluation (failed to eval chunk 0)',
          ),
        ),
      );
    });
  });

  test('reads device properties and memory through the barrier', () {
    start();
    barrier.calls.clear();

    // Every registered device is read, the CPU device included.
    service.listGpuDevices();

    expect(barrier.calls, contains('llama_dart_ggml_backend_dev_get_props'));
    expect(
      barrier.calls.where((call) => !call.contains('_ggml_backend_dev_')),
      isEmpty,
    );

    // The memory read is the fallback of a GPU that reports none in its
    // properties, which a CPU host has no device for.
    barrier.calls.clear();
    final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
    final free = calloc<Size>();
    final total = calloc<Size>();
    addTearDown(() {
      calloc.free(free);
      calloc.free(total);
    });
    Object? invoke(String member, List<Object?> arguments) => reflect(
      service,
    ).invoke(MirrorSystem.getSymbol(member, owner), arguments).reflectee;
    final device = invoke('_ggmlBackendDevGet', [0]);
    bool readMemory() =>
        invoke('_ggmlBackendDevMemory', [device, free, total])! as bool;

    expect(readMemory(), isTrue);
    expect(barrier.calls, ['llama_dart_ggml_backend_dev_memory']);
    barrier.failing.add('llama_dart_ggml_backend_dev_memory');
    expect(readMemory(), isFalse);
  });

  test('a decision encoder pass that throws is a typed error, and the head '
      'is unusable until it is loaded again', () {
    start();
    writeSyntheticModernBertGguf(
      '${dir.path}/encoder.gguf',
      decisionTokens: true,
    );
    final encoder = service.loadModel('${dir.path}/encoder.gguf', _params);
    SyntheticDecisionHead(
      d: 16,
      layers: 1,
      seed: 1,
    ).write('${dir.path}/head.safetensors');
    File(
      '${dir.path}/config.json',
    ).writeAsStringSync('{"max_len": 64, "head_layers": 1}');
    int loadHead() => service
        .loadDecisionHead(
          encoder,
          '${dir.path}/head.safetensors',
          '${dir.path}/config.json',
        )
        .handle;
    List<BackendDecisionOutput> run(int head) => service.runDecision(head, [
      BackendDecisionSequence(
        tokens: Int32List.fromList([1, 5, 0, 6, 0, 2]),
        markers: Int32List.fromList([2, 4]),
        questionType: DecisionQuestionType.choice,
      ),
    ]);
    final head = loadHead();
    throwing.add(_encode);

    expect(
      () => run(head),
      throwsA(_caught<LlamaInferenceException>('llama_encode')),
    );

    throwing.clear();
    expect(
      () => run(head),
      throwsA(_unusable('This decision head', 'llama_encode')),
    );
    service.freeDecisionHead(head);
    expect(run(loadHead()), hasLength(1));
  });
}

/// Generates to the end and returns the limit that ended it, if one did.
Future<BackendGenerationLimit?> _generate(
  LlamaCppService service,
  int context,
  String prompt,
  GenerationParams params, {
  List<LlamaContentPart>? parts,
}) async {
  final cancel = calloc<Int8>();
  BackendGenerationLimit? limit;
  try {
    await service
        .generate(
          context,
          prompt,
          params,
          cancel.address,
          parts: parts,
          onLimit: (reached) => limit = reached,
        )
        .drain<void>();
    return limit;
  } finally {
    calloc.free(cancel);
  }
}
