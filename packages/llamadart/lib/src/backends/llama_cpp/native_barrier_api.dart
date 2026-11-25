import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../core/exceptions.dart';
import 'bindings.dart';

const _wrapperAsset = 'package:llamadart/llamadart_wrapper';

typedef _LastErrorNative = Pointer<Char> Function();
typedef _ClearLastErrorNative = Void Function();
typedef _SamplerAcceptNative =
    Bool Function(Pointer<llama_sampler>, llama_token);
typedef _GrammarLazyPatternsNative =
    Pointer<llama_sampler> Function(
      Pointer<llama_vocab>,
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Pointer<Char>>,
      Size,
      Pointer<llama_token>,
      Size,
    );
typedef _TokenizeNative =
    Int32 Function(
      Pointer<llama_vocab>,
      Pointer<Char>,
      Int32,
      Pointer<llama_token>,
      Int32,
      Bool,
      Bool,
    );
typedef _TokenToPieceNative =
    Int32 Function(
      Pointer<llama_vocab>,
      llama_token,
      Pointer<Char>,
      Int32,
      Int32,
      Bool,
    );
typedef _MemoryClearNative = Bool Function(llama_memory_t, Bool);
typedef _BitmapFromAudioNative =
    Pointer<mtmd_bitmap> Function(Size, Pointer<Float>);
typedef _BitmapFromBufNative =
    Pointer<mtmd_bitmap> Function(
      Pointer<mtmd_context>,
      Pointer<UnsignedChar>,
      Size,
    );
typedef _BitmapFromFileNative =
    Pointer<mtmd_bitmap> Function(Pointer<mtmd_context>, Pointer<Char>);
typedef _DevInitNative =
    ggml_backend_t Function(ggml_backend_dev_t, Pointer<Char>);
typedef _DevMemoryNative =
    Bool Function(ggml_backend_dev_t, Pointer<Size>, Pointer<Size>);
typedef _DevGetPropsNative =
    Bool Function(ggml_backend_dev_t, Pointer<ggml_backend_dev_props>);
typedef _AllocCtxTensorsNative =
    ggml_backend_buffer_t Function(Pointer<ggml_context>, ggml_backend_t);
typedef _TensorDataNative =
    Bool Function(Pointer<ggml_tensor>, Pointer<Void>, Size, Size);
typedef _SchedAllocGraphNative =
    Bool Function(ggml_backend_sched_t, Pointer<ggml_cgraph>);
typedef _SchedSynchronizeNative = Bool Function(ggml_backend_sched_t);

/// Builds the typed error of a native call that caught a C++ exception.
typedef NativeCallError =
    LlamaException Function(String message, [dynamic details]);

/// libllamadart's exception barrier, resolved from one library.
///
/// llama.cpp reports some failures by throwing a C++ exception, which ends
/// the process when it crosses the C ABI into Dart. From `llamadart-native`
/// [minimumNativeRelease] every `llama_dart_` function that calls llama.cpp
/// catches it, records its message for the calling thread and returns a
/// failure value. These are the functions that release adds: the message
/// accessors, and wrappers for the upstream functions the service used to
/// call directly and that throw.
///
/// Windows bundles export them from `llamadart.dll` rather than the default
/// `llama.dll` asset, so [tryResolve] resolves `@Native` declarations bound
/// to that asset on Windows. Elsewhere it resolves the generated bindings.
final class NativeBarrierApi {
  /// Creates an API from resolved functions.
  const NativeBarrierApi({
    required this.lastError,
    required this.clearLastError,
    required this.samplerAccept,
    required this.samplerInitGrammarLazyPatterns,
    required this.tokenize,
    required this.tokenToPiece,
    required this.memoryClear,
    required this.mtmdBitmapInitFromAudio,
    required this.mtmdBitmapInitFromBuf,
    required this.mtmdBitmapInitFromFile,
    required this.ggmlBackendDevInit,
    required this.ggmlBackendDevMemory,
    required this.ggmlBackendDevGetProps,
    required this.ggmlBackendAllocCtxTensors,
    required this.ggmlBackendTensorSet,
    required this.ggmlBackendTensorGet,
    required this.ggmlBackendSchedAllocGraph,
    required this.ggmlBackendSchedSynchronize,
  });

  /// The oldest `llamadart-native` release that exports these functions.
  static const String minimumNativeRelease = 'v0.6.0-1';

