part of 'llama_cpp_service.dart';

typedef _GgmlBackendLoadNative = ggml_backend_reg_t Function(Pointer<Char>);
typedef _GgmlBackendLoadDart = ggml_backend_reg_t Function(Pointer<Char>);

typedef _TtsApiVersionNative = Uint32 Function();
typedef _TtsApiVersionDart = int Function();
typedef _TtsRequestDefaultNative = llama_dart_tts_request Function();
typedef _TtsRequestDefaultDart = llama_dart_tts_request Function();
typedef _TtsGetInfoNative =
    Int32 Function(Pointer<mtmd_context>, Pointer<llama_dart_tts_info>);
typedef _TtsGetInfoDart =
    int Function(Pointer<mtmd_context>, Pointer<llama_dart_tts_info>);
typedef _TtsInitNative =
    Pointer<llama_dart_tts> Function(
      Pointer<llama_context>,
      Pointer<mtmd_context>,
      Pointer<Int32>,
    );
typedef _TtsInitDart =
    Pointer<llama_dart_tts> Function(
      Pointer<llama_context>,
      Pointer<mtmd_context>,
      Pointer<Int32>,
    );
typedef _TtsFreeNative = Void Function(Pointer<llama_dart_tts>);
typedef _TtsFreeDart = void Function(Pointer<llama_dart_tts>);
typedef _TtsStartNative =
    Int32 Function(Pointer<llama_dart_tts>, Pointer<llama_dart_tts_request>);
typedef _TtsStartDart =
    int Function(Pointer<llama_dart_tts>, Pointer<llama_dart_tts_request>);
typedef _TtsStepNative =
    Int32 Function(Pointer<llama_dart_tts>, Pointer<llama_dart_tts_progress>);
typedef _TtsStepDart =
    int Function(Pointer<llama_dart_tts>, Pointer<llama_dart_tts_progress>);
typedef _TtsCancelNative = Void Function(Pointer<llama_dart_tts>);
typedef _TtsCancelDart = void Function(Pointer<llama_dart_tts>);
typedef _TtsSetCancelFlagNative =
    Int32 Function(Pointer<llama_dart_tts>, Pointer<Int8>);
typedef _TtsSetCancelFlagDart =
    int Function(Pointer<llama_dart_tts>, Pointer<Int8>);
typedef _TtsResetNative = Int32 Function(Pointer<llama_dart_tts>);
typedef _TtsResetDart = int Function(Pointer<llama_dart_tts>);
typedef _TtsGetOutputInfoNative =
    Int32 Function(
      Pointer<llama_dart_tts>,
      Pointer<llama_dart_tts_output_info>,
    );
typedef _TtsGetOutputInfoDart =
    int Function(Pointer<llama_dart_tts>, Pointer<llama_dart_tts_output_info>);
typedef _TtsReadPcmNative =
    Int32 Function(
      Pointer<llama_dart_tts>,
      Int64,
      Pointer<Float>,
      Size,
      Pointer<Size>,
    );
typedef _TtsReadPcmDart =
    int Function(
      Pointer<llama_dart_tts>,
      int,
      Pointer<Float>,
      int,
      Pointer<Size>,
    );
typedef _TtsLastErrorNative = Pointer<Char> Function(Pointer<llama_dart_tts>);
typedef _TtsLastErrorDart = Pointer<Char> Function(Pointer<llama_dart_tts>);
typedef _TtsSupportedModelTypesNative = Uint32 Function();
typedef _TtsSupportedModelTypesDart = int Function();
typedef _TtsGetInfoExtNative =
    Int32 Function(Pointer<mtmd_context>, Uint32, Pointer<llama_dart_tts_info>);
typedef _TtsGetInfoExtDart =
    int Function(Pointer<mtmd_context>, int, Pointer<llama_dart_tts_info>);
typedef _TtsInitExtNative =
    Pointer<llama_dart_tts> Function(
      Pointer<llama_context>,
      Pointer<mtmd_context>,
      Uint32,
      Pointer<Int32>,
    );
typedef _TtsInitExtDart =
    Pointer<llama_dart_tts> Function(
      Pointer<llama_context>,
      Pointer<mtmd_context>,
      int,
      Pointer<Int32>,
    );
