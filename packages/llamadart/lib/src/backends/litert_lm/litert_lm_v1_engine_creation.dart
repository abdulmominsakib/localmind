part of 'litert_lm_v1_runtime.dart';

/// Retains the settings and its borrowed strings across an asynchronous call.
final class _V1EngineCreationResources {
  Pointer<Void> settings = nullptr;
  final List<Pointer<Utf8>> strings = [];
  bool _released = false;

  Pointer<Utf8> owned(String? value) {
    if (value == null) return nullptr;
    final pointer = value.toNativeUtf8(allocator: calloc);
    strings.add(pointer);
    return pointer;
  }

  void release(LiteRtLmV1Runtime runtime) {
    if (_released) return;
    if (settings != nullptr) runtime._settingsDelete(settings);
    for (final pointer in strings) {
      calloc.free(pointer);
    }
    _released = true;
  }
}

extension _V1EngineCreation on LiteRtLmV1Runtime {
  _V1EngineCreationResources _prepareEngineCreation(
    String modelPath,
    LiteRtLmV1EngineSettings options,
  ) {
    final resources = _V1EngineCreationResources();
    try {
      final model = resources.owned(modelPath);
      final backend = resources.owned(options.backend.name);
      final vision = resources.owned(options.visionBackend?.name);
      final audio = resources.owned(options.audioBackend?.name);
      resources.settings = _create(
        'engine_settings_create',
        (out) => _settingsCreate(model, backend, vision, audio, out),
      );
      _check(
        _setContext(resources.settings, options.contextSize),
        'set_max_num_tokens',
      );
      if (options.numberOfThreads case final threads?) {
        _check(_setThreads(resources.settings, threads), 'set_num_threads');
      }
      if (options.cacheDir case final cache?) {
        _check(
          _setCache(resources.settings, resources.owned(cache)),
          'set_cache_dir',
        );
      }
      _applyEngineSettings(resources.settings, options, resources.owned);
      return resources;
    } on Object {
      resources.release(this);
      rethrow;
    }
  }

  void _adoptEngine(
    Pointer<Void> engine,
    LiteRtLmV1EngineSettings options,
    List<String> diagnosticPaths,
  ) {
    if (_engine != nullptr) _engineDelete(_engine);
    _engine = engine;
    _engineModelPath = diagnosticPaths.first;
    _engineOptions = options;
    _mediaSupport = null;
    _engineBackend = options.backend;
    _engineSpeculativeDecoding = options.speculativeDecoding;
    _diagnosticPaths = diagnosticPaths;
  }
}

/// Asynchronous owned-engine creation, without public runtime selection.
extension LiteRtLmV1AsyncEngineCreation on LiteRtLmV1Runtime {
  /// Keeps the previous engine and all creation inputs until explicit native
  /// completion. A lost isolate receipt quarantines this native family.
  Future<void> loadConfiguredAsync(
    String modelPath,
    LiteRtLmV1EngineSettings options,
  ) async {
    _requireLive();
    _requireNoConversation();
    options._validate(modelPath);
    final oldDiagnosticPaths = _diagnosticPaths;
    final diagnosticPaths = [
      modelPath,
      ?options.cacheDir,
      ?options.dispatchLibDir,
    ];
    _diagnosticPaths = [...oldDiagnosticPaths, ...diagnosticPaths];
    _V1EngineCreationResources? resources;
    try {
      final errors = liteRtLmV1ErrorAddressesForLibrary(_library);
      resources = _prepareEngineCreation(modelPath, options);
      _pendingCreation = resources;
      _creationSettlement = LiteRtLmNativeSettlement.pending;
      final request = (
        createAddress: _library.lookup<Void>('litert_lm_engine_create').address,
        configAddress: resources.settings.address,
        deleteAddress: _library.lookup<Void>('litert_lm_engine_delete').address,
        errors: errors,
        diagnosticPaths: List<String>.unmodifiable(diagnosticPaths),
      );
      late final LiteRtLmBlockingCallResult<LiteRtLmV1CreateResult> completion;
      try {
        completion = await _createRunner(request);
      } catch (error, stack) {
        _creationSettlement = LiteRtLmNativeSettlement.quarantined;
        Error.throwWithStackTrace(
          LlamaStateException(
            'C API 1.0 engine creation lost its completion receipt; retain the native family until process restart.',
          ),
          stack,
        );
      }
      _creationSettlement = LiteRtLmNativeSettlement.settled;
      if (completion.error case final error?) {
        Error.throwWithStackTrace(error, completion.stackTrace!);
      }
      final result = completion.value!;
      legacy.liteRtLmCheckEngineCreated(
        result.ownerAddress,
        backend: options.backend.name,
        modelPath: modelPath,
        nativeError: result.nativeError,
      );
      _adoptEngine(
        Pointer<Void>.fromAddress(result.ownerAddress),
        options,
        diagnosticPaths,
      );
    } on Object {
      _diagnosticPaths = oldDiagnosticPaths;
      rethrow;
    } finally {
      if (_creationSettlement == LiteRtLmNativeSettlement.settled) {
        resources?.release(this);
        _pendingCreation = null;
      }
    }
  }
}