  /// Resolves every function from the loaded runtime, or returns `null` when
  /// it does not export all of them.
  ///
  /// [isWindows] selects the asset the functions are bound to. [symbol]
  /// replaces that lookup: it returns the address of the function exported
  /// under a name, and throws [ArgumentError] when there is none.
  static NativeBarrierApi? tryResolve({
    required bool isWindows,
    Pointer<NativeType> Function(String name)? symbol,
  }) {
    try {
      return NativeBarrierApi._fromSymbols(
        symbol ?? (name) => symbolAddress(name, isWindows: isWindows),
      );
    } on ArgumentError {
      return null;
    }
  }

  /// The address of the function the loaded runtime exports as [name], from
  /// the asset [isWindows] selects; throws [ArgumentError] when it exports
  /// none.
  static Pointer<NativeType> symbolAddress(
    String name, {
    required bool isWindows,
  }) => (isWindows ? _wrapperAssetSymbol : _bindingsSymbol)(name);

  // Every function is called through the address resolved here, so none can
  // be bound without being part of the probe.
  factory NativeBarrierApi._fromSymbols(
    Pointer<NativeType> Function(String name) symbol,
  ) {
    Pointer<NativeFunction<T>> function<T extends Function>(String name) =>
        symbol(name).cast();
    return NativeBarrierApi(
      lastError: function<_LastErrorNative>(
        'llama_dart_last_error',
      ).asFunction(),
      clearLastError: function<_ClearLastErrorNative>(
        'llama_dart_clear_last_error',
      ).asFunction(),
      samplerAccept: function<_SamplerAcceptNative>(
        'llama_dart_sampler_accept',
      ).asFunction(),
      samplerInitGrammarLazyPatterns: function<_GrammarLazyPatternsNative>(
        'llama_dart_sampler_init_grammar_lazy_patterns',
      ).asFunction(),
      tokenize: function<_TokenizeNative>('llama_dart_tokenize').asFunction(),
      tokenToPiece: function<_TokenToPieceNative>(
        'llama_dart_token_to_piece',
      ).asFunction(),
      memoryClear: function<_MemoryClearNative>(
        'llama_dart_memory_clear',
      ).asFunction(),
      mtmdBitmapInitFromAudio: function<_BitmapFromAudioNative>(
        'llama_dart_mtmd_bitmap_init_from_audio',
      ).asFunction(),
      mtmdBitmapInitFromBuf: function<_BitmapFromBufNative>(
        'llama_dart_mtmd_bitmap_init_from_buf',
      ).asFunction(),
      mtmdBitmapInitFromFile: function<_BitmapFromFileNative>(
        'llama_dart_mtmd_bitmap_init_from_file',
      ).asFunction(),
      ggmlBackendDevInit: function<_DevInitNative>(
        'llama_dart_ggml_backend_dev_init',
      ).asFunction(),
      ggmlBackendDevMemory: function<_DevMemoryNative>(
        'llama_dart_ggml_backend_dev_memory',
      ).asFunction(),
      ggmlBackendDevGetProps: function<_DevGetPropsNative>(
        'llama_dart_ggml_backend_dev_get_props',
      ).asFunction(),
      ggmlBackendAllocCtxTensors: function<_AllocCtxTensorsNative>(
        'llama_dart_ggml_backend_alloc_ctx_tensors',
      ).asFunction(),
      ggmlBackendTensorSet: function<_TensorDataNative>(
        'llama_dart_ggml_backend_tensor_set',
      ).asFunction(),
      ggmlBackendTensorGet: function<_TensorDataNative>(
        'llama_dart_ggml_backend_tensor_get',
      ).asFunction(),
      ggmlBackendSchedAllocGraph: function<_SchedAllocGraphNative>(
        'llama_dart_ggml_backend_sched_alloc_graph',
      ).asFunction(),
      ggmlBackendSchedSynchronize: function<_SchedSynchronizeNative>(
        'llama_dart_ggml_backend_sched_synchronize',
      ).asFunction(),
    );
  }

  /// `llama_dart_last_error`: the message of the exception the calling
  /// thread's last call with a barrier caught, or `nullptr`.
  final Pointer<Char> Function() lastError;

  /// `llama_dart_clear_last_error`.
  final void Function() clearLastError;

  /// `llama_dart_sampler_accept`; `false` after a caught exception.
  final bool Function(Pointer<llama_sampler> sampler, int token) samplerAccept;