typedef _TtsStartWithVoiceNative =
    Int32 Function(
      Pointer<llama_dart_tts>,
      Pointer<llama_dart_tts_request>,
      Pointer<Char>,
    );
typedef _TtsStartWithVoiceDart =
    int Function(
      Pointer<llama_dart_tts>,
      Pointer<llama_dart_tts_request>,
      Pointer<Char>,
    );
typedef _TtsGetVoiceCountNative =
    Int32 Function(Pointer<mtmd_context>, Uint32, Pointer<Int32>);
typedef _TtsGetVoiceCountDart =
    int Function(Pointer<mtmd_context>, int, Pointer<Int32>);
typedef _TtsGetVoiceNameNative =
    Int32 Function(
      Pointer<mtmd_context>,
      Uint32,
      Int32,
      Pointer<Char>,
      Size,
      Pointer<Size>,
    );
typedef _TtsGetVoiceNameDart =
    int Function(
      Pointer<mtmd_context>,
      int,
      int,
      Pointer<Char>,
      int,
      Pointer<Size>,
    );
typedef _GgmlBackendInitNative = ggml_backend_reg_t Function();
typedef _GgmlBackendInitDart = ggml_backend_reg_t Function();
typedef _GgmlBackendLoadAllNative = Void Function();
typedef _GgmlBackendLoadAllDart = void Function();
typedef _GgmlBackendLoadAllFromPathNative = Void Function(Pointer<Char>);
typedef _GgmlBackendLoadAllFromPathDart = void Function(Pointer<Char>);
typedef _GgmlBackendScoreNative = Int32 Function();
typedef _GgmlBackendScoreDart = int Function();
typedef _GgmlBackendRegisterNative = Void Function(ggml_backend_reg_t);
typedef _GgmlBackendRegisterDart = void Function(ggml_backend_reg_t);
typedef _GgmlBackendRegCountNative = Size Function();
typedef _GgmlBackendRegCountDart = int Function();
typedef _GgmlBackendRegGetNative = ggml_backend_reg_t Function(Size);
typedef _GgmlBackendRegGetDart = ggml_backend_reg_t Function(int);
typedef _GgmlBackendRegNameNative = Pointer<Char> Function(ggml_backend_reg_t);
typedef _GgmlBackendRegNameDart = Pointer<Char> Function(ggml_backend_reg_t);
typedef _GgmlBackendRegGetProcAddressNative =
    Pointer<Void> Function(ggml_backend_reg_t, Pointer<Char>);
typedef _GgmlBackendRegGetProcAddressDart =
    Pointer<Void> Function(ggml_backend_reg_t, Pointer<Char>);
typedef _GgmlBackendRegByNameNative =
    ggml_backend_reg_t Function(Pointer<Char>);
typedef _GgmlBackendRegByNameDart = ggml_backend_reg_t Function(Pointer<Char>);
typedef _GgmlBackendRegDevCountNative = Size Function(ggml_backend_reg_t);
typedef _GgmlBackendRegDevCountDart = int Function(ggml_backend_reg_t);
typedef _GgmlBackendRegDevGetNative =
    ggml_backend_dev_t Function(ggml_backend_reg_t, Size);
typedef _GgmlBackendRegDevGetDart =
    ggml_backend_dev_t Function(ggml_backend_reg_t, int);
typedef _LoadLibraryExWNative =
    Pointer<Void> Function(Pointer<Utf16>, Pointer<Void>, Uint32);
typedef _LoadLibraryExWDart =
    Pointer<Void> Function(Pointer<Utf16>, Pointer<Void>, int);
typedef _FreeLibraryNative = Int32 Function(Pointer<Void>);
typedef _FreeLibraryDart = int Function(Pointer<Void>);
typedef _SetErrorModeNative = Uint32 Function(Uint32);
typedef _SetErrorModeDart = int Function(int);
typedef _GgmlBackendDevCountNative = Size Function();
typedef _GgmlBackendDevCountDart = int Function();
typedef _GgmlBackendDevGetNative = ggml_backend_dev_t Function(Size);
typedef _GgmlBackendDevGetDart = ggml_backend_dev_t Function(int);
typedef _GgmlBackendDevNameNative = Pointer<Char> Function(ggml_backend_dev_t);
typedef _GgmlBackendDevNameDart = Pointer<Char> Function(ggml_backend_dev_t);
typedef _GgmlBackendDevBackendRegNative =
    ggml_backend_reg_t Function(ggml_backend_dev_t);
