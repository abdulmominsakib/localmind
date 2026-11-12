@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/isolate_shutdown_releases.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:test/test.dart';

import '../../../support/fake_native_barrier.dart';
import '../../../support/synthetic_embedding_gguf.dart';

// The exports a service on the tracked calls depends on.
const _symbols = [
  'llama_dart_exit_track',
  'llama_dart_exit_untrack',
  'llama_dart_exit_free',
  'llama_dart_model_load_from_file',
  'llama_dart_init_from_model',
  'llama_dart_mtmd_init_from_file',
  'llama_dart_decode',
  'llama_dart_encode',
  'llama_dart_synchronize',
  'llama_dart_sampler_sample',
  'llama_dart_state_save_file',
  'llama_dart_state_load_file',
  'llama_dart_state_seq_get_size_ext',
  'llama_dart_state_seq_get_data_ext',
  'llama_dart_state_seq_set_data_ext',
  'llama_dart_adapter_lora_init',
  'llama_dart_mtmd_tokenize',
  'llama_dart_mtmd_encode_chunk',
  'llama_dart_mtmd_helper_eval_chunks',
  'llama_dart_mtmd_helper_eval_chunk_single',
  'llama_dart_mtmd_helper_decode_image_chunk',
  'llama_dart_ggml_backend_sched_graph_compute',
];

final _statusException = llama_dart_status.LLAMA_DART_STATUS_EXCEPTION.value;

