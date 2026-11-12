part of 'litert_lm_runtime.dart';

/// Embedding dispatch through the same selected ABI as text and ASR.
extension LiteRtLmEmbeddingRuntime on LiteRtLmRuntimeClient {
  /// Creates an owned session using the selected native runtime.
  Future<LiteRtLmEmbeddingSession> createEmbeddingSession({
    required String modelPath,
    required String backend,
    required String cacheDir,
    required int maxInputLength,
    required int numberOfThreads,
  }) async {
    if (this is _LegacyLiteRtLmRuntimeClient) {
      return _LegacyLiteRtLmEmbeddingRuntime(
        this as _LegacyLiteRtLmRuntimeClient,
      ).createEmbeddingSession(
        modelPath: modelPath,
        backend: backend,
        cacheDir: cacheDir,
        maxInputLength: maxInputLength,
        numberOfThreads: numberOfThreads,
      );
    }
    final session = await _runtime.createEmbeddingSession(
      modelPath: modelPath,
      backend: backend,
      cacheDir: cacheDir,
      maxInputLength: maxInputLength,
      numberOfThreads: numberOfThreads,
    );
    if (session is LiteRtLmEmbeddingSession) return session;
    return _SelectedLiteRtLmEmbeddingSession(session, _libraryOwner!);
  }
}

final class _SelectedLiteRtLmEmbeddingSession extends LiteRtLmEmbeddingSession {
  _SelectedLiteRtLmEmbeddingSession(this._session, this._owner)
    : super(
        _owner._liteRtLmLibraryPath!,
        _owner._liteRtLmCompanionLibraryPaths,
        0,
        _session.capabilities,
      );
  final LiteRtLmEmbeddingRuntimeSession _session;
  final _LegacyLiteRtLmRuntimeClient _owner;
  @override
  Future<List<double>> compute(
    List<LiteRtLmEmbeddingPart> input, {
    required bool normalize,
    Allocator inputAllocator = calloc,
  }) => _session.compute(input, normalize: normalize);
  @override
  void dispose() {
    _session.dispose();
    _keepAlive(_owner);
  }
}

/// Internal embedding-engine integration, sharing the runtime's library loader.
extension _LegacyLiteRtLmEmbeddingRuntime on _LegacyLiteRtLmRuntimeClient {
  /// Creates processors only for actual embedding bundle sections.
  Future<LiteRtLmEmbeddingSession> createEmbeddingSession({
    required String modelPath,
    required String backend,
    required String cacheDir,
    required int maxInputLength,
    required int numberOfThreads,
  }) async {
    liteRtLmEnsureLegacyNativeEmbeddingsQualified();
    ensureLiteRtLmNativeEmbeddingBackend(backend);
    _ensureLibrariesLoaded();
    final file = File(modelPath).openSync();
    late LlamaEmbeddingCapabilities declared;
    try {
      final prefix = file.readSync(32);
      if (prefix.length != 32) {
        throw LlamaUnsupportedException(
          'LiteRT-LM embedding bundle header is unavailable.',
        );
      }
      final end = ByteData.sublistView(prefix).getUint64(24, Endian.little);
      if (end <= 32 || end > 16 * 1024 * 1024) {
        throw LlamaUnsupportedException(
          'LiteRT-LM embedding bundle header is unsupported.',
        );
      }
      declared = liteRtLmEmbeddingBundleCapabilities(
        Uint8List.fromList([...prefix, ...file.readSync(end - 32)]),
      );
    } finally {
      file.closeSync();
    }
    if (!declared.text) {
      throw LlamaUnsupportedException(
        'LiteRT-LM embedding loading requires bundle text-encoder and embedder sections.',
      );
    }
    final library = _liteRtLmLibraryPath!;
    final companions = _liteRtLmCompanionLibraryPaths;
    final address = await Isolate.run(
      () => _createEmbeddingEngine(
        library,
        companions,
        modelPath,
        backend,
        cacheDir,
        maxInputLength,
        numberOfThreads,
        declared,
      ),
    );
    return LiteRtLmEmbeddingSession(library, companions, address, declared);
  }
}