  /// `llama_dart_sampler_init_grammar_lazy_patterns`; `nullptr` after a
  /// caught exception and for a grammar that does not parse.
  final Pointer<llama_sampler> Function(
    Pointer<llama_vocab> vocab,
    Pointer<Char> grammar,
    Pointer<Char> grammarRoot,
    Pointer<Pointer<Char>> triggerPatterns,
    int triggerPatternCount,
    Pointer<llama_token> triggerTokens,
    int triggerTokenCount,
  )
  samplerInitGrammarLazyPatterns;

  /// `llama_dart_tokenize`; `LLAMA_DART_STATUS_EXCEPTION` after a caught
  /// exception.
  final int Function(
    Pointer<llama_vocab> vocab,
    Pointer<Char> text,
    int textLength,
    Pointer<llama_token> tokens,
    int tokenCapacity,
    bool addSpecial,
    bool parseSpecial,
  )
  tokenize;

  /// `llama_dart_token_to_piece`; `LLAMA_DART_STATUS_EXCEPTION` after a
  /// caught exception.
  final int Function(
    Pointer<llama_vocab> vocab,
    int token,
    Pointer<Char> buffer,
    int length,
    int lstrip,
    bool special,
  )
  tokenToPiece;

  /// `llama_dart_memory_clear`; `false` after a caught exception.
  final bool Function(llama_memory_t memory, bool data) memoryClear;

  /// `llama_dart_mtmd_bitmap_init_from_audio`.
  final Pointer<mtmd_bitmap> Function(int sampleCount, Pointer<Float> samples)
  mtmdBitmapInitFromAudio;

  /// `llama_dart_mtmd_bitmap_init_from_buf`.
  final Pointer<mtmd_bitmap> Function(
    Pointer<mtmd_context> ctx,
    Pointer<UnsignedChar> data,
    int length,
  )
  mtmdBitmapInitFromBuf;

  /// `llama_dart_mtmd_bitmap_init_from_file`.
  final Pointer<mtmd_bitmap> Function(
    Pointer<mtmd_context> ctx,
    Pointer<Char> path,
  )
  mtmdBitmapInitFromFile;

  /// `llama_dart_ggml_backend_dev_init`.
  final ggml_backend_t Function(ggml_backend_dev_t device, Pointer<Char> params)
  ggmlBackendDevInit;

  /// `llama_dart_ggml_backend_dev_memory`; `false` with both outputs zero
  /// after a caught exception.
  final bool Function(
    ggml_backend_dev_t device,
    Pointer<Size> free,
    Pointer<Size> total,
  )
  ggmlBackendDevMemory;

  /// `llama_dart_ggml_backend_dev_get_props`; `false` with the properties
  /// zeroed after a caught exception.
  final bool Function(
    ggml_backend_dev_t device,
    Pointer<ggml_backend_dev_props> props,
  )
  ggmlBackendDevGetProps;

  /// `llama_dart_ggml_backend_alloc_ctx_tensors`.
  final ggml_backend_buffer_t Function(
    Pointer<ggml_context> ctx,
    ggml_backend_t backend,
  )
  ggmlBackendAllocCtxTensors;

  /// `llama_dart_ggml_backend_tensor_set`; `false` after a caught exception.
  final bool Function(
    Pointer<ggml_tensor> tensor,
    Pointer<Void> data,
    int offset,
    int size,
  )
  ggmlBackendTensorSet;

  /// `llama_dart_ggml_backend_tensor_get`; `false` after a caught exception.
  final bool Function(
    Pointer<ggml_tensor> tensor,
    Pointer<Void> data,
    int offset,
    int size,
  )
  ggmlBackendTensorGet;

  /// `llama_dart_ggml_backend_sched_alloc_graph`.
  final bool Function(ggml_backend_sched_t sched, Pointer<ggml_cgraph> graph)
  ggmlBackendSchedAllocGraph;

  /// `llama_dart_ggml_backend_sched_synchronize`; `false` after a caught
  /// exception.
  final bool Function(ggml_backend_sched_t sched) ggmlBackendSchedSynchronize;

  /// The message of the C++ exception the calling thread's last call with a
  /// barrier caught, or `null` when it caught none.
  ///
  /// The message is per thread, so read it in the same synchronous run as
  /// the call: an isolate can resume on another thread after an `await`.
  String? caughtException() {
    final message = lastError();
    return message == nullptr ? null : message.cast<Utf8>().toDartString();
  }
}