typedef _GgmlBackendDevBackendRegDart =
    ggml_backend_reg_t Function(ggml_backend_dev_t);
typedef _GgmlBackendDevByTypeNative = ggml_backend_dev_t Function(UnsignedInt);
typedef _GgmlBackendDevByTypeDart = ggml_backend_dev_t Function(int);
typedef _GgmlBackendDevBufferTypeNative =
    ggml_backend_buffer_type_t Function(ggml_backend_dev_t);
typedef _GgmlBackendDevBufferTypeDart =
    ggml_backend_buffer_type_t Function(ggml_backend_dev_t);
typedef _GgmlBackendDevTypeNative = UnsignedInt Function(ggml_backend_dev_t);
typedef _GgmlBackendDevTypeDart = int Function(ggml_backend_dev_t);
typedef _GgmlBackendDevGetPropsNative =
    Void Function(ggml_backend_dev_t, Pointer<ggml_backend_dev_props>);
typedef _GgmlBackendDevGetPropsDart =
    void Function(ggml_backend_dev_t, Pointer<ggml_backend_dev_props>);
typedef _GgmlBackendDevMemoryNative =
    Void Function(ggml_backend_dev_t, Pointer<Size>, Pointer<Size>);
typedef _GgmlBackendDevMemoryDart =
    void Function(ggml_backend_dev_t, Pointer<Size>, Pointer<Size>);
typedef _LlamaDartSetLogLevelNative = Void Function(Int32);
typedef _LlamaDartSetLogLevelDart = void Function(int);
typedef _LlamaDartReasoningBudgetInitNative =
    Pointer<llama_sampler> Function(
      Pointer<llama_vocab>,
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Char>,
      Int32,
      Bool,
      Pointer<llama_sampler>,
      Pointer<Int32>,
      Int32,
    );
typedef _LlamaDartReasoningBudgetInitDart =
    Pointer<llama_sampler> Function(
      Pointer<llama_vocab>,
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Char>,
      int,
      bool,
      Pointer<llama_sampler>,
      Pointer<Int32>,
      int,
    );
typedef _LlamaDartSpeculativeInitNative =
    Pointer<llama_dart_speculative> Function(
      Pointer<llama_model>,
      Pointer<llama_model>,
      Pointer<llama_context>,
      llama_context_params,
      Pointer<llama_dart_speculative_params>,
    );
typedef _LlamaDartSpeculativeInitDart =
    Pointer<llama_dart_speculative> Function(
      Pointer<llama_model>,
      Pointer<llama_model>,
      Pointer<llama_context>,
      llama_context_params,
      Pointer<llama_dart_speculative_params>,
    );
typedef _LlamaDartSpeculativeFreeNative =
    Void Function(Pointer<llama_dart_speculative>);
typedef _LlamaDartSpeculativeFreeDart =
    void Function(Pointer<llama_dart_speculative>);
typedef _LlamaDartSpeculativeGetDraftContextNative =
    Pointer<llama_context> Function(Pointer<llama_dart_speculative>);
typedef _LlamaDartSpeculativeGetDraftContextDart =
    Pointer<llama_context> Function(Pointer<llama_dart_speculative>);
typedef _LlamaDartSpeculativeBeginNative =
    Bool Function(
      Pointer<llama_dart_speculative>,
      llama_seq_id,
      Pointer<Int32>,
      Int32,
    );
typedef _LlamaDartSpeculativeBeginDart =
    bool Function(Pointer<llama_dart_speculative>, int, Pointer<Int32>, int);
typedef _LlamaDartSpeculativeProcessBatchNative =
    Bool Function(Pointer<llama_dart_speculative>, llama_batch);
typedef _LlamaDartSpeculativeProcessBatchDart =
    bool Function(Pointer<llama_dart_speculative>, llama_batch);
typedef _LlamaDartSpeculativeDraftNative =
    Int32 Function(
      Pointer<llama_dart_speculative>,
      llama_seq_id,
      llama_pos,
      llama_token,
      Pointer<Int32>,
      Int32,
      Int32,
      Pointer<Int32>,
      Int32,
    );