int _createEmbeddingEngine(
  String library,
  List<String> companions,
  String modelPath,
  String backend,
  String cacheDir,
  int maxInputLength,
  int threads,
  LlamaEmbeddingCapabilities capabilities,
) {
  final keep = liteRtLmOpenCompanionLibraries(companions);
  final lib = _openLiteRtLmLibraryCandidate(library);
  // Probe the complete required group before allocating any native object.
  const required = [
    'engine_settings_create',
    'engine_settings_delete',
    'engine_settings_set_cache_dir',
    'engine_settings_set_max_input_length',
    'engine_settings_set_num_threads',
    'engine_create',
    'engine_delete',
    'engine_compute_embedding',
    'options_create',
    'options_delete',
    'options_set_normalize',
    'options_set_input_overflow_strategy',
    'response_delete',
    'response_get_size',
    'response_get_values',
  ];
  for (final suffix in required) {
    if (!lib.providesSymbol('litert_lm_embedding_$suffix')) {
      throw LlamaUnsupportedException(
        'LiteRT-LM embedding engines require the v0.18.0 single-input embedding C API.',
      );
    }
  }
  for (final suffix in ['create', 'delete']) {
    if (!lib.providesSymbol('litert_lm_input_data_$suffix')) {
      throw LlamaUnsupportedException(
        'LiteRT-LM embedding input C API is missing.',
      );
    }
  }
  final api = emb.LiteRtLmEmbeddingBindings(lib);
  final strings = [
    modelPath,
    backend,
    cacheDir,
    'cpu',
  ].map((s) => s.toNativeUtf8(allocator: calloc)).toList();
  Pointer<emb.LiteRtLmEmbeddingEngineSettings> settings = nullptr;
  try {
    settings = api.litert_lm_embedding_engine_settings_create(
      strings[0].cast(),
      strings[1].cast(),
      capabilities.image ? strings[3].cast() : nullptr,
      capabilities.audio ? strings[3].cast() : nullptr,
    );
    if (settings == nullptr) {
      throw LlamaModelException(
        'LiteRT-LM embedding settings creation failed.',
      );
    }
    api.litert_lm_embedding_engine_settings_set_cache_dir(
      settings,
      strings[2].cast(),
    );
    api.litert_lm_embedding_engine_settings_set_max_input_length(
      settings,
      maxInputLength,
    );
    if (threads > 0) {
      api.litert_lm_embedding_engine_settings_set_num_threads(
        settings,
        threads,
      );
    }
    final engine = api.litert_lm_embedding_engine_create(settings);
    if (engine == nullptr) {
      throw LlamaUnsupportedException(
        'LiteRT-LM v0.18 embedding engine or required processor could not start on the selected backend; try CPU and a writable cache directory.',
      );
    }
    return engine.address;
  } finally {
    if (settings != nullptr) {
      api.litert_lm_embedding_engine_settings_delete(settings);
    }
    for (final s in strings) {
      calloc.free(s);
    }
    _keepAlive(keep);
  }
}

/// Owns an embedding engine; callers serialize operations and await settlement.
class LiteRtLmEmbeddingSession implements LiteRtLmEmbeddingRuntimeSession {
  /// Loaded runtime path.
  final String library;

  /// Companion library paths retained during every native call.
  final List<String> companions;

  /// Processor-backed modalities of the loaded bundle.
  @override
  final LlamaEmbeddingCapabilities capabilities;
  int _address;

  /// Creates an internal owned session.
  LiteRtLmEmbeddingSession(
    this.library,
    this.companions,
    this._address,
    this.capabilities,
  );

