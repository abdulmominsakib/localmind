part of 'llama_cpp_service.dart';

class _TtsApi {
  final _TtsApiVersionDart apiVersion;
  final _TtsRequestDefaultDart requestDefault;
  final _TtsGetInfoDart getInfo;
  final _TtsInitDart init;
  final _TtsFreeDart free;
  final Pointer<NativeFinalizerFunction> freeAddress;
  final _TtsStartDart start;
  final _TtsStepDart step;
  final _TtsCancelDart cancel;
  final _TtsResetDart reset;
  final _TtsGetOutputInfoDart getOutputInfo;
  final _TtsReadPcmDart readPcm;
  final _TtsLastErrorDart lastError;
  final _TtsSetCancelFlagDart? setCancelFlag;
  final ggml_backend_sched_eval_callback evalCallback;

  // Model-type opt-in (llamadart-native v0.8.0). Older wrappers lack it and
  // drive Qwen3-TTS only through the legacy calls.
  final _TtsSupportedModelTypesDart? supportedModelTypes;
  final _TtsGetInfoExtDart? getInfoExt;
  final _TtsInitExtDart? initExt;
  final _TtsStartWithVoiceDart? startWithVoice;

  // Predefined-voice listing (llamadart-native v0.9.0).
  final _TtsGetVoiceCountDart? getVoiceCount;
  final _TtsGetVoiceNameDart? getVoiceName;

  const _TtsApi({
    required this.apiVersion,
    required this.requestDefault,
    required this.getInfo,
    required this.init,
    required this.free,
    required this.freeAddress,
    required this.start,
    required this.step,
    required this.cancel,
    required this.reset,
    required this.getOutputInfo,
    required this.readPcm,
    required this.lastError,
    required this.setCancelFlag,
    required this.evalCallback,
    required this.supportedModelTypes,
    required this.getInfoExt,
    required this.initExt,
    required this.startWithVoice,
    required this.getVoiceCount,
    required this.getVoiceName,
  });

  /// Whether the runtime has the whole model-type opt-in.
  bool get hasModelTypeOptIn =>
      supportedModelTypes != null &&
      getInfoExt != null &&
      initExt != null &&
      startWithVoice != null;

  /// Whether the runtime lists predefined voices.
  bool get listsVoices => getVoiceCount != null && getVoiceName != null;