typedef _LlamaDartSpeculativeDraftDart =
    int Function(
      Pointer<llama_dart_speculative>,
      int,
      int,
      int,
      Pointer<Int32>,
      int,
      int,
      Pointer<Int32>,
      int,
    );
typedef _LlamaDartSpeculativeAcceptNative =
    Void Function(Pointer<llama_dart_speculative>, llama_seq_id, Uint16);
typedef _LlamaDartSpeculativeAcceptDart =
    void Function(Pointer<llama_dart_speculative>, int, int);
typedef _MtmdDefaultMarkerNative = Pointer<Char> Function();
typedef _MtmdDefaultMarkerDart = Pointer<Char> Function();
typedef _MtmdContextParamsDefaultNative = mtmd_context_params Function();
typedef _MtmdContextParamsDefaultDart = mtmd_context_params Function();
typedef _MtmdInitFromFileNative =
    Pointer<mtmd_context> Function(
      Pointer<Char>,
      Pointer<llama_model>,
      mtmd_context_params,
    );
typedef _MtmdInitFromFileDart =
    Pointer<mtmd_context> Function(
      Pointer<Char>,
      Pointer<llama_model>,
      mtmd_context_params,
    );
typedef _MtmdFreeNative = Void Function(Pointer<mtmd_context>);
typedef _MtmdFreeDart = void Function(Pointer<mtmd_context>);
typedef _MtmdInputChunksInitNative = Pointer<mtmd_input_chunks> Function();
typedef _MtmdInputChunksInitDart = Pointer<mtmd_input_chunks> Function();
typedef _MtmdInputChunksFreeNative = Void Function(Pointer<mtmd_input_chunks>);
typedef _MtmdInputChunksFreeDart = void Function(Pointer<mtmd_input_chunks>);
typedef _MtmdHelperInitOptDefaultNative = mtmd_helper_init_opt Function();
typedef _MtmdHelperInitOptDefaultDart = mtmd_helper_init_opt Function();
typedef _MtmdHelperBitmapInitFromFileNative =
    mtmd_helper_bitmap_wrapper Function(
      Pointer<mtmd_context>,
      Pointer<Char>,
      Bool,
      mtmd_helper_init_opt,
    );
typedef _MtmdHelperBitmapInitFromFileDart =
    mtmd_helper_bitmap_wrapper Function(
      Pointer<mtmd_context>,
      Pointer<Char>,
      bool,
      mtmd_helper_init_opt,
    );
typedef _MtmdHelperBitmapInitFromBufNative =
    mtmd_helper_bitmap_wrapper Function(
      Pointer<mtmd_context>,
      Pointer<UnsignedChar>,
      Size,
      Bool,
      mtmd_helper_init_opt,
    );
typedef _MtmdHelperBitmapInitFromBufDart =
    mtmd_helper_bitmap_wrapper Function(
      Pointer<mtmd_context>,
      Pointer<UnsignedChar>,
      int,
      bool,
      mtmd_helper_init_opt,
    );
typedef _MtmdBitmapInitFromAudioNative =
    Pointer<mtmd_bitmap> Function(Size, Pointer<Float>);
typedef _MtmdBitmapInitFromAudioDart =
    Pointer<mtmd_bitmap> Function(int, Pointer<Float>);
typedef _MtmdSupportVisionNative = Bool Function(Pointer<mtmd_context>);
typedef _MtmdSupportVisionDart = bool Function(Pointer<mtmd_context>);
typedef _MtmdSupportAudioNative = Bool Function(Pointer<mtmd_context>);
typedef _MtmdSupportAudioDart = bool Function(Pointer<mtmd_context>);
typedef _MtmdSupportVideoNative = Bool Function(Pointer<mtmd_context>);
typedef _MtmdSupportVideoDart = bool Function(Pointer<mtmd_context>);
typedef _MtmdBitmapFreeNative = Void Function(Pointer<mtmd_bitmap>);
typedef _MtmdBitmapFreeDart = void Function(Pointer<mtmd_bitmap>);
typedef _MtmdTokenizeNative =
    Int32 Function(
      Pointer<mtmd_context>,
      Pointer<mtmd_input_chunks>,
      Pointer<mtmd_input_text>,
      Pointer<Pointer<mtmd_bitmap>>,
      Size,
    );