// Runs the real llama.cpp runtime on the CPU.
void main() {
  test('a runtime without the reranker symbols is unsupported, naming the '
      'pinned runtime that has them', () {
    expect(requireRerankingSymbols(() => 3), 3);
    expect(
      () => requireRerankingSymbols<int>(
        () => throw ArgumentError(
          "Couldn't resolve native function 'llama_model_n_cls_out'",
        ),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('pinned llama.cpp runtime ($llamaCppTag)'),
        ),
      ),
    );
    expect(
      () => requireRerankingSymbols<int>(
        () => throw LlamaUnsupportedException('no classifier outputs'),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          'no classifier outputs',
        ),
      ),
    );
  });

  late Directory dir;
  late String modelPath;

  setUpAll(() => LlamaCppService().initializeBackend());

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_exit_teardown_');
    modelPath = writeSyntheticLlamaGguf('${dir.path}/model.gguf').path;
  });

  tearDown(() => dir.deleteSync(recursive: true));

  ExitTeardownApi resolved() =>
      ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!;

  Pointer<llama_model> load(LlamaCppObjectCalls calls) {
    final path = modelPath.toNativeUtf8();
    try {
      final params = llama_model_default_params()..n_gpu_layers = 0;
      final model = calls.loadModel(path.cast(), params);
      expect(model, isNot(nullptr));
      return model;
    } finally {
      malloc.free(path);
    }
  }

  test('maps each shutdown stage to the llama_dart_exit_stage teardown frees '
      'in that order', () {
    expect(
      [for (final stage in ShutdownStage.values) exitStageValue(stage)],
      [0, 1, 2, 3, 4, 5],
    );
  });

  test('binds every function through the lookup, and resolves none when one '
      'is missing', () {
    final requested = <String>[];
    Pointer<NativeType> exported(String name) {
      requested.add(name);
      return Pointer.fromAddress(0x1000 + requested.length);
    }

    expect(
      ExitTeardownApi.tryResolve(isWindows: false, symbol: exported),
      isNotNull,
    );
    expect(requested, unorderedEquals(_symbols));

    for (final missing in _symbols) {
      expect(
        ExitTeardownApi.tryResolve(
          isWindows: false,
          symbol: (name) => name == missing
              ? throw ArgumentError("Couldn't resolve native function '$name'")
              : exported(name),
        ),
        isNull,
        reason: missing,
      );
    }
  });

  test('calls the function exported under the name of each of its '
      'members', () {
    final exports = _RecordingExports();
    addTearDown(exports.close);
    final api = ExitTeardownApi.tryResolve(
      isWindows: false,
      symbol: exports.symbol,
    )!;
    final batch = llama_batch_init(1, 0, 1);
    addTearDown(() => llama_batch_free(batch));

    final members = <String, void Function()>{
      'llama_dart_exit_track': () => api.track(nullptr, nullptr, 0),
      'llama_dart_exit_untrack': () => api.untrack(nullptr),
      'llama_dart_exit_free': () => api.free(nullptr),
      'llama_dart_model_load_from_file': () =>
          api.modelLoadFromFile(nullptr, llama_model_default_params()),
      'llama_dart_init_from_model': () =>
          api.initFromModel(nullptr, llama_context_default_params()),
      'llama_dart_mtmd_init_from_file': () =>
          api.mtmdInitFromFile(nullptr, nullptr, nullptr),
      'llama_dart_decode': () => api.decode(nullptr, batch),
      'llama_dart_encode': () => api.encode(nullptr, batch),
      'llama_dart_synchronize': () => api.synchronize(nullptr),
      'llama_dart_sampler_sample': () => api.samplerSample(nullptr, nullptr, 0),
      'llama_dart_state_save_file': () =>
          api.stateSaveFile(nullptr, nullptr, nullptr, 0),
      'llama_dart_state_load_file': () =>
          api.stateLoadFile(nullptr, nullptr, nullptr, 0, nullptr),
      'llama_dart_state_seq_get_size_ext': () =>
          api.stateSeqGetSizeExt(nullptr, 0, 0),
      'llama_dart_state_seq_get_data_ext': () =>
          api.stateSeqGetDataExt(nullptr, nullptr, 0, 0, 0),
      'llama_dart_state_seq_set_data_ext': () =>
          api.stateSeqSetDataExt(nullptr, nullptr, 0, 0, 0),
      'llama_dart_adapter_lora_init': () =>
          api.adapterLoraInit(nullptr, nullptr),
      'llama_dart_mtmd_tokenize': () =>
          api.mtmdTokenize(nullptr, nullptr, nullptr, nullptr, 0),
      'llama_dart_mtmd_encode_chunk': () =>
          api.mtmdEncodeChunk(nullptr, nullptr),
      'llama_dart_mtmd_helper_eval_chunks': () => api.mtmdHelperEvalChunks(
        nullptr,
        nullptr,
        nullptr,
        0,
        0,
        0,
        false,
        nullptr,
      ),
      'llama_dart_mtmd_helper_eval_chunk_single': () =>
          api.mtmdHelperEvalChunkSingle(
            nullptr,
            nullptr,
            nullptr,
            0,
            0,
            0,
            false,
            nullptr,
          ),
      'llama_dart_mtmd_helper_decode_image_chunk': () =>
          api.mtmdHelperDecodeImageChunk(
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            0,
            0,
            0,
            nullptr,
            nullptr,
            nullptr,
          ),
      'llama_dart_ggml_backend_sched_graph_compute': () =>
          api.schedGraphCompute(nullptr, nullptr),
    };
    expect(members.keys, unorderedEquals(_symbols));
    for (final MapEntry(key: name, value: call) in members.entries) {
      exports.called.clear();
      call();
      expect(exports.called, [name]);
    }
    expect(
      api.freeAddress.address,
      exports.symbol('llama_dart_exit_free').address,
    );
  });

  test('reranker metadata of a runtime without the symbols is unsupported, '
      'naming the pinned runtime', () {
    final calls = LlamaCppObjectCalls.upstream;
    final model = load(calls);
    addTearDown(() => calls.freeModel(model));

    expect(
      () => calls.rerankingModelInfo(
        model,
        classifierOutputs: (_) => throw ArgumentError(
          "Couldn't resolve native function 'llama_model_n_cls_out'",
        ),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('pinned llama.cpp runtime ($llamaCppTag)'),
        ),
      ),
    );
  });

  test('tracked calls use the exit API for every call', () {
    final exports = _RecordingExports();
    addTearDown(exports.close);
    final api = ExitTeardownApi.tryResolve(
      isWindows: false,
      symbol: exports.symbol,
    )!;
    final calls = LlamaCppObjectCalls.tracked(api);
    final batch = llama_batch_init(1, 0, 1);
    addTearDown(() => llama_batch_free(batch));

    final members = <String, void Function()>{
      'llama_dart_model_load_from_file': () =>
          calls.loadModel(nullptr, llama_model_default_params()),
      'llama_dart_init_from_model': () =>
          calls.createContext(nullptr, llama_context_default_params()),
      'llama_dart_decode': () => calls.decode(nullptr, batch),
      'llama_dart_encode': () => calls.encode(nullptr, batch),
      'llama_dart_synchronize': () => calls.synchronize(nullptr),
      'llama_dart_sampler_sample': () =>
          calls.samplerSample(nullptr, nullptr, 0),
      'llama_dart_state_save_file': () =>
          calls.stateSaveFile(nullptr, nullptr, nullptr, 0),
      'llama_dart_state_load_file': () =>
          calls.stateLoadFile(nullptr, nullptr, nullptr, 0, nullptr),
      'llama_dart_state_seq_get_size_ext': () =>
          calls.stateSeqGetSizeExt(nullptr, 0, 0),
      'llama_dart_state_seq_get_data_ext': () =>
          calls.stateSeqGetDataExt(nullptr, nullptr, 0, 0, 0),
      'llama_dart_state_seq_set_data_ext': () =>
          calls.stateSeqSetDataExt(nullptr, nullptr, 0, 0, 0),
      'llama_dart_adapter_lora_init': () =>
          calls.adapterLoraInit(nullptr, nullptr),
    };
    for (final MapEntry(key: name, value: call) in members.entries) {
      exports.called.clear();
      call();
      expect(exports.called, [name]);
    }
    exports.called.clear();
    calls.freeModel(nullptr);
    calls.freeContext(nullptr);
    expect(exports.called, ['llama_dart_exit_free', 'llama_dart_exit_free']);
    expect(calls.failures.barrier, isNull);
  });

  group('tracked calls with the exception barrier', () {
    late FakeNativeBarrier barrier;
    late bool exitThrows;

    final model = Pointer<llama_model>.fromAddress(0x100);
    final context = Pointer<llama_context>.fromAddress(0x200);
    final vocab = Pointer<llama_vocab>.fromAddress(0x300);
    final sampler = Pointer<llama_sampler>.fromAddress(0x400);

    setUp(() {
      barrier = FakeNativeBarrier();
      exitThrows = true;
    });
    tearDown(() => barrier.dispose());

    // Every function returns its failure value, after catching an exception
    // when [exitThrows] is set.
    T fail<T>(T failure) {
      barrier.clear();
      if (exitThrows) barrier.catchException('boom');
      return failure;
    }

    ExitTeardownApi failingExit() => ExitTeardownApi(
      track: (_, _, _) => false,
      untrack: (_) => false,
      free: (_) {},
      freeAddress: nullptr,
      modelLoadFromFile: (_, _) => fail(nullptr),
      initFromModel: (_, _) => fail(nullptr),
      mtmdInitFromFile: (_, _, _) => fail(nullptr),
      decode: (_, _) => fail(_statusException),
      encode: (_, _) => fail(_statusException),
      synchronize: (_) => fail(null),
      samplerSample: (_, _, _) => fail(LLAMA_TOKEN_NULL),
      stateSaveFile: (_, _, _, _) => fail(false),
      stateLoadFile: (_, _, _, _, _) => fail(false),
      stateSeqGetSizeExt: (_, _, _) => fail(0),
      stateSeqGetDataExt: (_, _, _, _, _) => fail(0),
      stateSeqSetDataExt: (_, _, _, _, _) => fail(0),
      adapterLoraInit: (_, _) => fail(nullptr),
      mtmdTokenize: (_, _, _, _, _) => fail(_statusException),
      mtmdEncodeChunk: (_, _) => fail(_statusException),
      mtmdHelperEvalChunks: (_, _, _, _, _, _, _, _) => fail(_statusException),
      mtmdHelperEvalChunkSingle: (_, _, _, _, _, _, _, _) =>
          fail(_statusException),
      mtmdHelperDecodeImageChunk: (_, _, _, _, _, _, _, _, _, _) =>
          fail(_statusException),
      schedGraphCompute: (_, _) => fail(-1),
    );

    LlamaCppObjectCalls tracked({bool isWindows = false}) =>
        LlamaCppObjectCalls.tracked(
          failingExit(),
          barrier: barrier.api,
          isWindows: isWindows,
        );

    // Each call, the error it throws after a caught exception, and the
    // objects that leaves free-only everywhere and on Windows only.
    List<
      (
        String,
        void Function(LlamaCppObjectCalls, llama_batch),
        TypeMatcher<LlamaException>,
        List<Pointer<NativeType>>,
        List<Pointer<NativeType>>,
      )
    >
    cases() => [
      (
        'llama_model_load_from_file',
        (calls, _) => calls.loadModel(nullptr, llama_model_default_params()),
        isA<LlamaModelException>(),
        [],
        [],
      ),
      (
        'llama_init_from_model',
        (calls, _) =>
            calls.createContext(model, llama_context_default_params()),
        isA<LlamaContextException>(),
        [],
        [model],
      ),
      (
        'llama_decode',
        (calls, batch) => calls.decode(context, batch),
        isA<LlamaInferenceException>(),
        [context],
        [],
      ),
      (
        'llama_encode',
        (calls, batch) => calls.encode(context, batch),
        isA<LlamaInferenceException>(),
        [context],
        [],
      ),
      (
        'llama_synchronize',
        (calls, _) => calls.synchronize(context),
        isA<LlamaInferenceException>(),
        [context],
        [],
      ),
      (
        'llama_sampler_sample',
        (calls, _) => calls.samplerSample(sampler, context, -1),
        isA<LlamaInferenceException>(),
        [],
        [context],
      ),
      (
        'llama_sampler_accept',
        (calls, _) => calls.samplerAccept(sampler, 1),
        isA<LlamaInferenceException>(),
        [],
        [],
      ),
      (
        'llama_sampler_init_grammar_lazy_patterns',
        (calls, _) => calls.samplerInitGrammarLazyPatterns(
          vocab,
          nullptr,
          nullptr,
          nullptr,
          0,
          nullptr,
          0,
        ),
        isA<LlamaInferenceException>(),
        [],
        [vocab],
      ),
      (
        'llama_tokenize',
        (calls, _) =>
            calls.tokenize(vocab, nullptr, 0, nullptr, 0, false, false),
        isA<LlamaInferenceException>(),
        [],
        [vocab],
      ),
      (
        'llama_token_to_piece',
        (calls, _) => calls.tokenToPiece(vocab, 1, nullptr, 0, 0, false),
        isA<LlamaInferenceException>(),
        [],
        [vocab],
      ),
      (
        'llama_memory_clear',
        (calls, _) => calls.memoryClear(context, nullptr, true),
        isA<LlamaInferenceException>(),
        [context],
        [],
      ),
      (
        'llama_state_save_file',
        (calls, _) => calls.stateSaveFile(context, nullptr, nullptr, 0),
        isA<LlamaStateException>(),
        [context],
        [],
      ),
      (
        'llama_state_load_file',
        (calls, _) =>
            calls.stateLoadFile(context, nullptr, nullptr, 0, nullptr),
        isA<LlamaStateException>(),
        [context],
        [],
      ),
      (
        'llama_state_seq_get_size_ext',
        (calls, _) => calls.stateSeqGetSizeExt(context, 0, 0),
        isA<LlamaStateException>(),
        [context],
        [],
      ),
      (
        'llama_state_seq_get_data_ext',
        (calls, _) => calls.stateSeqGetDataExt(context, nullptr, 0, 0, 0),
        isA<LlamaStateException>(),
        [context],
        [],
      ),
      (
        'llama_state_seq_set_data_ext',
        (calls, _) => calls.stateSeqSetDataExt(context, nullptr, 0, 0, 0),
        isA<LlamaStateException>(),
        [context],
        [],
      ),
      (
        'llama_adapter_lora_init',
        (calls, _) => calls.adapterLoraInit(model, nullptr),
        isA<LlamaModelException>(),
        [model],
        [],
      ),
    ];

    const barrierCalls = {
      'llama_sampler_accept',
      'llama_sampler_init_grammar_lazy_patterns',
      'llama_tokenize',
      'llama_token_to_piece',
      'llama_memory_clear',
    };

    for (final isWindows in [false, true]) {
      test('a caught exception is the typed error of its call and leaves '
          'the objects of the call free-only (Windows rule: $isWindows)', () {
        final batch = llama_batch_init(1, 0, 1);
        addTearDown(() => llama_batch_free(batch));
        barrier.throwing.addAll([
          for (final name in barrierCalls)
            name.replaceFirst('llama_', 'llama_dart_'),
        ]);
        barrier.message = 'boom';

        for (final (name, call, error, freeOnly, windowsFreeOnly) in cases()) {
          final calls = tracked(isWindows: isWindows);
          expect(
            () => call(calls, batch),
            throwsA(
              error
                  .having(
                    (e) => e.message,
                    'message',
                    'llama.cpp raised an exception in $name.',
                  )
                  .having((e) => e.details, 'details', 'boom'),
            ),
            reason: name,
          );
          final expected = {...freeOnly, if (isWindows) ...windowsFreeOnly};
          for (final object in <Pointer<NativeType>>[
            model,
            context,
            vocab,
            sampler,
          ]) {
            expect(
              () => calls.failures.ensureUsable(object, 'This object'),
              expected.contains(object)
                  ? throwsA(isA<LlamaStateException>())
                  : returnsNormally,
              reason: '$name ${object.address.toRadixString(16)}',
            );
          }
        }
      });
    }

    test('a failure value without a caught exception is returned', () {
      exitThrows = false;
      barrier.failing.addAll([
        for (final name in barrierCalls)
          name.replaceFirst('llama_', 'llama_dart_'),
      ]);
      final batch = llama_batch_init(1, 0, 1);
      addTearDown(() => llama_batch_free(batch));
      final calls = tracked(isWindows: true);

      expect(calls.loadModel(nullptr, llama_model_default_params()), nullptr);
      expect(
        calls.createContext(model, llama_context_default_params()),
        nullptr,
      );
      expect(calls.decode(context, batch), _statusException);
      expect(calls.encode(context, batch), _statusException);
      calls.synchronize(context);
      expect(calls.samplerSample(sampler, context, -1), LLAMA_TOKEN_NULL);
      calls.samplerAccept(sampler, 1);
      expect(
        calls.samplerInitGrammarLazyPatterns(
          vocab,
          nullptr,
          nullptr,
          nullptr,
          0,
          nullptr,
          0,
        ),
        nullptr,
      );
      expect(
        calls.tokenize(vocab, nullptr, 0, nullptr, 0, false, false),
        _statusException,
      );
      expect(
        calls.tokenToPiece(vocab, 1, nullptr, 0, 0, false),
        _statusException,
      );
      calls.memoryClear(context, nullptr, true);
      expect(calls.stateSaveFile(context, nullptr, nullptr, 0), isFalse);
      expect(
        calls.stateLoadFile(context, nullptr, nullptr, 0, nullptr),
        isFalse,
      );
      expect(calls.stateSeqGetSizeExt(context, 0, 0), 0);
      expect(calls.stateSeqGetDataExt(context, nullptr, 0, 0, 0), 0);
      expect(calls.stateSeqSetDataExt(context, nullptr, 0, 0, 0), 0);
      expect(calls.adapterLoraInit(model, nullptr), nullptr);
      for (final object in <Pointer<NativeType>>[model, context, vocab]) {
        calls.failures.ensureUsable(object, 'This object');
      }
    });

    test('routes the calls that used to reach an upstream function that '
        'throws through the barrier wrappers', () {
      final calls = tracked();

      calls.samplerAccept(sampler, 1);
      calls.samplerInitGrammarLazyPatterns(
        vocab,
        nullptr,
        nullptr,
        nullptr,
        0,
        nullptr,
        0,
      );
      calls.tokenize(vocab, nullptr, 0, nullptr, 0, false, false);
      calls.tokenToPiece(vocab, 1, nullptr, 0, 0, false);
      calls.memoryClear(context, nullptr, true);

      expect(barrier.calls, [
        'llama_dart_sampler_accept',
        'llama_dart_sampler_init_grammar_lazy_patterns',
        'llama_dart_tokenize',
        'llama_dart_token_to_piece',
        'llama_dart_memory_clear',
      ]);
    });

    test('freeing an object forgets that it was free-only', () {
      final calls = tracked();
      final batch = llama_batch_init(1, 0, 1);
      addTearDown(() => llama_batch_free(batch));
      expect(
        () => calls.decode(context, batch),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(
        () => calls.adapterLoraInit(model, nullptr),
        throwsA(isA<LlamaModelException>()),
      );

      calls.freeContext(context);
      calls.freeModel(model);

      calls.failures.ensureUsable(context, 'This context');
      calls.failures.ensureUsable(model, 'This model');
    });
  });

  test('resolve picks the calls by what the runtime exports, and passes the '
      'Windows rule on', () {
    Pointer<NativeType> exported(String name) => Pointer.fromAddress(0x1000);
    Never missing(String name) =>
        throw ArgumentError("Couldn't resolve native function '$name'");

    for (final isWindows in [false, true]) {
      // llamadart-native v0.6.0-1 and later: exit teardown and the barrier.
      final current = LlamaCppObjectCalls.resolve(
        isWindows: isWindows,
        symbol: exported,
      );
      expect(current.exit, isNotNull);
      expect(current.failures.barrier, isNotNull);
      expect(current.failures.isWindows, isWindows);

      // v0.5.0-1 to v0.6.0: exit teardown only.
      final withoutBarrier = LlamaCppObjectCalls.resolve(
        isWindows: isWindows,
        symbol: (name) =>
            _symbols.contains(name) ? exported(name) : missing(name),
      );
      expect(withoutBarrier.exit, isNotNull);
      expect(withoutBarrier.failures.barrier, isNull);
      expect(withoutBarrier.failures.isWindows, isWindows);

      // Older: the upstream functions.
      expect(
        LlamaCppObjectCalls.resolve(isWindows: isWindows, symbol: missing),
        same(LlamaCppObjectCalls.upstream),
      );
    }
  });

  test('resolve adds the exception barrier of the pinned runtime', () {
    final calls = LlamaCppObjectCalls.resolve(isWindows: Platform.isWindows);

    expect(calls.exit, isNotNull);
    expect(calls.failures.barrier, isNotNull);
    expect(calls.failures.isWindows, Platform.isWindows);
    expect(LlamaCppObjectCalls.upstream.failures.barrier, isNull);
  });

  test('frees a tracked object once, with the function it was tracked '
      'with', () {
    final exit = resolved();
    final freed = <int>[];
    final free = NativeCallable<Void Function(Pointer<Void>)>.isolateLocal(
      (Pointer<Void> object) => freed.add(object.address),
    );
    addTearDown(free.close);
    final object = malloc<Int32>();
    addTearDown(() => malloc.free(object));

    expect(
      exit.track(
        object.cast(),
        free.nativeFunction,
        exitStageValue(ShutdownStage.modelUser),
      ),
      isTrue,
    );
    exit.free(object.cast());
    exit.free(object.cast());

    expect(freed, [object.address]);
    expect(exit.untrack(object.cast()), isFalse);
  });

  test('tracked calls create objects the runtime tracks and frees', () {
    final exit = resolved();
    final calls = LlamaCppObjectCalls.tracked(exit);
    expect(calls.modelFreeAddress, exit.freeAddress);
    expect(calls.contextFreeAddress, exit.freeAddress);

    final model = load(calls);
    final context = calls.createContext(
      model,
      llama_context_default_params()..n_ctx = 64,
    );
    expect(context, isNot(nullptr));
    final batch = llama_batch_init(2, 0, 1);
    try {
      batch.n_tokens = 2;
      for (var i = 0; i < 2; i++) {
        batch.token[i] = 1 + i;
        batch.pos[i] = i;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        batch.logits[i] = i;
      }
      expect(calls.decode(context, batch), 0);
      calls.synchronize(context);
    } finally {
      llama_batch_free(batch);
    }

    calls.freeContext(context);
    expect(exit.untrack(context.cast()), isFalse);
    // Untracking shows the load tracked the model; the upstream free then
    // releases what the tracked free no longer knows.
    expect(exit.untrack(model.cast()), isTrue);
    llama_model_free(model);
  });

  test('untracked decode and encode return once the backend has finished', () {
    final context = Pointer<llama_context>.fromAddress(0x10);
    final batch = calloc<llama_batch>();
    addTearDown(() => calloc.free(batch));
    final called = <String>[];
    final calls = LlamaCppObjectCalls.untracked(
      decode: (ctx, batch) {
        called.add('decode');
        return 1;
      },
      encode: (ctx, batch) {
        called.add('encode');
        return 2;
      },
      synchronize: (ctx) {
        expect(ctx, context);
        called.add('synchronize');
      },
    );

    expect(calls.decode(context, batch.ref), 1);
    expect(calls.encode(context, batch.ref), 2);
    expect(called, ['decode', 'synchronize', 'encode', 'synchronize']);
  });

  test('upstream decode returns once llama.cpp has finished the batch', () {
    final calls = LlamaCppObjectCalls.upstream;
    final model = load(calls);
    final context = calls.createContext(
      model,
      llama_context_default_params()..n_ctx = 64,
    );
    final batch = llama_batch_init(2, 0, 1);
    try {
      batch.n_tokens = 2;
      for (var i = 0; i < 2; i++) {
        batch.token[i] = 1 + i;
        batch.pos[i] = i;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        batch.logits[i] = i;
      }

      expect(calls.decode(context, batch), 0);
      // llama.cpp counts queued prompt tokens when it synchronizes.
      expect(llama_perf_context(context).n_p_eval, 2);
    } finally {
      llama_batch_free(batch);
      calls.freeContext(context);
      calls.freeModel(model);
    }
  });

  test('upstream calls create objects the runtime does not track', () {
    final calls = LlamaCppObjectCalls.upstream;
    expect(calls.exit, isNull);
    expect(
      calls.modelFreeAddress.address,
      Native.addressOf<NativeFunction<Void Function(Pointer<llama_model>)>>(
        llama_model_free,
      ).address,
    );
    expect(
      calls.contextFreeAddress.address,
      Native.addressOf<NativeFunction<Void Function(Pointer<llama_context>)>>(
        llama_free,
      ).address,
    );

    final model = load(calls);
    final context = calls.createContext(
      model,
      llama_context_default_params()..n_ctx = 64,
    );
    expect(context, isNot(nullptr));
    final exit = resolved();
    expect(exit.untrack(context.cast()), isFalse);
    expect(exit.untrack(model.cast()), isFalse);
    calls.freeContext(context);
    calls.freeModel(model);
  });
}