  static _TtsApi? tryLoad(DynamicLibrary library) {
    try {
      const setCancelFlagSymbol = 'llama_dart_tts_set_cancel_flag';
      const evalCallbackSymbol = 'llama_dart_tts_eval_callback';
      bool has(String symbol) => library.providesSymbol(symbol);
      const supportedModelTypesSymbol = 'llama_dart_tts_supported_model_types';
      const getInfoExtSymbol = 'llama_dart_tts_get_info_ext';
      const initExtSymbol = 'llama_dart_tts_init_ext';
      const startWithVoiceSymbol = 'llama_dart_tts_start_with_voice';
      const getVoiceCountSymbol = 'llama_dart_tts_get_voice_count';
      const getVoiceNameSymbol = 'llama_dart_tts_get_voice_name';
      return _TtsApi(
        apiVersion: library
            .lookupFunction<_TtsApiVersionNative, _TtsApiVersionDart>(
              'llama_dart_tts_api_version',
            ),
        requestDefault: library
            .lookupFunction<_TtsRequestDefaultNative, _TtsRequestDefaultDart>(
              'llama_dart_tts_request_default',
            ),
        getInfo: library.lookupFunction<_TtsGetInfoNative, _TtsGetInfoDart>(
          'llama_dart_tts_get_info',
        ),
        init: library.lookupFunction<_TtsInitNative, _TtsInitDart>(
          'llama_dart_tts_init',
        ),
        free: library.lookupFunction<_TtsFreeNative, _TtsFreeDart>(
          'llama_dart_tts_free',
        ),
        freeAddress: library.lookup('llama_dart_tts_free'),
        start: library.lookupFunction<_TtsStartNative, _TtsStartDart>(
          'llama_dart_tts_start',
        ),
        step: library.lookupFunction<_TtsStepNative, _TtsStepDart>(
          'llama_dart_tts_step',
        ),
        cancel: library.lookupFunction<_TtsCancelNative, _TtsCancelDart>(
          'llama_dart_tts_cancel',
        ),
        reset: library.lookupFunction<_TtsResetNative, _TtsResetDart>(
          'llama_dart_tts_reset',
        ),
        getOutputInfo: library
            .lookupFunction<_TtsGetOutputInfoNative, _TtsGetOutputInfoDart>(
              'llama_dart_tts_get_output_info',
            ),
        readPcm: library.lookupFunction<_TtsReadPcmNative, _TtsReadPcmDart>(
          'llama_dart_tts_read_pcm',
        ),
        lastError: library
            .lookupFunction<_TtsLastErrorNative, _TtsLastErrorDart>(
              'llama_dart_tts_last_error',
            ),
        setCancelFlag: library.providesSymbol(setCancelFlagSymbol)
            ? library.lookupFunction<
                _TtsSetCancelFlagNative,
                _TtsSetCancelFlagDart
              >(setCancelFlagSymbol)
            : null,
        evalCallback: library.providesSymbol(evalCallbackSymbol)
            ? library.lookup<
                NativeFunction<ggml_backend_sched_eval_callbackFunction>
              >(evalCallbackSymbol)
            : nullptr,
        supportedModelTypes: has(supportedModelTypesSymbol)
            ? library.lookupFunction<
                _TtsSupportedModelTypesNative,
                _TtsSupportedModelTypesDart
              >(supportedModelTypesSymbol)
            : null,
        getInfoExt: has(getInfoExtSymbol)
            ? library.lookupFunction<_TtsGetInfoExtNative, _TtsGetInfoExtDart>(
                getInfoExtSymbol,
              )
            : null,
        initExt: has(initExtSymbol)
            ? library.lookupFunction<_TtsInitExtNative, _TtsInitExtDart>(
                initExtSymbol,
              )
            : null,
        startWithVoice: has(startWithVoiceSymbol)
            ? library.lookupFunction<
                _TtsStartWithVoiceNative,
                _TtsStartWithVoiceDart
              >(startWithVoiceSymbol)
            : null,
        getVoiceCount: has(getVoiceCountSymbol)
            ? library.lookupFunction<
                _TtsGetVoiceCountNative,
                _TtsGetVoiceCountDart
              >(getVoiceCountSymbol)
            : null,
        getVoiceName: has(getVoiceNameSymbol)
            ? library
                  .lookupFunction<_TtsGetVoiceNameNative, _TtsGetVoiceNameDart>(
                    getVoiceNameSymbol,
                  )
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

class _ReasoningBudgetApi {
  const _ReasoningBudgetApi({required this.init});

  final _LlamaDartReasoningBudgetInitDart init;

  Pointer<llama_sampler> initSampler({
    required Pointer<llama_vocab> vocab,
    required _LlamaCppThinkingBudgetConfig config,
    required bool pauseGrammarDuringReasoning,
    required Pointer<llama_sampler> grammarSampler,
    required Pointer<Int32> promptTokens,
    required int promptTokenCount,
  }) {
    final startTag = config.startTag.toNativeUtf8();
    final endTag = config.endTag.toNativeUtf8();
    final forcedMessage = config.forcedMessage.toNativeUtf8();
    try {
      return init(
        vocab,
        startTag.cast(),
        endTag.cast(),
        forcedMessage.cast(),
        config.maxTokens,
        pauseGrammarDuringReasoning,
        grammarSampler,
        promptTokens,
        promptTokenCount,
      );
    } finally {
      malloc.free(startTag);
      malloc.free(endTag);
      malloc.free(forcedMessage);
    }
  }

  static _ReasoningBudgetApi load(DynamicLibrary library) {
    return _ReasoningBudgetApi(
      init: library
          .lookupFunction<
            _LlamaDartReasoningBudgetInitNative,
            _LlamaDartReasoningBudgetInitDart
          >('llama_dart_sampler_init_reasoning_budget'),
    );
  }
}

class _SpeculativeApi {
  final _LlamaDartSpeculativeInitDart init;
  final _LlamaDartSpeculativeFreeDart free;
  final Pointer<NativeFinalizerFunction> freeAddress;
  final _LlamaDartSpeculativeGetDraftContextDart getDraftContext;
  final _LlamaDartSpeculativeBeginDart begin;
  final _LlamaDartSpeculativeProcessBatchDart processBatch;
  final _LlamaDartSpeculativeDraftDart draft;
  final _LlamaDartSpeculativeAcceptDart accept;
  final _LlamaDartSamplerSampleAndAcceptNDart sampleAndAcceptN;

  const _SpeculativeApi({
    required this.init,
    required this.free,
    required this.freeAddress,
    required this.getDraftContext,
    required this.begin,
    required this.processBatch,
    required this.draft,
    required this.accept,
    required this.sampleAndAcceptN,
  });

  factory _SpeculativeApi.direct() {
    final api = _SpeculativeApi(
      init: llama_dart_speculative_init,
      free: llama_dart_speculative_free,
      freeAddress:
          Native.addressOf<NativeFunction<_LlamaDartSpeculativeFreeNative>>(
            llama_dart_speculative_free,
          ).cast(),
      getDraftContext: llama_dart_speculative_get_draft_context,
      begin: llama_dart_speculative_begin,
      processBatch: llama_dart_speculative_process_batch,
      draft: llama_dart_speculative_draft,
      accept: llama_dart_speculative_accept,
      sampleAndAcceptN: llama_dart_sampler_sample_and_accept_n,
    );
    api.probe();
    return api;
  }

  factory _SpeculativeApi.windowsAsset() {
    final api = _SpeculativeApi(
      init: _llamadartWrapperSpeculativeInit,
      free: _llamadartWrapperSpeculativeFree,
      freeAddress:
          Native.addressOf<NativeFunction<_LlamaDartSpeculativeFreeNative>>(
            _llamadartWrapperSpeculativeFree,
          ).cast(),
      getDraftContext: _llamadartWrapperSpeculativeGetDraftContext,
      begin: _llamadartWrapperSpeculativeBegin,
      processBatch: _llamadartWrapperSpeculativeProcessBatch,
      draft: _llamadartWrapperSpeculativeDraft,
      accept: _llamadartWrapperSpeculativeAccept,
      sampleAndAcceptN: _llamadartWrapperSamplerSampleAndAcceptN,
    );
    api.probe();
    return api;
  }

  void probe() {
    final nullSpeculative = nullptr.cast<llama_dart_speculative>();
    final nullModel = nullptr.cast<llama_model>();
    final nullContext = nullptr.cast<llama_context>();
    final nullParams = nullptr.cast<llama_dart_speculative_params>();
    final nullSampler = nullptr.cast<llama_sampler>();
    final nullTokenArray = nullptr.cast<Int32>();
    final ctxParams = llama_context_default_params();
    final batch = llama_batch_init(1, 0, 1);
    try {
      init(nullModel, nullModel, nullContext, ctxParams, nullParams);
      free(nullSpeculative);
      getDraftContext(nullSpeculative);
      begin(nullSpeculative, 0, nullTokenArray, 0);
      processBatch(nullSpeculative, batch);
      draft(nullSpeculative, 0, 0, 0, nullTokenArray, 0, 1, nullTokenArray, 0);
      accept(nullSpeculative, 0, 0);
      sampleAndAcceptN(
        nullSampler,
        nullContext,
        nullTokenArray,
        0,
        nullTokenArray,
        0,
        nullTokenArray,
        0,
      );
    } finally {
      llama_batch_free(batch);
    }
  }

  static _SpeculativeApi? tryLoad(DynamicLibrary library) {
    try {
      return _SpeculativeApi(
        init: library
            .lookupFunction<
              _LlamaDartSpeculativeInitNative,
              _LlamaDartSpeculativeInitDart
            >('llama_dart_speculative_init'),
        free: library
            .lookupFunction<
              _LlamaDartSpeculativeFreeNative,
              _LlamaDartSpeculativeFreeDart
            >('llama_dart_speculative_free'),
        freeAddress: library.lookup('llama_dart_speculative_free'),
        getDraftContext: library
            .lookupFunction<
              _LlamaDartSpeculativeGetDraftContextNative,
              _LlamaDartSpeculativeGetDraftContextDart
            >('llama_dart_speculative_get_draft_context'),
        begin: library
            .lookupFunction<
              _LlamaDartSpeculativeBeginNative,
              _LlamaDartSpeculativeBeginDart
            >('llama_dart_speculative_begin'),
        processBatch: library
            .lookupFunction<
              _LlamaDartSpeculativeProcessBatchNative,
              _LlamaDartSpeculativeProcessBatchDart
            >('llama_dart_speculative_process_batch'),
        draft: library
            .lookupFunction<
              _LlamaDartSpeculativeDraftNative,
              _LlamaDartSpeculativeDraftDart
            >('llama_dart_speculative_draft'),
        accept: library
            .lookupFunction<
              _LlamaDartSpeculativeAcceptNative,
              _LlamaDartSpeculativeAcceptDart
            >('llama_dart_speculative_accept'),
        sampleAndAcceptN: library
            .lookupFunction<
              _LlamaDartSamplerSampleAndAcceptNNative,
              _LlamaDartSamplerSampleAndAcceptNDart
            >('llama_dart_sampler_sample_and_accept_n'),
      );
    } catch (_) {
      return null;
    }
  }

  Pointer<llama_dart_speculative> initSession({
    required Pointer<llama_model> targetModel,
    required Pointer<llama_model>? draftModel,
    required Pointer<llama_context> targetContext,
    required llama_context_params contextParams,
    required _LlamaCppSpeculativeConfig config,
  }) {
    final params = malloc<llama_dart_speculative_params>();
    final draftContextParams = malloc<llama_context_params>();
    final typeNamesPtr = config.typeNames.toNativeUtf8();
    final staticCachePathPtr = config.ngramCacheStaticPath?.toNativeUtf8();
    final dynamicCachePathPtr = config.ngramCacheDynamicPath?.toNativeUtf8();

    try {
      params.ref.type_names = typeNamesPtr.cast();
      params.ref.type_mask = 0;
      params.ref.draft_token_max = config.draftTokenMax;
      params.ref.draft_token_min = config.draftTokenMin;
      params.ref.draft_min_probability = config.minProbability ?? -1.0;
      params.ref.draft_split_probability = config.draftSplitProbability ?? -1.0;
      params.ref.backend_sampling = true;
      params.ref.ngram_size_n = config.ngramSizeN ?? 0;
      params.ref.ngram_size_m = config.ngramSizeM ?? 0;
      params.ref.ngram_min_hits = config.ngramMinHits ?? 0;
      params.ref.ngram_match = config.ngramMatch ?? 0;
      params.ref.ngram_token_min = config.ngramTokenMin ?? -1;
      params.ref.ngram_token_max = config.ngramTokenMax ?? 0;
      params.ref.ngram_cache_static_path = staticCachePathPtr == null
          ? nullptr
          : staticCachePathPtr.cast();
      params.ref.ngram_cache_dynamic_path = dynamicCachePathPtr == null
          ? nullptr
          : dynamicCachePathPtr.cast();

      return init(
        targetModel,
        draftModel ?? nullptr.cast<llama_model>(),
        targetContext,
        speculativeDraftContextParams(
          contextParams,
          config.draftMicroBatchSize,
          draftContextParams,
        ),
        params,
      );
    } finally {
      malloc.free(params);
      malloc.free(draftContextParams);
      malloc.free(typeNamesPtr);
      if (staticCachePathPtr != null) {
        malloc.free(staticCachePathPtr);
      }
      if (dynamicCachePathPtr != null) {
        malloc.free(dynamicCachePathPtr);
      }
    }
  }
}

class _MtmdApi {
  final DynamicLibrary? library;
  final _MtmdDefaultMarkerDart defaultMarker;
  final _MtmdContextParamsDefaultDart contextParamsDefault;
  final _MtmdInitFromFileDart initFromFile;
  final _MtmdFreeDart free;
  final Pointer<NativeFinalizerFunction> freeAddress;
  final _MtmdInputChunksInitDart inputChunksInit;
  final _MtmdInputChunksFreeDart inputChunksFree;
  final _MtmdHelperInitOptDefaultDart helperInitOptDefault;
  final _MtmdHelperBitmapInitFromFileDart helperBitmapInitFromFile;
  final _MtmdHelperBitmapInitFromBufDart helperBitmapInitFromBuf;
  final _MtmdBitmapInitFromAudioDart bitmapInitFromAudio;
  final _MtmdSupportVisionDart supportsVision;
  final _MtmdSupportAudioDart supportsAudio;
  final _MtmdSupportVideoDart supportsVideo;
  final _MtmdBitmapFreeDart bitmapFree;
  final _MtmdTokenizeDart tokenize;
  final _MtmdHelperEvalChunksDart helperEvalChunks;
  final MtmdChunkEvalApi? chunkEval;
  final _MtmdLogSetDart? logSet;
  final _MtmdLogSetDart? helperLogSet;

  const _MtmdApi({
    this.library,
    required this.defaultMarker,
    required this.contextParamsDefault,
    required this.initFromFile,
    required this.free,
    required this.freeAddress,
    required this.inputChunksInit,
    required this.inputChunksFree,
    required this.helperInitOptDefault,
    required this.helperBitmapInitFromFile,
    required this.helperBitmapInitFromBuf,
    required this.bitmapInitFromAudio,
    required this.supportsVision,
    required this.supportsAudio,
    required this.supportsVideo,
    required this.bitmapFree,
    required this.tokenize,
    required this.helperEvalChunks,
    required this.chunkEval,
    required this.logSet,
    required this.helperLogSet,
  });

  static _MtmdApi? tryLoad(
    DynamicLibrary library, {
    bool loadChunkEval = true,
  }) {
    try {
      _MtmdLogSetDart? logSet;
      _MtmdLogSetDart? helperLogSet;
      _MtmdSupportVideoDart supportsVideo = (_) => false;
      try {
        logSet = library.lookupFunction<_MtmdLogSetNative, _MtmdLogSetDart>(
          'mtmd_log_set',
        );
      } catch (_) {}
      try {
        helperLogSet = library
            .lookupFunction<_MtmdLogSetNative, _MtmdLogSetDart>(
              'mtmd_helper_log_set',
            );
      } catch (_) {}
      try {
        supportsVideo = library
            .lookupFunction<_MtmdSupportVideoNative, _MtmdSupportVideoDart>(
              'mtmd_helper_support_video',
            );
      } catch (_) {}

      return _MtmdApi(
        library: library,
        defaultMarker: library
            .lookupFunction<_MtmdDefaultMarkerNative, _MtmdDefaultMarkerDart>(
              'mtmd_default_marker',
            ),
        contextParamsDefault: library
            .lookupFunction<
              _MtmdContextParamsDefaultNative,
              _MtmdContextParamsDefaultDart
            >('mtmd_context_params_default'),
        initFromFile: library
            .lookupFunction<_MtmdInitFromFileNative, _MtmdInitFromFileDart>(
              'mtmd_init_from_file',
            ),
        free: library.lookupFunction<_MtmdFreeNative, _MtmdFreeDart>(
          'mtmd_free',
        ),
        freeAddress: library.lookup('mtmd_free'),
        inputChunksInit: library
            .lookupFunction<
              _MtmdInputChunksInitNative,
              _MtmdInputChunksInitDart
            >('mtmd_input_chunks_init'),
        inputChunksFree: library
            .lookupFunction<
              _MtmdInputChunksFreeNative,
              _MtmdInputChunksFreeDart
            >('mtmd_input_chunks_free'),
        helperInitOptDefault: library
            .lookupFunction<
              _MtmdHelperInitOptDefaultNative,
              _MtmdHelperInitOptDefaultDart
            >('mtmd_helper_init_opt_default'),
        helperBitmapInitFromFile: library
            .lookupFunction<
              _MtmdHelperBitmapInitFromFileNative,
              _MtmdHelperBitmapInitFromFileDart
            >('mtmd_helper_bitmap_init_from_file'),
        helperBitmapInitFromBuf: library
            .lookupFunction<
              _MtmdHelperBitmapInitFromBufNative,
              _MtmdHelperBitmapInitFromBufDart
            >('mtmd_helper_bitmap_init_from_buf'),
        bitmapInitFromAudio: library
            .lookupFunction<
              _MtmdBitmapInitFromAudioNative,
              _MtmdBitmapInitFromAudioDart
            >('mtmd_bitmap_init_from_audio'),
        supportsVision: library
            .lookupFunction<_MtmdSupportVisionNative, _MtmdSupportVisionDart>(
              'mtmd_support_vision',
            ),
        supportsAudio: library
            .lookupFunction<_MtmdSupportAudioNative, _MtmdSupportAudioDart>(
              'mtmd_support_audio',
            ),
        supportsVideo: supportsVideo,
        bitmapFree: library
            .lookupFunction<_MtmdBitmapFreeNative, _MtmdBitmapFreeDart>(
              'mtmd_bitmap_free',
            ),
        tokenize: library
            .lookupFunction<_MtmdTokenizeNative, _MtmdTokenizeDart>(
              'mtmd_tokenize',
            ),
        helperEvalChunks: library
            .lookupFunction<
              _MtmdHelperEvalChunksNative,
              _MtmdHelperEvalChunksDart
            >('mtmd_helper_eval_chunks'),
        chunkEval: loadChunkEval ? MtmdChunkEvalApi.tryLoad(library) : null,
        logSet: logSet,
        helperLogSet: helperLogSet,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Native bundle directory names for the Linux [abi], empty for other ABIs.
List<String> linuxNativeBundleNames(Abi abi) {
  switch (abi) {
    case Abi.linuxArm64:
      return const <String>['linux-arm64'];
    case Abi.linuxX64:
      return const <String>['linux-x64'];
    default:
      return const <String>[];
  }
}

/// Candidate failures of one native discovery family, grouped by reason.
///
/// Candidates are stored as [probeCandidateIdentity] and reasons in
/// first-seen order; a reason repeated for the same identity is stored once.
class BackendProbeFailures {
  final Map<String, Set<String>> _candidatesByReason = <String, Set<String>>{};

  /// Whether nothing was recorded.
  bool get isEmpty => _candidatesByReason.isEmpty;

  /// Records that [candidate] failed for [reason].
  void add(String candidate, String reason) {
    _candidatesByReason
        .putIfAbsent(reason, () => <String>{})
        .add(probeCandidateIdentity(candidate));
  }

  /// Renders `reason (id, id); reason (id)`, or `no candidates` when
  /// [isEmpty].
  String describe() {
    if (isEmpty) {
      return 'no candidates';
    }
    return _candidatesByReason.entries
        .map((entry) => '${entry.key} (${entry.value.join(', ')})')
        .join('; ');
  }
}

/// Opens each of [candidates] in order, skipping repeats, until [accept]
/// returns a non-null result for an opened library, and returns that result.
///
/// A candidate [open] throws for is recorded in [failures] under
/// [describeLibraryProbeError]. [accept] records its own reason for rejecting
/// an opened library before returning `null`. Returns `null` when no
/// candidate is accepted.
T? probeLibraryCandidates<T extends Object>(
  Iterable<String> candidates, {
  required BackendProbeFailures failures,
  required DynamicLibrary Function(String candidate) open,
  required T? Function(String candidate, DynamicLibrary library) accept,
}) {
  final seen = <String>{};
  for (final candidate in candidates) {
    if (!seen.add(candidate)) {
      continue;
    }
    final DynamicLibrary library;
    try {
      library = open(candidate);
    } catch (error) {
      failures.add(candidate, describeLibraryProbeError(error, candidate));
      continue;
    }
    final accepted = accept(candidate, library);
    if (accepted != null) {
      return accepted;
    }
  }
  return null;
}

/// The identity a probe summary keeps for [candidate]: a `package:` asset URI
/// verbatim, otherwise the file name without its directory. Anything from the
/// first `?` or `#` on is dropped first.
String probeCandidateIdentity(String candidate) {
  final bare = candidate.split(RegExp(r'[?#]')).first;
  if (bare.startsWith('package:')) {
    return bare;
  }
  return path.basename(bare);
}

/// Runs [init], the first call that loads the llama.cpp runtime, and replaces
/// a Windows load failure with [llamaCppWindowsLoadFailure] when that names
/// the missing Visual C++ runtime; any other error is rethrown unchanged.
void runLlamaBackendInit(
  void Function() init, {
  required Abi abi,
  List<String> Function(List<String> names) missingWindowsLibraries =
      findMissingWindowsLibraries,
}) {
  try {
    init();
  } on ArgumentError catch (error) {
    final failure = llamaCppWindowsLoadFailure(
      error: error,
      abi: abi,
      missingWindowsLibraries: missingWindowsLibraries,
    );
    if (failure == null) {
      rethrow;
    }
    throw failure;
  }
}

/// Maps a failure to load the llama.cpp runtime on Windows to the Visual C++
/// runtime it lacks.
///
/// Every llama.cpp library in the pinned Windows bundles imports the Visual
/// C++ v14 runtime, which stock Windows Server does not ship, and
/// Windows reports the missing import only as error 126 without naming it.
/// Returns `null` off Windows, for any other error, and when
/// [missingWindowsLibraries] reports none of the runtime missing, so the
/// caller keeps the loader's own error.
LlamaBackendInitializationException? llamaCppWindowsLoadFailure({
  required ArgumentError error,
  required Abi abi,
  List<String> Function(List<String> names) missingWindowsLibraries =
      findMissingWindowsLibraries,
}) {
  final architecture = switch (abi) {
    Abi.windowsX64 => 'x64',
    Abi.windowsArm64 => 'arm64',
    _ => null,
  };
  final detail = '${error.message ?? error}';
  if (architecture == null || !isWindowsModuleNotFoundError(detail)) {
    return null;
  }
  final missing = missingWindowsLibraries([
    'msvcp140.dll',
    'vcruntime140.dll',
    // Only the x64 libraries import the x64 C++ exception-handling runtime.
    if (abi == Abi.windowsX64) 'vcruntime140_1.dll',
  ]);
  if (missing.isEmpty) {
    return null;
  }
  final cause = detail
      .split('\n')
      .first
      .trimRight()
      .replaceFirst(RegExp(r'\.+$'), '');
  final advice = visualCppRuntimeAdvice(
    architecture: architecture,
    missing: missing,
    library: 'llamadart.dll',
  );
  return LlamaBackendInitializationException(
    'llama.cpp runtime could not be loaded on '
    'windows-$architecture: $cause. $advice',
  );
}

/// Names the system library a Windows GPU [backend] module could not load,
/// as a sentence to append to its load-failure diagnostic.
///
/// The bundles ship each module's other imports, but not the Vulkan loader
/// (`vulkan-1.dll`), which a GPU driver installs, nor `nvcuda.dll`, which
/// the NVIDIA driver installs. Returns an empty string off Windows, for other
/// backends, and when [missingWindowsLibraries] does not report the library
/// missing.
String describeMissingWindowsBackendLoader(
  String backend, {
  required bool isWindows,
  List<String> Function(List<String> names) missingWindowsLibraries =
      findMissingWindowsLibraries,
}) {
  final (library, provider) = switch (backend) {
    'vulkan' => (
      'vulkan-1.dll',
      'a GPU driver that provides the Vulkan loader',
    ),
    'cuda' => ('nvcuda.dll', 'an NVIDIA driver'),
    _ => (null, null),
  };
  if (!isWindows ||
      library == null ||
      missingWindowsLibraries([library]).isEmpty) {
    return '';
  }
  return ' $library could not be loaded; install $provider.';
}

/// Classifies a `DynamicLibrary.open` failure for [candidate] as one of
/// `unresolved symbol \`name\``, `unresolved symbol`, `incompatible binary`,
/// `dependency not loaded \`name\``, `blocked by namespace`, `not found` or
/// `open failed`.
///
/// The loader text itself is never returned: it can carry the process search
/// paths and the candidate's directory.
String describeLibraryProbeError(Object error, String candidate) {
  final text = error.toString();
  final symbol = RegExp(
    r'(?:undefined symbol|symbol not found|cannot locate symbol)'
    r'(?: in flat namespace)?'
    r'''[:\s]+['"]?_?([A-Za-z_][A-Za-z0-9_]*)''',
    caseSensitive: false,
  ).firstMatch(text);
  if (symbol != null) {
    return 'unresolved symbol `${symbol.group(1)}`';
  }
  if (RegExp(
    r'undefined symbol|symbol not found|cannot locate symbol|error code: 127',
    caseSensitive: false,
  ).hasMatch(text)) {
    return 'unresolved symbol';
  }
  if (RegExp(
    r'incompatible architecture|wrong ELF class|invalid ELF header|'
    r'unexpected e_machine|has bad ELF magic|'
    r'not a valid Win32 application|error code: 193|cannot execute binary',
    caseSensitive: false,
  ).hasMatch(text)) {
    return 'incompatible binary';
  }
  if (text.contains('is not accessible for the namespace')) {
    return 'blocked by namespace';
  }
  final appleDependency = RegExp(
    r'Library not loaded:\s*(\S+)',
  ).firstMatch(text);
  if (appleDependency != null) {
    return 'dependency not loaded '
        '`${path.basename(appleDependency.group(1)!)}`';
  }
  final missing =
      RegExp(
        r'''([^\s"']+): cannot open shared object file''',
      ).firstMatch(text) ??
      RegExp(r'library "([^"]+)" not found').firstMatch(text);
  if (missing != null &&
      path.basename(missing.group(1)!) != path.basename(candidate)) {
    return 'dependency not loaded `${path.basename(missing.group(1)!)}`';
  }
  if (RegExp(
    r'no such file|not found|cannot open shared object|could not be found|'
    r'error code: 126',
    caseSensitive: false,
  ).hasMatch(text)) {
    return 'not found';
  }
  return 'open failed';
}

extension _LlamaCppLibraryLoading on LlamaCppService {
  void _applyConfiguredLogLevel() {
    var applied = false;
    try {
      llama_dart_set_log_level(_configuredLogLevel.index);
      applied = true;
    } on ArgumentError {
      // Continue with explicit fallback lookup below.
    }

    // Apply via explicit wrapper lookup as well. On Windows split bundles the
    // primary @DefaultAsset can resolve to a different loaded copy than the
    // runtime backend modules, so applying to both keeps log-level state in
    // sync across module-loading layouts.
    _resolveLogLevelFallbackFunction();
    final fallback = _llamaDartSetLogLevelFallback;
    if (fallback != null) {
      try {
        fallback(_configuredLogLevel.index);
        applied = true;
      } catch (_) {
        // Ignore fallback invocation errors and preserve existing behavior.
      }
    }

    if (!applied && fallback == null) {
      _recordStartupDiagnostic(
        '`llama_dart_set_log_level` is unavailable: the primary FFI asset '
        'does not export it and no wrapper candidate provided it '
        '(${_logLevelProbeOutcome ?? 'no wrapper candidate probed'}).',
      );
    }

    // mtmd/clip uses its own logger callback chain; mirror llama logger so
    // multimodal projector logs honor the same configured native log level.
    _syncMtmdLogCallbackToLlamaLogger();
  }

  void _syncMtmdLogCallbackToLlamaLogger() {
    final logCallbackPtr = malloc<ggml_log_callback>();
    final userDataPtr = malloc<Pointer<Void>>();

    try {
      try {
        llama_log_get(logCallbackPtr, userDataPtr);
      } on ArgumentError {
        return;
      }

      final callback = logCallbackPtr.value;
      final userData = userDataPtr.value;
      if (callback == nullptr) {
        return;
      }

      var applied = false;
      if (!_mtmdPrimarySymbolsUnavailable) {
        try {
          mtmd_log_set(callback, userData);
          mtmd_helper_log_set(callback, userData);
          applied = true;
        } on ArgumentError {
          _mtmdPrimarySymbolsUnavailable = true;
        }
      }

      if (!applied) {
        final fallback = _resolveMtmdFallbackApi();
        if (fallback != null) {
          fallback.logSet?.call(callback, userData);
          fallback.helperLogSet?.call(callback, userData);
        }
      }
    } finally {
      malloc.free(logCallbackPtr);
      malloc.free(userDataPtr);
    }
  }

  void _preloadLinuxCoreLibrariesForSonameResolution() {
    if (!Platform.isLinux || _linuxCorePreloadAttempted) {
      return;
    }

    _linuxCorePreloadAttempted = true;

    // Linux split bundles expose versioned SONAMEs (e.g. libllama.so.0).
    // Preloading dependency libraries through native-asset URIs ensures their
    // SONAMEs are already registered before @Native resolves libllamadart.
    final moduleDir = _resolveLinuxPrimaryLibraryDirectory();

    final preloadCandidates = <List<String>>[
      <String>[
        'package:llamadart/ggml-base',
        if (moduleDir != null) path.join(moduleDir, 'libggml-base.so.0'),
        if (moduleDir != null) path.join(moduleDir, 'libggml-base.so'),
      ],
      <String>[
        'package:llamadart/ggml',
        if (moduleDir != null) path.join(moduleDir, 'libggml.so.0'),
        if (moduleDir != null) path.join(moduleDir, 'libggml.so'),
      ],
      <String>[
        'package:llamadart/llama',
        if (moduleDir != null) path.join(moduleDir, 'libllama.so.0'),
        if (moduleDir != null) path.join(moduleDir, 'libllama.so'),
      ],
    ];

    for (final candidates in preloadCandidates) {
      var loaded = false;
      Object? lastError;
      String? lastCandidate;
      for (final candidate in candidates) {
        try {
          _preloadedCoreLibraries.add(DynamicLibrary.open(candidate));
          loaded = true;
          break;
        } catch (error) {
          lastError = error;
          lastCandidate = candidate;
          continue;
        }
      }

      if (!loaded && lastError != null && lastCandidate != null) {
        _recordStartupDiagnostic(
          'Failed to preload Linux core library candidates '
          '`${candidates.join(', ')}`; last error from `$lastCandidate`: '
          '$lastError',
        );
      }
    }
  }

  List<String> _linuxDependencySourceDirectories(String targetDirectory) {
    final dirs = <String>{targetDirectory};
    final bundleNames = _linuxBundleNamesForCurrentAbi();
    if (bundleNames.isEmpty) {
      return dirs.toList(growable: false);
    }

    final cacheRoot = Directory(
      path.join(
        Directory.current.path,
        '.dart_tool',
        'llamadart',
        'native_bundles_v2',
      ),
    );
    if (!cacheRoot.existsSync()) {
      return dirs.toList(growable: false);
    }

    final tagDirectories = cacheRoot.listSync().whereType<Directory>().toList()
      ..sort((a, b) => path.basename(b.path).compareTo(path.basename(a.path)));

    for (final tagDir in tagDirectories) {
      for (final bundleName in bundleNames) {
        final extractedDir = Directory(
          path.join(tagDir.path, bundleName, 'extracted'),
        );
        if (extractedDir.existsSync()) {
          dirs.add(extractedDir.path);
        }
      }
    }

    return dirs.toList(growable: false);
  }

  List<String> _linuxBundleNamesForCurrentAbi() =>
      linuxNativeBundleNames(Abi.current());

  bool _tryLoadAllBackendsBestEffort() {
    if (_backendLoadAllSymbolUnavailable) {
      return false;
    }

    try {
      ggml_backend_load_all();
      return true;
    } on ArgumentError {
      _resolveGgmlFallbackFunctions();
      final fallback = _ggmlBackendLoadAllFallback;
      if (fallback != null) {
        fallback();
        return true;
      }

      // Some split bundles don't expose this symbol on the primary FFI asset.
      // Continue with explicit backend-module loading fallback.
      _recordMissingGgmlSymbol('`ggml_backend_load_all`');
      _backendLoadAllSymbolUnavailable = true;
      return false;
    }
  }

  bool _tryLoadAllBackendsFromPathBestEffort(String directoryPath) {
    if (_backendLoadAllFromPathSymbolUnavailable) {
      return false;
    }

    final directoryPathPtr = directoryPath.toNativeUtf8();
    try {
      try {
        ggml_backend_load_all_from_path(directoryPathPtr.cast());
        return true;
      } on ArgumentError {
        _resolveGgmlFallbackFunctions();
        final fallback = _ggmlBackendLoadAllFromPathFallback;
        if (fallback != null) {
          fallback(directoryPathPtr.cast());
          return true;
        }

        _recordMissingGgmlSymbol('`ggml_backend_load_all_from_path`');
        _backendLoadAllFromPathSymbolUnavailable = true;
        return false;
      }
    } finally {
      malloc.free(directoryPathPtr);
    }
  }

  void _tryLoadBackendModuleIfBundled(String backend) {
    if (_backendModuleDirectory != null && !_isBackendModuleBundled(backend)) {
      return;
    }
    _tryLoadBackendModule(backend);
  }

  bool _isBackendModuleBundled(String backend) {
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      return true;
    }

    final fileNameCandidates = _libraryCandidates.backend(backend);
    if (fileNameCandidates.isEmpty) {
      return false;
    }

    for (final fileName in fileNameCandidates) {
      final fullPath = path.join(backendModuleDirectory, fileName);
      if (File(fullPath).existsSync()) {
        return true;
      }
    }
    return false;
  }

  void _freeWindowsBackendModule(
    Pointer<Void> handle,
    String libraryPath,
    String backend,
  ) {
    if (!Platform.isWindows || handle == nullptr) {
      return;
    }

    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final freeLibrary = kernel32
          .lookupFunction<_FreeLibraryNative, _FreeLibraryDart>('FreeLibrary');
      if (freeLibrary(handle) == 0) {
        _recordWindowsBackendModuleReleaseFailure(libraryPath, backend);
      }
    } catch (error) {
      _recordWindowsBackendModuleReleaseFailure(libraryPath, backend, error);
    }
  }

  int? _lookupBackendAssetScore(DynamicLibrary library) {
    try {
      final score = library
          .lookupFunction<_GgmlBackendScoreNative, _GgmlBackendScoreDart>(
            'ggml_backend_score',
          );
      return score();
    } catch (_) {
      return null;
    }
  }

  bool _registerBackendRegBestEffort(ggml_backend_reg_t reg) {
    try {
      ggml_backend_register(reg);
      return true;
    } on ArgumentError {
      _resolveGgmlFallbackFunctions();
      final fallback = _ggmlBackendRegisterFallback;
      if (fallback == null) {
        _recordMissingGgmlSymbol('`ggml_backend_register`');
        return false;
      }
      try {
        fallback(reg);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// True once every ggml fallback symbol has been bound, so the candidate
  /// search can stop early.
  bool get _ggmlFallbacksFullyResolved =>
      _ggmlBackendLoadFallback != null &&
      _ggmlBackendLoadAllFallback != null &&
      _ggmlBackendLoadAllFromPathFallback != null &&
      _ggmlBackendRegisterFallback != null &&
      _ggmlBackendRegCountFallback != null &&
      _ggmlBackendRegGetFallback != null &&
      _ggmlBackendRegNameFallback != null &&
      _ggmlBackendRegByNameFallback != null &&
      _ggmlBackendRegDevCountFallback != null &&
      _ggmlBackendRegDevGetFallback != null &&
      _ggmlBackendDevCountFallback != null &&
      _ggmlBackendDevGetFallback != null &&
      _ggmlBackendDevNameFallback != null &&
      _ggmlBackendDevBackendRegFallback != null &&
      _ggmlBackendDevByTypeFallback != null &&
      _ggmlBackendDevTypeFallback != null &&
      _ggmlBackendDevGetPropsFallback != null &&
      _ggmlBackendDevMemoryFallback != null;

  bool _supportsThinkingBudget() {
    try {
      _resolveReasoningBudgetApi();
      return true;
    } on LlamaUnsupportedException {
      return false;
    }
  }

  String _speculativeUnavailableMessage() {
    return 'llama.cpp speculative decoding is unavailable in this native '
        'runtime bundle (missing llama_dart_speculative_* wrapper symbols). '
        'Use the package-pinned native runtime or an ABI-compatible build.';
  }

  ggml_backend_sched_eval_callback _ttsEvalCallback() {
    try {
      return _resolveTtsApi().evalCallback;
    } on LlamaUnsupportedException {
      return nullptr;
    }
  }

  String _ttsUnavailableMessage() {
    return 'Native text-to-speech is unavailable in this runtime bundle '
        '(missing llama_dart_tts_* ABI v$LLAMA_DART_TTS_API_VERSION symbols). '
        'Update to a compatible llamadart-native artifact.';
  }

  List<String> _llamadartWrapperLibraryCandidates() =>
      _libraryCandidates.wrapperPaths(_llamadartFallbackLookupDirectories());

  List<String> _llamadartFallbackLookupDirectories() {
    final directories = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      directories.add(backendModuleDirectory);
    }

    final executableDir = path.dirname(Platform.resolvedExecutable);
    directories.add(executableDir);
    directories.add(Directory.current.path);
    directories.add(path.join(Directory.current.path, '.dart_tool', 'lib'));

    if (Platform.isIOS) {
      directories.add(path.normalize(path.join(executableDir, 'Frameworks')));
    }

    if (Platform.isMacOS) {
      directories.add(
        path.normalize(path.join(executableDir, '..', 'Frameworks')),
      );
      directories.add(path.normalize(path.join(executableDir, 'Frameworks')));
    }

    return directories.toList(growable: false);
  }

  ggml_backend_reg_t _ggmlBackendRegByName(Pointer<Char> name) {
    return _ggmlRegistryFallbackOr<ggml_backend_reg_t>(
      nullptr,
      () => ggml_backend_reg_by_name(name),
      () => _ggmlBackendRegByNameFallback?.call(name),
    );
  }

  /// `ggml_backend_reg_get_proc_address`, or `null` when neither the primary
  /// asset nor the ggml runtime exports it.
  Pointer<Void>? _ggmlBackendRegGetProcAddress(
    ggml_backend_reg_t reg,
    Pointer<Char> name,
  ) {
    return _ggmlRegistryFallbackOr<Pointer<Void>?>(
      null,
      () => _ggmlBackendRegGetProcAddressPrimary(reg, name),
      () => _ggmlBackendRegGetProcAddressFallback?.call(reg, name),
    );
  }

  ggml_backend_dev_t _ggmlBackendRegDevGet(ggml_backend_reg_t reg, int index) {
    return _ggmlRegistryFallbackOr<ggml_backend_dev_t>(
      nullptr,
      () => ggml_backend_reg_dev_get(reg, index),
      () => _ggmlBackendRegDevGetFallback?.call(reg, index),
    );
  }

  int _ggmlBackendDevCount() {
    return _ggmlRegistryFallbackOr<int>(
      0,
      ggml_backend_dev_count,
      () => _ggmlBackendDevCountFallback?.call(),
    );
  }

  Pointer<Char> _ggmlBackendDevName(ggml_backend_dev_t dev) {
    return _ggmlRegistryFallbackOr<Pointer<Char>>(
      nullptr,
      () => ggml_backend_dev_name(dev),
      () => _ggmlBackendDevNameFallback?.call(dev),
    );
  }

  ggml_backend_reg_t _ggmlBackendDevBackendReg(ggml_backend_dev_t dev) {
    return _ggmlRegistryFallbackOr<ggml_backend_reg_t>(
      nullptr,
      () => ggml_backend_dev_backend_reg(dev),
      () => _ggmlBackendDevBackendRegFallback?.call(dev),
    );
  }

  ggml_backend_dev_t _ggmlBackendDevByType(ggml_backend_dev_type type) {
    return _ggmlRegistryFallbackOr<ggml_backend_dev_t>(
      nullptr,
      () => ggml_backend_dev_by_type(type),
      () => _ggmlBackendDevByTypeFallback?.call(type.value),
    );
  }

  ggml_backend_buffer_type_t _ggmlBackendDevBufferType(ggml_backend_dev_t dev) {
    return _ggmlRegistryFallbackOr<ggml_backend_buffer_type_t>(
      nullptr,
      () => ggml_backend_dev_buffer_type(dev),
      () => _ggmlBackendDevBufferTypeFallback?.call(dev),
    );
  }

  /// Raw `ggml_backend_dev_type` value (the C enum int) for a device.
  /// Callers compare against `ggml_backend_dev_type.GGML_*.value` so a
  /// newer llama.cpp adding a new enum variant doesn't crash here via
  /// the high-level binding's `fromValue` ArgumentError — unknown
  /// values just don't match any of the GPU-class checks. Returns `-1`
  /// when both the primary `@DefaultAsset` lookup and the ggml-runtime
  /// fallback can't resolve the symbol.
  int _ggmlBackendDevType(ggml_backend_dev_t dev) {
    return _ggmlRegistryFallbackOr<int>(
      -1,
      () => ggml_backend_dev_type$1(dev).value,
      () => _ggmlBackendDevTypeFallback?.call(dev),
    );
  }

  /// Routes `ggml_backend_dev_get_props` through the registry fallback
  /// so the call lands on whichever ggml runtime owns the device state
  /// on Windows split bundles. Returns `false` when the symbol is
  /// unavailable from both the primary asset and the ggml runtime.
  bool _ggmlBackendDevGetProps(
    ggml_backend_dev_t dev,
    Pointer<ggml_backend_dev_props> props,
  ) {
    final barrier = _calls.failures.barrier;
    if (barrier != null) return barrier.ggmlBackendDevGetProps(dev, props);
    return _ggmlRegistryFallbackOr<bool>(
      false,
      () {
        ggml_backend_dev_get_props(dev, props);
        return true;
      },
      () {
        final fn = _ggmlBackendDevGetPropsFallback;
        if (fn == null) return null;
        fn(dev, props);
        return true;
      },
    );
  }
}