typedef _MtmdTokenizeDart =
    int Function(
      Pointer<mtmd_context>,
      Pointer<mtmd_input_chunks>,
      Pointer<mtmd_input_text>,
      Pointer<Pointer<mtmd_bitmap>>,
      int,
    );
typedef _MtmdHelperEvalChunksNative =
    Int32 Function(
      Pointer<mtmd_context>,
      Pointer<llama_context>,
      Pointer<mtmd_input_chunks>,
      llama_pos,
      llama_seq_id,
      Int32,
      Bool,
      Pointer<llama_pos>,
    );
typedef _MtmdHelperEvalChunksDart =
    int Function(
      Pointer<mtmd_context>,
      Pointer<llama_context>,
      Pointer<mtmd_input_chunks>,
      int,
      int,
      int,
      bool,
      Pointer<llama_pos>,
    );
typedef _MtmdLogSetNative = Void Function(ggml_log_callback, Pointer<Void>);
typedef _MtmdLogSetDart = void Function(ggml_log_callback, Pointer<Void>);
typedef _LlamaDartSamplerSampleAndAcceptNNative =
    Int32 Function(
      Pointer<llama_sampler>,
      Pointer<llama_context>,
      Pointer<Int32>,
      Int32,
      Pointer<Int32>,
      Int32,
      Pointer<Int32>,
      Int32,
    );
typedef _LlamaDartSamplerSampleAndAcceptNDart =
    int Function(
      Pointer<llama_sampler>,
      Pointer<llama_context>,
      Pointer<Int32>,
      int,
      Pointer<Int32>,
      int,
      Pointer<Int32>,
      int,
    );

@Native<_LlamaDartSpeculativeInitNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_speculative_init',
)
external Pointer<llama_dart_speculative> _llamadartWrapperSpeculativeInit(
  Pointer<llama_model> targetModel,
  Pointer<llama_model> draftModel,
  Pointer<llama_context> targetContext,
  llama_context_params contextParams,
  Pointer<llama_dart_speculative_params> params,
);

@Native<_LlamaDartSpeculativeFreeNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_speculative_free',
)
external void _llamadartWrapperSpeculativeFree(
  Pointer<llama_dart_speculative> speculative,
);

@Native<_LlamaDartSpeculativeGetDraftContextNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_speculative_get_draft_context',
)
external Pointer<llama_context> _llamadartWrapperSpeculativeGetDraftContext(
  Pointer<llama_dart_speculative> speculative,
);

@Native<_LlamaDartSpeculativeBeginNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_speculative_begin',
)
external bool _llamadartWrapperSpeculativeBegin(
  Pointer<llama_dart_speculative> speculative,
  int seqId,
  Pointer<Int32> prompt,
  int promptCount,
);

@Native<_LlamaDartSpeculativeProcessBatchNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_speculative_process_batch',
)
external bool _llamadartWrapperSpeculativeProcessBatch(
  Pointer<llama_dart_speculative> speculative,
  llama_batch batch,
);

@Native<_LlamaDartSpeculativeDraftNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_speculative_draft',
)
external int _llamadartWrapperSpeculativeDraft(
  Pointer<llama_dart_speculative> speculative,
  int seqId,
  int nPast,
  int idLast,
  Pointer<Int32> prompt,
  int promptCount,
  int draftTokenMax,
  Pointer<Int32> outTokens,
  int outCapacity,
);

@Native<_LlamaDartSpeculativeAcceptNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_speculative_accept',
)
external void _llamadartWrapperSpeculativeAccept(
  Pointer<llama_dart_speculative> speculative,
  int seqId,
  int acceptedCount,
);

@Native<_LlamaDartSamplerSampleAndAcceptNNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_sampler_sample_and_accept_n',
)
external int _llamadartWrapperSamplerSampleAndAcceptN(
  Pointer<llama_sampler> sampler,
  Pointer<llama_context> context,
  Pointer<Int32> indexes,
  int indexCount,
  Pointer<Int32> draftTokens,
  int draftCount,
  Pointer<Int32> outTokens,
  int outCapacity,
);

@Native<_GgmlBackendLoadNative>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_load',
)
external ggml_backend_reg_t _windowsGgmlBackendLoad(Pointer<Char> path);