/// Turns the C++ exceptions libllamadart catches into typed errors, and
/// remembers which native objects a failed call left only fit to be freed.
///
/// The native contract (`src/llama_dart_wrapper.h` in `llamadart-native`)
/// leaves a llama or mtmd context in no defined state after a call on it
/// caught an exception. On Windows that holds for every object of the call:
/// llama.cpp's own libraries assume their `extern "C"` functions never throw,
/// so an unwinding exception can skip their cleanups.
final class NativeCallFailures {
  /// Reads caught exceptions from [barrier]; without one, nothing is ever
  /// reported.
  NativeCallFailures(this.barrier, {required this.isWindows});

  /// The exception barrier, or `null` on a runtime older than
  /// [NativeBarrierApi.minimumNativeRelease].
  final NativeBarrierApi? barrier;

  /// Whether the Windows rule applies: every object of a failed call is
  /// free-only.
  final bool isWindows;

  final Map<int, String> _freeOnly = <int, String>{};

  /// Throws the [error] of the barrier call [call] when that call, which has
  /// just returned on this thread, caught a C++ exception.
  ///
  /// The error's details are the exception's message as libllamadart recorded
  /// it. [freeOnly] names the objects the failure leaves free-only on every
  /// platform, [windowsFreeOnly] the ones only the Windows rule adds.
  void throwIfCaught(
    String call,
    NativeCallError error, {
    List<Pointer<NativeType>> freeOnly = const [],
    List<Pointer<NativeType>> windowsFreeOnly = const [],
  }) {
    final message = barrier?.caughtException();
    if (message == null) return;
    for (final object in [...freeOnly, if (isWindows) ...windowsFreeOnly]) {
      if (object != nullptr) _freeOnly[object.address] = call;
    }
    throw error('llama.cpp raised an exception in $call.', message);
  }

  /// Throws [LlamaStateException] when a failed call left [object], described
  /// as [what], free-only.
  void ensureUsable(Pointer<NativeType> object, String what) {
    final call = _freeOnly[object.address];
    if (call == null) return;
    throw LlamaStateException(
      '$what is unusable after a llama.cpp exception in $call. Unload the '
      'model and load it again.',
    );
  }

  /// Forgets [object], which is about to be freed: its address may be reused.
  void forget(Pointer<NativeType> object) => _freeOnly.remove(object.address);
}

Pointer<NativeType> _bindingsSymbol(String symbol) => switch (symbol) {
  'llama_dart_last_error' => Native.addressOf<NativeFunction<_LastErrorNative>>(
    llama_dart_last_error,
  ),
  'llama_dart_clear_last_error' =>
    Native.addressOf<NativeFunction<_ClearLastErrorNative>>(
      llama_dart_clear_last_error,
    ),
  'llama_dart_sampler_accept' =>
    Native.addressOf<NativeFunction<_SamplerAcceptNative>>(
      llama_dart_sampler_accept,
    ),
  'llama_dart_sampler_init_grammar_lazy_patterns' =>
    Native.addressOf<NativeFunction<_GrammarLazyPatternsNative>>(
      llama_dart_sampler_init_grammar_lazy_patterns,
    ),
  'llama_dart_tokenize' => Native.addressOf<NativeFunction<_TokenizeNative>>(
    llama_dart_tokenize,
  ),
  'llama_dart_token_to_piece' =>
    Native.addressOf<NativeFunction<_TokenToPieceNative>>(
      llama_dart_token_to_piece,
    ),
  'llama_dart_memory_clear' =>
    Native.addressOf<NativeFunction<_MemoryClearNative>>(
      llama_dart_memory_clear,
    ),
  'llama_dart_mtmd_bitmap_init_from_audio' =>
    Native.addressOf<NativeFunction<_BitmapFromAudioNative>>(
      llama_dart_mtmd_bitmap_init_from_audio,
    ),
  'llama_dart_mtmd_bitmap_init_from_buf' =>
    Native.addressOf<NativeFunction<_BitmapFromBufNative>>(
      llama_dart_mtmd_bitmap_init_from_buf,
    ),
  'llama_dart_mtmd_bitmap_init_from_file' =>
    Native.addressOf<NativeFunction<_BitmapFromFileNative>>(
      llama_dart_mtmd_bitmap_init_from_file,
    ),
  'llama_dart_ggml_backend_dev_init' =>
    Native.addressOf<NativeFunction<_DevInitNative>>(
      llama_dart_ggml_backend_dev_init,
    ),
  'llama_dart_ggml_backend_dev_memory' =>
    Native.addressOf<NativeFunction<_DevMemoryNative>>(
      llama_dart_ggml_backend_dev_memory,
    ),
  'llama_dart_ggml_backend_dev_get_props' =>
    Native.addressOf<NativeFunction<_DevGetPropsNative>>(
      llama_dart_ggml_backend_dev_get_props,
    ),
  'llama_dart_ggml_backend_alloc_ctx_tensors' =>
    Native.addressOf<NativeFunction<_AllocCtxTensorsNative>>(
      llama_dart_ggml_backend_alloc_ctx_tensors,
    ),
  'llama_dart_ggml_backend_tensor_set' =>
    Native.addressOf<NativeFunction<_TensorDataNative>>(
      llama_dart_ggml_backend_tensor_set,
    ),
  'llama_dart_ggml_backend_tensor_get' =>
    Native.addressOf<NativeFunction<_TensorDataNative>>(
      llama_dart_ggml_backend_tensor_get,
    ),
  'llama_dart_ggml_backend_sched_alloc_graph' =>
    Native.addressOf<NativeFunction<_SchedAllocGraphNative>>(
      llama_dart_ggml_backend_sched_alloc_graph,
    ),
  'llama_dart_ggml_backend_sched_synchronize' =>
    Native.addressOf<NativeFunction<_SchedSynchronizeNative>>(
      llama_dart_ggml_backend_sched_synchronize,
    ),
  _ => throw ArgumentError.value(symbol, 'symbol', 'not bound'),
};

