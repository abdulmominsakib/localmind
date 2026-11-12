@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/native_barrier_api.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';

import '../../../support/fake_native_barrier.dart';
import '../../../support/synthetic_embedding_gguf.dart';

// The exports the exception barrier depends on.
const _symbols = [
  'llama_dart_last_error',
  'llama_dart_clear_last_error',
  'llama_dart_sampler_accept',
  'llama_dart_sampler_init_grammar_lazy_patterns',
  'llama_dart_tokenize',
  'llama_dart_token_to_piece',
  'llama_dart_memory_clear',
  'llama_dart_mtmd_bitmap_init_from_audio',
  'llama_dart_mtmd_bitmap_init_from_buf',
  'llama_dart_mtmd_bitmap_init_from_file',
  'llama_dart_ggml_backend_dev_init',
  'llama_dart_ggml_backend_dev_memory',
  'llama_dart_ggml_backend_dev_get_props',
  'llama_dart_ggml_backend_alloc_ctx_tensors',
  'llama_dart_ggml_backend_tensor_set',
  'llama_dart_ggml_backend_tensor_get',
  'llama_dart_ggml_backend_sched_alloc_graph',
  'llama_dart_ggml_backend_sched_synchronize',
];

final _statusException = llama_dart_status.LLAMA_DART_STATUS_EXCEPTION.value;