/// Stands in for a runtime's exports: one native function per name, each of
/// which records its name in [called] and returns zero.
final class _RecordingExports {
  final List<String> called = <String>[];

  late final Map<String, NativeCallable<Function>> _functions = {
    'llama_dart_exit_track':
        NativeCallable<
          Bool Function(
            Pointer<Void>,
            Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
            Int32,
          )
        >.isolateLocal(
          (Pointer<Void> _, Pointer<NativeType> _, int _) =>
              _record('llama_dart_exit_track', false),
          exceptionalReturn: false,
        ),
    'llama_dart_exit_untrack':
        NativeCallable<Bool Function(Pointer<Void>)>.isolateLocal(
          (Pointer<Void> _) => _record('llama_dart_exit_untrack', false),
          exceptionalReturn: false,
        ),
    'llama_dart_exit_free':
        NativeCallable<Void Function(Pointer<Void>)>.isolateLocal(
          (Pointer<Void> _) => _record('llama_dart_exit_free', null),
        ),
    'llama_dart_model_load_from_file':
        NativeCallable<
          Pointer<llama_model> Function(Pointer<Char>, llama_model_params)
        >.isolateLocal(
          (Pointer<Char> _, llama_model_params _) => _record(
            'llama_dart_model_load_from_file',
            nullptr.cast<llama_model>(),
          ),
        ),
    'llama_dart_init_from_model':
        NativeCallable<
          Pointer<llama_context> Function(
            Pointer<llama_model>,
            llama_context_params,
          )
        >.isolateLocal(
          (Pointer<llama_model> _, llama_context_params _) => _record(
            'llama_dart_init_from_model',
            nullptr.cast<llama_context>(),
          ),
        ),
    'llama_dart_mtmd_init_from_file':
        NativeCallable<
          Pointer<mtmd_context> Function(
            Pointer<Char>,
            Pointer<llama_model>,
            Pointer<mtmd_context_params>,
          )
        >.isolateLocal(
          (
            Pointer<Char> _,
            Pointer<llama_model> _,
            Pointer<mtmd_context_params> _,
          ) => _record(
            'llama_dart_mtmd_init_from_file',
            nullptr.cast<mtmd_context>(),
          ),
        ),
    for (final name in ['llama_dart_decode', 'llama_dart_encode'])
      name:
          NativeCallable<
            Int32 Function(Pointer<llama_context>, llama_batch)
          >.isolateLocal(
            (Pointer<llama_context> _, llama_batch _) => _record(name, 0),
            exceptionalReturn: 0,
          ),
    'llama_dart_synchronize':
        NativeCallable<Void Function(Pointer<llama_context>)>.isolateLocal(
          (Pointer<llama_context> _) => _record('llama_dart_synchronize', null),
        ),
    'llama_dart_sampler_sample':
        NativeCallable<
          Int32 Function(Pointer<llama_sampler>, Pointer<llama_context>, Int32)
        >.isolateLocal(
          (Pointer<llama_sampler> _, Pointer<llama_context> _, int _) =>
              _record('llama_dart_sampler_sample', 0),
          exceptionalReturn: 0,
        ),
    'llama_dart_state_save_file':
        NativeCallable<
          Bool Function(
            Pointer<llama_context>,
            Pointer<Char>,
            Pointer<Int32>,
            Size,
          )
        >.isolateLocal(
          (
            Pointer<llama_context> _,
            Pointer<Char> _,
            Pointer<Int32> _,
            int _,
          ) => _record('llama_dart_state_save_file', false),
          exceptionalReturn: false,
        ),
    'llama_dart_state_load_file':
        NativeCallable<
          Bool Function(
            Pointer<llama_context>,
            Pointer<Char>,
            Pointer<Int32>,
            Size,
            Pointer<Size>,
          )
        >.isolateLocal(
          (
            Pointer<llama_context> _,
            Pointer<Char> _,
            Pointer<Int32> _,
            int _,
            Pointer<Size> _,
          ) => _record('llama_dart_state_load_file', false),
          exceptionalReturn: false,
        ),
    'llama_dart_state_seq_get_size_ext':
        NativeCallable<
          Size Function(Pointer<llama_context>, Int32, Uint32)
        >.isolateLocal(
          (Pointer<llama_context> _, int _, int _) =>
              _record('llama_dart_state_seq_get_size_ext', 0),
          exceptionalReturn: 0,
        ),
    for (final name in [
      'llama_dart_state_seq_get_data_ext',
      'llama_dart_state_seq_set_data_ext',
    ])
      name:
          NativeCallable<
            Size Function(
              Pointer<llama_context>,
              Pointer<Uint8>,
              Size,
              Int32,
              Uint32,
            )
          >.isolateLocal(
            (Pointer<llama_context> _, Pointer<Uint8> _, int _, int _, int _) =>
                _record(name, 0),
            exceptionalReturn: 0,
          ),
    'llama_dart_adapter_lora_init':
        NativeCallable<
          Pointer<llama_adapter_lora> Function(
            Pointer<llama_model>,
            Pointer<Char>,
          )
        >.isolateLocal(
          (Pointer<llama_model> _, Pointer<Char> _) => _record(
            'llama_dart_adapter_lora_init',
            nullptr.cast<llama_adapter_lora>(),
          ),
        ),
    'llama_dart_mtmd_tokenize':
        NativeCallable<
          Int32 Function(
            Pointer<mtmd_context>,
            Pointer<mtmd_input_chunks>,
            Pointer<mtmd_input_text>,
            Pointer<Pointer<mtmd_bitmap>>,
            Size,
          )
        >.isolateLocal(
          (
            Pointer<mtmd_context> _,
            Pointer<mtmd_input_chunks> _,
            Pointer<mtmd_input_text> _,
            Pointer<Pointer<mtmd_bitmap>> _,
            int _,
          ) => _record('llama_dart_mtmd_tokenize', 0),
          exceptionalReturn: 0,
        ),
    'llama_dart_mtmd_encode_chunk':
        NativeCallable<
          Int32 Function(Pointer<mtmd_context>, Pointer<mtmd_input_chunk>)
        >.isolateLocal(
          (Pointer<mtmd_context> _, Pointer<mtmd_input_chunk> _) =>
              _record('llama_dart_mtmd_encode_chunk', 0),
          exceptionalReturn: 0,
        ),
    'llama_dart_mtmd_helper_eval_chunks':
        NativeCallable<
          Int32 Function(
            Pointer<mtmd_context>,
            Pointer<llama_context>,
            Pointer<mtmd_input_chunks>,
            Int32,
            Int32,
            Int32,
            Bool,
            Pointer<Int32>,
          )
        >.isolateLocal(
          (
            Pointer<mtmd_context> _,
            Pointer<llama_context> _,
            Pointer<mtmd_input_chunks> _,
            int _,
            int _,
            int _,
            bool _,
            Pointer<Int32> _,
          ) => _record('llama_dart_mtmd_helper_eval_chunks', 0),
          exceptionalReturn: 0,
        ),
    'llama_dart_mtmd_helper_eval_chunk_single':
        NativeCallable<
          Int32 Function(
            Pointer<mtmd_context>,
            Pointer<llama_context>,
            Pointer<mtmd_input_chunk>,
            Int32,
            Int32,
            Int32,
            Bool,
            Pointer<Int32>,
          )
        >.isolateLocal(
          (
            Pointer<mtmd_context> _,
            Pointer<llama_context> _,
            Pointer<mtmd_input_chunk> _,
            int _,
            int _,
            int _,
            bool _,
            Pointer<Int32> _,
          ) => _record('llama_dart_mtmd_helper_eval_chunk_single', 0),
          exceptionalReturn: 0,
        ),
    'llama_dart_mtmd_helper_decode_image_chunk':
        NativeCallable<
          Int32 Function(
            Pointer<mtmd_context>,
            Pointer<llama_context>,
            Pointer<mtmd_input_chunk>,
            Pointer<Float>,
            Int32,
            Int32,
            Int32,
            Pointer<Int32>,
            LlamaDartPostDecodeCallback,
            Pointer<Void>,
          )
        >.isolateLocal(
          (
            Pointer<mtmd_context> _,
            Pointer<llama_context> _,
            Pointer<mtmd_input_chunk> _,
            Pointer<Float> _,
            int _,
            int _,
            int _,
            Pointer<Int32> _,
            LlamaDartPostDecodeCallback _,
            Pointer<Void> _,
          ) => _record('llama_dart_mtmd_helper_decode_image_chunk', 0),
          exceptionalReturn: 0,
        ),
    'llama_dart_ggml_backend_sched_graph_compute':
        NativeCallable<
          Int Function(ggml_backend_sched_t, Pointer<ggml_cgraph>)
        >.isolateLocal(
          (ggml_backend_sched_t _, Pointer<ggml_cgraph> _) =>
              _record('llama_dart_ggml_backend_sched_graph_compute', 0),
          exceptionalReturn: 0,
        ),
  };

  T _record<T>(String name, T result) {
    called.add(name);
    return result;
  }

  /// The address of the function exported as [name].
  Pointer<NativeType> symbol(String name) => _functions[name]!.nativeFunction;

  void close() {
    for (final function in _functions.values) {
      function.close();
    }
  }
}