Pointer<NativeType> _wrapperAssetSymbol(String symbol) => switch (symbol) {
  'llama_dart_last_error' => Native.addressOf<NativeFunction<_LastErrorNative>>(
    _wrapperLastError,
  ),
  'llama_dart_clear_last_error' =>
    Native.addressOf<NativeFunction<_ClearLastErrorNative>>(
      _wrapperClearLastError,
    ),
  'llama_dart_sampler_accept' =>
    Native.addressOf<NativeFunction<_SamplerAcceptNative>>(
      _wrapperSamplerAccept,
    ),
  'llama_dart_sampler_init_grammar_lazy_patterns' =>
    Native.addressOf<NativeFunction<_GrammarLazyPatternsNative>>(
      _wrapperGrammarLazyPatterns,
    ),
  'llama_dart_tokenize' => Native.addressOf<NativeFunction<_TokenizeNative>>(
    _wrapperTokenize,
  ),
  'llama_dart_token_to_piece' =>
    Native.addressOf<NativeFunction<_TokenToPieceNative>>(_wrapperTokenToPiece),
  'llama_dart_memory_clear' =>
    Native.addressOf<NativeFunction<_MemoryClearNative>>(_wrapperMemoryClear),
  'llama_dart_mtmd_bitmap_init_from_audio' =>
    Native.addressOf<NativeFunction<_BitmapFromAudioNative>>(
      _wrapperBitmapFromAudio,
    ),
  'llama_dart_mtmd_bitmap_init_from_buf' =>
    Native.addressOf<NativeFunction<_BitmapFromBufNative>>(
      _wrapperBitmapFromBuf,
    ),
  'llama_dart_mtmd_bitmap_init_from_file' =>
    Native.addressOf<NativeFunction<_BitmapFromFileNative>>(
      _wrapperBitmapFromFile,
    ),
  'llama_dart_ggml_backend_dev_init' =>
    Native.addressOf<NativeFunction<_DevInitNative>>(_wrapperDevInit),
  'llama_dart_ggml_backend_dev_memory' =>
    Native.addressOf<NativeFunction<_DevMemoryNative>>(_wrapperDevMemory),
  'llama_dart_ggml_backend_dev_get_props' =>
    Native.addressOf<NativeFunction<_DevGetPropsNative>>(_wrapperDevGetProps),
  'llama_dart_ggml_backend_alloc_ctx_tensors' =>
    Native.addressOf<NativeFunction<_AllocCtxTensorsNative>>(
      _wrapperAllocCtxTensors,
    ),
  'llama_dart_ggml_backend_tensor_set' =>
    Native.addressOf<NativeFunction<_TensorDataNative>>(_wrapperTensorSet),
  'llama_dart_ggml_backend_tensor_get' =>
    Native.addressOf<NativeFunction<_TensorDataNative>>(_wrapperTensorGet),
  'llama_dart_ggml_backend_sched_alloc_graph' =>
    Native.addressOf<NativeFunction<_SchedAllocGraphNative>>(
      _wrapperSchedAllocGraph,
    ),
  'llama_dart_ggml_backend_sched_synchronize' =>
    Native.addressOf<NativeFunction<_SchedSynchronizeNative>>(
      _wrapperSchedSynchronize,
    ),
  _ => throw ArgumentError.value(symbol, 'symbol', 'not bound'),
};