void main() {
  group('NativeBarrierApi', () {
    test('binds every function through the lookup, and resolves none when '
        'one is missing', () {
      final requested = <String>[];
      Pointer<NativeType> exported(String name) {
        requested.add(name);
        return Pointer.fromAddress(0x1000 + requested.length);
      }

      expect(
        NativeBarrierApi.tryResolve(isWindows: false, symbol: exported),
        isNotNull,
      );
      expect(requested, unorderedEquals(_symbols));

      for (final missing in _symbols) {
        expect(
          NativeBarrierApi.tryResolve(
            isWindows: false,
            symbol: (name) => name == missing
                ? throw ArgumentError(
                    "Couldn't resolve native function '$name'",
                  )
                : exported(name),
          ),
          isNull,
          reason: missing,
        );
      }
    });

    test('resolves nothing from a library that exports none of them', () {
      final library = DynamicLibrary.open(switch (Platform.operatingSystem) {
        'macos' => '/usr/lib/libSystem.B.dylib',
        'windows' => 'kernel32.dll',
        _ => 'libc.so.6',
      });

      expect(
        NativeBarrierApi.tryResolve(isWindows: false, symbol: library.lookup),
        isNull,
      );
    });

    test('calls the function exported under the name of each of its '
        'members', () {
      final exports = _RecordingExports();
      addTearDown(exports.close);
      final api = NativeBarrierApi.tryResolve(
        isWindows: false,
        symbol: exports.symbol,
      )!;

      final members = <String, void Function()>{
        'llama_dart_last_error': () => api.lastError(),
        'llama_dart_clear_last_error': () => api.clearLastError(),
        'llama_dart_sampler_accept': () => api.samplerAccept(nullptr, 0),
        'llama_dart_sampler_init_grammar_lazy_patterns': () =>
            api.samplerInitGrammarLazyPatterns(
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              0,
              nullptr,
              0,
            ),
        'llama_dart_tokenize': () =>
            api.tokenize(nullptr, nullptr, 0, nullptr, 0, false, false),
        'llama_dart_token_to_piece': () =>
            api.tokenToPiece(nullptr, 0, nullptr, 0, 0, false),
        'llama_dart_memory_clear': () => api.memoryClear(nullptr, false),
        'llama_dart_mtmd_bitmap_init_from_audio': () =>
            api.mtmdBitmapInitFromAudio(0, nullptr),
        'llama_dart_mtmd_bitmap_init_from_buf': () =>
            api.mtmdBitmapInitFromBuf(nullptr, nullptr, 0),
        'llama_dart_mtmd_bitmap_init_from_file': () =>
            api.mtmdBitmapInitFromFile(nullptr, nullptr),
        'llama_dart_ggml_backend_dev_init': () =>
            api.ggmlBackendDevInit(nullptr, nullptr),
        'llama_dart_ggml_backend_dev_memory': () =>
            api.ggmlBackendDevMemory(nullptr, nullptr, nullptr),
        'llama_dart_ggml_backend_dev_get_props': () =>
            api.ggmlBackendDevGetProps(nullptr, nullptr),
        'llama_dart_ggml_backend_alloc_ctx_tensors': () =>
            api.ggmlBackendAllocCtxTensors(nullptr, nullptr),
        'llama_dart_ggml_backend_tensor_set': () =>
            api.ggmlBackendTensorSet(nullptr, nullptr, 0, 0),
        'llama_dart_ggml_backend_tensor_get': () =>
            api.ggmlBackendTensorGet(nullptr, nullptr, 0, 0),
        'llama_dart_ggml_backend_sched_alloc_graph': () =>
            api.ggmlBackendSchedAllocGraph(nullptr, nullptr),
        'llama_dart_ggml_backend_sched_synchronize': () =>
            api.ggmlBackendSchedSynchronize(nullptr),
      };
      expect(members.keys, unorderedEquals(_symbols));
      for (final MapEntry(key: name, value: call) in members.entries) {
        exports.called.clear();
        call();
        expect(exports.called, [name]);
      }
    });

    test('reads no exception from a null last error', () {
      final exports = _RecordingExports();
      addTearDown(exports.close);
      final api = NativeBarrierApi.tryResolve(
        isWindows: false,
        symbol: exports.symbol,
      )!;

      expect(api.caughtException(), isNull);
    });
  });

  // Runs the real llama.cpp runtime on the CPU.
  group('the pinned runtime', () {
    late Directory dir;
    late Pointer<llama_model> model;
    late LlamaCppObjectCalls calls;
    late NativeBarrierApi barrier;

    setUpAll(() => LlamaCppService().initializeBackend());

    setUp(() {
      dir = Directory.systemTemp.createTempSync('llamadart_barrier_');
      final path = writeSyntheticLlamaGguf(
        '${dir.path}/model.gguf',
      ).path.toNativeUtf8();
      calls = LlamaCppObjectCalls.resolve(isWindows: Platform.isWindows);
      barrier = calls.failures.barrier!;
      try {
        model = calls.loadModel(
          path.cast(),
          llama_model_default_params()..n_gpu_layers = 0,
        );
      } finally {
        malloc.free(path);
      }
      expect(model, isNot(nullptr));
    });

    tearDown(() {
      calls.freeModel(model);
      dir.deleteSync(recursive: true);
    });

    test('records the message of an exception llama.cpp throws, for the '
        'next call to clear', () {
      final vocab = llama_model_get_vocab(model);
      final buffer = malloc<Char>(64);
      addTearDown(() => malloc.free(buffer));
      final known = _tokenOf(calls, vocab, 'a');
      expect(
        barrier.tokenToPiece(vocab, known, buffer, 64, 0, false),
        greaterThan(0),
      );
      expect(barrier.caughtException(), isNull);

      // llama.cpp throws std::out_of_range for a token outside the
      // vocabulary; without the barrier that ends the process.
      expect(
        barrier.tokenToPiece(vocab, LLAMA_TOKEN_NULL, buffer, 64, 0, false),
        _statusException,
      );
      expect(barrier.caughtException(), isNotEmpty);
      barrier.clearLastError();
      expect(barrier.caughtException(), isNull);

      // On Windows the vocabulary of a failed call is not used again.
      if (Platform.isWindows) return;
      barrier.tokenToPiece(vocab, LLAMA_TOKEN_NULL, buffer, 64, 0, false);
      expect(barrier.caughtException(), isNotEmpty);
      expect(
        barrier.tokenToPiece(vocab, known, buffer, 64, 0, false),
        greaterThan(0),
      );
      expect(barrier.caughtException(), isNull);
    });

    test('a token outside the vocabulary is a typed error that leaves the '
        'model usable', () {
      final vocab = llama_model_get_vocab(model);
      final buffer = malloc<Char>(64);
      addTearDown(() => malloc.free(buffer));

      expect(
        () => calls.tokenToPiece(vocab, LLAMA_TOKEN_NULL, buffer, 64, 0, false),
        throwsA(
          isA<LlamaInferenceException>()
              .having(
                (e) => e.message,
                'message',
                'llama.cpp raised an exception in llama_token_to_piece.',
              )
              .having((e) => e.details, 'details', isA<String>()),
        ),
      );
      if (Platform.isWindows) {
        expect(
          () => calls.failures.ensureUsable(vocab, 'This model'),
          throwsA(isA<LlamaStateException>()),
        );
        return;
      }
      calls.failures.ensureUsable(vocab, 'This model');
      expect(
        calls.tokenToPiece(
          vocab,
          _tokenOf(calls, vocab, 'a'),
          buffer,
          64,
          0,
          false,
        ),
        greaterThan(0),
      );
    });

    test('a trigger pattern that is not a regular expression is a typed '
        'error', () {
      final vocab = llama_model_get_vocab(model);
      final grammar = 'root ::= "a"'.toNativeUtf8();
      final root = 'root'.toNativeUtf8();
      final pattern = '('.toNativeUtf8();
      final patterns = malloc<Pointer<Char>>()..value = pattern.cast();
      addTearDown(() {
        malloc.free(grammar);
        malloc.free(root);
        malloc.free(pattern);
        malloc.free(patterns);
      });

      expect(
        () => calls.samplerInitGrammarLazyPatterns(
          vocab,
          grammar.cast(),
          root.cast(),
          patterns,
          1,
          nullptr,
          0,
        ),
        throwsA(
          isA<LlamaInferenceException>().having(
            (e) => e.message,
            'message',
            'llama.cpp raised an exception in '
                'llama_sampler_init_grammar_lazy_patterns.',
          ),
        ),
      );
    });

    test('a grammar that rejects an accepted token is a typed error', () {
      final vocab = llama_model_get_vocab(model);
      final grammar = 'root ::= "a"'.toNativeUtf8();
      final root = 'root'.toNativeUtf8();
      addTearDown(() {
        malloc.free(grammar);
        malloc.free(root);
      });
      final sampler = llama_sampler_init_grammar(
        vocab,
        grammar.cast(),
        root.cast(),
      );
      expect(sampler, isNot(nullptr));
      addTearDown(() => llama_sampler_free(sampler));
      final rejected = _tokenOf(calls, vocab, 'b');

      expect(
        () => calls.samplerAccept(sampler, rejected),
        throwsA(
          isA<LlamaInferenceException>()
              .having(
                (e) => e.message,
                'message',
                'llama.cpp raised an exception in llama_sampler_accept.',
              )
              .having(
                (e) => e.details,
                'details',
                contains('Unexpected empty grammar stack'),
              ),
        ),
      );
    });
  });

  group('NativeCallFailures', () {
    late FakeNativeBarrier fake;

    setUp(() => fake = FakeNativeBarrier());
    tearDown(() => fake.dispose());

    final context = Pointer<Void>.fromAddress(0x10);
    final model = Pointer<Void>.fromAddress(0x20);

    test('reports nothing without a barrier', () {
      final failures = NativeCallFailures(null, isWindows: true);

      failures.throwIfCaught(
        'llama_decode',
        LlamaInferenceException.new,
        freeOnly: [context],
        windowsFreeOnly: [model],
      );
      failures.ensureUsable(context, 'This context');
      failures.ensureUsable(model, 'This model');
    });

    test('reports nothing when the barrier caught nothing', () {
      final failures = NativeCallFailures(fake.api, isWindows: false);

      failures.throwIfCaught(
        'llama_decode',
        LlamaInferenceException.new,
        freeOnly: [context],
      );
      failures.ensureUsable(context, 'This context');
    });

    test('throws the typed error with the exception message as its '
        'details', () {
      final failures = NativeCallFailures(fake.api, isWindows: false);
      fake.catchException('Unexpected empty grammar stack');

      expect(
        () => failures.throwIfCaught('llama_decode', LlamaStateException.new),
        throwsA(
          isA<LlamaStateException>()
              .having(
                (e) => e.message,
                'message',
                'llama.cpp raised an exception in llama_decode.',
              )
              .having(
                (e) => e.details,
                'details',
                'Unexpected empty grammar stack',
              ),
        ),
      );
    });

    for (final isWindows in [false, true]) {
      test('leaves the objects of a failed call free-only '
          '(Windows rule: $isWindows)', () {
        final failures = NativeCallFailures(fake.api, isWindows: isWindows);
        fake.catchException();

        expect(
          () => failures.throwIfCaught(
            'llama_decode',
            LlamaInferenceException.new,
            freeOnly: [context, nullptr],
            windowsFreeOnly: [model],
          ),
          throwsA(isA<LlamaInferenceException>()),
        );

        expect(
          () => failures.ensureUsable(context, 'This context'),
          throwsA(
            isA<LlamaStateException>().having(
              (e) => e.message,
              'message',
              'This context is unusable after a llama.cpp exception in '
                  'llama_decode. Unload the model and load it again.',
            ),
          ),
        );
        failures.ensureUsable(nullptr, 'Nothing');
        if (isWindows) {
          expect(
            () => failures.ensureUsable(model, 'This model'),
            throwsA(isA<LlamaStateException>()),
          );
        } else {
          failures.ensureUsable(model, 'This model');
        }

        // A freed address can come back as a new object.
        failures.forget(context);
        failures.ensureUsable(context, 'This context');
      });
    }
  });
}