@Native<_GgmlBackendLoadAllNative>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_load_all',
)
external void _windowsGgmlBackendLoadAll();

@Native<_GgmlBackendLoadAllFromPathNative>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_load_all_from_path',
)
external void _windowsGgmlBackendLoadAllFromPath(Pointer<Char> directory);

@Native<_GgmlBackendRegisterNative>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_register',
)
external void _windowsGgmlBackendRegister(ggml_backend_reg_t registry);

@Native<_GgmlBackendRegCountNative>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_reg_count',
)
external int _windowsGgmlBackendRegCount();

@Native<_GgmlBackendRegGetNative>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_reg_get',
)
external ggml_backend_reg_t _windowsGgmlBackendRegGet(int index);

@Native<_GgmlBackendRegNameNative>(
  assetId: 'package:llamadart/ggml-base',
  symbol: 'ggml_backend_reg_name',
)
external Pointer<Char> _windowsGgmlBackendRegName(ggml_backend_reg_t registry);

@Native<_GgmlBackendRegByNameNative>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_reg_by_name',
)
external ggml_backend_reg_t _windowsGgmlBackendRegByName(Pointer<Char> name);

@Native<_GgmlBackendRegGetProcAddressNative>(
  assetId: 'package:llamadart/ggml-base',
  symbol: 'ggml_backend_reg_get_proc_address',
)
external Pointer<Void> _windowsGgmlBackendRegGetProcAddress(
  ggml_backend_reg_t registry,
  Pointer<Char> name,
);

@Native<_GgmlBackendRegDevCountNative>(
  assetId: 'package:llamadart/ggml-base',
  symbol: 'ggml_backend_reg_dev_count',
)
external int _windowsGgmlBackendRegDevCount(ggml_backend_reg_t registry);

@Native<_GgmlBackendRegDevGetNative>(
  assetId: 'package:llamadart/ggml-base',
  symbol: 'ggml_backend_reg_dev_get',
)
external ggml_backend_dev_t _windowsGgmlBackendRegDevGet(
  ggml_backend_reg_t registry,
  int index,
);

@Native<_GgmlBackendDevCountNative>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_dev_count',
)
external int _windowsGgmlBackendDevCount();

@Native<_GgmlBackendDevGetNative>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_dev_get',
)
external ggml_backend_dev_t _windowsGgmlBackendDevGet(int index);

@Native<_GgmlBackendDevNameNative>(
  assetId: 'package:llamadart/ggml-base',
  symbol: 'ggml_backend_dev_name',
)
external Pointer<Char> _windowsGgmlBackendDevName(ggml_backend_dev_t device);

@Native<_GgmlBackendDevBackendRegNative>(
  assetId: 'package:llamadart/ggml-base',
  symbol: 'ggml_backend_dev_backend_reg',
)
external ggml_backend_reg_t _windowsGgmlBackendDevBackendReg(
  ggml_backend_dev_t device,
);

@Native<_GgmlBackendDevByTypeNative>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_dev_by_type',
)
external ggml_backend_dev_t _windowsGgmlBackendDevByType(int type);

@Native<_GgmlBackendDevBufferTypeNative>(
  assetId: 'package:llamadart/ggml-base',
  symbol: 'ggml_backend_dev_buffer_type',
)
external ggml_backend_buffer_type_t _windowsGgmlBackendDevBufferType(
  ggml_backend_dev_t device,
);

@Native<_GgmlBackendDevTypeNative>(
  assetId: 'package:llamadart/ggml-base',
  symbol: 'ggml_backend_dev_type',
)
external int _windowsGgmlBackendDevType(ggml_backend_dev_t device);

@Native<_GgmlBackendDevGetPropsNative>(
  assetId: 'package:llamadart/ggml-base',
  symbol: 'ggml_backend_dev_get_props',
)
external void _windowsGgmlBackendDevGetProps(
  ggml_backend_dev_t device,
  Pointer<ggml_backend_dev_props> properties,
);

@Native<_GgmlBackendDevMemoryNative>(
  assetId: 'package:llamadart/ggml-base',
  symbol: 'ggml_backend_dev_memory',
)
external void _windowsGgmlBackendDevMemory(
  ggml_backend_dev_t device,
  Pointer<Size> free,
  Pointer<Size> total,
);
