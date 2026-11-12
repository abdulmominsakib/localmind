import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/native_barrier_api.dart';

/// A [NativeBarrierApi] that stands in for libllamadart's exception barrier.
///
/// Every function records its native name in [calls] and clears the last
/// error, as a function with a barrier does. A name in [throwing] then
/// "catches an exception": the function sets the last error to [message] and
/// returns its failure value. A name in [failing] returns the failure value
/// without an exception. Other calls go on to [real], or without one succeed
/// with [object], `true` or [count].
final class FakeNativeBarrier {
  /// Fails the calls named in [throwing] and [failing]; the others go on to
  /// [real].
  FakeNativeBarrier({this.real});

  /// The functions that do the work of a call that does not fail.
  final NativeBarrierApi? real;

  /// Native names of the functions that catch an exception.
  final Set<String> throwing = <String>{};

  /// Native names of the functions that fail without an exception.
  final Set<String> failing = <String>{};

  /// The message of the exception a [throwing] function catches.
  String message = 'fake exception';

  /// What `llama_dart_tokenize` and `llama_dart_token_to_piece` return when
  /// they succeed without [real].
  int count = 0;

  /// Native names of the calls made so far, in order.
  final List<String> calls = <String>[];

  /// The pointer the creating functions return when they succeed without
  /// [real].
  static final Pointer<Void> object = Pointer.fromAddress(0x7000);

  static const int _statusException = -2147483648;

  Pointer<Utf8> _lastError = nullptr;

  /// Sets the last error to [message], as a function of another API that
  /// has a barrier does when it catches an exception.
  void catchException([String? message]) {
    clear();
    _lastError = (message ?? this.message).toNativeUtf8();
  }

  /// Clears the last error, as a function with a barrier does on entry.
  void clear() {
    if (_lastError != nullptr) malloc.free(_lastError);
    _lastError = nullptr;
    real?.clearLastError();
  }

  /// Frees the last error.
  void dispose() => clear();

  bool _succeeds(String name) {
    calls.add(name);
    clear();
    if (throwing.contains(name)) {
      catchException();
      return false;
    }
    return !failing.contains(name);
  }

  /// The fake functions.
  late final NativeBarrierApi api = NativeBarrierApi(
    lastError: () => _lastError != nullptr
        ? _lastError.cast()
        : real?.lastError() ?? nullptr,
    clearLastError: clear,
    samplerAccept: (sampler, token) =>
        _succeeds('llama_dart_sampler_accept') &&
        (real?.samplerAccept(sampler, token) ?? true),
    samplerInitGrammarLazyPatterns:
        (
          vocab,
          grammar,
          grammarRoot,
          triggerPatterns,
          triggerPatternCount,
          triggerTokens,
          triggerTokenCount,
        ) => !_succeeds('llama_dart_sampler_init_grammar_lazy_patterns')
        ? nullptr
        : real?.samplerInitGrammarLazyPatterns(
                vocab,
                grammar,
                grammarRoot,
                triggerPatterns,
                triggerPatternCount,
                triggerTokens,
                triggerTokenCount,
              ) ??
              object.cast(),
    tokenize:
        (
          vocab,
          text,
          textLength,
          tokens,
          tokenCapacity,
          addSpecial,
          parseSpecial,
        ) => !_succeeds('llama_dart_tokenize')
        ? _statusException
        : real?.tokenize(
                vocab,
                text,
                textLength,
                tokens,
                tokenCapacity,
                addSpecial,
                parseSpecial,
              ) ??
              count,
    tokenToPiece: (vocab, token, buffer, length, lstrip, special) =>
        !_succeeds('llama_dart_token_to_piece')
        ? _statusException
        : real?.tokenToPiece(vocab, token, buffer, length, lstrip, special) ??
              count,
    memoryClear: (memory, data) =>
        _succeeds('llama_dart_memory_clear') &&
        (real?.memoryClear(memory, data) ?? true),
    mtmdBitmapInitFromAudio: (sampleCount, samples) =>
        _succeeds('llama_dart_mtmd_bitmap_init_from_audio')
        ? object.cast()
        : nullptr,
    mtmdBitmapInitFromBuf: (ctx, data, length) =>
        _succeeds('llama_dart_mtmd_bitmap_init_from_buf')
        ? object.cast()
        : nullptr,
    mtmdBitmapInitFromFile: (ctx, path) =>
        _succeeds('llama_dart_mtmd_bitmap_init_from_file')
        ? object.cast()
        : nullptr,
    ggmlBackendDevInit: (device, params) =>
        !_succeeds('llama_dart_ggml_backend_dev_init')
        ? nullptr
        : real?.ggmlBackendDevInit(device, params) ?? object.cast(),
    ggmlBackendDevMemory: (device, free, total) =>
        _succeeds('llama_dart_ggml_backend_dev_memory') &&
        (real?.ggmlBackendDevMemory(device, free, total) ?? true),
    ggmlBackendDevGetProps: (device, props) =>
        _succeeds('llama_dart_ggml_backend_dev_get_props') &&
        (real?.ggmlBackendDevGetProps(device, props) ?? true),
    ggmlBackendAllocCtxTensors: (ctx, backend) =>
        !_succeeds('llama_dart_ggml_backend_alloc_ctx_tensors')
        ? nullptr
        : real?.ggmlBackendAllocCtxTensors(ctx, backend) ?? object.cast(),
    ggmlBackendTensorSet: (tensor, data, offset, size) =>
        _succeeds('llama_dart_ggml_backend_tensor_set') &&
        (real?.ggmlBackendTensorSet(tensor, data, offset, size) ?? true),
    ggmlBackendTensorGet: (tensor, data, offset, size) =>
        _succeeds('llama_dart_ggml_backend_tensor_get') &&
        (real?.ggmlBackendTensorGet(tensor, data, offset, size) ?? true),
    ggmlBackendSchedAllocGraph: (sched, graph) =>
        _succeeds('llama_dart_ggml_backend_sched_alloc_graph') &&
        (real?.ggmlBackendSchedAllocGraph(sched, graph) ?? true),
    ggmlBackendSchedSynchronize: (sched) =>
        _succeeds('llama_dart_ggml_backend_sched_synchronize') &&
        (real?.ggmlBackendSchedSynchronize(sched) ?? true),
  );
}