/// The token of the one-byte [text] in [vocab].
int _tokenOf(
  LlamaCppObjectCalls calls,
  Pointer<llama_vocab> vocab,
  String text,
) {
  final native = text.toNativeUtf8();
  final tokens = malloc<Int32>(4);
  try {
    final count = calls.tokenize(
      vocab,
      native.cast(),
      native.length,
      tokens,
      4,
      false,
      false,
    );
    expect(count, greaterThan(0));
    return tokens[count - 1];
  } finally {
    malloc.free(native);
    malloc.free(tokens);
  }
}

/// Stands in for a runtime's exports: one native function per name, each of
/// which records its name in [called] and returns zero.
final class _RecordingExports {
  final List<String> called = <String>[];

  late final Map<String, NativeCallable<Function>> _functions = {
    'llama_dart_last_error':
        NativeCallable<Pointer<Char> Function()>.isolateLocal(
          () => _record('llama_dart_last_error', nullptr.cast<Char>()),
        ),
    'llama_dart_clear_last_error': NativeCallable<Void Function()>.isolateLocal(
      () => _record('llama_dart_clear_last_error', null),
    ),
    'llama_dart_sampler_accept':
        NativeCallable<
          Bool Function(Pointer<llama_sampler>, Int32)
        >.isolateLocal(
          (Pointer<llama_sampler> _, int _) =>
              _record('llama_dart_sampler_accept', false),
          exceptionalReturn: false,
        ),
    'llama_dart_sampler_init_grammar_lazy_patterns':
        NativeCallable<
          Pointer<llama_sampler> Function(
            Pointer<llama_vocab>,
            Pointer<Char>,
            Pointer<Char>,
            Pointer<Pointer<Char>>,
            Size,
            Pointer<Int32>,
            Size,
          )
        >.isolateLocal(
          (
            Pointer<llama_vocab> _,
            Pointer<Char> _,
            Pointer<Char> _,
            Pointer<Pointer<Char>> _,
            int _,
            Pointer<Int32> _,
            int _,
          ) => _record(
            'llama_dart_sampler_init_grammar_lazy_patterns',
            nullptr.cast<llama_sampler>(),
          ),
        ),
    'llama_dart_tokenize':
        NativeCallable<
          Int32 Function(
            Pointer<llama_vocab>,
            Pointer<Char>,
            Int32,
            Pointer<Int32>,
            Int32,
            Bool,
            Bool,
          )
        >.isolateLocal(
          (
            Pointer<llama_vocab> _,
            Pointer<Char> _,
            int _,
            Pointer<Int32> _,
            int _,
            bool _,
            bool _,
          ) => _record('llama_dart_tokenize', 0),
          exceptionalReturn: 0,
        ),
    'llama_dart_token_to_piece':
        NativeCallable<
          Int32 Function(
            Pointer<llama_vocab>,
            Int32,
            Pointer<Char>,
            Int32,
            Int32,
            Bool,
          )
        >.isolateLocal(
          (
            Pointer<llama_vocab> _,
            int _,
            Pointer<Char> _,
            int _,
            int _,
            bool _,
          ) => _record('llama_dart_token_to_piece', 0),
          exceptionalReturn: 0,
        ),
    'llama_dart_memory_clear':
        NativeCallable<Bool Function(llama_memory_t, Bool)>.isolateLocal(
          (llama_memory_t _, bool _) =>
              _record('llama_dart_memory_clear', false),
          exceptionalReturn: false,
        ),
    'llama_dart_mtmd_bitmap_init_from_audio':
        NativeCallable<
          Pointer<mtmd_bitmap> Function(Size, Pointer<Float>)
        >.isolateLocal(
          (int _, Pointer<Float> _) => _record(
            'llama_dart_mtmd_bitmap_init_from_audio',
            nullptr.cast<mtmd_bitmap>(),
          ),
        ),
    'llama_dart_mtmd_bitmap_init_from_buf':
        NativeCallable<
          Pointer<mtmd_bitmap> Function(
            Pointer<mtmd_context>,
            Pointer<UnsignedChar>,
            Size,
          )
        >.isolateLocal(
          (Pointer<mtmd_context> _, Pointer<UnsignedChar> _, int _) => _record(
            'llama_dart_mtmd_bitmap_init_from_buf',
            nullptr.cast<mtmd_bitmap>(),
          ),
        ),
    'llama_dart_mtmd_bitmap_init_from_file':
        NativeCallable<
          Pointer<mtmd_bitmap> Function(Pointer<mtmd_context>, Pointer<Char>)
        >.isolateLocal(
          (Pointer<mtmd_context> _, Pointer<Char> _) => _record(
            'llama_dart_mtmd_bitmap_init_from_file',
            nullptr.cast<mtmd_bitmap>(),
          ),
        ),
    'llama_dart_ggml_backend_dev_init':
        NativeCallable<
          ggml_backend_t Function(ggml_backend_dev_t, Pointer<Char>)
        >.isolateLocal(
          (ggml_backend_dev_t _, Pointer<Char> _) => _record(
            'llama_dart_ggml_backend_dev_init',
            nullptr.cast<ggml_backend>(),
          ),
        ),
    'llama_dart_ggml_backend_dev_memory':
        NativeCallable<
          Bool Function(ggml_backend_dev_t, Pointer<Size>, Pointer<Size>)
        >.isolateLocal(
          (ggml_backend_dev_t _, Pointer<Size> _, Pointer<Size> _) =>
              _record('llama_dart_ggml_backend_dev_memory', false),
          exceptionalReturn: false,
        ),
    'llama_dart_ggml_backend_dev_get_props':
        NativeCallable<
          Bool Function(ggml_backend_dev_t, Pointer<ggml_backend_dev_props>)
        >.isolateLocal(
          (ggml_backend_dev_t _, Pointer<ggml_backend_dev_props> _) =>
              _record('llama_dart_ggml_backend_dev_get_props', false),
          exceptionalReturn: false,
        ),
    'llama_dart_ggml_backend_alloc_ctx_tensors':
        NativeCallable<
          ggml_backend_buffer_t Function(Pointer<ggml_context>, ggml_backend_t)
        >.isolateLocal(
          (Pointer<ggml_context> _, ggml_backend_t _) => _record(
            'llama_dart_ggml_backend_alloc_ctx_tensors',
            nullptr.cast<ggml_backend_buffer>(),
          ),
        ),
    for (final name in [
      'llama_dart_ggml_backend_tensor_set',
      'llama_dart_ggml_backend_tensor_get',
    ])
      name:
          NativeCallable<
            Bool Function(Pointer<ggml_tensor>, Pointer<Void>, Size, Size)
          >.isolateLocal(
            (Pointer<ggml_tensor> _, Pointer<Void> _, int _, int _) =>
                _record(name, false),
            exceptionalReturn: false,
          ),
    'llama_dart_ggml_backend_sched_alloc_graph':
        NativeCallable<
          Bool Function(ggml_backend_sched_t, Pointer<ggml_cgraph>)
        >.isolateLocal(
          (ggml_backend_sched_t _, Pointer<ggml_cgraph> _) =>
              _record('llama_dart_ggml_backend_sched_alloc_graph', false),
          exceptionalReturn: false,
        ),
    'llama_dart_ggml_backend_sched_synchronize':
        NativeCallable<Bool Function(ggml_backend_sched_t)>.isolateLocal(
          (ggml_backend_sched_t _) =>
              _record('llama_dart_ggml_backend_sched_synchronize', false),
          exceptionalReturn: false,
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