  /// Copies one vector before deleting its native response; cancellation waits for this call.
  /// [inputAllocator] substitutes temporary allocations for VM ownership tests.
  @override
  Future<List<double>> compute(
    List<LiteRtLmEmbeddingPart> input, {
    required bool normalize,
    Allocator inputAllocator = calloc,
  }) {
    final address = _address;
    if (address == 0) {
      throw LlamaStateException('LiteRT-LM embedding engine is disposed.');
    }
    final runtime = library, libs = companions;
    return Isolate.run(
      () => _computeEmbedding(
        runtime,
        libs,
        address,
        input,
        normalize,
        inputAllocator,
      ),
    );
  }

  /// Deletes the settled engine exactly once.
  @override
  void dispose() {
    if (_address == 0) {
      return;
    }
    emb.LiteRtLmEmbeddingBindings(
      _openLiteRtLmLibraryCandidate(library),
    ).litert_lm_embedding_engine_delete(Pointer.fromAddress(_address));
    _address = 0;
  }
}

List<double> _computeEmbedding(
  String library,
  List<String> companions,
  int address,
  List<LiteRtLmEmbeddingPart> input,
  bool normalize,
  Allocator calloc,
) {
  final keep = liteRtLmOpenCompanionLibraries(companions);
  final api = emb.LiteRtLmEmbeddingBindings(
    _openLiteRtLmLibraryCandidate(library),
  );
  final engine = Pointer<emb.LiteRtLmEmbeddingEngine>.fromAddress(address);
  final options = api.litert_lm_embedding_options_create();
  if (options == nullptr) {
    throw LlamaInferenceException(
      'LiteRT-LM embedding options allocation failed.',
    );
  }
  final data = calloc<Pointer<emb.LiteRtLmInputData>>(input.length);
  final allocated = <Pointer<emb.LiteRtLmInputData>>[];
  List<double> vector(Pointer<emb.LiteRtLmEmbeddingResponse> response) {
    if (response == nullptr) {
      throw LlamaInferenceException(
        'LiteRT-LM embedding failed (input capacity or runtime execution).',
      );
    }
    final size = api.litert_lm_embedding_response_get_size(response);
    final values = api.litert_lm_embedding_response_get_values(response);
    if (size == 0 || values == nullptr) {
      throw LlamaInferenceException('LiteRT-LM returned an empty embedding.');
    }
    final result = List<double>.of(values.asTypedList(size));
    if (result.any((v) => !v.isFinite)) {
      throw LlamaInferenceException(
        'LiteRT-LM returned a nonfinite embedding.',
      );
    }
    return result;
  }

  try {
    api.litert_lm_embedding_options_set_normalize(options, normalize);
    api.litert_lm_embedding_options_set_input_overflow_strategy(
      options,
      emb.LiteRtLmInputOverflowStrategy.kLiteRtLmInputOverflowStrategyError,
    );
    for (var i = 0; i < input.length; i++) {
      final part = input[i];
      final bytes = calloc<Uint8>(part.bytes.length + 1);
      try {
        bytes.asTypedList(part.bytes.length).setAll(0, part.bytes);
        final partData = api.litert_lm_input_data_create(
          emb.LiteRtLmInputDataType.fromValue(part.type),
          bytes.cast(),
          part.bytes.length,
        );
        if (partData == nullptr) {
          throw LlamaInferenceException(
            'LiteRT-LM embedding input allocation failed.',
          );
        }
        allocated.add(partData);
        data[i] = partData;
      } finally {
        calloc.free(bytes);
      }
    }
    final response = api.litert_lm_embedding_engine_compute_embedding(
      engine,
      data,
      input.length,
      options,
    );
    try {
      return vector(response);
    } finally {
      if (response != nullptr) {
        api.litert_lm_embedding_response_delete(response);
      }
    }
  } finally {
    for (final data in allocated) {
      api.litert_lm_input_data_delete(data);
    }
    calloc.free(data);
    api.litert_lm_embedding_options_delete(options);
    _keepAlive(keep);
  }
}