@Native<_LastErrorNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_last_error',
)
external Pointer<Char> _wrapperLastError();

@Native<_ClearLastErrorNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_clear_last_error',
)
external void _wrapperClearLastError();

@Native<_SamplerAcceptNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_sampler_accept',
)
external bool _wrapperSamplerAccept(Pointer<llama_sampler> sampler, int token);

@Native<_GrammarLazyPatternsNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_sampler_init_grammar_lazy_patterns',
)
external Pointer<llama_sampler> _wrapperGrammarLazyPatterns(
  Pointer<llama_vocab> vocab,
  Pointer<Char> grammar,
  Pointer<Char> grammarRoot,
  Pointer<Pointer<Char>> triggerPatterns,
  int triggerPatternCount,
  Pointer<llama_token> triggerTokens,
  int triggerTokenCount,
);

@Native<_TokenizeNative>(assetId: _wrapperAsset, symbol: 'llama_dart_tokenize')
external int _wrapperTokenize(
  Pointer<llama_vocab> vocab,
  Pointer<Char> text,
  int textLength,
  Pointer<llama_token> tokens,
  int tokenCapacity,
  bool addSpecial,
  bool parseSpecial,
);

@Native<_TokenToPieceNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_token_to_piece',
)
external int _wrapperTokenToPiece(
  Pointer<llama_vocab> vocab,
  int token,
  Pointer<Char> buffer,
  int length,
  int lstrip,
  bool special,
);

@Native<_MemoryClearNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_memory_clear',
)
external bool _wrapperMemoryClear(llama_memory_t memory, bool data);

@Native<_BitmapFromAudioNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_mtmd_bitmap_init_from_audio',
)
external Pointer<mtmd_bitmap> _wrapperBitmapFromAudio(
  int sampleCount,
  Pointer<Float> samples,
);

@Native<_BitmapFromBufNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_mtmd_bitmap_init_from_buf',
)
external Pointer<mtmd_bitmap> _wrapperBitmapFromBuf(
  Pointer<mtmd_context> ctx,
  Pointer<UnsignedChar> data,
  int length,
);

@Native<_BitmapFromFileNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_mtmd_bitmap_init_from_file',
)
external Pointer<mtmd_bitmap> _wrapperBitmapFromFile(
  Pointer<mtmd_context> ctx,
  Pointer<Char> path,
);

@Native<_DevInitNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_ggml_backend_dev_init',
)
external ggml_backend_t _wrapperDevInit(
  ggml_backend_dev_t device,
  Pointer<Char> params,
);

@Native<_DevMemoryNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_ggml_backend_dev_memory',
)
external bool _wrapperDevMemory(
  ggml_backend_dev_t device,
  Pointer<Size> free,
  Pointer<Size> total,
);

@Native<_DevGetPropsNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_ggml_backend_dev_get_props',
)
external bool _wrapperDevGetProps(
  ggml_backend_dev_t device,
  Pointer<ggml_backend_dev_props> props,
);

@Native<_AllocCtxTensorsNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_ggml_backend_alloc_ctx_tensors',
)
external ggml_backend_buffer_t _wrapperAllocCtxTensors(
  Pointer<ggml_context> ctx,
  ggml_backend_t backend,
);

@Native<_TensorDataNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_ggml_backend_tensor_set',
)
external bool _wrapperTensorSet(
  Pointer<ggml_tensor> tensor,
  Pointer<Void> data,
  int offset,
  int size,
);

@Native<_TensorDataNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_ggml_backend_tensor_get',
)
external bool _wrapperTensorGet(
  Pointer<ggml_tensor> tensor,
  Pointer<Void> data,
  int offset,
  int size,
);

@Native<_SchedAllocGraphNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_ggml_backend_sched_alloc_graph',
)
external bool _wrapperSchedAllocGraph(
  ggml_backend_sched_t sched,
  Pointer<ggml_cgraph> graph,
);

@Native<_SchedSynchronizeNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_ggml_backend_sched_synchronize',
)
external bool _wrapperSchedSynchronize(ggml_backend_sched_t sched);
