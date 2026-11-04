import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../../core/exceptions.dart';
import '../../core/llama_logger.dart';
import '../../core/models/chat/chat_message.dart';
import '../../core/models/chat/chat_role.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/gpu_device_info.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/diagnostics/model_file_type.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/template/chat_template_engine.dart';
import 'load_param_helpers.dart';
import 'sampled_token_validation.dart';
import 'bindings.dart';
import 'llama_cpp_raw_bindings.dart' as raw_bindings;

const _llamadartWrapperAssetId = 'package:llamadart/llamadart_wrapper';

typedef _GgmlBackendLoadNative = ggml_backend_reg_t Function(Pointer<Char>);
typedef _GgmlBackendLoadDart = ggml_backend_reg_t Function(Pointer<Char>);
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
typedef _LlamaDartSpeculativeNeedEmbdNative =
    Bool Function(Pointer<llama_dart_speculative>);
typedef _LlamaDartSpeculativeNeedEmbdDart =
    bool Function(Pointer<llama_dart_speculative>);
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
typedef _MtmdHelperBitmapInitFromFileNative =
    mtmd_helper_bitmap_wrapper Function(
      Pointer<mtmd_context>,
      Pointer<Char>,
      Bool,
    );
typedef _MtmdHelperBitmapInitFromFileDart =
    mtmd_helper_bitmap_wrapper Function(
      Pointer<mtmd_context>,
      Pointer<Char>,
      bool,
    );
typedef _MtmdHelperBitmapInitFromBufNative =
    mtmd_helper_bitmap_wrapper Function(
      Pointer<mtmd_context>,
      Pointer<UnsignedChar>,
      Size,
      Bool,
    );
typedef _MtmdHelperBitmapInitFromBufDart =
    mtmd_helper_bitmap_wrapper Function(
      Pointer<mtmd_context>,
      Pointer<UnsignedChar>,
      int,
      bool,
    );
typedef _MtmdBitmapInitFromAudioNative =
    Pointer<mtmd_bitmap> Function(Size, Pointer<Float>);
typedef _MtmdBitmapInitFromAudioDart =
    Pointer<mtmd_bitmap> Function(int, Pointer<Float>);
typedef _MtmdSupportVisionNative = Bool Function(Pointer<mtmd_context>);
typedef _MtmdSupportVisionDart = bool Function(Pointer<mtmd_context>);
typedef _MtmdSupportAudioNative = Bool Function(Pointer<mtmd_context>);
typedef _MtmdSupportAudioDart = bool Function(Pointer<mtmd_context>);
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
typedef _LlamaDartMtpInitNative =
    Pointer<llama_dart_mtp> Function(
      Pointer<llama_model>,
      Pointer<llama_context>,
      llama_context_params,
      Int32,
      Int32,
      Float,
      Bool,
    );
typedef _LlamaDartMtpInitDart =
    Pointer<llama_dart_mtp> Function(
      Pointer<llama_model>,
      Pointer<llama_context>,
      llama_context_params,
      int,
      int,
      double,
      bool,
    );
typedef _LlamaDartMtpFreeNative = Void Function(Pointer<llama_dart_mtp>);
typedef _LlamaDartMtpFreeDart = void Function(Pointer<llama_dart_mtp>);
typedef _LlamaDartMtpGetDraftContextNative =
    Pointer<llama_context> Function(Pointer<llama_dart_mtp>);
typedef _LlamaDartMtpGetDraftContextDart =
    Pointer<llama_context> Function(Pointer<llama_dart_mtp>);
typedef _LlamaDartMtpBeginNative =
    Bool Function(Pointer<llama_dart_mtp>, llama_seq_id, Pointer<Int32>, Int32);
typedef _LlamaDartMtpBeginDart =
    bool Function(Pointer<llama_dart_mtp>, int, Pointer<Int32>, int);
typedef _LlamaDartMtpProcessBatchNative =
    Bool Function(Pointer<llama_dart_mtp>, llama_batch);
typedef _LlamaDartMtpProcessBatchDart =
    bool Function(Pointer<llama_dart_mtp>, llama_batch);
typedef _LlamaDartMtpDraftNative =
    Int32 Function(
      Pointer<llama_dart_mtp>,
      llama_seq_id,
      llama_pos,
      llama_token,
      Pointer<Int32>,
      Int32,
      Int32,
      Pointer<Int32>,
      Int32,
    );
typedef _LlamaDartMtpDraftDart =
    int Function(
      Pointer<llama_dart_mtp>,
      int,
      int,
      int,
      Pointer<Int32>,
      int,
      int,
      Pointer<Int32>,
      int,
    );
typedef _LlamaDartMtpAcceptNative =
    Void Function(Pointer<llama_dart_mtp>, llama_seq_id, Uint16);
typedef _LlamaDartMtpAcceptDart =
    void Function(Pointer<llama_dart_mtp>, int, int);
typedef _LlamaDartNgramSimpleInitNative =
    Pointer<llama_dart_ngram> Function(Int32, Int32);
typedef _LlamaDartNgramSimpleInitDart =
    Pointer<llama_dart_ngram> Function(int, int);
typedef _LlamaDartNgramFreeNative = Void Function(Pointer<llama_dart_ngram>);
typedef _LlamaDartNgramFreeDart = void Function(Pointer<llama_dart_ngram>);
typedef _LlamaDartNgramBeginNative =
    Bool Function(
      Pointer<llama_dart_ngram>,
      llama_seq_id,
      Pointer<Int32>,
      Int32,
    );
typedef _LlamaDartNgramBeginDart =
    bool Function(Pointer<llama_dart_ngram>, int, Pointer<Int32>, int);
typedef _LlamaDartNgramProcessBatchNative =
    Bool Function(Pointer<llama_dart_ngram>, llama_batch);
typedef _LlamaDartNgramProcessBatchDart =
    bool Function(Pointer<llama_dart_ngram>, llama_batch);
typedef _LlamaDartNgramDraftNative =
    Int32 Function(
      Pointer<llama_dart_ngram>,
      llama_seq_id,
      llama_pos,
      llama_token,
      Pointer<Int32>,
      Int32,
      Int32,
      Pointer<Int32>,
      Int32,
    );
typedef _LlamaDartNgramDraftDart =
    int Function(
      Pointer<llama_dart_ngram>,
      int,
      int,
      int,
      Pointer<Int32>,
      int,
      int,
      Pointer<Int32>,
      int,
    );
typedef _LlamaDartNgramAcceptNative =
    Void Function(Pointer<llama_dart_ngram>, llama_seq_id, Uint16);
typedef _LlamaDartNgramAcceptDart =
    void Function(Pointer<llama_dart_ngram>, int, int);
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

@Native<_LlamaDartSpeculativeNeedEmbdNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_speculative_need_embd',
)
external bool _llamadartWrapperSpeculativeNeedEmbd(
  Pointer<llama_dart_speculative> speculative,
);

@Native<_LlamaDartSpeculativeNeedEmbdNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_speculative_need_embd_nextn',
)
external bool _llamadartWrapperSpeculativeNeedEmbdNextn(
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

@Native<_LlamaDartMtpInitNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_mtp_init',
)
external Pointer<llama_dart_mtp> _llamadartWrapperMtpInit(
  Pointer<llama_model> model,
  Pointer<llama_context> context,
  llama_context_params contextParams,
  int draftTokenMax,
  int draftTokenMin,
  double minProbability,
  bool backendSampling,
);

@Native<_LlamaDartMtpInitNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_mtp_init_with_draft_model',
)
external Pointer<llama_dart_mtp> _llamadartWrapperMtpInitWithDraftModel(
  Pointer<llama_model> draftModel,
  Pointer<llama_context> context,
  llama_context_params contextParams,
  int draftTokenMax,
  int draftTokenMin,
  double minProbability,
  bool backendSampling,
);

@Native<_LlamaDartMtpFreeNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_mtp_free',
)
external void _llamadartWrapperMtpFree(Pointer<llama_dart_mtp> mtp);

@Native<_LlamaDartMtpGetDraftContextNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_mtp_get_draft_context',
)
external Pointer<llama_context> _llamadartWrapperMtpGetDraftContext(
  Pointer<llama_dart_mtp> mtp,
);

@Native<_LlamaDartMtpBeginNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_mtp_begin',
)
external bool _llamadartWrapperMtpBegin(
  Pointer<llama_dart_mtp> mtp,
  int seqId,
  Pointer<Int32> prompt,
  int promptCount,
);

@Native<_LlamaDartMtpProcessBatchNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_mtp_process_batch',
)
external bool _llamadartWrapperMtpProcessBatch(
  Pointer<llama_dart_mtp> mtp,
  llama_batch batch,
);

@Native<_LlamaDartMtpDraftNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_mtp_draft',
)
external int _llamadartWrapperMtpDraft(
  Pointer<llama_dart_mtp> mtp,
  int seqId,
  int nPast,
  int idLast,
  Pointer<Int32> prompt,
  int promptCount,
  int draftTokenMax,
  Pointer<Int32> outTokens,
  int outCapacity,
);

@Native<_LlamaDartMtpAcceptNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_mtp_accept',
)
external void _llamadartWrapperMtpAccept(
  Pointer<llama_dart_mtp> mtp,
  int seqId,
  int acceptedCount,
);

@Native<_LlamaDartNgramSimpleInitNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_ngram_simple_init',
)
external Pointer<llama_dart_ngram> _llamadartWrapperNgramSimpleInit(
  int ngramSize,
  int draftTokenMax,
);

@Native<_LlamaDartNgramFreeNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_ngram_free',
)
external void _llamadartWrapperNgramFree(Pointer<llama_dart_ngram> ngram);

@Native<_LlamaDartNgramBeginNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_ngram_begin',
)
external bool _llamadartWrapperNgramBegin(
  Pointer<llama_dart_ngram> ngram,
  int seqId,
  Pointer<Int32> prompt,
  int promptCount,
);

@Native<_LlamaDartNgramProcessBatchNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_ngram_process_batch',
)
external bool _llamadartWrapperNgramProcessBatch(
  Pointer<llama_dart_ngram> ngram,
  llama_batch batch,
);

@Native<_LlamaDartNgramDraftNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_ngram_draft',
)
external int _llamadartWrapperNgramDraft(
  Pointer<llama_dart_ngram> ngram,
  int seqId,
  int nPast,
  int idLast,
  Pointer<Int32> prompt,
  int promptCount,
  int draftTokenMax,
  Pointer<Int32> outTokens,
  int outCapacity,
);

@Native<_LlamaDartNgramAcceptNative>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_ngram_accept',
)
external void _llamadartWrapperNgramAccept(
  Pointer<llama_dart_ngram> ngram,
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

final RegExp _linuxLlamadartProcMapsPattern = RegExp(
  r'/libllamadart\.so(?:\.\d+)?$',
);

const int _maxLlamaCppReasoningBudgetTokens = 0x7fffffff;

class _LlamaCppThinkingBudgetConfig {
  const _LlamaCppThinkingBudgetConfig({
    required this.maxTokens,
    required this.startTag,
    required this.endTag,
    required this.forcedMessage,
  });

  final int maxTokens;
  final String startTag;
  final String endTag;
  final String forcedMessage;
}

class _LlamaCppSpeculativeConfig {
  const _LlamaCppSpeculativeConfig({
    required this.strategies,
    required this.typeNames,
    required this.draftTokenMax,
    required this.draftTokenMin,
    required this.minProbability,
    required this.draftSplitProbability,
    required this.draftModelPath,
    required this.ngramSizeN,
    required this.ngramSizeM,
    required this.ngramMinHits,
    required this.ngramMatch,
    required this.ngramTokenMin,
    required this.ngramTokenMax,
    required this.ngramCacheStaticPath,
    required this.ngramCacheDynamicPath,
  });

  final List<SpeculativeDecodingStrategy> strategies;
  final String typeNames;
  final int draftTokenMax;
  final int draftTokenMin;
  final double? minProbability;
  final double? draftSplitProbability;
  final String? draftModelPath;
  final int? ngramSizeN;
  final int? ngramSizeM;
  final int? ngramMinHits;
  final int? ngramMatch;
  final int? ngramTokenMin;
  final int? ngramTokenMax;
  final String? ngramCacheStaticPath;
  final String? ngramCacheDynamicPath;

  bool get hasDraftContextStrategy => strategies.any(
    (strategy) =>
        strategy == SpeculativeDecodingStrategy.draftSimple ||
        strategy == SpeculativeDecodingStrategy.draftEagle3 ||
        strategy == SpeculativeDecodingStrategy.mtp ||
        strategy == SpeculativeDecodingStrategy.draftDflash,
  );

  bool get requiresExternalDraftModel => strategies.any(
    (strategy) =>
        strategy == SpeculativeDecodingStrategy.draftSimple ||
        strategy == SpeculativeDecodingStrategy.draftEagle3 ||
        strategy == SpeculativeDecodingStrategy.draftDflash,
  );

  bool get usesMtp => strategies.contains(SpeculativeDecodingStrategy.mtp);

  bool get suppressDraftProcessLogits => strategies.any(
    (strategy) =>
        strategy == SpeculativeDecodingStrategy.draftSimple ||
        strategy == SpeculativeDecodingStrategy.draftEagle3 ||
        strategy == SpeculativeDecodingStrategy.draftDflash,
  );
}

class _LlamaCppMtpConfig {
  const _LlamaCppMtpConfig({
    required this.draftTokenMax,
    required this.draftTokenMin,
    required this.minProbability,
    required this.draftModelPath,
  });

  final int draftTokenMax;
  final int draftTokenMin;
  final double minProbability;
  final String? draftModelPath;
}

class _LlamaCppNgramSimpleConfig {
  const _LlamaCppNgramSimpleConfig({
    required this.draftTokenMax,
    required this.ngramSize,
  });

  final int draftTokenMax;
  final int ngramSize;
}

/// Service responsible for managing Llama.cpp models and contexts.
///
/// This service handles the direct interaction with the native Llama.cpp library,
/// including loading models, creating contexts, managing memory, and running inference.
class LlamaCppService {
  static const bool _androidVulkanAllowKqvOffload = bool.fromEnvironment(
    'LLAMADART_ANDROID_VULKAN_ALLOW_KQV',
    defaultValue: false,
  );
  static const bool _androidVulkanAllowOpOffload = bool.fromEnvironment(
    'LLAMADART_ANDROID_VULKAN_ALLOW_OP_OFFLOAD',
    defaultValue: false,
  );
  static const bool _androidVulkanAllowFlashAttn = bool.fromEnvironment(
    'LLAMADART_ANDROID_VULKAN_ALLOW_FLASH_ATTN',
    defaultValue: false,
  );
  static const int _maxStartupDiagnostics = 32;
  static const int _loadWithAlteredSearchPath = 0x00000008;
  static const int _semFailCriticalErrors = 0x0001;
  static const Map<String, int> _androidCpuVariantPriority = <String, int>{
    'android_armv9.2_2': 0,
    'android_armv9.2_1': 1,
    'android_armv9.0_1': 2,
    'android_armv8.6_1': 3,
    'android_armv8.2_2': 4,
    'android_armv8.2_1': 5,
    'android_armv8.0_1': 6,
  };
  static const Map<SpeculativeDecodingStrategy, String>
  _llamaCppSpeculativeTypeNames = <SpeculativeDecodingStrategy, String>{
    SpeculativeDecodingStrategy.draftSimple: 'draft-simple',
    SpeculativeDecodingStrategy.draftEagle3: 'draft-eagle3',
    SpeculativeDecodingStrategy.mtp: 'draft-mtp',
    SpeculativeDecodingStrategy.draftDflash: 'draft-dflash',
    SpeculativeDecodingStrategy.ngramSimple: 'ngram-simple',
    SpeculativeDecodingStrategy.ngramMapK: 'ngram-map-k',
    SpeculativeDecodingStrategy.ngramMapK4v: 'ngram-map-k4v',
    SpeculativeDecodingStrategy.ngramMod: 'ngram-mod',
    SpeculativeDecodingStrategy.ngramCache: 'ngram-cache',
  };
  static const Set<SpeculativeDecodingStrategy> _llamaCppDraftStrategies =
      <SpeculativeDecodingStrategy>{
        SpeculativeDecodingStrategy.draftSimple,
        SpeculativeDecodingStrategy.draftEagle3,
        SpeculativeDecodingStrategy.mtp,
        SpeculativeDecodingStrategy.draftDflash,
      };

  int _nextHandle = 1;
  String? _backendModuleDirectory;
  final Set<String> _loadedBackendModules = <String>{};
  final Set<String> _failedBackendModules = <String>{};
  final Map<String, DynamicLibrary> _loadedBackendLibraries =
      <String, DynamicLibrary>{};
  final Map<String, List<DynamicLibrary>> _preloadedBackendDependencyLibraries =
      <String, List<DynamicLibrary>>{};
  final List<DynamicLibrary> _preloadedCoreLibraries = <DynamicLibrary>[];
  bool _backendLoadAllSymbolUnavailable = false;
  bool _backendLoadAllFromPathSymbolUnavailable = false;
  bool _backendLoadSymbolUnavailable = false;
  bool _backendRegistrySymbolUnavailable = false;
  bool _linuxCorePreloadAttempted = false;
  bool _linuxRuntimeDepsPrepared = false;
  String? _linuxPreparedLibraryDirectory;
  bool _ggmlFallbackLookupAttempted = false;
  String? _ggmlFallbackLookupSearchKey;
  _GgmlBackendLoadDart? _ggmlBackendLoadFallback;
  _GgmlBackendLoadAllDart? _ggmlBackendLoadAllFallback;
  _GgmlBackendLoadAllFromPathDart? _ggmlBackendLoadAllFromPathFallback;
  _GgmlBackendRegisterDart? _ggmlBackendRegisterFallback;
  _GgmlBackendRegCountDart? _ggmlBackendRegCountFallback;
  _GgmlBackendRegGetDart? _ggmlBackendRegGetFallback;
  _GgmlBackendRegNameDart? _ggmlBackendRegNameFallback;
  _GgmlBackendRegByNameDart? _ggmlBackendRegByNameFallback;
  _GgmlBackendRegDevCountDart? _ggmlBackendRegDevCountFallback;
  _GgmlBackendRegDevGetDart? _ggmlBackendRegDevGetFallback;
  _GgmlBackendDevCountDart? _ggmlBackendDevCountFallback;
  _GgmlBackendDevGetDart? _ggmlBackendDevGetFallback;
  _GgmlBackendDevNameDart? _ggmlBackendDevNameFallback;
  _GgmlBackendDevBackendRegDart? _ggmlBackendDevBackendRegFallback;
  _GgmlBackendDevByTypeDart? _ggmlBackendDevByTypeFallback;
  _GgmlBackendDevTypeDart? _ggmlBackendDevTypeFallback;
  _GgmlBackendDevGetPropsDart? _ggmlBackendDevGetPropsFallback;
  _GgmlBackendDevMemoryDart? _ggmlBackendDevMemoryFallback;
  bool _logLevelFallbackLookupAttempted = false;
  String? _logLevelFallbackLookupSearchKey;
  _LlamaDartSetLogLevelDart? _llamaDartSetLogLevelFallback;
  LlamaLogLevel _configuredLogLevel = LlamaLogLevel.warn;
  String _activeBackendName = 'CPU';
  int _activeResolvedGpuLayers = 0;
  bool _mtmdFallbackLookupAttempted = false;
  bool _mtmdPrimarySymbolsUnavailable = false;
  _MtmdApi? _mtmdFallbackApi;
  bool _reasoningBudgetApiLookupAttempted = false;
  _ReasoningBudgetApi? _reasoningBudgetApi;
  bool _speculativeApiLookupAttempted = false;
  _SpeculativeApi? _speculativeApi;
  bool _mtpApiLookupAttempted = false;
  _MtpApi? _mtpApi;
  bool _ngramApiLookupAttempted = false;
  _NgramApi? _ngramApi;
  final List<String> _startupDiagnostics = <String>[];

  // --- Internal State ---
  final Map<int, _LlamaModelWrapper> _models = {};
  final Map<int, _LlamaContextWrapper> _contexts = {};
  final Map<int, int> _contextToModel = {};
  final Map<int, Pointer<llama_sampler>> _samplers = {};
  final Map<int, llama_batch> _batches = {};
  final Map<int, llama_context_params> _contextParams = {};
  final Map<int, Map<String, _LlamaLoraWrapper>> _loraAdapters = {};
  final Map<int, Map<String, double>> _activeLoras = {};
  final Map<int, String> _modelBackendNames = <int, String>{};
  final Map<int, int> _modelResolvedGpuLayers = <int, int>{};
  final Map<int, ModelParams> _modelLoadParams = <int, ModelParams>{};
  final Map<String, _LlamaModelWrapper> _speculativeDraftModels =
      <String, _LlamaModelWrapper>{};
  final Map<int, Set<String>> _modelToSpeculativeDraftModelKeys =
      <int, Set<String>>{};

  /// Refcount of in-flight `generate()` calls per context. A set would let the
  /// first completion clear the marker while another decode is still running.
  final Map<int, int> _generatingContexts = <int, int>{};

  // Mapping: modelHandle -> mtmdContextHandle
  final Map<int, int> _modelToMtmd = {};
  final Map<int, Pointer<mtmd_context>> _mtmdContexts = {};
  final Map<int, bool> _modelToMtmdUseGpu = {};

  int _getHandle() => _nextHandle++;

  /// Resolves the effective backend preference for model loading.
  ///
  /// Android keeps Vulkan bundled, but `auto` currently prefers CPU to avoid
  /// initializing optional GPU backends by default on devices with unstable
  /// Vulkan stacks.
  static GpuBackend resolvePreferredBackendForLoad(
    ModelParams modelParams, {
    bool isAndroid = false,
  }) {
    if (isAndroid && modelParams.preferredBackend == GpuBackend.auto) {
      return GpuBackend.cpu;
    }
    return modelParams.preferredBackend;
  }

  /// Resolves the effective GPU layer count for model loading.
  ///
  /// CPU backend preference always forces zero offloaded layers.
  static int resolveGpuLayersForLoad(
    ModelParams modelParams, {
    bool isAndroid = false,
  }) {
    return resolvePreferredBackendForLoad(modelParams, isAndroid: isAndroid) ==
            GpuBackend.cpu
        ? 0
        : modelParams.gpuLayers;
  }

  /// Returns whether context-time GPU offload should be disabled.
  ///
  /// When CPU mode is selected (or model load resolved to zero GPU layers),
  /// context-level offload knobs must also be disabled to prevent runtime
  /// GPU initialization during `llama_init_from_model(...)`.
  static bool shouldDisableContextGpuOffload(
    ModelParams modelParams, {
    int? resolvedGpuLayers,
  }) {
    final effectiveGpuLayers =
        resolvedGpuLayers ?? resolveGpuLayersForLoad(modelParams);
    return modelParams.preferredBackend == GpuBackend.cpu ||
        effectiveGpuLayers <= 0;
  }

  /// Returns whether Android Vulkan should use conservative context settings.
  ///
  /// Some Android Vulkan stacks can abort during decode scheduling when
  /// context-time KQV/op offload and flash-attention auto-selection stay fully
  /// enabled. We keep model layers offloaded but disable the more aggressive
  /// context compute knobs for stability.
  static bool shouldUseConservativeAndroidVulkanContextConfig(
    ModelParams modelParams, {
    int? resolvedGpuLayers,
    bool isAndroid = false,
  }) {
    if (!isAndroid) {
      return false;
    }

    final effectiveGpuLayers =
        resolvedGpuLayers ?? resolveGpuLayersForLoad(modelParams);
    return modelParams.preferredBackend == GpuBackend.vulkan &&
        effectiveGpuLayers > 0;
  }

  /// Resolves effective context batch parameters.
  ///
  /// Uses the shared non-FFI helper for consistent default resolution and
  /// clamping while allowing each backend to select its compatibility policy.
  static ({int batchSize, int microBatchSize}) resolveContextBatchSizes(
    ModelParams modelParams,
    int contextSize, {
    bool useFullContextDefaults = false,
  }) {
    return resolveModelContextBatchSizes(
      modelParams,
      contextSize,
      useFullContextDefaults: useFullContextDefaults,
    );
  }

  /// Resolves whether multimodal projector init should use GPU.
  ///
  /// This follows effective model-load configuration from model loading.
  static bool resolveMtmdUseGpuForLoad(
    ModelParams modelParams,
    int effectiveGpuLayers, {
    String? modelPath,
    bool isAndroid = false,
  }) {
    if (shouldForceCpuProjectorForAndroid(modelPath, isAndroid: isAndroid)) {
      return false;
    }

    return !shouldDisableContextGpuOffload(
      modelParams,
      resolvedGpuLayers: effectiveGpuLayers,
    );
  }

  /// Returns whether Android should keep mtmd projector work on CPU for the
  /// given model file.
  static bool shouldForceCpuProjectorForAndroid(
    String? modelPath, {
    bool isAndroid = false,
  }) {
    if (!isAndroid || modelPath == null || modelPath.isEmpty) {
      return false;
    }

    final normalized = path.basename(modelPath).toLowerCase();
    return normalized.contains('qwen3.5-0.8b') ||
        normalized.contains('qwen_qwen3.5-0.8b');
  }

  // --- Core Methods ---

  /// Sets the log level for the Llama.cpp library.
  void setLogLevel(LlamaLogLevel level) {
    _configuredLogLevel = level;
    _applyConfiguredLogLevel();
  }

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

    if (!applied) {
      // No applicable symbol found for this runtime layout.
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

  /// Initializes the Llama.cpp backend.
  ///
  /// This must be called before loading any models.
  void initializeBackend() {
    _prepareLinuxRuntimeDependenciesBeforeBinding();
    _preloadLinuxCoreLibrariesForSonameResolution();
    _backendModuleDirectory = resolveBackendModuleDirectory();
    if (_backendModuleDirectory == null && Platform.isLinux) {
      _backendModuleDirectory =
          _linuxPreparedLibraryDirectory ??
          _resolveLinuxPrimaryLibraryDirectory();
    }
    _applyConfiguredLogLevel();
    llama_backend_init();
    _refreshBackendModuleDirectoryAfterPrimaryLoad();
    _applyConfiguredLogLevel();

    if ((Platform.isMacOS || Platform.isIOS) &&
        _backendModuleDirectory == null) {
      return;
    }

    // Startup path should remain CPU-safe so reading backend options does not
    // initialize optional GPU backends.
    if (_backendModuleDirectory != null) {
      _tryLoadBackendModuleIfBundled('cpu');
    } else {
      _tryLoadBackendModule('cpu');
    }

    if (_ggmlBackendRegCount() == 0) {
      // Fallback path: attempt to load CPU backend by filename resolution.
      _tryLoadBackendModule('cpu');
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

  void _prepareLinuxRuntimeDependenciesBeforeBinding() {
    if (!Platform.isLinux || _linuxRuntimeDepsPrepared) {
      return;
    }
    _linuxRuntimeDepsPrepared = true;

    final targetDir = _resolveLinuxPrimaryLibraryDirectory();
    if (targetDir == null) {
      return;
    }

    final sourceDirectories = _linuxDependencySourceDirectories(targetDir);
    const coreLibraries = <String>[
      'libggml-base.so',
      'libggml.so',
      'libllama.so',
    ];

    for (final libraryFileName in coreLibraries) {
      copyMissingLinuxLibrary(
        targetDirectory: targetDir,
        sourceDirectories: sourceDirectories,
        fileName: libraryFileName,
        onDiagnostic: _recordStartupDiagnostic,
      );
      ensureLinuxSonameAlias(
        directory: targetDir,
        baseFileName: libraryFileName,
        onDiagnostic: _recordStartupDiagnostic,
      );
    }

    const backendModuleLibraries = <String>[
      'libggml-cpu.so',
      'libggml-vulkan.so',
      'libggml-opencl.so',
      'libggml-cuda.so',
      'libggml-blas.so',
      'libggml-hip.so',
    ];

    for (final libraryFileName in backendModuleLibraries) {
      copyMissingLinuxLibrary(
        targetDirectory: targetDir,
        sourceDirectories: sourceDirectories,
        fileName: libraryFileName,
        onDiagnostic: _recordStartupDiagnostic,
      );
      ensureLinuxSonameAlias(
        directory: targetDir,
        baseFileName: libraryFileName,
        onDiagnostic: _recordStartupDiagnostic,
      );
    }

    _linuxPreparedLibraryDirectory = targetDir;
  }

  String? _resolveLinuxPrimaryLibraryDirectory() {
    return resolveLinuxPrimaryLibraryDirectory(
      resolvedExecutablePath: Platform.resolvedExecutable,
      currentDirectoryPath: Directory.current.path,
      environment: Platform.environment,
    );
  }

  void _refreshBackendModuleDirectoryAfterPrimaryLoad() {
    if (_backendModuleDirectory != null) {
      return;
    }

    if (!Platform.isAndroid && !Platform.isLinux) {
      return;
    }

    _backendModuleDirectory = resolveBackendModuleDirectory();
    if (_backendModuleDirectory == null && Platform.isLinux) {
      _backendModuleDirectory =
          _linuxPreparedLibraryDirectory ??
          _resolveLinuxPrimaryLibraryDirectory();
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
        'native_bundles',
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

  List<String> _linuxBundleNamesForCurrentAbi() {
    switch (Abi.current()) {
      case Abi.linuxArm64:
        return const <String>['linux-arm64'];
      case Abi.linuxX64:
        return const <String>['linux-x64'];
      default:
        return const <String>[];
    }
  }

  /// Copies a missing Linux runtime dependency into the target directory.
  ///
  /// Returns `true` when the dependency already exists or is copied
  /// successfully. When a copy attempt fails, [onDiagnostic] receives a
  /// best-effort diagnostic message.
  static bool copyMissingLinuxLibrary({
    required String targetDirectory,
    required List<String> sourceDirectories,
    required String fileName,
    void Function(String message)? onDiagnostic,
  }) {
    final targetPath = path.join(targetDirectory, fileName);
    if (File(targetPath).existsSync()) {
      return true;
    }

    for (final sourceDirectory in sourceDirectories) {
      final sourcePath = path.join(sourceDirectory, fileName);
      final sourceFile = File(sourcePath);
      if (!sourceFile.existsSync()) {
        continue;
      }
      try {
        sourceFile.copySync(targetPath);
        return true;
      } catch (error) {
        onDiagnostic?.call(
          'Failed to copy Linux runtime dependency `$fileName` from '
          '`$sourcePath` to `$targetPath`: $error',
        );
        continue;
      }
    }

    return false;
  }

  /// Ensures a Linux SONAME alias file exists for [baseFileName].
  ///
  /// Returns `true` when the alias already exists or is created successfully.
  /// When both symlink creation and fallback copying fail, [onDiagnostic]
  /// receives a best-effort diagnostic message.
  static bool ensureLinuxSonameAlias({
    required String directory,
    required String baseFileName,
    void Function(String message)? onDiagnostic,
  }) {
    final sourcePath = path.join(directory, baseFileName);
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync()) {
      return false;
    }

    final aliasPath = '$sourcePath.0';
    final aliasFile = File(aliasPath);
    if (aliasFile.existsSync()) {
      return true;
    }

    Object? linkError;
    try {
      Link(aliasPath).createSync(baseFileName);
      return true;
    } catch (error) {
      linkError = error;
    }

    try {
      sourceFile.copySync(aliasPath);
      return true;
    } catch (copyError) {
      onDiagnostic?.call(
        'Failed to create or copy Linux SONAME alias `$aliasPath` for '
        '`$sourcePath`: link error=$linkError; copy error=$copyError',
      );
      return false;
    }
  }

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

        _backendLoadAllFromPathSymbolUnavailable = true;
        return false;
      }
    } finally {
      malloc.free(directoryPathPtr);
    }
  }

  /// Resolves the native backend module directory for dynamic backend loading.
  ///
  /// On Android/Linux we inspect `/proc/self/maps` to find the loaded
  /// `libllamadart.so` location, then load backend modules from that directory.
  /// Returns `null` when the path cannot be resolved.
  static String? resolveBackendModuleDirectory() {
    if (Platform.isWindows) {
      return resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: Platform.resolvedExecutable,
        currentDirectoryPath: Directory.current.path,
        environment: Platform.environment,
      );
    }

    if (!Platform.isAndroid && !Platform.isLinux) {
      return null;
    }

    try {
      final mapsFile = File('/proc/self/maps');
      if (!mapsFile.existsSync()) {
        return null;
      }

      final mapsContent = mapsFile.readAsStringSync();
      return parseBackendModuleDirectoryFromProcMaps(mapsContent);
    } catch (_) {
      return null;
    }
  }

  /// Returns recent best-effort startup diagnostics collected during setup.
  List<String> getStartupDiagnostics() {
    return List<String>.unmodifiable(_startupDiagnostics);
  }

  /// Returns whether a backend score allows a dynamically loaded module.
  ///
  /// Native runtimes expose `ggml_backend_score` to reject unsupported backend
  /// variants on the current system. A `null` score means the optional symbol
  /// is unavailable, so the candidate remains eligible for compatibility.
  static bool isBackendCandidateScoreSupported(int? score) {
    return score == null || score > 0;
  }

  /// Returns the first candidate whose probed score indicates support.
  ///
  /// Candidates with a missing score symbol (`null`) remain eligible so older
  /// backends that do not export `ggml_backend_score` still work.
  static T? selectFirstSupportedBackendCandidate<T>(
    Iterable<T> candidates, {
    required int? Function(T candidate) scoreForCandidate,
  }) {
    for (final candidate in candidates) {
      final score = scoreForCandidate(candidate);
      if (isBackendCandidateScoreSupported(score)) {
        return candidate;
      }
    }

    return null;
  }

  /// Describes why a backend asset candidate was skipped.
  static String describeSkippedBackendAssetCandidate(
    String assetUri,
    int score,
  ) {
    return 'Skipped backend asset `$assetUri` because '
        '`ggml_backend_score` returned $score.';
  }

  /// Describes which backend asset candidate was loaded.
  static String describeLoadedBackendAssetCandidate(
    String assetUri,
    int? score,
  ) {
    if (score == null) {
      return 'Loaded backend asset `$assetUri` without '
          '`ggml_backend_score`.';
    }
    return 'Loaded backend asset `$assetUri` with '
        '`ggml_backend_score`=$score.';
  }

  void _recordStartupDiagnostic(String message) {
    if (message.isEmpty) {
      return;
    }
    if (_startupDiagnostics.length >= _maxStartupDiagnostics) {
      _startupDiagnostics.removeAt(0);
    }
    _startupDiagnostics.add(message);
  }

  /// Resolves Windows backend-module directory for dynamic backend loading.
  ///
  /// Resolution order:
  /// 1. Explicit environment override (`LLAMADART_NATIVE_LIB_DIR` or
  ///    `LLAMADART_BACKEND_MODULE_DIR`)
  /// 2. Directory of resolved executable (if it looks like a native bundle)
  /// 3. Current working directory (if it looks like a native bundle)
  /// 4. Hook cache under `.dart_tool/llamadart/native_bundles`, including
  ///    default, custom GitHub, and local archive cache namespaces.
  /// 5. Directory of resolved executable (best-effort fallback)
  static String? resolveWindowsBackendModuleDirectory({
    required String resolvedExecutablePath,
    required String currentDirectoryPath,
    required Map<String, String> environment,
  }) {
    final overrideCandidates = <String>[
      environment['LLAMADART_NATIVE_LIB_DIR'] ?? '',
      environment['LLAMADART_BACKEND_MODULE_DIR'] ?? '',
    ];
    for (final override in overrideCandidates) {
      if (override.isEmpty) {
        continue;
      }
      if (_containsWindowsNativeModules(override)) {
        return override;
      }
    }

    final executableDir = path.dirname(resolvedExecutablePath);
    if (_containsWindowsNativeModules(executableDir)) {
      return executableDir;
    }

    if (_containsWindowsNativeModules(currentDirectoryPath)) {
      return currentDirectoryPath;
    }

    final dartToolLibDir = _findDartToolLibDirectory(currentDirectoryPath);
    if (dartToolLibDir != null) {
      return dartToolLibDir;
    }

    final preferredBundle = _preferredWindowsBundleName();
    final hookCacheDir = _findHookCacheWindowsBundleDirectory(
      currentDirectoryPath,
      preferredBundleName: preferredBundle,
    );
    if (hookCacheDir != null) {
      return hookCacheDir;
    }

    return executableDir;
  }

  /// Resolves the primary Linux native-library directory.
  ///
  /// Resolution order:
  /// 1. Explicit environment override (`LLAMADART_NATIVE_LIB_DIR` or
  ///    `LLAMADART_BACKEND_MODULE_DIR`)
  /// 2. `.dart_tool/lib`
  /// 3. Executable-adjacent `lib/` directory
  /// 4. Directory of resolved executable
  /// 5. Current working directory `lib/`
  /// 6. Current working directory
  static String? resolveLinuxPrimaryLibraryDirectory({
    required String resolvedExecutablePath,
    required String currentDirectoryPath,
    required Map<String, String> environment,
  }) {
    final overrideCandidates = <String>[
      environment['LLAMADART_NATIVE_LIB_DIR'] ?? '',
      environment['LLAMADART_BACKEND_MODULE_DIR'] ?? '',
    ];
    for (final override in overrideCandidates) {
      if (override.isEmpty) {
        continue;
      }
      if (_containsLinuxPrimaryLibrary(override)) {
        return override;
      }
    }

    final executableDir = path.dirname(resolvedExecutablePath);
    final candidates = <String>[
      path.join(currentDirectoryPath, '.dart_tool', 'lib'),
      path.join(executableDir, 'lib'),
      executableDir,
      path.join(currentDirectoryPath, 'lib'),
      currentDirectoryPath,
    ];

    final seen = <String>{};
    for (final candidate in candidates) {
      final normalized = path.normalize(candidate);
      if (!seen.add(normalized)) {
        continue;
      }
      if (_containsLinuxPrimaryLibrary(normalized)) {
        return normalized;
      }
    }

    return null;
  }

  static String? _preferredWindowsBundleName() {
    switch (Abi.current()) {
      case Abi.windowsX64:
        return 'windows-x64';
      case Abi.windowsArm64:
        return 'windows-arm64';
      default:
        return null;
    }
  }

  static String? _findHookCacheWindowsBundleDirectory(
    String currentDirectoryPath, {
    String? preferredBundleName,
  }) {
    var cursor = Directory(currentDirectoryPath).absolute;
    while (true) {
      final cacheRoot = Directory(
        path.join(cursor.path, '.dart_tool', 'llamadart', 'native_bundles'),
      );
      if (cacheRoot.existsSync()) {
        final found = _selectWindowsBundleDirectoryFromCache(
          cacheRoot.path,
          preferredBundleName: preferredBundleName,
        );
        if (found != null) {
          return found;
        }
      }

      final parent = cursor.parent;
      if (parent.path == cursor.path) {
        break;
      }
      cursor = parent;
    }

    return null;
  }

  static String? _selectWindowsBundleDirectoryFromCache(
    String cacheRootPath, {
    String? preferredBundleName,
  }) {
    final bundleDirs = _windowsBundleDirectoriesFromCache(
      cacheRootPath,
      preferredBundleName: preferredBundleName,
    );

    for (final bundleDir in bundleDirs) {
      final extractedDir = path.join(bundleDir.path, 'extracted');
      if (_containsWindowsNativeModules(extractedDir)) {
        return extractedDir;
      }
      if (_containsWindowsNativeModules(bundleDir.path)) {
        return bundleDir.path;
      }
    }

    return null;
  }

  static List<Directory> _windowsBundleDirectoriesFromCache(
    String cacheRootPath, {
    String? preferredBundleName,
  }) {
    final cacheRoot = Directory(cacheRootPath);
    final tagDirectories = <Directory>[];

    void addDefaultTags(Directory root) {
      for (final child in _listChildDirectories(root)) {
        final name = path.basename(child.path);
        if (name == 'github' || name == 'local') {
          continue;
        }
        tagDirectories.add(child);
      }
    }

    void addGitHubTags(Directory root) {
      final githubRoot = Directory(path.join(root.path, 'github'));
      for (final ownerDir in _listChildDirectories(githubRoot)) {
        for (final repoDir in _listChildDirectories(ownerDir)) {
          tagDirectories.addAll(_listChildDirectories(repoDir));
        }
      }
    }

    void addLocalTags(Directory root) {
      final localRoot = Directory(path.join(root.path, 'local'));
      for (final digestDir in _listChildDirectories(localRoot)) {
        tagDirectories.addAll(_listChildDirectories(digestDir));
      }
    }

    addDefaultTags(cacheRoot);
    addGitHubTags(cacheRoot);
    addLocalTags(cacheRoot);

    tagDirectories.sort(
      (a, b) => path.basename(b.path).compareTo(path.basename(a.path)),
    );

    final candidates = <Directory>[];
    for (final tagDirectory in tagDirectories) {
      if (preferredBundleName != null) {
        final preferred = Directory(
          path.join(tagDirectory.path, preferredBundleName),
        );
        if (preferred.existsSync()) {
          candidates.add(preferred);
        }
      }

      for (final directory in _listChildDirectories(tagDirectory)) {
        if (path.basename(directory.path).startsWith('windows-')) {
          candidates.add(directory);
        }
      }
    }

    final seen = <String>{};
    return candidates
        .where((directory) {
          return seen.add(path.normalize(directory.path));
        })
        .toList(growable: false);
  }

  static List<Directory> _listChildDirectories(Directory directory) {
    try {
      return directory.listSync().whereType<Directory>().toList(
        growable: false,
      );
    } catch (_) {
      return const <Directory>[];
    }
  }

  static bool _containsWindowsNativeModules(String directoryPath) {
    try {
      final directory = Directory(directoryPath);
      if (!directory.existsSync()) {
        return false;
      }

      final fileNames = directory
          .listSync()
          .whereType<File>()
          .map((file) => path.basename(file.path).toLowerCase())
          .toSet();

      final hasLlama = fileNames.any(
        (name) => RegExp(r'^llama(?:-[^.\\/]+)*\.dll$').hasMatch(name),
      );
      final hasGgml = fileNames.any(
        (name) => RegExp(r'^ggml(?:-[^.\\/]+)*\.dll$').hasMatch(name),
      );
      final hasCpuBackend = fileNames.any(
        (name) => RegExp(r'^ggml-cpu(?:-[^.\\/]+)*\.dll$').hasMatch(name),
      );
      return hasLlama && hasGgml && hasCpuBackend;
    } catch (_) {
      return false;
    }
  }

  static bool _containsLinuxPrimaryLibrary(String directoryPath) {
    try {
      final directory = Directory(directoryPath);
      if (!directory.existsSync()) {
        return false;
      }

      return File(path.join(directoryPath, 'libllamadart.so')).existsSync() ||
          File(path.join(directoryPath, 'libllamadart.so.0')).existsSync();
    } catch (_) {
      return false;
    }
  }

  static String? _findDartToolLibDirectory(String currentDirectoryPath) {
    var cursor = Directory(currentDirectoryPath).absolute;
    while (true) {
      final dartToolLib = path.join(cursor.path, '.dart_tool', 'lib');
      if (_containsWindowsNativeModules(dartToolLib)) {
        return dartToolLib;
      }

      final parent = cursor.parent;
      if (parent.path == cursor.path) {
        break;
      }
      cursor = parent;
    }

    return null;
  }

  /// Parses `/proc/self/maps` content and returns the module directory.
  ///
  /// This is exposed for testability.
  static String? parseBackendModuleDirectoryFromProcMaps(String mapsContent) {
    for (final rawLine in mapsContent.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final slashIndex = line.indexOf('/');
      if (slashIndex < 0) {
        continue;
      }

      final mappedPath = line.substring(slashIndex).trim();
      final normalizedPath = mappedPath.endsWith(' (deleted)')
          ? mappedPath.substring(0, mappedPath.length - ' (deleted)'.length)
          : mappedPath;

      if (!_linuxLlamadartProcMapsPattern.hasMatch(normalizedPath)) {
        continue;
      }

      return path.dirname(normalizedPath);
    }

    return null;
  }

  /// Loads a model from the specified [modelPath].
  ///
  /// Returns a handle to the loaded model.
  /// Throws an [Exception] if the file does not exist or fails to load.
  int loadModel(String modelPath, ModelParams modelParams) {
    final modelFileSize = _validateGgufModelFile(modelPath, 'Model');

    _applyConfiguredLogLevel();
    final effectiveBackend = resolvePreferredBackendForLoad(
      modelParams,
      isAndroid: Platform.isAndroid,
    );

    _prepareBackendsForModelLoad(effectiveBackend);

    final modelPathPtr = modelPath.toNativeUtf8();
    final mparams = llama_model_default_params();
    var preferredDevices = _createPreferredDeviceList(effectiveBackend);
    var gpuLayers = resolveGpuLayersForLoad(
      modelParams,
      isAndroid: Platform.isAndroid,
    );
    var forcedCpuFallback = false;

    final explicitGpuBackend =
        effectiveBackend != GpuBackend.auto &&
        effectiveBackend != GpuBackend.cpu;
    if (explicitGpuBackend &&
        preferredDevices == null &&
        _shouldForceCpuFallbackForMissingPreferredDevices(effectiveBackend)) {
      // Honor explicit backend intent: if requested GPU backend is unavailable,
      // fall back to CPU instead of letting another GPU backend auto-select.
      preferredDevices = _createPreferredDeviceList(GpuBackend.cpu);
      gpuLayers = 0;
      forcedCpuFallback = true;
    }
    final mtmdUseGpu = resolveMtmdUseGpuForLoad(
      modelParams,
      gpuLayers,
      modelPath: modelPath,
      isAndroid: Platform.isAndroid,
    );

    mparams.n_gpu_layers = gpuLayers;
    mparams.split_modeAsInt = modelParams.splitMode.llamaCppValue;
    mparams.main_gpu = modelParams.mainGpu;
    applyModelParams(mparams, modelParams);
    if (preferredDevices != null) {
      mparams.devices = preferredDevices;
    }

    Pointer<llama_model> modelPtr = nullptr;
    try {
      modelPtr = llama_model_load_from_file(modelPathPtr.cast(), mparams);
    } finally {
      malloc.free(modelPathPtr);
      if (preferredDevices != null) {
        malloc.free(preferredDevices);
      }
    }

    if (modelPtr == nullptr) {
      final diagnostics = _backendDiagnostics();
      throw Exception(
        "Failed to load model (size=$modelFileSize bytes, "
        "diagnostics=$diagnostics)",
      );
    }

    final model = _createModelWrapper(modelPtr, sourcePath: modelPath);
    final handle = _getHandle();
    _models[handle] = model;
    _loraAdapters[handle] = {};
    _modelToMtmdUseGpu[handle] = mtmdUseGpu;
    final resolvedBackend = _resolveBackendNameForLoad(
      requestedBackend: modelParams.preferredBackend,
      resolvedGpuLayers: gpuLayers,
      forcedCpuFallback: forcedCpuFallback,
    );
    _modelBackendNames[handle] = resolvedBackend;
    _modelResolvedGpuLayers[handle] = gpuLayers;
    _modelLoadParams[handle] = modelParams;
    _activeBackendName = resolvedBackend;
    _activeResolvedGpuLayers = gpuLayers;

    return handle;
  }

  int _validateGgufModelFile(String modelPath, String label) {
    final modelFile = File(modelPath);
    if (!modelFile.existsSync()) {
      throw Exception("$label file not found: $modelPath");
    }
    final modelFileSize = modelFile.lengthSync();
    if (modelFileSize <= 0) {
      throw Exception("$label file is empty: $modelPath");
    }
    if (!_looksLikeGguf(modelFile)) {
      throw Exception(
        "$label file does not appear to be GGUF: $modelPath. "
        "Please verify the download completed correctly.",
      );
    }
    return modelFileSize;
  }

  String _speculativeDraftModelCacheKey(
    int targetModelHandle,
    String draftModelPath,
    int resolvedGpuLayers,
    bool loadMtp,
  ) {
    final normalizedPath = File(draftModelPath).absolute.path;
    return '$targetModelHandle\x00$normalizedPath\x00$resolvedGpuLayers\x00$loadMtp';
  }

  _LlamaModelWrapper _loadSpeculativeDraftModel(
    int targetModelHandle,
    String draftModelPath,
    String label, {
    required bool loadMtp,
  }) {
    final modelFileSize = _validateGgufModelFile(draftModelPath, label);
    final targetModelParams =
        _modelLoadParams[targetModelHandle] ?? const ModelParams();
    final targetBackendName = _modelBackendNames[targetModelHandle];
    final effectiveBackend = targetBackendName == _backendDisplayName('cpu')
        ? GpuBackend.cpu
        : resolvePreferredBackendForLoad(
            targetModelParams,
            isAndroid: Platform.isAndroid,
          );
    final targetResolvedGpuLayers =
        _modelResolvedGpuLayers[targetModelHandle] ??
        resolveGpuLayersForLoad(
          targetModelParams,
          isAndroid: Platform.isAndroid,
        );
    final draftBackend = effectiveBackend;
    final draftGpuLayers = targetResolvedGpuLayers;
    final cacheKey = _speculativeDraftModelCacheKey(
      targetModelHandle,
      draftModelPath,
      draftGpuLayers,
      loadMtp,
    );

    final cached = _speculativeDraftModels[cacheKey];
    if (cached != null) {
      return cached;
    }

    _prepareBackendsForModelLoad(draftBackend);

    final modelPathPtr = draftModelPath.toNativeUtf8();
    final mparams = llama_model_default_params();
    final preferredDevices = _createPreferredDeviceList(draftBackend);
    mparams.n_gpu_layers = draftGpuLayers;
    mparams.split_modeAsInt = targetModelParams.splitMode.llamaCppValue;
    mparams.main_gpu = targetModelParams.mainGpu;
    applyModelParams(mparams, targetModelParams.copyWith(loadMtp: loadMtp));
    if (preferredDevices != null) {
      mparams.devices = preferredDevices;
    }

    Pointer<llama_model> modelPtr = nullptr;
    try {
      modelPtr = llama_model_load_from_file(modelPathPtr.cast(), mparams);
    } finally {
      malloc.free(modelPathPtr);
      if (preferredDevices != null) {
        malloc.free(preferredDevices);
      }
    }

    if (modelPtr == nullptr) {
      final diagnostics = _backendDiagnostics();
      throw Exception(
        "Failed to load $label (size=$modelFileSize bytes, "
        "path=$draftModelPath, diagnostics=$diagnostics)",
      );
    }

    final wrapper = _createModelWrapper(modelPtr, sourcePath: draftModelPath);
    _speculativeDraftModels[cacheKey] = wrapper;
    _modelToSpeculativeDraftModelKeys
        .putIfAbsent(targetModelHandle, () => <String>{})
        .add(cacheKey);
    return wrapper;
  }

  String _resolveBackendNameForLoad({
    required GpuBackend requestedBackend,
    required int resolvedGpuLayers,
    required bool forcedCpuFallback,
  }) {
    if (forcedCpuFallback || resolvedGpuLayers <= 0) {
      return _backendDisplayName('cpu');
    }

    final backendInfo = getBackendInfo().join(', ');

    switch (requestedBackend) {
      case GpuBackend.auto:
        return _resolveAutoBackendName(backendInfo) ??
            _backendDisplayName('cpu');
      case GpuBackend.cpu:
        return _backendDisplayName('cpu');
      case GpuBackend.vulkan:
        return _resolveExplicitBackendName(GpuBackend.vulkan, backendInfo);
      case GpuBackend.metal:
        return _resolveExplicitBackendName(GpuBackend.metal, backendInfo);
      case GpuBackend.cuda:
        return _resolveExplicitBackendName(GpuBackend.cuda, backendInfo);
      case GpuBackend.blas:
        return _resolveExplicitBackendName(GpuBackend.blas, backendInfo);
      case GpuBackend.opencl:
        return _resolveExplicitBackendName(GpuBackend.opencl, backendInfo);
      case GpuBackend.hip:
        return _resolveExplicitBackendName(GpuBackend.hip, backendInfo);
    }
  }

  _LlamaModelWrapper _createModelWrapper(
    Pointer<llama_model> modelPointer, {
    required String sourcePath,
  }) {
    try {
      final vocab = llama_model_get_vocab(modelPointer);
      return _LlamaModelWrapper(
        modelPointer,
        sourcePath: sourcePath,
        vocabSize: llama_vocab_n_tokens(vocab),
        suppressedTokens: readModelSuppressTokens(vocab),
      );
    } catch (_) {
      llama_model_free(modelPointer);
      rethrow;
    }
  }

  String _resolveExplicitBackendName(GpuBackend backend, String backendInfo) {
    if (_backendInfoContainsBackendMarker(backendInfo, backend)) {
      return _backendDisplayName(backend.name);
    }
    return _backendDisplayName('cpu');
  }

  String? _resolveAutoBackendName(String backendInfo) {
    const preferredOrder = <GpuBackend>[
      GpuBackend.metal,
      GpuBackend.cuda,
      GpuBackend.hip,
      GpuBackend.vulkan,
      GpuBackend.opencl,
      GpuBackend.blas,
    ];

    for (final backend in preferredOrder) {
      if (_backendInfoContainsBackendMarker(backendInfo, backend)) {
        return _backendDisplayName(backend.name);
      }
    }

    return null;
  }

  bool _shouldForceCpuFallbackForMissingPreferredDevices(
    GpuBackend requestedBackend,
  ) {
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      // Consolidated runtimes (notably Apple) do not expose per-backend
      // dynamic modules. Missing preferred-device pointers here does not
      // reliably mean GPU is unavailable.
      return false;
    }

    return !_isBackendModuleBundled(requestedBackend.name);
  }

  static bool _backendInfoContainsBackendMarker(
    String value,
    GpuBackend backend,
  ) {
    final lower = value.toLowerCase();
    switch (backend) {
      case GpuBackend.metal:
        return lower.contains('metal') || lower.contains('mtl');
      case GpuBackend.vulkan:
        return lower.contains('vulkan');
      case GpuBackend.opencl:
        return lower.contains('opencl');
      case GpuBackend.hip:
        return lower.contains('hip');
      case GpuBackend.cuda:
        return lower.contains('cuda');
      case GpuBackend.blas:
        return lower.contains('blas');
      case GpuBackend.cpu:
        return lower.contains('cpu') || lower.contains('llvm');
      case GpuBackend.auto:
        return false;
    }
  }

  void _prepareBackendsForModelLoad(GpuBackend preferredBackend) {
    // Apple bundles are consolidated into a single native library and do not
    // ship separate ggml backend modules.
    if ((Platform.isMacOS || Platform.isIOS) &&
        _backendModuleDirectory == null) {
      return;
    }
    final backendModuleDirectory = _backendModuleDirectory;

    switch (preferredBackend) {
      case GpuBackend.auto:
        final loadedAll = backendModuleDirectory == null
            ? _tryLoadAllBackendsBestEffort()
            : _tryLoadAllBackendsFromPathBestEffort(backendModuleDirectory);

        if (!loadedAll) {
          // Fallback when load-all symbols are unavailable.
          _tryLoadBackendModuleIfBundled('cpu');
        }

        if (Platform.isAndroid || Platform.isLinux || Platform.isWindows) {
          _tryLoadBackendModuleIfBundled('vulkan');
        }
        if (Platform.isLinux || Platform.isWindows) {
          _tryLoadBackendModuleIfBundled('blas');
          _tryLoadBackendModuleIfBundled('cuda');
        }
        if (Platform.isLinux) {
          _tryLoadBackendModuleIfBundled('hip');
        }
        return;
      case GpuBackend.cpu:
        // Explicit CPU mode must not initialize optional GPU backends.
        _tryLoadBackendModuleIfBundled('cpu');
        return;
      case GpuBackend.vulkan:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('vulkan');
        return;
      case GpuBackend.metal:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('metal');
        return;
      case GpuBackend.cuda:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('cuda');
        return;
      case GpuBackend.blas:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('blas');
        return;
      case GpuBackend.opencl:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('opencl');
        return;
      case GpuBackend.hip:
        _tryLoadBackendModuleIfBundled('cpu');
        _tryLoadBackendModuleIfBundled('hip');
        return;
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

    final fileNameCandidates = _backendLibraryCandidateFileNames(backend);
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

  bool _tryLoadBackendModule(String backend) {
    if (_backendLoadSymbolUnavailable) {
      return false;
    }

    if (_loadedBackendModules.contains(backend)) {
      return true;
    }
    if (_failedBackendModules.contains(backend)) {
      return false;
    }

    final fileNameCandidates = _backendLibraryCandidateFileNames(backend);
    final candidates = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      for (final fileName in fileNameCandidates) {
        candidates.add(path.join(backendModuleDirectory, fileName));
      }
    } else {
      // No resolved module directory: rely on platform search paths.
      candidates.addAll(fileNameCandidates);
    }

    _preloadWindowsBackendDependencies(backend);

    for (final candidate in candidates) {
      if (path.isAbsolute(candidate) && !File(candidate).existsSync()) {
        continue;
      }

      final alteredSearchPathHandle = _preloadWindowsBackendModule(
        candidate,
        backend,
      );
      final libraryPathPtr = candidate.toNativeUtf8();
      try {
        ggml_backend_reg_t reg;
        try {
          reg = ggml_backend_load(libraryPathPtr.cast());
        } on ArgumentError {
          _resolveGgmlFallbackFunctions();
          final fallback = _ggmlBackendLoadFallback;
          if (fallback == null) {
            // Optional dynamic-loader symbol can be missing from the primary
            // FFI asset in split bundles. If ggml fallback is unavailable,
            // stop retrying.
            _backendLoadSymbolUnavailable = true;
            return false;
          }
          reg = fallback(libraryPathPtr.cast());
        }
        if (reg == nullptr) {
          continue;
        }

        // Best-effort compatibility call for runtimes where explicit register is
        // required after dynamic load. We still consider the module load
        // successful even if this symbol is unavailable.
        _registerBackendRegBestEffort(reg);
        _loadedBackendModules.add(backend);
        _failedBackendModules.remove(backend);
        return true;
      } finally {
        if (alteredSearchPathHandle != nullptr) {
          _freeWindowsBackendModule(
            alteredSearchPathHandle,
            candidate,
            backend,
          );
        }
        malloc.free(libraryPathPtr);
      }
    }

    if (_tryRegisterBackendModuleViaAsset(backend)) {
      return true;
    }

    _failedBackendModules.add(backend);
    return false;
  }

  List<String> _backendAssetUriCandidates(String backend) {
    final candidates = <String>{
      'package:llamadart/$backend',
      'package:llamadart/ggml_$backend',
      'package:llamadart/ggml-$backend',
    };

    if (backend == 'cpu' && Platform.isAndroid) {
      for (final variant in _androidCpuVariantPriority.keys) {
        candidates.add(
          'package:llamadart/ggml-cpu-${variant.replaceAll('.', '_')}',
        );
      }
      candidates.add('package:llamadart/ggml-cpu');
    }

    return candidates.toList(growable: false);
  }

  Pointer<Void> _preloadWindowsBackendModule(
    String libraryPath,
    String backend,
  ) {
    final flags = windowsBackendModuleLoadFlags(libraryPath);
    if (!Platform.isWindows || flags == 0) {
      return nullptr;
    }

    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final setErrorMode = kernel32
          .lookupFunction<_SetErrorModeNative, _SetErrorModeDart>(
            'SetErrorMode',
          );
      final loadLibraryExW = kernel32
          .lookupFunction<_LoadLibraryExWNative, _LoadLibraryExWDart>(
            'LoadLibraryExW',
          );
      final oldMode = setErrorMode(_semFailCriticalErrors);
      setErrorMode(oldMode | _semFailCriticalErrors);

      final libraryPathPtr = libraryPath.toNativeUtf16();
      try {
        final handle = loadLibraryExW(libraryPathPtr, nullptr, flags);
        if (handle == nullptr) {
          _recordStartupDiagnostic(
            'Failed to preload Windows backend module `$libraryPath` with '
            'LOAD_WITH_ALTERED_SEARCH_PATH for `$backend`.',
          );
        }
        return handle;
      } finally {
        malloc.free(libraryPathPtr);
        setErrorMode(oldMode);
      }
    } catch (error) {
      _recordStartupDiagnostic(
        'Failed to preload Windows backend module `$libraryPath` with '
        'LOAD_WITH_ALTERED_SEARCH_PATH for `$backend`: $error',
      );
      return nullptr;
    }
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
        _recordStartupDiagnostic(
          'Failed to release temporary Windows backend module preload for '
          '`$libraryPath` (`$backend`).',
        );
      }
    } catch (error) {
      _recordStartupDiagnostic(
        'Failed to release temporary Windows backend module preload for '
        '`$libraryPath` (`$backend`): $error',
      );
    }
  }

  void _preloadWindowsBackendDependencies(String backend) {
    if (!Platform.isWindows) {
      return;
    }

    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      return;
    }

    final cacheKey =
        '$backend|${path.normalize(backendModuleDirectory).toLowerCase()}';
    if (_preloadedBackendDependencyLibraries.containsKey(cacheKey)) {
      return;
    }

    final handles = <DynamicLibrary>[];
    _preloadedBackendDependencyLibraries[cacheKey] = handles;

    for (final dependencyPath in windowsBackendDependencyPaths(
      backendModuleDirectory,
      backend,
    )) {
      try {
        handles.add(DynamicLibrary.open(dependencyPath));
      } catch (error) {
        _recordStartupDiagnostic(
          'Failed to preload Windows backend dependency '
          '`$dependencyPath` for `$backend`: $error',
        );
      }
    }
  }

  /// Returns Windows `LoadLibraryExW` flags for preloading a backend module.
  ///
  /// llama.cpp currently opens dynamic backend modules with plain
  /// `LoadLibraryW`. For absolute native-asset bundle paths, an earlier
  /// `LOAD_WITH_ALTERED_SEARCH_PATH` load lets Windows resolve transitive DLL
  /// imports from the backend module directory before llama.cpp registers it.
  static int windowsBackendModuleLoadFlags(String libraryPath) {
    if (!path.isAbsolute(libraryPath)) {
      return 0;
    }
    return _loadWithAlteredSearchPath;
  }

  /// Returns absolute paths for backend-owned Windows dependency DLLs that
  /// can be preloaded before asking llama.cpp to dynamically load [backend].
  ///
  /// This is only a best-effort compatibility path. The backend module itself
  /// is also preloaded with `LOAD_WITH_ALTERED_SEARCH_PATH`, because Windows
  /// may still fail to resolve module-owned transitive imports from the bundle
  /// directory after individual dependency DLLs were loaded by absolute path.
  static List<String> windowsBackendDependencyPaths(
    String directoryPath,
    String backend, {
    Iterable<String>? fileNames,
  }) {
    if (backend != 'cuda') {
      return const <String>[];
    }

    final names =
        fileNames?.toList(growable: false) ??
        _listWindowsBackendDependencyFileNames(directoryPath);
    final selected = <String>[];
    for (final name in names) {
      final lower = name.toLowerCase();
      if (!lower.endsWith('.dll')) {
        continue;
      }
      if (lower.startsWith('cudart64_') ||
          lower.startsWith('cublas64_') ||
          lower.startsWith('cublaslt64_')) {
        selected.add(name);
      }
    }

    selected.sort((a, b) {
      final priorityCompare = _windowsCudaDependencyPriority(
        a,
      ).compareTo(_windowsCudaDependencyPriority(b));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    return selected
        .map((name) => path.join(directoryPath, name))
        .toList(growable: false);
  }

  static List<String> _listWindowsBackendDependencyFileNames(
    String directoryPath,
  ) {
    try {
      return Directory(directoryPath)
          .listSync()
          .whereType<File>()
          .map((file) => path.basename(file.path))
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  static int _windowsCudaDependencyPriority(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.startsWith('cudart64_')) {
      return 0;
    }
    if (lower.startsWith('cublas64_')) {
      return 1;
    }
    if (lower.startsWith('cublaslt64_')) {
      return 2;
    }
    return 100;
  }

  bool _tryRegisterBackendModuleViaAsset(String backend) {
    final assetCandidates = _backendAssetUriCandidates(backend);
    final recordAssetDiagnostics = backend == 'cpu' && Platform.isAndroid;

    for (final assetUri in assetCandidates) {
      try {
        final library = DynamicLibrary.open(assetUri);
        final score = _lookupBackendAssetScore(library);
        if (!isBackendCandidateScoreSupported(score)) {
          if (recordAssetDiagnostics && score != null) {
            _recordStartupDiagnostic(
              describeSkippedBackendAssetCandidate(assetUri, score),
            );
          }
          continue;
        }

        final init = library
            .lookupFunction<_GgmlBackendInitNative, _GgmlBackendInitDart>(
              'ggml_backend_init',
            );
        final reg = init();
        if (reg == nullptr) {
          if (recordAssetDiagnostics) {
            _recordStartupDiagnostic(
              'Backend asset `$assetUri` returned null from '
              '`ggml_backend_init`.',
            );
          }
          continue;
        }

        // Asset init path mirrors ggml_backend_load() by honoring optional
        // backend score gates before initialization, then explicitly
        // registering the backend because asset loading bypasses the native
        // dynamic-loader helper.
        if (!_registerBackendRegBestEffort(reg)) {
          if (recordAssetDiagnostics) {
            _recordStartupDiagnostic(
              'Backend asset `$assetUri` failed explicit backend '
              'registration.',
            );
          }
          continue;
        }
        _loadedBackendLibraries[backend] = library;
        _loadedBackendModules.add(backend);
        if (recordAssetDiagnostics) {
          _recordStartupDiagnostic(
            describeLoadedBackendAssetCandidate(assetUri, score),
          );
        }
        return true;
      } catch (_) {
        continue;
      }
    }

    return false;
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

  void _resolveGgmlFallbackFunctions() {
    final fileNameCandidates = _ggmlLibraryCandidateFileNames();
    final candidates = <String>[..._ggmlAssetUriCandidates()];
    final filesystemCandidates = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      for (final fileName in fileNameCandidates) {
        filesystemCandidates.add(path.join(backendModuleDirectory, fileName));
      }
    }
    // Keep bare-name fallback last so module-dir resolution wins when present.
    filesystemCandidates.addAll(fileNameCandidates);
    candidates.addAll(filesystemCandidates);

    final searchKey = candidates.map(path.normalize).join('|');
    if (_ggmlFallbackLookupAttempted &&
        _ggmlFallbackLookupSearchKey == searchKey) {
      return;
    }
    _ggmlFallbackLookupAttempted = true;
    _ggmlFallbackLookupSearchKey = searchKey;

    final seen = <String>{};
    for (final candidate in candidates) {
      if (!seen.add(candidate)) {
        continue;
      }

      DynamicLibrary library;
      try {
        library = DynamicLibrary.open(candidate);
      } catch (_) {
        continue;
      }

      if (_ggmlBackendLoadFallback == null) {
        try {
          _ggmlBackendLoadFallback = library
              .lookupFunction<_GgmlBackendLoadNative, _GgmlBackendLoadDart>(
                'ggml_backend_load',
              );
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendLoadAllFallback == null) {
        try {
          _ggmlBackendLoadAllFallback = library
              .lookupFunction<
                _GgmlBackendLoadAllNative,
                _GgmlBackendLoadAllDart
              >('ggml_backend_load_all');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendLoadAllFromPathFallback == null) {
        try {
          _ggmlBackendLoadAllFromPathFallback = library
              .lookupFunction<
                _GgmlBackendLoadAllFromPathNative,
                _GgmlBackendLoadAllFromPathDart
              >('ggml_backend_load_all_from_path');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendRegisterFallback == null) {
        try {
          _ggmlBackendRegisterFallback = library
              .lookupFunction<
                _GgmlBackendRegisterNative,
                _GgmlBackendRegisterDart
              >('ggml_backend_register');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendRegCountFallback == null) {
        try {
          _ggmlBackendRegCountFallback = library
              .lookupFunction<
                _GgmlBackendRegCountNative,
                _GgmlBackendRegCountDart
              >('ggml_backend_reg_count');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendRegGetFallback == null) {
        try {
          _ggmlBackendRegGetFallback = library
              .lookupFunction<_GgmlBackendRegGetNative, _GgmlBackendRegGetDart>(
                'ggml_backend_reg_get',
              );
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendRegNameFallback == null) {
        try {
          _ggmlBackendRegNameFallback = library
              .lookupFunction<
                _GgmlBackendRegNameNative,
                _GgmlBackendRegNameDart
              >('ggml_backend_reg_name');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendRegByNameFallback == null) {
        try {
          _ggmlBackendRegByNameFallback = library
              .lookupFunction<
                _GgmlBackendRegByNameNative,
                _GgmlBackendRegByNameDart
              >('ggml_backend_reg_by_name');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendRegDevCountFallback == null) {
        try {
          _ggmlBackendRegDevCountFallback = library
              .lookupFunction<
                _GgmlBackendRegDevCountNative,
                _GgmlBackendRegDevCountDart
              >('ggml_backend_reg_dev_count');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendRegDevGetFallback == null) {
        try {
          _ggmlBackendRegDevGetFallback = library
              .lookupFunction<
                _GgmlBackendRegDevGetNative,
                _GgmlBackendRegDevGetDart
              >('ggml_backend_reg_dev_get');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendDevCountFallback == null) {
        try {
          _ggmlBackendDevCountFallback = library
              .lookupFunction<
                _GgmlBackendDevCountNative,
                _GgmlBackendDevCountDart
              >('ggml_backend_dev_count');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendDevGetFallback == null) {
        try {
          _ggmlBackendDevGetFallback = library
              .lookupFunction<_GgmlBackendDevGetNative, _GgmlBackendDevGetDart>(
                'ggml_backend_dev_get',
              );
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendDevNameFallback == null) {
        try {
          _ggmlBackendDevNameFallback = library
              .lookupFunction<
                _GgmlBackendDevNameNative,
                _GgmlBackendDevNameDart
              >('ggml_backend_dev_name');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendDevBackendRegFallback == null) {
        try {
          _ggmlBackendDevBackendRegFallback = library
              .lookupFunction<
                _GgmlBackendDevBackendRegNative,
                _GgmlBackendDevBackendRegDart
              >('ggml_backend_dev_backend_reg');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendDevByTypeFallback == null) {
        try {
          _ggmlBackendDevByTypeFallback = library
              .lookupFunction<
                _GgmlBackendDevByTypeNative,
                _GgmlBackendDevByTypeDart
              >('ggml_backend_dev_by_type');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendDevTypeFallback == null) {
        try {
          _ggmlBackendDevTypeFallback = library
              .lookupFunction<
                _GgmlBackendDevTypeNative,
                _GgmlBackendDevTypeDart
              >('ggml_backend_dev_type');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendDevGetPropsFallback == null) {
        try {
          _ggmlBackendDevGetPropsFallback = library
              .lookupFunction<
                _GgmlBackendDevGetPropsNative,
                _GgmlBackendDevGetPropsDart
              >('ggml_backend_dev_get_props');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendDevMemoryFallback == null) {
        try {
          _ggmlBackendDevMemoryFallback = library
              .lookupFunction<
                _GgmlBackendDevMemoryNative,
                _GgmlBackendDevMemoryDart
              >('ggml_backend_dev_memory');
        } catch (_) {
          // Keep searching other candidates.
        }
      }

      if (_ggmlBackendLoadFallback != null &&
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
          _ggmlBackendDevMemoryFallback != null) {
        return;
      }
    }
  }

  List<String> _ggmlAssetUriCandidates() {
    if (Platform.isWindows) {
      return const <String>[
        'package:llamadart/ggml',
        'package:llamadart/ggml-base',
      ];
    }
    return const <String>['package:llamadart/ggml'];
  }

  void _resolveLogLevelFallbackFunction() {
    final directories = _llamadartFallbackLookupDirectories();
    final searchKey = directories.map(path.normalize).join('|');

    if (_logLevelFallbackLookupAttempted &&
        _llamaDartSetLogLevelFallback != null) {
      return;
    }

    if (_logLevelFallbackLookupAttempted &&
        _llamaDartSetLogLevelFallback == null &&
        _logLevelFallbackLookupSearchKey == searchKey) {
      return;
    }

    _logLevelFallbackLookupAttempted = true;
    _logLevelFallbackLookupSearchKey = searchKey;

    final fileNameCandidates = _llamadartLibraryCandidateFileNames();
    final candidates = <String>[..._llamadartAssetUriCandidates()];
    final pattern = _llamadartLibraryPattern();
    for (final directoryPath in directories) {
      for (final fileName in fileNameCandidates) {
        candidates.add(path.join(directoryPath, fileName));
      }
      for (final fileName in _matchingLibraryNames(directoryPath, pattern)) {
        candidates.add(path.join(directoryPath, fileName));
      }
    }
    // Keep bare-name fallback last so module-dir resolution wins when present.
    candidates.addAll(fileNameCandidates);

    final seen = <String>{};
    for (final candidate in candidates) {
      if (!seen.add(candidate)) {
        continue;
      }
      try {
        final library = DynamicLibrary.open(candidate);
        _llamaDartSetLogLevelFallback = library
            .lookupFunction<
              _LlamaDartSetLogLevelNative,
              _LlamaDartSetLogLevelDart
            >('llama_dart_set_log_level');
        return;
      } catch (_) {
        continue;
      }
    }
  }

  _ReasoningBudgetApi _resolveReasoningBudgetApi() {
    final cached = _reasoningBudgetApi;
    if (cached != null) {
      return cached;
    }

    if (_reasoningBudgetApiLookupAttempted) {
      throw LlamaUnsupportedException(_reasoningBudgetUnavailableMessage());
    }
    _reasoningBudgetApiLookupAttempted = true;

    for (final candidate in _llamadartWrapperLibraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final api = _ReasoningBudgetApi.tryLoad(library);
        if (api != null) {
          _reasoningBudgetApi = api;
          return api;
        }
      } catch (_) {
        continue;
      }
    }

    throw LlamaUnsupportedException(_reasoningBudgetUnavailableMessage());
  }

  String _reasoningBudgetUnavailableMessage() {
    return 'llama.cpp thinking-budget control is unavailable in this native '
        'runtime bundle (missing llama_dart_sampler_init_reasoning_budget). '
        'Update to a libllamadart build that includes the reasoning-budget '
        'wrapper.';
  }

  _SpeculativeApi _resolveSpeculativeApi() {
    final cached = _speculativeApi;
    if (cached != null) {
      return cached;
    }

    if (_speculativeApiLookupAttempted) {
      throw UnsupportedError(_speculativeUnavailableMessage());
    }
    _speculativeApiLookupAttempted = true;

    if (!Platform.isWindows) {
      try {
        final direct = _SpeculativeApi.direct();
        _speculativeApi = direct;
        return direct;
      } catch (_) {}
    }

    if (Platform.isWindows) {
      try {
        final asset = _SpeculativeApi.windowsAsset();
        _speculativeApi = asset;
        return asset;
      } catch (_) {}
    }

    for (final candidate in _llamadartWrapperLibraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final api = _SpeculativeApi.tryLoad(library);
        if (api != null) {
          _speculativeApi = api;
          return api;
        }
      } catch (_) {
        continue;
      }
    }

    throw UnsupportedError(_speculativeUnavailableMessage());
  }

  String _speculativeUnavailableMessage() {
    return 'llama.cpp speculative decoding is unavailable in this native '
        'runtime bundle (missing llama_dart_speculative_* wrapper symbols).';
  }

  // Legacy wrapper resolver retained for native bundles that still expose only
  // the MTP-specific speculative symbols.
  // ignore: unused_element
  _MtpApi _resolveMtpApi() {
    final cached = _mtpApi;
    if (cached != null) {
      return cached;
    }

    if (_mtpApiLookupAttempted) {
      throw UnsupportedError(_mtpUnavailableMessage());
    }
    _mtpApiLookupAttempted = true;

    if (!Platform.isWindows) {
      try {
        final direct = _MtpApi.direct();
        _mtpApi = direct;
        return direct;
      } catch (_) {}
    }

    if (Platform.isWindows) {
      try {
        final asset = _MtpApi.windowsAsset();
        _mtpApi = asset;
        return asset;
      } catch (_) {}
    }

    for (final candidate in _llamadartWrapperLibraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final api = _MtpApi.tryLoad(library);
        if (api != null) {
          _mtpApi = api;
          return api;
        }
      } catch (_) {
        continue;
      }
    }

    throw UnsupportedError(_mtpUnavailableMessage());
  }

  String _mtpUnavailableMessage() {
    return 'llama.cpp MTP speculative decoding is unavailable in this native '
        'runtime bundle (missing llama_dart_mtp_* wrapper symbols).';
  }

  // Legacy wrapper resolver retained for native bundles that still expose only
  // the ngram-specific speculative symbols.
  // ignore: unused_element
  _NgramApi _resolveNgramApi() {
    final cached = _ngramApi;
    if (cached != null) {
      return cached;
    }

    if (_ngramApiLookupAttempted) {
      throw UnsupportedError(_ngramUnavailableMessage());
    }
    _ngramApiLookupAttempted = true;

    if (!Platform.isWindows) {
      try {
        final direct = _NgramApi.direct();
        _ngramApi = direct;
        return direct;
      } catch (_) {}
    }

    if (Platform.isWindows) {
      try {
        final asset = _NgramApi.windowsAsset();
        _ngramApi = asset;
        return asset;
      } catch (_) {}
    }

    for (final candidate in _llamadartWrapperLibraryCandidates()) {
      try {
        final library = DynamicLibrary.open(candidate);
        final api = _NgramApi.tryLoad(library);
        if (api != null) {
          _ngramApi = api;
          return api;
        }
      } catch (_) {
        continue;
      }
    }

    throw UnsupportedError(_ngramUnavailableMessage());
  }

  String _ngramUnavailableMessage() {
    return 'llama.cpp ngram-simple speculative decoding is unavailable in this '
        'native runtime bundle (missing llama_dart_ngram_* wrapper symbols).';
  }

  List<String> _llamadartWrapperLibraryCandidates() {
    final candidates = <String>[..._llamadartAssetUriCandidates()];
    final fileNameCandidates = _llamadartLibraryCandidateFileNames();
    final pattern = _llamadartLibraryPattern();
    for (final directoryPath in _llamadartFallbackLookupDirectories()) {
      for (final fileName in fileNameCandidates) {
        candidates.add(path.join(directoryPath, fileName));
      }
      for (final fileName in _matchingLibraryNames(directoryPath, pattern)) {
        candidates.add(path.join(directoryPath, fileName));
      }
    }
    candidates.addAll(fileNameCandidates);

    final seen = <String>{};
    return [
      for (final candidate in candidates)
        if (seen.add(candidate)) candidate,
    ];
  }

  List<String> _llamadartAssetUriCandidates() {
    // Prefer asset-URI resolution so Windows split bundles can reliably resolve
    // the wrapper helper library without relying on process cwd/search paths.
    if (Platform.isWindows) {
      return const <String>[
        'package:llamadart/llamadart_wrapper',
        'package:llamadart/llamadart',
      ];
    }
    return const <String>['package:llamadart/llamadart'];
  }

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

  static String _ggmlLibraryFileName() {
    if (Platform.isWindows) {
      return 'ggml.dll';
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libggml.dylib';
    }
    return 'libggml.so';
  }

  static String _llamadartLibraryFileName() {
    if (Platform.isWindows) {
      return 'llamadart.dll';
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libllamadart.dylib';
    }
    return 'libllamadart.so';
  }

  List<String> _backendLibraryCandidateFileNames(String backend) {
    final baseName = _backendLibraryFileName(backend);
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      if (backend == 'cpu' && Platform.isAndroid) {
        final variants = _androidCpuVariantPriority.keys
            .map((variant) => 'libggml-cpu-$variant.so')
            .toList(growable: false);
        return <String>[...variants, baseName];
      }
      return <String>[baseName];
    }

    final candidates = <String>{};
    final basePath = path.join(backendModuleDirectory, baseName);
    if (File(basePath).existsSync()) {
      candidates.add(baseName);
    }
    final dynamicNames = _matchingLibraryNames(
      backendModuleDirectory,
      _backendLibraryPattern(backend),
    );
    if (backend == 'cpu' && Platform.isAndroid) {
      dynamicNames.sort(_compareAndroidCpuLibraryCandidates);
    }
    candidates.addAll(dynamicNames);
    final resolved = candidates.toList(growable: false);
    if (backend == 'cpu' && Platform.isAndroid) {
      resolved.sort(_compareAndroidCpuLibraryCandidates);
    }
    return resolved;
  }

  static int _compareAndroidCpuLibraryCandidates(String a, String b) {
    final rankA = _androidCpuLibraryCandidateRank(a);
    final rankB = _androidCpuLibraryCandidateRank(b);
    if (rankA != rankB) {
      return rankA.compareTo(rankB);
    }
    return a.compareTo(b);
  }

  static int _androidCpuLibraryCandidateRank(String fileName) {
    final lowered = fileName.toLowerCase();
    if (lowered == 'libggml-cpu.so') {
      return 1000;
    }

    final variantMatch = RegExp(
      r'^libggml-cpu-([^/\\]+)\.so$',
    ).firstMatch(lowered);
    if (variantMatch == null) {
      return 2000;
    }

    final variant = variantMatch.group(1)!;
    return _androidCpuVariantPriority[variant] ?? 900;
  }

  List<String> _ggmlLibraryCandidateFileNames() {
    final baseName = _ggmlLibraryFileName();
    final candidates = <String>{baseName};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      return candidates.toList(growable: false);
    }

    final dynamicNames = _matchingLibraryNames(
      backendModuleDirectory,
      _ggmlLibraryPattern(),
    );
    candidates.addAll(dynamicNames);
    return candidates.toList(growable: false);
  }

  List<String> _llamadartLibraryCandidateFileNames() {
    final candidates = _llamadartStaticCandidateFileNames();
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      return candidates.toList(growable: false);
    }

    final dynamicNames = _matchingLibraryNames(
      backendModuleDirectory,
      _llamadartLibraryPattern(),
    );
    candidates.addAll(dynamicNames);
    return candidates.toList(growable: false);
  }

  Set<String> _llamadartStaticCandidateFileNames() {
    final candidates = <String>{_llamadartLibraryFileName()};
    if (Platform.isWindows) {
      // Hook asset naming can expose wrapper helper as `llamadart_wrapper.dll`.
      candidates.add('llamadart_wrapper.dll');
    }
    return candidates;
  }

  RegExp _backendLibraryPattern(String backend) {
    final escapedBackend = RegExp.escape(backend);
    if (Platform.isWindows) {
      return RegExp('^ggml-$escapedBackend(?:-[^\\\\/]+)*\\.dll\$');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return RegExp('^libggml-$escapedBackend(?:-[^\\\\/]+)*\\.dylib\$');
    }
    return RegExp('^libggml-$escapedBackend(?:-[^\\\\/]+)*\\.so\$');
  }

  RegExp _ggmlLibraryPattern() {
    if (Platform.isWindows) {
      return RegExp(r'^ggml(?:-[^.\\/]+)*\.dll$');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return RegExp(r'^libggml(?:-[^.\\/]+)*\.dylib$');
    }
    return RegExp(r'^libggml(?:-[^.\\/]+)*\.so$');
  }

  RegExp _llamadartLibraryPattern() {
    if (Platform.isWindows) {
      return RegExp(r'^llamadart(?:[-_][^.\\/]+)*\.dll$');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return RegExp(r'^libllamadart(?:[-_][^.\\/]+)*\.dylib$');
    }
    return RegExp(r'^libllamadart(?:[-_][^.\\/]+)*\.so$');
  }

  static List<String> _matchingLibraryNames(
    String directoryPath,
    RegExp regex,
  ) {
    try {
      final names = <String>[];
      for (final entity in Directory(directoryPath).listSync()) {
        if (entity is! File) {
          continue;
        }
        final name = path.basename(entity.path);
        if (regex.hasMatch(name)) {
          names.add(name);
        }
      }
      names.sort();
      return names;
    } catch (_) {
      return const [];
    }
  }

  T _ggmlRegistryFallbackOr<T>(
    T fallback,
    T Function() primaryCall,
    T? Function() fallbackCall,
  ) {
    if (Platform.isWindows) {
      // Windows split bundles can expose ggml registry state through ggml.dll
      // while the generated default asset points at llama.dll. Prefer the
      // explicit ggml runtime lookup when it is available so count/get/name
      // calls all read the same registry.
      _resolveGgmlFallbackFunctions();
      final fallbackValue = fallbackCall();
      if (fallbackValue != null) {
        return fallbackValue;
      }
    }

    try {
      return primaryCall();
    } on ArgumentError {
      _resolveGgmlFallbackFunctions();
      final fallbackValue = fallbackCall();
      if (fallbackValue != null) {
        return fallbackValue;
      }
      _backendRegistrySymbolUnavailable = true;
      return fallback;
    }
  }

  int _ggmlBackendRegCount() {
    return _ggmlRegistryFallbackOr<int>(
      0,
      ggml_backend_reg_count,
      () => _ggmlBackendRegCountFallback?.call(),
    );
  }

  ggml_backend_reg_t _ggmlBackendRegGet(int index) {
    return _ggmlRegistryFallbackOr<ggml_backend_reg_t>(
      nullptr,
      () => ggml_backend_reg_get(index),
      () => _ggmlBackendRegGetFallback?.call(index),
    );
  }

  Pointer<Char> _ggmlBackendRegName(ggml_backend_reg_t reg) {
    return _ggmlRegistryFallbackOr<Pointer<Char>>(
      nullptr,
      () => ggml_backend_reg_name(reg),
      () => _ggmlBackendRegNameFallback?.call(reg),
    );
  }

  ggml_backend_reg_t _ggmlBackendRegByName(Pointer<Char> name) {
    return _ggmlRegistryFallbackOr<ggml_backend_reg_t>(
      nullptr,
      () => ggml_backend_reg_by_name(name),
      () => _ggmlBackendRegByNameFallback?.call(name),
    );
  }

  int _ggmlBackendRegDevCount(ggml_backend_reg_t reg) {
    return _ggmlRegistryFallbackOr<int>(
      0,
      () => ggml_backend_reg_dev_count(reg),
      () => _ggmlBackendRegDevCountFallback?.call(reg),
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

  ggml_backend_dev_t _ggmlBackendDevGet(int index) {
    return _ggmlRegistryFallbackOr<ggml_backend_dev_t>(
      nullptr,
      () => ggml_backend_dev_get(index),
      () => _ggmlBackendDevGetFallback?.call(index),
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

  /// Routes `ggml_backend_dev_memory` through the registry fallback.
  /// Same shape as [_ggmlBackendDevGetProps]; returns `false` when the
  /// symbol is unavailable.
  bool _ggmlBackendDevMemory(
    ggml_backend_dev_t dev,
    Pointer<Size> free,
    Pointer<Size> total,
  ) {
    return _ggmlRegistryFallbackOr<bool>(
      false,
      () {
        ggml_backend_dev_memory(dev, free, total);
        return true;
      },
      () {
        final fn = _ggmlBackendDevMemoryFallback;
        if (fn == null) return null;
        fn(dev, free, total);
        return true;
      },
    );
  }

  static String _backendLibraryFileName(String backend) {
    if (Platform.isWindows) {
      return 'ggml-$backend.dll';
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libggml-$backend.dylib';
    }
    return 'libggml-$backend.so';
  }

  static bool _looksLikeGguf(File modelFile) {
    try {
      final header = modelFile.openSync(mode: FileMode.read);
      try {
        final magic = header.readSync(4);
        if (magic.length < 4) {
          return false;
        }
        return magic[0] == 0x47 &&
            magic[1] == 0x47 &&
            magic[2] == 0x55 &&
            magic[3] == 0x46;
      } finally {
        header.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  String _backendDiagnostics() {
    final regs = <String>[];
    final regCount = _ggmlBackendRegCount();
    for (var i = 0; i < regCount; i++) {
      final reg = _ggmlBackendRegGet(i);
      if (reg == nullptr) {
        continue;
      }
      final regNamePtr = _ggmlBackendRegName(reg);
      if (regNamePtr == nullptr) {
        continue;
      }
      regs.add(regNamePtr.cast<Utf8>().toDartString());
    }

    final devices = getBackendInfo();
    return '{moduleDir=${_backendModuleDirectory ?? "null"}, '
        'loadedModules=${_loadedBackendModules.toList(growable: false)}, '
        'registeredBackends=$regs, devices=$devices, '
        'registryApisUnavailable=$_backendRegistrySymbolUnavailable}';
  }

  Pointer<ggml_backend_dev_t>? _createPreferredDeviceList(GpuBackend backend) {
    final devices = _resolvePreferredDevices(backend);
    if (devices == null || devices.isEmpty) {
      return null;
    }

    final ptr = malloc<ggml_backend_dev_t>(devices.length + 1);
    for (var i = 0; i < devices.length; i++) {
      ptr[i] = devices[i];
    }
    ptr[devices.length] = nullptr;
    return ptr;
  }

  List<ggml_backend_dev_t>? _resolvePreferredDevices(GpuBackend backend) {
    switch (backend) {
      case GpuBackend.auto:
        return null;
      case GpuBackend.cpu:
        final cpuDev = _ggmlBackendDevByType(
          ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU,
        );
        if (cpuDev == nullptr) {
          return null;
        }
        return [cpuDev];
      case GpuBackend.vulkan:
        return _devicesForBackendRegName('Vulkan');
      case GpuBackend.metal:
        return _devicesForBackendRegName('Metal');
      case GpuBackend.cuda:
        return _devicesForBackendRegName('CUDA');
      case GpuBackend.blas:
        return _devicesForBackendRegName('BLAS');
      case GpuBackend.opencl:
        return _devicesForBackendRegName('OpenCL');
      case GpuBackend.hip:
        return _devicesForBackendRegName('HIP');
    }
  }

  List<ggml_backend_dev_t>? _devicesForBackendRegName(String regName) {
    final regNamePtr = regName.toNativeUtf8();
    try {
      final reg = _ggmlBackendRegByName(regNamePtr.cast());
      if (reg == nullptr) {
        return null;
      }

      final count = _ggmlBackendRegDevCount(reg);
      if (count <= 0) {
        return null;
      }

      final devices = <ggml_backend_dev_t>[];
      for (var i = 0; i < count; i++) {
        final dev = _ggmlBackendRegDevGet(reg, i);
        if (dev != nullptr) {
          devices.add(dev);
        }
      }

      if (devices.isEmpty) {
        return null;
      }

      return devices;
    } finally {
      malloc.free(regNamePtr);
    }
  }

  /// Frees the model associated with [modelHandle].
  ///
  /// This also frees all contexts and LoRA adapters associated with the model.
  void freeModel(int modelHandle) {
    final model = _models.remove(modelHandle);
    _modelToMtmdUseGpu.remove(modelHandle);
    if (model != null) {
      final contextsToRemove = _contextToModel.entries
          .where((e) => e.value == modelHandle)
          .map((e) => e.key)
          .toList();
      for (final ctxHandle in contextsToRemove) {
        _freeContext(ctxHandle);
      }
      final adapters = _loraAdapters.remove(modelHandle);
      adapters?.values.forEach((a) => a.dispose());

      // Free associated multimodal context
      final mmHandle = _modelToMtmd.remove(modelHandle);
      if (mmHandle != null) {
        final mmCtx = _mtmdContexts.remove(mmHandle);
        if (mmCtx != null) _mtmdFree(mmCtx);
      }

      model.dispose();
    }

    _modelBackendNames.remove(modelHandle);
    _modelResolvedGpuLayers.remove(modelHandle);
    _modelLoadParams.remove(modelHandle);
    final draftModelKeys = _modelToSpeculativeDraftModelKeys.remove(
      modelHandle,
    );
    if (draftModelKeys != null) {
      for (final key in draftModelKeys) {
        _speculativeDraftModels.remove(key)?.dispose();
      }
    }
    if (_modelBackendNames.isEmpty) {
      _activeBackendName = _backendDisplayName('cpu');
      _activeResolvedGpuLayers = 0;
    } else {
      _activeBackendName = _modelBackendNames.values.last;
      _activeResolvedGpuLayers = _modelResolvedGpuLayers.values.last;
    }
  }

  /// Creates an inference context for the specified [modelHandle].
  ///
  /// Returns a handle to the created context.
  /// Throws an [Exception] if the model handle is invalid or context creation fails.
  int createContext(int modelHandle, ModelParams params) {
    final model = _models[modelHandle];
    if (model == null) {
      throw Exception("Invalid model handle");
    }

    final ctxParams = llama_context_default_params();
    int nCtx = params.contextSize;
    if (nCtx <= 0) {
      nCtx = llama_model_n_ctx_train(model.pointer);
    }
    final hasEncoder = llama_model_has_encoder(model.pointer);
    final hasDecoder = llama_model_has_decoder(model.pointer);
    final resolvedBatchSizes = resolveContextBatchSizes(
      params,
      nCtx,
      useFullContextDefaults: hasEncoder && !hasDecoder,
    );
    final maxSeqLimit = llama_max_parallel_sequences();
    final resolvedMaxParallelSequences = math.max(
      1,
      math.min(params.maxParallelSequences, maxSeqLimit),
    );

    ctxParams.n_ctx = nCtx;
    ctxParams.n_batch = resolvedBatchSizes.batchSize;
    ctxParams.n_ubatch = resolvedBatchSizes.microBatchSize;
    ctxParams.n_seq_max = resolvedMaxParallelSequences;
    ctxParams.n_rs_seq = params.speculativeRollbackTokenMax;
    ctxParams.n_threads = params.numberOfThreads;
    ctxParams.n_threads_batch = params.numberOfThreadsBatch;
    if (resolvedMaxParallelSequences > 1) {
      // Keep per-sequence context at full n_ctx when multiple sequence slots
      // are enabled so regular generation behavior is unchanged.
      ctxParams.kv_unified = true;
    }

    final resolvedModelGpuLayers = _modelResolvedGpuLayers[modelHandle];
    if (shouldDisableContextGpuOffload(
      params,
      resolvedGpuLayers: resolvedModelGpuLayers,
    )) {
      ctxParams.offload_kqv = false;
      ctxParams.op_offload = false;
      ctxParams.flash_attn_typeAsInt =
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value;
    } else if (shouldUseConservativeAndroidVulkanContextConfig(
      params,
      resolvedGpuLayers: resolvedModelGpuLayers,
      isAndroid: Platform.isAndroid,
    )) {
      if (!_androidVulkanAllowKqvOffload) {
        ctxParams.offload_kqv = false;
      }
      if (!_androidVulkanAllowOpOffload) {
        ctxParams.op_offload = false;
      }
      if (!_androidVulkanAllowFlashAttn) {
        ctxParams.flash_attn_typeAsInt =
            llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value;
      }
    }

    params.validate();
    final resolvedFlashAttn = applyContextParams(ctxParams, params);
    if (resolvedFlashAttn != params.flashAttention) {
      LlamaLogger.instance.debug(
        'llama_cpp_service: promoting flash_attn=enabled for non-F16 KV '
        '(k=${params.cacheTypeK}, v=${params.cacheTypeV})',
      );
    }

    final ctxPtr = llama_init_from_model(model.pointer, ctxParams);
    if (ctxPtr == nullptr) {
      throw Exception("Failed to create context");
    }

    final handle = _getHandle();
    _contexts[handle] = _LlamaContextWrapper(ctxPtr, model);
    _contextToModel[handle] = modelHandle;
    _activeLoras[handle] = {};
    _contextParams[handle] = ctxParams;
    _samplers[handle] = llama_sampler_chain_init(
      llama_sampler_chain_default_params(),
    );
    _batches[handle] = llama_batch_init(resolvedBatchSizes.batchSize, 0, 1);

    return handle;
  }

  /// Frees the context associated with [contextHandle].
  void freeContext(int contextHandle) {
    _freeContext(contextHandle);
  }

  void _freeContext(int handle) {
    _contextToModel.remove(handle);
    _activeLoras.remove(handle);
    _contextParams.remove(handle);
    final sampler = _samplers.remove(handle);
    if (sampler != null && sampler != nullptr) llama_sampler_free(sampler);
    final batch = _batches.remove(handle);
    if (batch != null) llama_batch_free(batch);
    _contexts.remove(handle)?.dispose();
  }

  _LlamaCppThinkingBudgetConfig? _resolveLlamaCppThinkingBudgetConfig(
    GenerationParams params, {
    required bool hasMediaParts,
  }) {
    final budget = params.thinkingBudget;
    if (budget == null) {
      return null;
    }
    if (budget.maxTokens < 0) {
      throw RangeError.value(
        budget.maxTokens,
        'thinkingBudget.maxTokens',
        'must be non-negative for llama.cpp thinking-budget control',
      );
    }
    if (budget.maxTokens > _maxLlamaCppReasoningBudgetTokens) {
      throw RangeError.range(
        budget.maxTokens,
        0,
        _maxLlamaCppReasoningBudgetTokens,
        'thinkingBudget.maxTokens',
        'must fit the signed 32-bit llama.cpp reasoning-budget limit',
      );
    }
    if (hasMediaParts) {
      throw LlamaUnsupportedException(
        'llama.cpp thinking-budget control currently supports text-only '
        'generation in llamadart because template prompt tokens must be '
        'inspected by the native reasoning sampler.',
      );
    }

    final startTag = budget.startTag;
    final endTag = budget.endTag;
    if (startTag == null ||
        startTag.trim().isEmpty ||
        endTag == null ||
        endTag.trim().isEmpty) {
      throw ArgumentError(
        'GenerationParams.thinkingBudget requires non-empty startTag and '
        'endTag for raw generation. LlamaEngine.create fills them from the '
        'selected chat template automatically.',
      );
    }

    return _LlamaCppThinkingBudgetConfig(
      maxTokens: budget.maxTokens,
      startTag: startTag,
      endTag: endTag,
      forcedMessage: budget.forcedMessage ?? '',
    );
  }

  _LlamaCppSpeculativeConfig? _resolveLlamaCppSpeculativeConfig(
    GenerationParams params, {
    required bool hasMediaParts,
  }) {
    final speculativeConfig = params.resolvedSpeculativeDecodingConfig;
    if (speculativeConfig == null) {
      return null;
    }

    if (hasMediaParts) {
      throw UnsupportedError(
        'llama.cpp speculative decoding currently supports text-only '
        'generation in llamadart.',
      );
    }
    if (params.thinkingBudget != null) {
      throw LlamaUnsupportedException(
        'llama.cpp thinking-budget control cannot be combined with '
        'speculative decoding in llamadart.',
      );
    }
    if (params.grammar != null) {
      throw UnsupportedError(
        'llama.cpp speculative decoding does not yet support grammar '
        'sampling in llamadart.',
      );
    }

    final requestedStrategies = speculativeConfig.effectiveStrategies;
    final strategies = <SpeculativeDecodingStrategy>[
      for (final strategy in requestedStrategies)
        if (strategy == SpeculativeDecodingStrategy.backendDefault)
          SpeculativeDecodingStrategy.ngramMod
        else
          strategy,
    ];
    final uniqueStrategies = <SpeculativeDecodingStrategy>[];
    for (final strategy in strategies) {
      if (!_llamaCppSpeculativeTypeNames.containsKey(strategy)) {
        throw UnsupportedError(
          'llama.cpp does not support speculative strategy $strategy.',
        );
      }
      if (!uniqueStrategies.contains(strategy)) {
        uniqueStrategies.add(strategy);
      }
    }

    final draftStrategyCount = uniqueStrategies
        .where(_llamaCppDraftStrategies.contains)
        .length;
    if (draftStrategyCount > 1) {
      throw UnsupportedError(
        'llama.cpp speculative decoding can mix n-gram strategies with at '
        'most one draft-model strategy in llamadart.',
      );
    }

    final draftModelPath = speculativeConfig.draftModelPath;
    if (draftModelPath != null && draftModelPath.trim().isEmpty) {
      throw ArgumentError.value(
        draftModelPath,
        'draftModelPath',
        'must be null or a non-empty path for llama.cpp speculative decoding',
      );
    }

    final requiresExternalDraft = uniqueStrategies.any(
      (strategy) =>
          strategy == SpeculativeDecodingStrategy.draftSimple ||
          strategy == SpeculativeDecodingStrategy.draftEagle3 ||
          strategy == SpeculativeDecodingStrategy.draftDflash,
    );
    if (requiresExternalDraft && draftModelPath == null) {
      throw ArgumentError(
        'llama.cpp ${uniqueStrategies.map((s) => _llamaCppSpeculativeTypeNames[s]).join(', ')} '
        'requires draftModelPath.',
      );
    }

    final isNgramOnly =
        draftStrategyCount == 0 &&
        uniqueStrategies.every(
          (strategy) =>
              strategy != SpeculativeDecodingStrategy.backendDefault &&
              _llamaCppSpeculativeTypeNames.containsKey(strategy),
        );
    if (isNgramOnly &&
        (speculativeConfig.draftTokenMin != null ||
            speculativeConfig.minProbability != null ||
            speculativeConfig.draftSplitProbability != null ||
            speculativeConfig.draftModelPath != null)) {
      throw UnsupportedError(
        'llama.cpp n-gram speculative decoding uses token history and does '
        'not support draftTokenMin, minProbability, draftSplitProbability, or '
        'draftModelPath unless a draft-model strategy is also enabled.',
      );
    }

    final ngramCachePaths = <String?>[
      speculativeConfig.ngramCacheStaticPath,
      speculativeConfig.ngramCacheDynamicPath,
    ];
    for (final cachePath in ngramCachePaths) {
      if (cachePath == null) {
        continue;
      }
      if (cachePath.trim().isEmpty) {
        throw ArgumentError.value(
          cachePath,
          'ngramCachePath',
          'must be null or a non-empty path',
        );
      }
      if (!File(cachePath).existsSync()) {
        throw ArgumentError.value(
          cachePath,
          'ngramCachePath',
          'must exist before enabling llama.cpp ngram-cache',
        );
      }
    }

    final draftTokenMax = _resolveLlamaCppSpeculativeDraftTokenMax(
      uniqueStrategies,
      speculativeConfig,
    );
    final draftTokenMin = speculativeConfig.draftTokenMin ?? 0;
    if (draftTokenMax <= 0) {
      throw RangeError.value(
        draftTokenMax,
        'draftTokenMax',
        'must be greater than zero for llama.cpp speculative decoding',
      );
    }
    if (draftTokenMin < 0 || draftTokenMin > draftTokenMax) {
      throw RangeError.value(
        draftTokenMin,
        'draftTokenMin',
        'must be between zero and draftTokenMax for llama.cpp speculative decoding',
      );
    }

    final ngramTokenMin = speculativeConfig.ngramTokenMin;
    final ngramTokenMax = speculativeConfig.ngramTokenMax;
    if (ngramTokenMin != null &&
        ngramTokenMax != null &&
        ngramTokenMin > ngramTokenMax) {
      throw RangeError.value(
        ngramTokenMin,
        'ngramTokenMin',
        'must be less than or equal to ngramTokenMax',
      );
    }

    final typeNames = uniqueStrategies
        .map((strategy) => _llamaCppSpeculativeTypeNames[strategy]!)
        .join(',');
    return _LlamaCppSpeculativeConfig(
      strategies: List<SpeculativeDecodingStrategy>.unmodifiable(
        uniqueStrategies,
      ),
      typeNames: typeNames,
      draftTokenMax: draftTokenMax,
      draftTokenMin: draftTokenMin,
      minProbability: speculativeConfig.minProbability,
      draftSplitProbability: speculativeConfig.draftSplitProbability,
      draftModelPath: draftModelPath,
      ngramSizeN: speculativeConfig.ngramSizeN ?? speculativeConfig.ngramSize,
      ngramSizeM: speculativeConfig.ngramSizeM,
      ngramMinHits: speculativeConfig.ngramMinHits,
      ngramMatch: speculativeConfig.ngramMatch,
      ngramTokenMin: ngramTokenMin,
      ngramTokenMax:
          ngramTokenMax ??
          (uniqueStrategies.contains(SpeculativeDecodingStrategy.ngramMod)
              ? speculativeConfig.draftTokenMax
              : null),
      ngramCacheStaticPath: speculativeConfig.ngramCacheStaticPath,
      ngramCacheDynamicPath: speculativeConfig.ngramCacheDynamicPath,
    );
  }

  /// Resolves llama.cpp speculative strategy type names for unit tests.
  String? debugResolveSpeculativeTypeNamesForTesting(
    GenerationParams params, {
    bool hasMediaParts = false,
  }) {
    return _resolveLlamaCppSpeculativeConfig(
      params,
      hasMediaParts: hasMediaParts,
    )?.typeNames;
  }

  void _validateMtpModelLoad(
    _LlamaCppSpeculativeConfig? config,
    ModelParams modelParams,
  ) {
    if (config?.usesMtp == true &&
        config?.draftModelPath == null &&
        !modelParams.loadMtp) {
      throw LlamaUnsupportedException(
        'Bundled MTP speculative decoding requires the model to be loaded '
        'with ModelParams(loadMtp: true). Reload the target model with MTP '
        'tensors enabled, or provide a compatible external draftModelPath.',
      );
    }
  }

  /// Validates bundled MTP model-loading requirements for unit tests.
  void debugValidateMtpModelLoadForTesting(
    GenerationParams params,
    ModelParams modelParams, {
    bool hasMediaParts = false,
  }) {
    _validateMtpModelLoad(
      _resolveLlamaCppSpeculativeConfig(params, hasMediaParts: hasMediaParts),
      modelParams,
    );
  }

  /// Validates a llama.cpp thinking budget for unit tests.
  void debugValidateThinkingBudgetForTesting(
    GenerationParams params, {
    bool hasMediaParts = false,
  }) {
    _resolveLlamaCppThinkingBudgetConfig(params, hasMediaParts: hasMediaParts);
  }

  /// Resolves whether llama.cpp speculative prompt processing suppresses logits.
  bool debugSuppressesDraftProcessLogitsForTesting(
    GenerationParams params, {
    bool hasMediaParts = false,
  }) {
    return _resolveLlamaCppSpeculativeConfig(
          params,
          hasMediaParts: hasMediaParts,
        )?.suppressDraftProcessLogits ??
        false;
  }

  /// Resolves llama.cpp speculative native params for unit tests.
  Map<String, Object?> debugResolveSpeculativeNativeParamsForTesting(
    GenerationParams params, {
    bool hasMediaParts = false,
  }) {
    final config = _resolveLlamaCppSpeculativeConfig(
      params,
      hasMediaParts: hasMediaParts,
    );
    return <String, Object?>{
      'typeNames': config?.typeNames,
      'draftTokenMax': config?.draftTokenMax,
      'ngramSizeN': config?.ngramSizeN,
      'ngramSizeM': config?.ngramSizeM,
      'ngramTokenMax': config?.ngramTokenMax,
    };
  }

  ({int lastN, double repeat, double frequency, double presence})
  _resolvePenaltySamplerConfig(GenerationParams params) {
    return (
      lastN: 64,
      repeat: params.penalty,
      frequency: 0.0,
      presence: params.presencePenalty,
    );
  }

  /// Resolves llama.cpp penalty sampler parameters for unit tests.
  Map<String, Object> debugResolvePenaltySamplerParamsForTesting(
    GenerationParams params,
  ) {
    final config = _resolvePenaltySamplerConfig(params);
    return <String, Object>{
      'lastN': config.lastN,
      'repeat': config.repeat,
      'frequency': config.frequency,
      'presence': config.presence,
    };
  }

  /// Runs [action] while native batch logits are temporarily zeroed.
  static T debugWithSuppressedBatchLogitsForTesting<T>(
    Pointer<Int8> logits,
    int tokenCount,
    bool suppress,
    T Function() action,
  ) {
    return _withSuppressedBatchLogits(logits, tokenCount, suppress, action);
  }

  int _resolveLlamaCppSpeculativeDraftTokenMax(
    List<SpeculativeDecodingStrategy> strategies,
    SpeculativeDecodingConfig config,
  ) {
    var max = 0;
    for (final strategy in strategies) {
      switch (strategy) {
        case SpeculativeDecodingStrategy.draftSimple:
        case SpeculativeDecodingStrategy.draftEagle3:
        case SpeculativeDecodingStrategy.mtp:
        case SpeculativeDecodingStrategy.draftDflash:
          max = math.max(max, config.draftTokenMax ?? 3);
          break;
        case SpeculativeDecodingStrategy.ngramSimple:
        case SpeculativeDecodingStrategy.ngramMapK:
        case SpeculativeDecodingStrategy.ngramMapK4v:
          max = math.max(max, config.ngramSizeM ?? 48);
          break;
        case SpeculativeDecodingStrategy.ngramMod:
          max = math.max(
            max,
            config.ngramTokenMax ?? config.draftTokenMax ?? 64,
          );
          break;
        case SpeculativeDecodingStrategy.ngramCache:
          max = math.max(max, config.draftTokenMax ?? 8);
          break;
        case SpeculativeDecodingStrategy.backendDefault:
          max = math.max(max, config.draftTokenMax ?? 64);
          break;
      }
    }
    return max == 0 ? 64 : max;
  }

  /// Generates text based on the given [prompt] and [params].
  ///
  /// Returns a [Stream] of token bytes.
  /// Supports multimodal input via [parts].
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    List<LlamaContentPart>? parts,
  }) async* {
    var ctx = _contexts[contextHandle];
    if (ctx == null) throw Exception("Invalid context handle");
    _generatingContexts.update(
      contextHandle,
      (count) => count + 1,
      ifAbsent: () => 1,
    );

    Pointer<Int32> tokensPtr = nullptr;
    Pointer<Uint8> pieceBuf = nullptr;
    Pointer<Utf8> grammarPtr = nullptr;
    Pointer<Utf8> rootPtr = nullptr;
    _LazyGrammarConfig? lazyGrammarConfig;
    Pointer<llama_sampler> sampler = nullptr;
    Pointer<llama_dart_speculative> speculativeSession = nullptr;
    _SpeculativeApi? speculativeApi;

    try {
      final modelHandle = _contextToModel[contextHandle]!;
      final model = _models[modelHandle]!;
      final modelParams = _contextParams[contextHandle]!;
      final vocab = llama_model_get_vocab(model.pointer);
      final hasMediaParts =
          parts?.any((p) => p is LlamaImageContent || p is LlamaAudioContent) ??
          false;
      final thinkingBudgetConfig = _resolveLlamaCppThinkingBudgetConfig(
        params,
        hasMediaParts: hasMediaParts,
      );
      final speculativeConfig = _resolveLlamaCppSpeculativeConfig(
        params,
        hasMediaParts: hasMediaParts,
      );
      _validateMtpModelLoad(
        speculativeConfig,
        _modelLoadParams[modelHandle] ?? const ModelParams(),
      );
      final reasoningBudgetApi = thinkingBudgetConfig == null
          ? null
          : _resolveReasoningBudgetApi();
      // 1. Reset Context
      ctx = _resetContext(
        contextHandle,
        ctx,
        clearMemory:
            hasMediaParts ||
            speculativeConfig != null ||
            !params.reusePromptPrefix,
      );
      ctx.resetLastPerf();
      llama_perf_context_reset(ctx.pointer);
      final existingSampler = _samplers[contextHandle];
      if (existingSampler != null) {
        llama_perf_sampler_reset(existingSampler);
      }

      // 2. Prepare Resources
      final nCtx = llama_n_ctx(ctx.pointer);
      final batch = _batches[contextHandle]!;
      tokensPtr = malloc<Int32>(nCtx);
      pieceBuf = malloc<Uint8>(256);

      if (speculativeConfig != null) {
        speculativeApi = _resolveSpeculativeApi();
        final draftModelPath = speculativeConfig.draftModelPath;
        final draftModel = draftModelPath == null
            ? null
            : _loadSpeculativeDraftModel(
                modelHandle,
                draftModelPath,
                'speculative draft model',
                loadMtp: speculativeConfig.usesMtp,
              );
        speculativeSession = speculativeApi.initSession(
          targetModel: model.pointer,
          draftModel: draftModel?.pointer,
          targetContext: ctx.pointer,
          contextParams: modelParams,
          config: speculativeConfig,
        );
        if (speculativeSession == nullptr) {
          final draftHint = speculativeConfig.requiresExternalDraftModel
              ? 'Verify the draft model is compatible with the target model'
              : 'Verify the selected strategy is compatible with this model';
          throw UnsupportedError(
            'llama.cpp speculative decoding (${speculativeConfig.typeNames}) '
            'is not available for this model/context. $draftHint, use a '
            'native libllamadart build that includes llama-common generic '
            'speculative wrapper symbols, and set '
            'ModelParams.speculativeRollbackTokenMax >= the effective '
            'speculative draft length (draftTokenMax for draft-model or '
            'ngram-cache strategies; ngramTokenMax when set for ngram-mod, '
            'otherwise draftTokenMax/default; ngramSizeM for ngram-simple, '
            'ngram-map-k, or ngram-map-k4v) when the target architecture '
            'needs bounded rollback snapshots.',
          );
        }
        if (speculativeApi.needEmbd(speculativeSession)) {
          llama_set_embeddings(ctx.pointer, true);
        }
        llama_perf_context_reset(ctx.pointer);
      }

      if (params.grammar != null) {
        grammarPtr = params.grammar!.toNativeUtf8();
        rootPtr = params.grammarRoot.toNativeUtf8();
        if (params.grammarLazy && params.grammarTriggers.isNotEmpty) {
          lazyGrammarConfig = _buildLazyGrammarConfig(params);
        }
      }

      // 3. Ingest Prompt (Text or Multimodal)
      final promptEvalStopwatch = Stopwatch()..start();
      final initialTokens = _ingestPrompt(
        contextHandle,
        modelHandle,
        ctx,
        batch,
        vocab,
        prompt,
        parts,
        tokensPtr,
        nCtx,
        modelParams,
        allowTextPromptReuse:
            speculativeConfig == null &&
            !hasMediaParts &&
            params.reusePromptPrefix,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
      );
      promptEvalStopwatch.stop();
      ctx.lastPerfPromptEvalMs =
          promptEvalStopwatch.elapsedMicroseconds / 1000.0;
      ctx.lastPerfPromptEvalTokens = initialTokens;

      _ensureLogitsAvailableAfterPromptEval(ctx.pointer);
      if (speculativeSession != nullptr &&
          !speculativeApi!.begin(
            speculativeSession,
            0,
            tokensPtr,
            initialTokens,
          )) {
        throw Exception(
          "Failed to initialize llama.cpp speculative prompt state",
        );
      }

      // 4. Initialize and Run Sampler Loop
      sampler = _initializeSampler(
        params,
        vocab,
        model.vocabSize,
        model.suppressedTokens,
        grammarPtr,
        rootPtr,
        lazyGrammarConfig,
        thinkingBudgetConfig,
        reasoningBudgetApi,
        initialTokens,
        tokensPtr,
      );

      final preservedTokenIds = _resolvePreservedTokenIds(
        vocab,
        params.preservedTokens,
      );
      final effectiveStopSequences = _effectiveStopSequences(
        params.stopSequences,
        params.preservedTokens,
      );

      if (speculativeSession != nullptr && speculativeConfig != null) {
        yield* _runSpeculativeInferenceLoop(
          ctx,
          batch,
          vocab,
          sampler,
          params,
          speculativeConfig,
          initialTokens,
          nCtx,
          cancelTokenAddress,
          pieceBuf,
          preservedTokenIds,
          effectiveStopSequences,
          speculativeSession,
          speculativeApi!,
          tokensPtr,
        );
      } else {
        yield* _runInferenceLoop(
          ctx,
          batch,
          vocab,
          sampler,
          params,
          initialTokens,
          nCtx,
          cancelTokenAddress,
          pieceBuf,
          grammarPtr,
          preservedTokenIds,
          effectiveStopSequences,
        );
      }
    } finally {
      if (speculativeSession != nullptr) {
        speculativeApi?.free(speculativeSession);
      }
      if (sampler != nullptr) llama_sampler_free(sampler);
      final remaining = (_generatingContexts[contextHandle] ?? 1) - 1;
      if (remaining <= 0) {
        _generatingContexts.remove(contextHandle);
      } else {
        _generatingContexts[contextHandle] = remaining;
      }
      if (tokensPtr != nullptr) malloc.free(tokensPtr);
      if (pieceBuf != nullptr) malloc.free(pieceBuf);
      if (grammarPtr != nullptr) malloc.free(grammarPtr);
      if (rootPtr != nullptr) malloc.free(rootPtr);
      lazyGrammarConfig?.dispose();
    }
  }

  /// Generates a single embedding vector for [text].
  List<double> embed(int contextHandle, String text, {bool normalize = true}) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw Exception('Invalid context handle');
    }

    final modelHandle = _contextToModel[contextHandle];
    if (modelHandle == null) {
      throw Exception('Invalid context handle');
    }

    final model = _models[modelHandle];
    if (model == null) {
      throw Exception('Invalid model handle');
    }

    final contextParams = _contextParams[contextHandle];
    if (contextParams == null) {
      throw Exception('Missing context parameters');
    }

    final hasEncoder = llama_model_has_encoder(model.pointer);
    final hasDecoder = llama_model_has_decoder(model.pointer);
    if (hasEncoder && hasDecoder) {
      throw Exception(
        'Embedding extraction for encoder-decoder models is not supported',
      );
    }
    final useEncoderPath = hasEncoder && !hasDecoder;

    final vocab = llama_model_get_vocab(model.pointer);
    final nSeqCtx = llama_n_ctx_seq(ctx.pointer);
    final tokens = _tokenizeEmbeddingText(vocab, text, nSeqCtx);
    final configuredBatchSize = contextParams.n_batch > 0
        ? contextParams.n_batch
        : tokens.length;
    final batchCapacity = math.max(
      1,
      math.min(configuredBatchSize, tokens.length),
    );
    final batch = llama_batch_init(batchCapacity, 0, 1);
    final embeddingSize = _resolveEmbeddingDimension(model.pointer);

    try {
      llama_synchronize(ctx.pointer);
      _clearContextMemory(ctx.pointer, strict: false);
      ctx.cachedPromptTokens = null;
      llama_set_embeddings(ctx.pointer, true);

      var decodedTokens = 0;
      while (decodedTokens < tokens.length) {
        final remaining = tokens.length - decodedTokens;
        final chunkTokenCount = math.min(batchCapacity, remaining);
        batch.n_tokens = chunkTokenCount;

        for (int i = 0; i < chunkTokenCount; i++) {
          final tokenIndex = decodedTokens + i;
          batch.token[i] = tokens[tokenIndex];
          batch.pos[i] = tokenIndex;
          batch.n_seq_id[i] = 1;
          batch.seq_id[i][0] = 0;
          batch.logits[i] = 1;
        }

        final status = useEncoderPath
            ? llama_encode(ctx.pointer, batch)
            : llama_decode(ctx.pointer, batch);
        if (status != 0) {
          throw Exception('Embedding forward pass failed');
        }

        decodedTokens += chunkTokenCount;
      }

      final poolingType = llama_pooling_type$1(ctx.pointer);
      Pointer<Float> embeddingPtr;
      if (poolingType == llama_pooling_type.LLAMA_POOLING_TYPE_NONE) {
        embeddingPtr = llama_get_embeddings_ith(
          ctx.pointer,
          batch.n_tokens - 1,
        );
        if (embeddingPtr == nullptr) {
          embeddingPtr = llama_get_embeddings(ctx.pointer);
        }
      } else {
        embeddingPtr = llama_get_embeddings_seq(ctx.pointer, 0);
        if (embeddingPtr == nullptr) {
          embeddingPtr = llama_get_embeddings(ctx.pointer);
        }
      }

      if (embeddingPtr == nullptr) {
        throw Exception('Embedding output is unavailable');
      }

      final vector = List<double>.from(
        embeddingPtr.asTypedList(embeddingSize),
        growable: false,
      );

      if (!normalize) {
        return vector;
      }

      return _normalizeEmbeddingVector(vector);
    } finally {
      llama_set_embeddings(ctx.pointer, false);
      llama_batch_free(batch);
    }
  }

  /// Generates embedding vectors for [texts] in input order.
  List<List<double>> embedBatch(
    int contextHandle,
    List<String> texts, {
    bool normalize = true,
  }) {
    if (texts.isEmpty) {
      return const <List<double>>[];
    }

    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw Exception('Invalid context handle');
    }

    final modelHandle = _contextToModel[contextHandle];
    if (modelHandle == null) {
      throw Exception('Invalid context handle');
    }

    final model = _models[modelHandle];
    if (model == null) {
      throw Exception('Invalid model handle');
    }

    final contextParams = _contextParams[contextHandle];
    if (contextParams == null) {
      throw Exception('Missing context parameters');
    }

    final hasEncoder = llama_model_has_encoder(model.pointer);
    final hasDecoder = llama_model_has_decoder(model.pointer);
    if (hasEncoder && hasDecoder) {
      throw Exception(
        'Embedding extraction for encoder-decoder models is not supported',
      );
    }
    final useEncoderPath = hasEncoder && !hasDecoder;

    final poolingType = llama_pooling_type$1(ctx.pointer);
    final maxParallelSequences = llama_n_seq_max(ctx.pointer);
    if (poolingType == llama_pooling_type.LLAMA_POOLING_TYPE_NONE ||
        maxParallelSequences <= 1) {
      final fallbackVectors = <List<double>>[];
      for (final text in texts) {
        fallbackVectors.add(embed(contextHandle, text, normalize: normalize));
      }
      return fallbackVectors;
    }

    final vocab = llama_model_get_vocab(model.pointer);
    final nSeqCtx = llama_n_ctx_seq(ctx.pointer);
    final configuredBatchSize = contextParams.n_batch > 0
        ? contextParams.n_batch
        : llama_n_ctx(ctx.pointer);
    final batchCapacity = math.max(1, configuredBatchSize);
    final embeddingSize = _resolveEmbeddingDimension(model.pointer);

    final tokenizedInputs = <List<int>>[];
    for (final text in texts) {
      final tokens = _tokenizeEmbeddingText(vocab, text, nSeqCtx);
      tokenizedInputs.add(tokens);
    }

    final vectors = List<List<double>?>.filled(texts.length, null);

    int index = 0;
    while (index < texts.length) {
      final currentTokenCount = tokenizedInputs[index].length;

      if (currentTokenCount > batchCapacity) {
        vectors[index] = embed(
          contextHandle,
          texts[index],
          normalize: normalize,
        );
        index += 1;
        continue;
      }

      var groupTokenCount = 0;
      final groupStart = index;
      while (index < texts.length &&
          (index - groupStart) < maxParallelSequences) {
        final nextCount = tokenizedInputs[index].length;
        if (nextCount > batchCapacity) {
          break;
        }

        final nextTotal = groupTokenCount + nextCount;
        if (groupTokenCount > 0 && nextTotal > batchCapacity) {
          break;
        }

        groupTokenCount = nextTotal;
        index += 1;
      }

      if (groupStart == index) {
        vectors[index] = embed(
          contextHandle,
          texts[index],
          normalize: normalize,
        );
        index += 1;
        continue;
      }

      final groupSize = index - groupStart;
      final batch = llama_batch_init(groupTokenCount, 0, groupSize);
      try {
        llama_synchronize(ctx.pointer);
        _clearContextMemory(ctx.pointer, strict: false);
        ctx.cachedPromptTokens = null;
        llama_set_embeddings(ctx.pointer, true);

        batch.n_tokens = groupTokenCount;

        var tokenOffset = 0;
        for (int sequence = 0; sequence < groupSize; sequence++) {
          final tokens = tokenizedInputs[groupStart + sequence];
          for (int pos = 0; pos < tokens.length; pos++) {
            batch.token[tokenOffset] = tokens[pos];
            batch.pos[tokenOffset] = pos;
            batch.n_seq_id[tokenOffset] = 1;
            batch.seq_id[tokenOffset][0] = sequence;
            batch.logits[tokenOffset] = 1;
            tokenOffset += 1;
          }
        }

        final status = useEncoderPath
            ? llama_encode(ctx.pointer, batch)
            : llama_decode(ctx.pointer, batch);
        if (status != 0) {
          throw Exception('Batch embedding forward pass failed');
        }

        for (int sequence = 0; sequence < groupSize; sequence++) {
          var embeddingPtr = llama_get_embeddings_seq(ctx.pointer, sequence);
          if (embeddingPtr == nullptr && groupSize == 1) {
            embeddingPtr = llama_get_embeddings(ctx.pointer);
          }
          if (embeddingPtr == nullptr) {
            throw Exception('Batch embedding output is unavailable');
          }

          final vector = List<double>.from(
            embeddingPtr.asTypedList(embeddingSize),
            growable: false,
          );
          vectors[groupStart + sequence] = normalize
              ? _normalizeEmbeddingVector(vector)
              : vector;
        }
      } finally {
        llama_set_embeddings(ctx.pointer, false);
        llama_batch_free(batch);
      }
    }

    return vectors.map((vector) => vector!).toList(growable: false);
  }

  List<int> _tokenizeEmbeddingText(
    Pointer<llama_vocab> vocab,
    String text,
    int maxTokens,
  ) {
    final shouldAddSpecial = !_promptStartsWithBosToken(vocab, text);
    final textPtr = text.toNativeUtf8();

    final requiredTokenCount = -llama_tokenize(
      vocab,
      textPtr.cast(),
      textPtr.length,
      nullptr,
      0,
      shouldAddSpecial,
      true,
    );

    if (requiredTokenCount <= 0 || requiredTokenCount > maxTokens) {
      malloc.free(textPtr);
      throw Exception('Failed to tokenize embedding input');
    }

    final tokensPtr = malloc<Int32>(requiredTokenCount);
    try {
      final actualTokenCount = llama_tokenize(
        vocab,
        textPtr.cast(),
        textPtr.length,
        tokensPtr,
        requiredTokenCount,
        shouldAddSpecial,
        true,
      );
      if (actualTokenCount <= 0 || actualTokenCount > maxTokens) {
        throw Exception('Failed to encode embedding input');
      }

      return List<int>.from(tokensPtr.asTypedList(actualTokenCount));
    } finally {
      malloc.free(tokensPtr);
      malloc.free(textPtr);
    }
  }

  int _resolveEmbeddingDimension(Pointer<llama_model> modelPointer) {
    var embeddingSize = llama_model_n_embd_out(modelPointer);
    if (embeddingSize <= 0) {
      embeddingSize = llama_model_n_embd(modelPointer);
    }
    if (embeddingSize <= 0) {
      throw Exception('Failed to resolve embedding dimension');
    }
    return embeddingSize;
  }

  List<double> _normalizeEmbeddingVector(List<double> vector) {
    var normSquared = 0.0;
    for (final value in vector) {
      normSquared += value * value;
    }

    if (normSquared <= 0.0) {
      return vector;
    }

    final scale = 1.0 / math.sqrt(normSquared);
    final normalized = List<double>.filled(vector.length, 0.0, growable: false);
    for (int i = 0; i < vector.length; i++) {
      normalized[i] = vector[i] * scale;
    }
    return normalized;
  }

  /// Helper: Resets the context state to be ready for new generation.
  _LlamaContextWrapper _resetContext(
    int contextHandle,
    _LlamaContextWrapper ctx, {
    required bool clearMemory,
  }) {
    llama_synchronize(ctx.pointer);

    if (clearMemory) {
      _clearContextMemory(ctx.pointer);
      ctx.cachedPromptTokens = null;
    }

    _contexts[contextHandle] = ctx;
    return ctx;
  }

  void _clearContextMemory(
    Pointer<llama_context> contextPointer, {
    bool strict = true,
  }) {
    final memory = llama_get_memory(contextPointer);
    if (memory == nullptr) {
      if (strict) {
        throw Exception("Failed to reset context memory");
      }
      return;
    }

    llama_memory_clear(memory, true);
  }

  /// Helper: Ingests the prompt (text or multimodal) and returns initial token count.
  int _ingestPrompt(
    int contextHandle,
    int modelHandle,
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    String prompt,
    List<LlamaContentPart>? parts,
    Pointer<Int32> tokensPtr,
    int nCtx,
    llama_context_params modelParams, {
    required bool allowTextPromptReuse,
    required Pointer<llama_dart_speculative> speculativeSession,
    required _SpeculativeApi? speculativeApi,
    required _LlamaCppSpeculativeConfig? speculativeConfig,
  }) {
    final mediaParts =
        parts
            ?.where((p) => p is LlamaImageContent || p is LlamaAudioContent)
            .toList() ??
        [];
    final mmHandle = _modelToMtmd[modelHandle];
    final mmCtx = mmHandle != null ? _mtmdContexts[mmHandle] : null;

    if (mediaParts.isNotEmpty && mmCtx != null) {
      return _ingestMultimodalPrompt(
        mmCtx,
        ctx,
        vocab,
        prompt,
        mediaParts,
        modelParams,
      );
    } else {
      return _ingestTextPrompt(
        batch,
        vocab,
        prompt,
        tokensPtr,
        nCtx,
        ctx,
        maxBatchTokens: modelParams.n_batch,
        allowPromptReuse: allowTextPromptReuse,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
      );
    }
  }

  int _ingestMultimodalPrompt(
    Pointer<mtmd_context> mmCtx,
    _LlamaContextWrapper ctx,
    Pointer<llama_vocab> vocab,
    String prompt,
    List<LlamaContentPart> mediaParts,
    llama_context_params modelParams,
  ) {
    int initialTokens = 0;
    final bitmaps = malloc<Pointer<mtmd_bitmap>>(mediaParts.length);
    final chunks = _mtmdInputChunksInit();
    Pointer<mtmd_input_text> inputText = nullptr;
    Pointer<Utf8> promptPtr = nullptr;

    try {
      for (int i = 0; i < mediaParts.length; i++) {
        final p = mediaParts[i];
        bitmaps[i] = nullptr;
        if (p is LlamaImageContent) {
          if (p.path != null) {
            final pathPtr = p.path!.toNativeUtf8();
            bitmaps[i] = _mtmdHelperBitmapInitFromFile(mmCtx, pathPtr.cast());
            malloc.free(pathPtr);
          } else if (p.bytes != null) {
            final dataPtr = malloc<Uint8>(p.bytes!.length);
            dataPtr.asTypedList(p.bytes!.length).setAll(0, p.bytes!);
            bitmaps[i] = _mtmdHelperBitmapInitFromBuf(
              mmCtx,
              dataPtr.cast(),
              p.bytes!.length,
            );
            malloc.free(dataPtr);
          }
        } else if (p is LlamaAudioContent) {
          if (p.path != null) {
            final pathPtr = p.path!.toNativeUtf8();
            bitmaps[i] = _mtmdHelperBitmapInitFromFile(mmCtx, pathPtr.cast());
            malloc.free(pathPtr);
          } else if (p.bytes != null) {
            final dataPtr = malloc<Uint8>(p.bytes!.length);
            dataPtr.asTypedList(p.bytes!.length).setAll(0, p.bytes!);
            bitmaps[i] = _mtmdHelperBitmapInitFromBuf(
              mmCtx,
              dataPtr.cast(),
              p.bytes!.length,
            );
            malloc.free(dataPtr);
          } else if (p.samples != null) {
            final dataPtr = malloc<Float>(p.samples!.length);
            dataPtr.asTypedList(p.samples!.length).setAll(0, p.samples!);
            bitmaps[i] = _mtmdBitmapInitFromAudio(
              p.samples!.length,
              dataPtr.cast(),
            );
            malloc.free(dataPtr);
          }
        }

        if (bitmaps[i] == nullptr) {
          throw Exception("Failed to load media part $i");
        }
      }

      inputText = malloc<mtmd_input_text>();
      final normalizedPrompt = _normalizeMtmdPromptMarkers(
        prompt,
        mediaParts.length,
      );
      promptPtr = normalizedPrompt.toNativeUtf8();
      inputText.ref.text = promptPtr.cast();
      inputText.ref.text_len = utf8.encode(normalizedPrompt).length;

      final bos = llama_vocab_bos(vocab);
      final eos = llama_vocab_eos(vocab);
      final shouldAddSpecial =
          (bos != eos && bos != -1) &&
          !_promptStartsWithBosToken(vocab, normalizedPrompt);
      inputText.ref.add_special = shouldAddSpecial;
      inputText.ref.parse_special = true;

      final res = _mtmdTokenize(
        mmCtx,
        chunks,
        inputText,
        bitmaps.cast(),
        mediaParts.length,
      );

      if (res == 0) {
        final newPast = malloc<llama_pos>();
        try {
          final evalResult = _mtmdHelperEvalChunks(
            mmCtx,
            ctx.pointer,
            chunks,
            0,
            0,
            modelParams.n_batch,
            true,
            newPast,
          );
          if (evalResult == 0) {
            initialTokens = newPast.value;
          } else {
            throw Exception(
              'Multimodal prompt evaluation failed: $evalResult. '
              'The active context window may be too small for this image and conversation history.',
            );
          }
        } finally {
          malloc.free(newPast);
        }
      } else {
        throw Exception("mtmd_tokenize failed: $res");
      }
    } finally {
      // Free in finally so a tokenize/eval failure above does not leak the
      // prompt buffer or the input-text struct.
      if (promptPtr != nullptr) malloc.free(promptPtr);
      if (inputText != nullptr) malloc.free(inputText);
      for (int i = 0; i < mediaParts.length; i++) {
        if (bitmaps[i] != nullptr) _mtmdBitmapFree(bitmaps[i]);
      }
      malloc.free(bitmaps);
      _mtmdInputChunksFree(chunks);
    }
    ctx.cachedPromptTokens = null;
    return initialTokens;
  }

  void _ensureLogitsAvailableAfterPromptEval(Pointer<llama_context> ctx) {
    if (llama_get_logits(ctx) != nullptr) {
      return;
    }

    throw Exception(
      'Prompt evaluation produced no logits for sampling. '
      'The active context window may be too small for this prompt or multimodal decode failed.',
    );
  }

  String _normalizeMtmdPromptMarkers(String prompt, int mediaPartCount) {
    final markerPtr = _mtmdDefaultMarker();
    final marker = markerPtr == nullptr
        ? '<__media__>'
        : markerPtr.cast<Utf8>().toDartString();

    var normalized = prompt;
    const directPlaceholders = [
      '<image>',
      '[IMG]',
      '<|image|>',
      '<|audio|>',
      '<|video|>',
      '<img>',
      '<|img|>',
      '<image_soft_token>',
      '<audio_soft_token>',
      '<video_soft_token>',
    ];

    for (final placeholder in directPlaceholders) {
      normalized = normalized.replaceAll(placeholder, marker);
    }

    // Some VLM templates index image placeholders (e.g. <|image_1|>).
    normalized = normalized.replaceAll(RegExp(r'<\|image_\d+\|>'), marker);

    if (mediaPartCount <= 0) {
      return normalized;
    }

    final markerCount = _countOccurrences(normalized, marker);
    if (markerCount < mediaPartCount) {
      final missing = mediaPartCount - markerCount;
      final markerBlock = List.filled(missing, marker).join(' ');

      if (normalized.contains('User:')) {
        normalized = normalized.replaceFirst('User:', 'User: $markerBlock ');
      } else if (normalized.contains('user:')) {
        normalized = normalized.replaceFirst('user:', 'user: $markerBlock ');
      } else {
        normalized = '$markerBlock\n$normalized';
      }
    }

    return normalized;
  }

  int _countOccurrences(String text, String pattern) {
    if (pattern.isEmpty) {
      return 0;
    }

    int count = 0;
    int start = 0;
    while (true) {
      final index = text.indexOf(pattern, start);
      if (index == -1) {
        break;
      }
      count++;
      start = index + pattern.length;
    }
    return count;
  }

  bool _promptStartsWithBosToken(Pointer<llama_vocab> vocab, String prompt) {
    final bos = llama_vocab_bos(vocab);
    if (bos < 0) {
      return false;
    }

    final bosPtr = llama_token_get_text(vocab, bos);
    if (bosPtr == nullptr) {
      return false;
    }

    final bosToken = bosPtr.cast<Utf8>().toDartString();
    if (bosToken.isEmpty) {
      return false;
    }

    return prompt.trimLeft().startsWith(bosToken);
  }

  int _ingestTextPrompt(
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    String prompt,
    Pointer<Int32> tokensPtr,
    int nCtx,
    _LlamaContextWrapper ctx, {
    required int maxBatchTokens,
    required bool allowPromptReuse,
    required Pointer<llama_dart_speculative> speculativeSession,
    required _SpeculativeApi? speculativeApi,
    required _LlamaCppSpeculativeConfig? speculativeConfig,
  }) {
    final promptPtr = prompt.toNativeUtf8();
    final shouldAddSpecial = !_promptStartsWithBosToken(vocab, prompt);
    final nTokens = llama_tokenize(
      vocab,
      promptPtr.cast(),
      promptPtr.length,
      tokensPtr,
      nCtx,
      shouldAddSpecial,
      true,
    );
    malloc.free(promptPtr);

    if (nTokens < 0 || nTokens > nCtx) {
      throw Exception("Tokenization failed or prompt too long");
    }

    if (!allowPromptReuse || nTokens == 0) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        outputAllLogits: speculativeSession != nullptr,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
      );
    }

    final cachedTokens = ctx.cachedPromptTokens;
    if (cachedTokens == null || cachedTokens.isEmpty) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        outputAllLogits: speculativeSession != nullptr,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
      );
    }

    final reusedPrefix = _sharedPrefixLength(cachedTokens, tokensPtr, nTokens);

    // Loaded KV holds no live logits; re-decode only the final token. Gated
    // on kvFromStateLoad so the in-process reuse path stays bit-exact against
    // a cleared baseline (parity property).
    final exactStateLoadMatch =
        ctx.kvFromStateLoad &&
        reusedPrefix == nTokens &&
        cachedTokens.length == nTokens;

    if (reusedPrefix <= 0 ||
        (reusedPrefix >= nTokens && !exactStateLoadMatch)) {
      final canReuseCachedCopy =
          reusedPrefix == nTokens && cachedTokens.length == nTokens;
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        existingCachedTokens: canReuseCachedCopy ? cachedTokens : null,
        outputAllLogits: speculativeSession != nullptr,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
      );
    }

    final memory = llama_get_memory(ctx.pointer);
    if (memory == nullptr) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        outputAllLogits: speculativeSession != nullptr,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
      );
    }

    final decodeStart = exactStateLoadMatch ? nTokens - 1 : reusedPrefix;

    final maxSeqPos = llama_memory_seq_pos_max(memory, 0);
    final removeTo = maxSeqPos >= decodeStart ? maxSeqPos + 1 : decodeStart;
    final removedTail = llama_memory_seq_rm(memory, 0, decodeStart, removeTo);
    if (!removedTail) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        outputAllLogits: speculativeSession != nullptr,
        speculativeSession: speculativeSession,
        speculativeApi: speculativeApi,
        speculativeConfig: speculativeConfig,
      );
    }

    final suffixTokenCount = nTokens - decodeStart;
    _decodePromptSegment(
      batch,
      tokensPtr,
      ctx,
      startTokenIndex: decodeStart,
      tokenCount: suffixTokenCount,
      maxBatchTokens: maxBatchTokens,
      outputAllLogits: speculativeSession != nullptr,
      speculativeSession: speculativeSession,
      speculativeApi: speculativeApi,
      speculativeConfig: speculativeConfig,
    );

    ctx.cachedPromptTokens = exactStateLoadMatch
        ? cachedTokens
        : _copyPromptTokens(tokensPtr, nTokens);
    ctx.kvFromStateLoad = false;

    return nTokens;
  }

  int _decodeAndCacheFullPrompt(
    llama_batch batch,
    Pointer<Int32> tokensPtr,
    _LlamaContextWrapper ctx,
    int nTokens, {
    required int maxBatchTokens,
    List<int>? existingCachedTokens,
    bool outputAllLogits = false,
    Pointer<llama_dart_speculative>? speculativeSession,
    _SpeculativeApi? speculativeApi,
    _LlamaCppSpeculativeConfig? speculativeConfig,
  }) {
    _clearContextMemory(ctx.pointer);
    _decodePromptSegment(
      batch,
      tokensPtr,
      ctx,
      startTokenIndex: 0,
      tokenCount: nTokens,
      maxBatchTokens: maxBatchTokens,
      outputAllLogits: outputAllLogits,
      speculativeSession: speculativeSession,
      speculativeApi: speculativeApi,
      speculativeConfig: speculativeConfig,
    );
    ctx.cachedPromptTokens =
        existingCachedTokens ?? _copyPromptTokens(tokensPtr, nTokens);
    ctx.kvFromStateLoad = false;
    return nTokens;
  }

  List<int> _copyPromptTokens(Pointer<Int32> tokensPtr, int tokenCount) {
    if (tokenCount <= 0) {
      return const <int>[];
    }
    return List<int>.from(tokensPtr.asTypedList(tokenCount), growable: false);
  }

  void _decodePromptSegment(
    llama_batch batch,
    Pointer<Int32> tokensPtr,
    _LlamaContextWrapper ctx, {
    required int startTokenIndex,
    required int tokenCount,
    required int maxBatchTokens,
    bool outputAllLogits = false,
    Pointer<llama_dart_speculative>? speculativeSession,
    _SpeculativeApi? speculativeApi,
    _LlamaCppSpeculativeConfig? speculativeConfig,
  }) {
    if (tokenCount <= 0) {
      return;
    }

    final effectiveBatchTokens = maxBatchTokens > 0
        ? maxBatchTokens
        : tokenCount;
    var decoded = 0;

    while (decoded < tokenCount) {
      final remaining = tokenCount - decoded;
      final chunkTokenCount = remaining > effectiveBatchTokens
          ? effectiveBatchTokens
          : remaining;
      batch.n_tokens = chunkTokenCount;

      for (int i = 0; i < chunkTokenCount; i++) {
        final tokenIndex = startTokenIndex + decoded + i;
        batch.token[i] = tokensPtr[tokenIndex];
        batch.pos[i] = tokenIndex;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        final isLastTokenInPrompt = decoded + i == tokenCount - 1;
        batch.logits[i] = outputAllLogits || isLastTokenInPrompt ? 1 : 0;
      }

      if (llama_decode(ctx.pointer, batch) != 0) {
        throw Exception("Initial decode failed");
      }
      if (speculativeSession != null &&
          speculativeSession != nullptr &&
          !_processSpeculativeBatch(
            speculativeApi!,
            speculativeSession,
            batch,
            speculativeConfig,
          )) {
        throw Exception("Speculative prompt decode processing failed");
      }

      decoded += chunkTokenCount;
    }
  }

  bool _processSpeculativeBatch(
    _SpeculativeApi speculativeApi,
    Pointer<llama_dart_speculative> speculativeSession,
    llama_batch batch,
    _LlamaCppSpeculativeConfig? speculativeConfig,
  ) {
    return _withSuppressedBatchLogits(
      batch.logits,
      batch.n_tokens,
      speculativeConfig?.suppressDraftProcessLogits == true,
      () => speculativeApi.processBatch(speculativeSession, batch),
    );
  }

  static T _withSuppressedBatchLogits<T>(
    Pointer<Int8> logits,
    int tokenCount,
    bool suppress,
    T Function() action,
  ) {
    if (!suppress || logits == nullptr || tokenCount <= 0) {
      return action();
    }

    final logitView = logits.asTypedList(tokenCount);
    final previousLogits = List<int>.of(logitView, growable: false);
    try {
      logitView.fillRange(0, tokenCount, 0);
      return action();
    } finally {
      logitView.setAll(0, previousLogits);
    }
  }

  int _sharedPrefixLength(
    List<int> cachedTokens,
    Pointer<Int32> newTokens,
    int newTokenCount,
  ) {
    final maxLength = cachedTokens.length < newTokenCount
        ? cachedTokens.length
        : newTokenCount;
    int i = 0;
    while (i < maxLength && cachedTokens[i] == newTokens[i]) {
      i++;
    }
    return i;
  }

  /// Helper: Initializes the sampler chain.
  Pointer<llama_sampler> _initializeSampler(
    GenerationParams params,
    Pointer<llama_vocab> vocab,
    int vocabSize,
    List<int> suppressedTokens,
    Pointer<Utf8> grammarPtr,
    Pointer<Utf8> rootPtr,
    _LazyGrammarConfig? lazyGrammarConfig,
    _LlamaCppThinkingBudgetConfig? thinkingBudgetConfig,
    _ReasoningBudgetApi? reasoningBudgetApi,
    int initialTokens,
    Pointer<Int32> tokensPtr,
  ) {
    final sampler = llama_sampler_chain_init(
      llama_sampler_chain_default_params(),
    );

    final penaltyConfig = _resolvePenaltySamplerConfig(params);
    final penaltiesSampler = llama_sampler_init_penalties(
      vocabSize,
      penaltyConfig.lastN,
      penaltyConfig.repeat,
      penaltyConfig.frequency,
      penaltyConfig.presence,
    );
    llama_sampler_chain_add(sampler, penaltiesSampler);

    if (suppressedTokens.isNotEmpty) {
      final suppressSampler = createSuppressTokensSampler(
        vocabSize,
        suppressedTokens,
      );
      if (suppressSampler == nullptr) {
        llama_sampler_free(sampler);
        throw LlamaInferenceException(
          'llama.cpp failed to initialize model-specific suppressed tokens.',
        );
      }
      llama_sampler_chain_add(sampler, suppressSampler);
    }

    Pointer<llama_sampler> grammarSampler = nullptr;
    final useLazyGrammar = params.grammarLazy && lazyGrammarConfig != null;
    if (grammarPtr != nullptr) {
      if (useLazyGrammar) {
        grammarSampler = llama_sampler_init_grammar_lazy_patterns(
          vocab,
          grammarPtr.cast(),
          rootPtr.cast(),
          lazyGrammarConfig.triggerPatterns,
          lazyGrammarConfig.numTriggerPatterns,
          lazyGrammarConfig.triggerTokens,
          lazyGrammarConfig.numTriggerTokens,
        );
      } else {
        grammarSampler = llama_sampler_init_grammar(
          vocab,
          grammarPtr.cast(),
          rootPtr.cast(),
        );
      }
    }
    if (grammarPtr != nullptr && grammarSampler == nullptr) {
      llama_sampler_free(sampler);
      throw LlamaInferenceException(
        'llama.cpp failed to initialize the requested grammar sampler.',
      );
    }

    if (thinkingBudgetConfig != null) {
      final api = reasoningBudgetApi;
      if (api == null) {
        if (grammarSampler != nullptr) {
          llama_sampler_free(grammarSampler);
        }
        llama_sampler_free(sampler);
        throw StateError('Missing llama.cpp reasoning-budget sampler API.');
      }
      final budgetSampler = api.initSampler(
        vocab: vocab,
        config: thinkingBudgetConfig,
        pauseGrammarDuringReasoning: grammarSampler != nullptr,
        grammarSampler: grammarSampler,
        promptTokens: tokensPtr,
        promptTokenCount: initialTokens,
      );
      if (budgetSampler == nullptr) {
        if (grammarSampler != nullptr) {
          llama_sampler_free(grammarSampler);
        }
        llama_sampler_free(sampler);
        throw LlamaUnsupportedException(
          'llama.cpp could not initialize thinking-budget control. Verify '
          'that the configured thinking tags are supported by the loaded '
          'model vocabulary.',
        );
      }
      // The native composite sampler owns grammarSampler after this point.
      grammarSampler = nullptr;
      llama_sampler_chain_add(sampler, budgetSampler);
    } else if (grammarSampler != nullptr) {
      llama_sampler_chain_add(sampler, grammarSampler);
    }

    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(params.topK));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params.topP, 1));
    if (params.minP > 0) {
      llama_sampler_chain_add(
        sampler,
        llama_sampler_init_min_p(params.minP, 1),
      );
    }
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(params.temp));

    if (params.temp <= 0) {
      llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    } else {
      final seed = params.seed ?? DateTime.now().millisecondsSinceEpoch;
      llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));
    }

    if (grammarPtr == nullptr && tokensPtr != nullptr && initialTokens > 0) {
      if (thinkingBudgetConfig != null) {
        // The composite sampler derives its reasoning state from the complete
        // prompt rather than accepting it token by token, but prompt tokens
        // still need to seed the repeat-penalty sampler as before.
        for (int i = 0; i < initialTokens; i++) {
          llama_sampler_accept(penaltiesSampler, tokensPtr[i]);
        }
      } else {
        for (int i = 0; i < initialTokens; i++) {
          llama_sampler_accept(sampler, tokensPtr[i]);
        }
      }
    }

    return sampler;
  }

  /// Helper: Runs the main inference loop and yields tokens.
  Stream<List<int>> _runInferenceLoop(
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    Pointer<llama_sampler> sampler,
    GenerationParams params,
    int startPos,
    int nCtx,
    int cancelTokenAddress,
    Pointer<Uint8> pieceBuf,
    Pointer<Utf8> grammarPtr,
    Set<int> preservedTokenIds,
    List<String> stopSequences,
  ) async* {
    final cancelToken = Pointer<Int8>.fromAddress(cancelTokenAddress);
    int currentPos = startPos;
    final accumulatedBytes = <int>[];
    final evalStopwatch = Stopwatch()..start();
    var sampleMicros = 0;
    var evalMicros = 0;
    var generatedTokens = 0;

    for (int i = 0; i < params.maxTokens; i++) {
      if (cancelToken.value == 1) break;
      if (currentPos >= nCtx) break;

      final sampleTick = Stopwatch()..start();
      final selectedToken = llama_sampler_sample(sampler, ctx.pointer, -1);
      sampleTick.stop();
      sampleMicros += sampleTick.elapsedMicroseconds;
      // Never pass an invalid sampled token into get_rows / token_to_piece.
      // This applies only to sampled text tokens, not multimodal embeddings.
      validateSampledToken(selectedToken, llama_vocab_n_tokens(vocab));
      if (llama_vocab_is_eog(vocab, selectedToken)) break;

      final pieceTick = Stopwatch()..start();
      final n = llama_token_to_piece(
        vocab,
        selectedToken,
        pieceBuf.cast(),
        256,
        0,
        preservedTokenIds.contains(selectedToken),
      );
      pieceTick.stop();
      sampleMicros += pieceTick.elapsedMicroseconds;

      if (n > 0) {
        final bytes = pieceBuf.asTypedList(n).toList();
        yield bytes;
        generatedTokens++;

        if (stopSequences.isNotEmpty) {
          accumulatedBytes.addAll(bytes);
          if (accumulatedBytes.length > 64) {
            accumulatedBytes.removeRange(0, accumulatedBytes.length - 64);
          }
          final text = utf8.decode(accumulatedBytes, allowMalformed: true);
          if (stopSequences.any((s) => text.endsWith(s))) break;
        }
      }

      batch.n_tokens = 1;
      batch.token[0] = selectedToken;
      batch.pos[0] = currentPos++;
      batch.n_seq_id[0] = 1;
      batch.seq_id[0][0] = 0;
      batch.logits[0] = 1;

      final evalTick = Stopwatch()..start();
      final decodeStatus = llama_decode(ctx.pointer, batch);
      evalTick.stop();
      evalMicros += evalTick.elapsedMicroseconds;
      if (decodeStatus != 0) break;
    }

    evalStopwatch.stop();
    ctx.lastPerfEvalMs = evalMicros / 1000.0;
    ctx.lastPerfSampleMs = sampleMicros / 1000.0;
    ctx.lastPerfDecodeMs = evalMicros / 1000.0;
    ctx.lastPerfEvalTokens = generatedTokens;
    ctx.lastPerfSampleCount = generatedTokens;
  }

  Stream<List<int>> _runSpeculativeInferenceLoop(
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    Pointer<llama_sampler> sampler,
    GenerationParams params,
    _LlamaCppSpeculativeConfig speculativeConfig,
    int startPos,
    int nCtx,
    int cancelTokenAddress,
    Pointer<Uint8> pieceBuf,
    Set<int> preservedTokenIds,
    List<String> stopSequences,
    Pointer<llama_dart_speculative> speculativeSession,
    _SpeculativeApi speculativeApi,
    Pointer<Int32> tokensPtr,
  ) async* {
    final cancelToken = Pointer<Int8>.fromAddress(cancelTokenAddress);
    final draftCapacity = speculativeConfig.draftTokenMax;
    final draftPtr = malloc<Int32>(draftCapacity);
    final idxPtr = malloc<Int32>(draftCapacity + 1);
    final acceptedPtr = malloc<Int32>(draftCapacity + 1);
    final draftContext = speculativeApi.getDraftContext(speculativeSession);
    final hasDraftContext = draftContext != nullptr;

    int currentPos = startPos;
    int? pendingSampledToken;
    final accumulatedBytes = <int>[];
    final evalStopwatch = Stopwatch()..start();
    var sampleMicros = 0;
    var evalMicros = 0;
    var draftMicros = 0;
    var verifyMicros = 0;
    var generatedTokens = 0;
    var speculativeDraftTokens = 0;
    var speculativeAcceptedDraftTokens = 0;
    var speculativeDraftAttempts = 0;
    var speculativeVerifyTokens = 0;
    var speculativeReplayTokens = 0;
    var shouldStop = false;

    try {
      while (!shouldStop && generatedTokens < params.maxTokens) {
        if (cancelToken.value == 1) break;
        if (currentPos >= nCtx) break;

        int selectedToken;
        if (pendingSampledToken != null) {
          selectedToken = pendingSampledToken;
          pendingSampledToken = null;
        } else {
          final sampleTick = Stopwatch()..start();
          selectedToken = llama_sampler_sample(sampler, ctx.pointer, -1);
          sampleTick.stop();
          sampleMicros += sampleTick.elapsedMicroseconds;
          // Never pass an invalid sampled token into get_rows / token_to_piece.
          // This applies only to sampled text tokens, not multimodal embeddings.
          validateSampledToken(selectedToken, llama_vocab_n_tokens(vocab));
          if (llama_vocab_is_eog(vocab, selectedToken)) break;

          final pieceTick = Stopwatch()..start();
          final n = llama_token_to_piece(
            vocab,
            selectedToken,
            pieceBuf.cast(),
            256,
            0,
            preservedTokenIds.contains(selectedToken),
          );
          pieceTick.stop();
          sampleMicros += pieceTick.elapsedMicroseconds;
          generatedTokens++;

          if (n > 0) {
            final bytes = pieceBuf.asTypedList(n).toList();
            yield bytes;
            if (stopSequences.isNotEmpty) {
              accumulatedBytes.addAll(bytes);
              if (accumulatedBytes.length > 64) {
                accumulatedBytes.removeRange(0, accumulatedBytes.length - 64);
              }
              final text = utf8.decode(accumulatedBytes, allowMalformed: true);
              if (stopSequences.any((s) => text.endsWith(s))) {
                shouldStop = true;
              }
            }
          }

          if (shouldStop) {
            break;
          }
        }

        final remainingToGenerate = params.maxTokens - generatedTokens;
        final batchCapacity = math.max(1, llama_n_batch(ctx.pointer));
        final rollbackCapacity = llama_n_rs_seq(ctx.pointer);
        final contextDraftCapacity = rollbackCapacity > 0
            ? math.min(nCtx - currentPos - 2, rollbackCapacity)
            : nCtx - currentPos - 2;
        final draftLimit = remainingToGenerate <= 1
            ? 0
            : math.min(
                speculativeConfig.draftTokenMax,
                math.min(
                  math.min(remainingToGenerate - 1, contextDraftCapacity),
                  batchCapacity - 1,
                ),
              );

        var draftCount = 0;
        if (draftLimit > 0) {
          speculativeDraftAttempts++;
          final draftTick = Stopwatch()..start();
          draftCount = speculativeApi.draft(
            speculativeSession,
            0,
            currentPos,
            selectedToken,
            tokensPtr,
            currentPos,
            draftLimit,
            draftPtr,
            draftLimit,
          );
          draftTick.stop();
          draftMicros += draftTick.elapsedMicroseconds;
          if (draftCount < 0) {
            throw Exception("llama.cpp speculative draft failed");
          }
          speculativeDraftTokens += draftCount;
        }

        if (draftCount <= 0) {
          batch.n_tokens = 1;
          batch.token[0] = selectedToken;
          batch.pos[0] = currentPos;
          batch.n_seq_id[0] = 1;
          batch.seq_id[0][0] = 0;
          batch.logits[0] = 1;

          final evalTick = Stopwatch()..start();
          final decodeStatus = llama_decode(ctx.pointer, batch);
          if (decodeStatus == 0 &&
              !_processSpeculativeBatch(
                speculativeApi,
                speculativeSession,
                batch,
                speculativeConfig,
              )) {
            throw Exception("Speculative decode processing failed");
          }
          evalTick.stop();
          evalMicros += evalTick.elapsedMicroseconds;
          if (decodeStatus != 0) break;

          tokensPtr[currentPos] = selectedToken;
          currentPos++;
          continue;
        }

        Pointer<Uint8> seqCheckpoint = nullptr;
        var seqCheckpointSize = 0;
        final draftMemory = hasDraftContext
            ? llama_get_memory(draftContext)
            : nullptr;

        try {
          if (hasDraftContext) {
            if (draftMemory == nullptr ||
                !llama_memory_seq_rm(draftMemory, 0, currentPos, -1)) {
              throw UnsupportedError(
                'llama.cpp speculative draft rollback failed for this context.',
              );
            }
          } else {
            llama_synchronize(ctx.pointer);
            seqCheckpointSize = llama_state_seq_get_size_ext(
              ctx.pointer,
              0,
              LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY,
            );
            if (seqCheckpointSize > 0) {
              seqCheckpoint = malloc<Uint8>(seqCheckpointSize);
              final written = llama_state_seq_get_data_ext(
                ctx.pointer,
                seqCheckpoint,
                seqCheckpointSize,
                0,
                LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY,
              );
              if (written != seqCheckpointSize) {
                throw Exception(
                  'speculative checkpoint capture failed '
                  '(expected $seqCheckpointSize bytes, got $written)',
                );
              }
            }
          }

          final batchTokens = draftCount + 1;
          batch.n_tokens = batchTokens;
          batch.token[0] = selectedToken;
          batch.pos[0] = currentPos;
          batch.n_seq_id[0] = 1;
          batch.seq_id[0][0] = 0;
          batch.logits[0] = 1;
          for (int i = 0; i < draftCount; i++) {
            final batchIndex = i + 1;
            batch.token[batchIndex] = draftPtr[i];
            batch.pos[batchIndex] = currentPos + batchIndex;
            batch.n_seq_id[batchIndex] = 1;
            batch.seq_id[batchIndex][0] = 0;
            batch.logits[batchIndex] = 1;
          }

          final evalTick = Stopwatch()..start();
          final decodeStatus = llama_decode(ctx.pointer, batch);
          if (decodeStatus == 0 &&
              !_processSpeculativeBatch(
                speculativeApi,
                speculativeSession,
                batch,
                speculativeConfig,
              )) {
            throw Exception("Speculative decode processing failed");
          }
          if (decodeStatus == 0) {
            llama_synchronize(ctx.pointer);
          }
          evalTick.stop();
          evalMicros += evalTick.elapsedMicroseconds;
          if (decodeStatus != 0) break;
          speculativeVerifyTokens += batchTokens;

          for (int i = 0; i < batchTokens; i++) {
            idxPtr[i] = i;
          }

          final verifyTick = Stopwatch()..start();
          final acceptedCount = speculativeApi.sampleAndAcceptN(
            sampler,
            ctx.pointer,
            idxPtr,
            batchTokens,
            draftPtr,
            draftCount,
            acceptedPtr,
            batchTokens,
          );
          verifyTick.stop();
          verifyMicros += verifyTick.elapsedMicroseconds;
          if (acceptedCount <= 0) {
            throw Exception("llama.cpp speculative draft verification failed");
          }

          final acceptedDraftCount = acceptedCount - 1;
          final rejectedTailCount = batchTokens - acceptedCount;
          final keepUntil = currentPos + 1 + acceptedDraftCount;
          var targetTailReconciled = false;
          if (!hasDraftContext && rejectedTailCount > 0) {
            final targetMemory = llama_get_memory(ctx.pointer);
            final trimmedRejectedTail =
                targetMemory != nullptr &&
                llama_memory_seq_rm(targetMemory, 0, keepUntil, -1);
            if (trimmedRejectedTail) {
              targetTailReconciled = true;
            } else {
              if (seqCheckpoint == nullptr) {
                throw UnsupportedError(
                  'llama.cpp speculative checkpoint rollback is unavailable '
                  'for this context.',
                );
              }

              final restored = llama_state_seq_set_data_ext(
                ctx.pointer,
                seqCheckpoint,
                seqCheckpointSize,
                0,
                LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY,
              );
              if (restored != seqCheckpointSize) {
                throw Exception(
                  'speculative checkpoint restore failed '
                  '(expected $seqCheckpointSize bytes, got $restored)',
                );
              }

              final targetMemory = llama_get_memory(ctx.pointer);
              if (targetMemory == nullptr ||
                  !llama_memory_seq_rm(targetMemory, 0, currentPos, -1)) {
                throw UnsupportedError(
                  'llama.cpp speculative checkpoint rollback failed for this '
                  'context.',
                );
              }

              final replayTokens = 1 + acceptedDraftCount;
              batch.n_tokens = replayTokens;
              batch.token[0] = selectedToken;
              batch.pos[0] = currentPos;
              batch.n_seq_id[0] = 1;
              batch.seq_id[0][0] = 0;
              batch.logits[0] = 0;
              for (int i = 0; i < acceptedDraftCount; i++) {
                final batchIndex = i + 1;
                batch.token[batchIndex] = acceptedPtr[i];
                batch.pos[batchIndex] = currentPos + batchIndex;
                batch.n_seq_id[batchIndex] = 1;
                batch.seq_id[batchIndex][0] = 0;
                batch.logits[batchIndex] = 0;
              }

              final replayTick = Stopwatch()..start();
              final replayStatus = llama_decode(ctx.pointer, batch);
              if (replayStatus == 0 &&
                  !_processSpeculativeBatch(
                    speculativeApi,
                    speculativeSession,
                    batch,
                    speculativeConfig,
                  )) {
                throw Exception("Speculative replay processing failed");
              }
              if (replayStatus == 0) {
                llama_synchronize(ctx.pointer);
              }
              replayTick.stop();
              evalMicros += replayTick.elapsedMicroseconds;
              if (replayStatus != 0) {
                throw Exception("Speculative replay decode failed");
              }
              speculativeReplayTokens += replayTokens;
              targetTailReconciled = true;
            }
          }

          speculativeAcceptedDraftTokens += acceptedDraftCount;
          speculativeApi.accept(speculativeSession, 0, acceptedDraftCount);

          final targetMemory = llama_get_memory(ctx.pointer);
          final targetRollbackOk =
              targetTailReconciled ||
              targetMemory != nullptr &&
                  llama_memory_seq_rm(targetMemory, 0, keepUntil, -1);
          final draftRollbackOk =
              !hasDraftContext ||
              (draftMemory != nullptr &&
                  llama_memory_seq_rm(draftMemory, 0, keepUntil, -1));
          if (!targetRollbackOk || !draftRollbackOk) {
            throw UnsupportedError(
              'llama.cpp speculative target rollback failed for this context. '
              'Set ModelParams.speculativeRollbackTokenMax >= the effective '
              'speculative draft length (draftTokenMax for draft-model or '
              'ngram-cache strategies; ngramTokenMax when set for ngram-mod, '
              'otherwise draftTokenMax/default; ngramSizeM for ngram-simple, '
              'ngram-map-k, or ngram-map-k4v) if this model/backend uses '
              'bounded rollback snapshots.',
            );
          }

          tokensPtr[currentPos] = selectedToken;
          for (int i = 0; i < acceptedDraftCount; i++) {
            tokensPtr[currentPos + 1 + i] = acceptedPtr[i];
          }
          currentPos = keepUntil;

          for (int i = 0; i < acceptedCount; i++) {
            final token = acceptedPtr[i];
            if (llama_vocab_is_eog(vocab, token)) {
              shouldStop = true;
              break;
            }

            final pieceTick = Stopwatch()..start();
            final n = llama_token_to_piece(
              vocab,
              token,
              pieceBuf.cast(),
              256,
              0,
              preservedTokenIds.contains(token),
            );
            pieceTick.stop();
            sampleMicros += pieceTick.elapsedMicroseconds;
            generatedTokens++;

            if (n > 0) {
              final bytes = pieceBuf.asTypedList(n).toList();
              yield bytes;
              if (stopSequences.isNotEmpty) {
                accumulatedBytes.addAll(bytes);
                if (accumulatedBytes.length > 64) {
                  accumulatedBytes.removeRange(0, accumulatedBytes.length - 64);
                }
                final text = utf8.decode(
                  accumulatedBytes,
                  allowMalformed: true,
                );
                if (stopSequences.any((s) => text.endsWith(s))) {
                  shouldStop = true;
                }
              }
            }

            if (shouldStop || generatedTokens >= params.maxTokens) {
              break;
            }
          }

          if (!shouldStop && generatedTokens < params.maxTokens) {
            pendingSampledToken = acceptedPtr[acceptedCount - 1];
          }
        } finally {
          if (seqCheckpoint != nullptr) {
            malloc.free(seqCheckpoint);
          }
        }
      }
    } finally {
      malloc.free(draftPtr);
      malloc.free(idxPtr);
      malloc.free(acceptedPtr);
      evalStopwatch.stop();
      ctx.lastPerfEvalMs = evalMicros / 1000.0;
      ctx.lastPerfSampleMs = sampleMicros / 1000.0;
      ctx.lastPerfDecodeMs = evalMicros / 1000.0;
      ctx.lastPerfSpeculativeDraftMs = draftMicros / 1000.0;
      ctx.lastPerfSpeculativeVerifyMs = verifyMicros / 1000.0;
      ctx.lastPerfEvalTokens = generatedTokens;
      ctx.lastPerfSampleCount = generatedTokens;
      ctx.lastPerfSpeculativeDraftTokens = speculativeDraftTokens;
      ctx.lastPerfSpeculativeAcceptedDraftTokens =
          speculativeAcceptedDraftTokens;
      ctx.lastPerfSpeculativeDraftAttempts = speculativeDraftAttempts;
      ctx.lastPerfSpeculativeVerifyTokens = speculativeVerifyTokens;
      ctx.lastPerfSpeculativeReplayTokens = speculativeReplayTokens;
      ctx.lastPerfSpeculativeRan = true;
    }
  }

  // Legacy MTP loop retained while older wrapper symbols remain supported.
  // ignore: unused_element
  Stream<List<int>> _runMtpInferenceLoop(
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    Pointer<llama_sampler> sampler,
    GenerationParams params,
    _LlamaCppMtpConfig mtpConfig,
    int startPos,
    int nCtx,
    int cancelTokenAddress,
    Pointer<Uint8> pieceBuf,
    Set<int> preservedTokenIds,
    List<String> stopSequences,
    Pointer<llama_dart_mtp> mtpSession,
    _MtpApi mtpApi,
    Pointer<Int32> tokensPtr,
  ) async* {
    final cancelToken = Pointer<Int8>.fromAddress(cancelTokenAddress);
    final draftCapacity = mtpConfig.draftTokenMax;
    final draftPtr = malloc<Int32>(draftCapacity);
    final idxPtr = malloc<Int32>(draftCapacity + 1);
    final acceptedPtr = malloc<Int32>(draftCapacity + 1);

    int currentPos = startPos;
    int? pendingSampledToken;
    final accumulatedBytes = <int>[];
    final evalStopwatch = Stopwatch()..start();
    var sampleMicros = 0;
    var evalMicros = 0;
    var draftMicros = 0;
    var verifyMicros = 0;
    var generatedTokens = 0;
    var speculativeDraftTokens = 0;
    var speculativeAcceptedDraftTokens = 0;
    var speculativeDraftAttempts = 0;
    var speculativeVerifyTokens = 0;
    var speculativeReplayTokens = 0;
    var shouldStop = false;
    try {
      while (!shouldStop && generatedTokens < params.maxTokens) {
        if (cancelToken.value == 1) break;
        if (currentPos >= nCtx) break;

        int selectedToken;
        if (pendingSampledToken != null) {
          selectedToken = pendingSampledToken;
          pendingSampledToken = null;
        } else {
          final sampleTick = Stopwatch()..start();
          selectedToken = llama_sampler_sample(sampler, ctx.pointer, -1);
          sampleTick.stop();
          sampleMicros += sampleTick.elapsedMicroseconds;
          // Never pass an invalid sampled token into get_rows / token_to_piece.
          // This applies only to sampled text tokens, not multimodal embeddings.
          validateSampledToken(selectedToken, llama_vocab_n_tokens(vocab));
          if (llama_vocab_is_eog(vocab, selectedToken)) break;

          final pieceTick = Stopwatch()..start();
          final n = llama_token_to_piece(
            vocab,
            selectedToken,
            pieceBuf.cast(),
            256,
            0,
            preservedTokenIds.contains(selectedToken),
          );
          pieceTick.stop();
          sampleMicros += pieceTick.elapsedMicroseconds;
          generatedTokens++;

          if (n > 0) {
            final bytes = pieceBuf.asTypedList(n).toList();
            yield bytes;
            if (stopSequences.isNotEmpty) {
              accumulatedBytes.addAll(bytes);
              if (accumulatedBytes.length > 64) {
                accumulatedBytes.removeRange(0, accumulatedBytes.length - 64);
              }
              final text = utf8.decode(accumulatedBytes, allowMalformed: true);
              if (stopSequences.any((s) => text.endsWith(s))) {
                shouldStop = true;
              }
            }
          }

          if (shouldStop) {
            break;
          }
        }

        final remainingToGenerate = params.maxTokens - generatedTokens;
        final batchCapacity = math.max(1, llama_n_batch(ctx.pointer));
        final rollbackCapacity = llama_n_rs_seq(ctx.pointer);
        final contextDraftCapacity = rollbackCapacity > 0
            ? math.min(nCtx - currentPos - 2, rollbackCapacity)
            : nCtx - currentPos - 2;
        final draftLimit = remainingToGenerate <= 1
            ? 0
            : math.min(
                mtpConfig.draftTokenMax,
                math.min(
                  math.min(remainingToGenerate - 1, contextDraftCapacity),
                  batchCapacity - 1,
                ),
              );

        var draftCount = 0;
        if (draftLimit > 0) {
          speculativeDraftAttempts++;
          final draftTick = Stopwatch()..start();
          draftCount = mtpApi.draft(
            mtpSession,
            0,
            currentPos,
            selectedToken,
            tokensPtr,
            currentPos,
            draftLimit,
            draftPtr,
            draftLimit,
          );
          draftTick.stop();
          draftMicros += draftTick.elapsedMicroseconds;
          if (draftCount < 0) {
            throw Exception("llama.cpp MTP draft failed");
          }
          speculativeDraftTokens += draftCount;
        }

        if (draftCount <= 0) {
          batch.n_tokens = 1;
          batch.token[0] = selectedToken;
          batch.pos[0] = currentPos;
          batch.n_seq_id[0] = 1;
          batch.seq_id[0][0] = 0;
          batch.logits[0] = 1;

          final evalTick = Stopwatch()..start();
          final decodeStatus = llama_decode(ctx.pointer, batch);
          if (decodeStatus == 0 && !mtpApi.processBatch(mtpSession, batch)) {
            throw Exception("MTP decode processing failed");
          }
          evalTick.stop();
          evalMicros += evalTick.elapsedMicroseconds;
          if (decodeStatus != 0) break;

          tokensPtr[currentPos] = selectedToken;
          currentPos++;
          continue;
        }

        final draftContext = mtpApi.getDraftContext(mtpSession);
        final draftMemory = draftContext == nullptr
            ? nullptr
            : llama_get_memory(draftContext);
        if (draftMemory == nullptr ||
            !llama_memory_seq_rm(draftMemory, 0, currentPos, -1)) {
          throw UnsupportedError(
            'llama.cpp MTP draft rollback failed for this context.',
          );
        }

        final batchTokens = draftCount + 1;
        batch.n_tokens = batchTokens;
        batch.token[0] = selectedToken;
        batch.pos[0] = currentPos;
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = 1;
        for (int i = 0; i < draftCount; i++) {
          final batchIndex = i + 1;
          batch.token[batchIndex] = draftPtr[i];
          batch.pos[batchIndex] = currentPos + batchIndex;
          batch.n_seq_id[batchIndex] = 1;
          batch.seq_id[batchIndex][0] = 0;
          batch.logits[batchIndex] = 1;
        }

        final evalTick = Stopwatch()..start();
        final decodeStatus = llama_decode(ctx.pointer, batch);
        if (decodeStatus == 0 && !mtpApi.processBatch(mtpSession, batch)) {
          throw Exception("MTP decode processing failed");
        }
        evalTick.stop();
        evalMicros += evalTick.elapsedMicroseconds;
        if (decodeStatus != 0) break;
        speculativeVerifyTokens += batchTokens;

        for (int i = 0; i < batchTokens; i++) {
          idxPtr[i] = i;
        }

        final verifyTick = Stopwatch()..start();
        final acceptedCount = mtpApi.sampleAndAcceptN(
          sampler,
          ctx.pointer,
          idxPtr,
          batchTokens,
          draftPtr,
          draftCount,
          acceptedPtr,
          batchTokens,
        );
        verifyTick.stop();
        verifyMicros += verifyTick.elapsedMicroseconds;
        if (acceptedCount <= 0) {
          throw Exception("llama.cpp MTP draft verification failed");
        }

        final acceptedDraftCount = acceptedCount - 1;
        speculativeAcceptedDraftTokens += acceptedDraftCount;
        mtpApi.accept(mtpSession, 0, acceptedDraftCount);

        final keepUntil = currentPos + 1 + acceptedDraftCount;
        final targetMemory = llama_get_memory(ctx.pointer);
        if (targetMemory == nullptr ||
            !llama_memory_seq_rm(targetMemory, 0, keepUntil, -1) ||
            !llama_memory_seq_rm(draftMemory, 0, keepUntil, -1)) {
          throw UnsupportedError(
            'llama.cpp MTP target rollback failed for this context.',
          );
        }

        tokensPtr[currentPos] = selectedToken;
        for (int i = 0; i < acceptedDraftCount; i++) {
          tokensPtr[currentPos + 1 + i] = acceptedPtr[i];
        }
        currentPos = keepUntil;

        for (int i = 0; i < acceptedCount; i++) {
          final token = acceptedPtr[i];
          if (llama_vocab_is_eog(vocab, token)) {
            shouldStop = true;
            break;
          }

          final pieceTick = Stopwatch()..start();
          final n = llama_token_to_piece(
            vocab,
            token,
            pieceBuf.cast(),
            256,
            0,
            preservedTokenIds.contains(token),
          );
          pieceTick.stop();
          sampleMicros += pieceTick.elapsedMicroseconds;
          generatedTokens++;

          if (n > 0) {
            final bytes = pieceBuf.asTypedList(n).toList();
            yield bytes;
            if (stopSequences.isNotEmpty) {
              accumulatedBytes.addAll(bytes);
              if (accumulatedBytes.length > 64) {
                accumulatedBytes.removeRange(0, accumulatedBytes.length - 64);
              }
              final text = utf8.decode(accumulatedBytes, allowMalformed: true);
              if (stopSequences.any((s) => text.endsWith(s))) {
                shouldStop = true;
              }
            }
          }

          if (shouldStop || generatedTokens >= params.maxTokens) {
            break;
          }
        }

        if (!shouldStop && generatedTokens < params.maxTokens) {
          pendingSampledToken = acceptedPtr[acceptedCount - 1];
        }
      }
    } finally {
      malloc.free(draftPtr);
      malloc.free(idxPtr);
      malloc.free(acceptedPtr);
      evalStopwatch.stop();
      ctx.lastPerfEvalMs = evalMicros / 1000.0;
      ctx.lastPerfSampleMs = sampleMicros / 1000.0;
      ctx.lastPerfDecodeMs = evalMicros / 1000.0;
      ctx.lastPerfSpeculativeDraftMs = draftMicros / 1000.0;
      ctx.lastPerfSpeculativeVerifyMs = verifyMicros / 1000.0;
      ctx.lastPerfEvalTokens = generatedTokens;
      ctx.lastPerfSampleCount = generatedTokens;
      ctx.lastPerfSpeculativeDraftTokens = speculativeDraftTokens;
      ctx.lastPerfSpeculativeAcceptedDraftTokens =
          speculativeAcceptedDraftTokens;
      ctx.lastPerfSpeculativeDraftAttempts = speculativeDraftAttempts;
      ctx.lastPerfSpeculativeVerifyTokens = speculativeVerifyTokens;
      ctx.lastPerfSpeculativeReplayTokens = speculativeReplayTokens;
      ctx.lastPerfSpeculativeRan = true;
    }
  }

  // Legacy ngram-simple loop retained while older wrapper symbols remain
  // supported.
  // ignore: unused_element
  Stream<List<int>> _runNgramInferenceLoop(
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    Pointer<llama_sampler> sampler,
    GenerationParams params,
    _LlamaCppNgramSimpleConfig ngramConfig,
    int startPos,
    int nCtx,
    int cancelTokenAddress,
    Pointer<Uint8> pieceBuf,
    Set<int> preservedTokenIds,
    List<String> stopSequences,
    Pointer<llama_dart_ngram> ngramSession,
    _NgramApi ngramApi,
    Pointer<Int32> tokensPtr,
  ) async* {
    final cancelToken = Pointer<Int8>.fromAddress(cancelTokenAddress);
    final draftCapacity = ngramConfig.draftTokenMax;
    final draftPtr = malloc<Int32>(draftCapacity);
    final idxPtr = malloc<Int32>(draftCapacity + 1);
    final acceptedPtr = malloc<Int32>(draftCapacity + 1);

    int currentPos = startPos;
    int? pendingSampledToken;
    final accumulatedBytes = <int>[];
    final evalStopwatch = Stopwatch()..start();
    var sampleMicros = 0;
    var evalMicros = 0;
    var draftMicros = 0;
    var verifyMicros = 0;
    var generatedTokens = 0;
    var speculativeDraftTokens = 0;
    var speculativeAcceptedDraftTokens = 0;
    var speculativeDraftAttempts = 0;
    var speculativeVerifyTokens = 0;
    var speculativeReplayTokens = 0;
    var shouldStop = false;

    try {
      while (!shouldStop && generatedTokens < params.maxTokens) {
        if (cancelToken.value == 1) break;
        if (currentPos >= nCtx) break;

        int selectedToken;
        if (pendingSampledToken != null) {
          selectedToken = pendingSampledToken;
          pendingSampledToken = null;
        } else {
          final sampleTick = Stopwatch()..start();
          selectedToken = llama_sampler_sample(sampler, ctx.pointer, -1);
          sampleTick.stop();
          sampleMicros += sampleTick.elapsedMicroseconds;
          // Never pass an invalid sampled token into get_rows / token_to_piece.
          // This applies only to sampled text tokens, not multimodal embeddings.
          validateSampledToken(selectedToken, llama_vocab_n_tokens(vocab));
          if (llama_vocab_is_eog(vocab, selectedToken)) break;

          final pieceTick = Stopwatch()..start();
          final n = llama_token_to_piece(
            vocab,
            selectedToken,
            pieceBuf.cast(),
            256,
            0,
            preservedTokenIds.contains(selectedToken),
          );
          pieceTick.stop();
          sampleMicros += pieceTick.elapsedMicroseconds;
          generatedTokens++;

          if (n > 0) {
            final bytes = pieceBuf.asTypedList(n).toList();
            yield bytes;
            if (stopSequences.isNotEmpty) {
              accumulatedBytes.addAll(bytes);
              if (accumulatedBytes.length > 64) {
                accumulatedBytes.removeRange(0, accumulatedBytes.length - 64);
              }
              final text = utf8.decode(accumulatedBytes, allowMalformed: true);
              if (stopSequences.any((s) => text.endsWith(s))) {
                shouldStop = true;
              }
            }
          }

          if (shouldStop) {
            break;
          }
        }

        final remainingToGenerate = params.maxTokens - generatedTokens;
        final batchCapacity = math.max(1, llama_n_batch(ctx.pointer));
        final rollbackCapacity = llama_n_rs_seq(ctx.pointer);
        final contextDraftCapacity = rollbackCapacity > 0
            ? math.min(nCtx - currentPos - 2, rollbackCapacity)
            : nCtx - currentPos - 2;
        final draftLimit = remainingToGenerate <= 1
            ? 0
            : math.min(
                ngramConfig.draftTokenMax,
                math.min(
                  math.min(remainingToGenerate - 1, contextDraftCapacity),
                  batchCapacity - 1,
                ),
              );

        var draftCount = 0;
        if (draftLimit > 0) {
          speculativeDraftAttempts++;
          final draftTick = Stopwatch()..start();
          draftCount = ngramApi.draft(
            ngramSession,
            0,
            currentPos,
            selectedToken,
            tokensPtr,
            currentPos,
            draftLimit,
            draftPtr,
            draftLimit,
          );
          draftTick.stop();
          draftMicros += draftTick.elapsedMicroseconds;
          if (draftCount < 0) {
            throw Exception("llama.cpp ngram-simple draft failed");
          }
          speculativeDraftTokens += draftCount;
        }

        if (draftCount <= 0) {
          batch.n_tokens = 1;
          batch.token[0] = selectedToken;
          batch.pos[0] = currentPos;
          batch.n_seq_id[0] = 1;
          batch.seq_id[0][0] = 0;
          batch.logits[0] = 1;

          final evalTick = Stopwatch()..start();
          final decodeStatus = llama_decode(ctx.pointer, batch);
          if (decodeStatus == 0 &&
              !ngramApi.processBatch(ngramSession, batch)) {
            throw Exception("ngram-simple decode processing failed");
          }
          evalTick.stop();
          evalMicros += evalTick.elapsedMicroseconds;
          if (decodeStatus != 0) break;

          tokensPtr[currentPos] = selectedToken;
          currentPos++;
          continue;
        }

        final batchTokens = draftCount + 1;
        Pointer<Uint8> seqCheckpoint = nullptr;
        var seqCheckpointSize = 0;
        try {
          llama_synchronize(ctx.pointer);
          seqCheckpointSize = llama_state_seq_get_size_ext(
            ctx.pointer,
            0,
            LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY,
          );
          if (seqCheckpointSize > 0) {
            seqCheckpoint = malloc<Uint8>(seqCheckpointSize);
            final written = llama_state_seq_get_data_ext(
              ctx.pointer,
              seqCheckpoint,
              seqCheckpointSize,
              0,
              LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY,
            );
            if (written != seqCheckpointSize) {
              throw Exception(
                'ngram-simple checkpoint capture failed '
                '(expected $seqCheckpointSize bytes, got $written)',
              );
            }
          }

          batch.n_tokens = batchTokens;
          batch.token[0] = selectedToken;
          batch.pos[0] = currentPos;
          batch.n_seq_id[0] = 1;
          batch.seq_id[0][0] = 0;
          batch.logits[0] = 1;
          for (int i = 0; i < draftCount; i++) {
            final batchIndex = i + 1;
            batch.token[batchIndex] = draftPtr[i];
            batch.pos[batchIndex] = currentPos + batchIndex;
            batch.n_seq_id[batchIndex] = 1;
            batch.seq_id[batchIndex][0] = 0;
            batch.logits[batchIndex] = 1;
          }

          final evalTick = Stopwatch()..start();
          final decodeStatus = llama_decode(ctx.pointer, batch);
          if (decodeStatus == 0 &&
              !ngramApi.processBatch(ngramSession, batch)) {
            throw Exception("ngram-simple decode processing failed");
          }
          if (decodeStatus == 0) {
            llama_synchronize(ctx.pointer);
          }
          evalTick.stop();
          evalMicros += evalTick.elapsedMicroseconds;
          if (decodeStatus != 0) break;
          speculativeVerifyTokens += batchTokens;

          for (int i = 0; i < batchTokens; i++) {
            idxPtr[i] = i;
          }

          final verifyTick = Stopwatch()..start();
          final acceptedCount = ngramApi.sampleAndAcceptN(
            sampler,
            ctx.pointer,
            idxPtr,
            batchTokens,
            draftPtr,
            draftCount,
            acceptedPtr,
            batchTokens,
          );
          verifyTick.stop();
          verifyMicros += verifyTick.elapsedMicroseconds;
          if (acceptedCount <= 0) {
            throw Exception("llama.cpp ngram-simple draft verification failed");
          }

          final acceptedDraftCount = acceptedCount - 1;
          final rejectedTailCount = batchTokens - acceptedCount;
          final keepUntil = currentPos + 1 + acceptedDraftCount;
          var targetTailReconciled = false;
          if (rejectedTailCount > 0) {
            final targetMemory = llama_get_memory(ctx.pointer);
            final trimmedRejectedTail =
                targetMemory != nullptr &&
                llama_memory_seq_rm(targetMemory, 0, keepUntil, -1);
            if (trimmedRejectedTail) {
              targetTailReconciled = true;
            } else {
              if (seqCheckpoint == nullptr) {
                throw UnsupportedError(
                  'llama.cpp ngram-simple checkpoint rollback is unavailable '
                  'for this context.',
                );
              }

              final restored = llama_state_seq_set_data_ext(
                ctx.pointer,
                seqCheckpoint,
                seqCheckpointSize,
                0,
                LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY,
              );
              if (restored != seqCheckpointSize) {
                throw Exception(
                  'ngram-simple checkpoint restore failed '
                  '(expected $seqCheckpointSize bytes, got $restored)',
                );
              }

              final targetMemory = llama_get_memory(ctx.pointer);
              if (targetMemory == nullptr ||
                  !llama_memory_seq_rm(targetMemory, 0, currentPos, -1)) {
                throw UnsupportedError(
                  'llama.cpp ngram-simple checkpoint rollback failed for this '
                  'context.',
                );
              }

              final replayTokens = 1 + acceptedDraftCount;
              batch.n_tokens = replayTokens;
              batch.token[0] = selectedToken;
              batch.pos[0] = currentPos;
              batch.n_seq_id[0] = 1;
              batch.seq_id[0][0] = 0;
              batch.logits[0] = 0;
              for (int i = 0; i < acceptedDraftCount; i++) {
                final batchIndex = i + 1;
                batch.token[batchIndex] = acceptedPtr[i];
                batch.pos[batchIndex] = currentPos + batchIndex;
                batch.n_seq_id[batchIndex] = 1;
                batch.seq_id[batchIndex][0] = 0;
                batch.logits[batchIndex] = 0;
              }

              final replayTick = Stopwatch()..start();
              final replayStatus = llama_decode(ctx.pointer, batch);
              if (replayStatus == 0 &&
                  !ngramApi.processBatch(ngramSession, batch)) {
                throw Exception("ngram-simple replay processing failed");
              }
              if (replayStatus == 0) {
                llama_synchronize(ctx.pointer);
              }
              replayTick.stop();
              evalMicros += replayTick.elapsedMicroseconds;
              if (replayStatus != 0) {
                throw Exception("ngram-simple replay decode failed");
              }
              speculativeReplayTokens += replayTokens;
              targetTailReconciled = true;
            }
          }
          speculativeAcceptedDraftTokens += acceptedDraftCount;
          ngramApi.accept(ngramSession, 0, acceptedDraftCount);

          final targetMemory = llama_get_memory(ctx.pointer);
          if (!targetTailReconciled &&
              (targetMemory == nullptr ||
                  !llama_memory_seq_rm(targetMemory, 0, keepUntil, -1))) {
            throw UnsupportedError(
              'llama.cpp ngram-simple target rollback failed for this context. '
              'Set ModelParams.speculativeRollbackTokenMax >= ngramSizeM if '
              'this model/backend uses bounded rollback snapshots.',
            );
          }

          tokensPtr[currentPos] = selectedToken;
          for (int i = 0; i < acceptedDraftCount; i++) {
            tokensPtr[currentPos + 1 + i] = acceptedPtr[i];
          }
          currentPos = keepUntil;

          for (int i = 0; i < acceptedCount; i++) {
            final token = acceptedPtr[i];
            if (llama_vocab_is_eog(vocab, token)) {
              shouldStop = true;
              break;
            }

            final pieceTick = Stopwatch()..start();
            final n = llama_token_to_piece(
              vocab,
              token,
              pieceBuf.cast(),
              256,
              0,
              preservedTokenIds.contains(token),
            );
            pieceTick.stop();
            sampleMicros += pieceTick.elapsedMicroseconds;
            generatedTokens++;

            if (n > 0) {
              final bytes = pieceBuf.asTypedList(n).toList();
              yield bytes;
              if (stopSequences.isNotEmpty) {
                accumulatedBytes.addAll(bytes);
                if (accumulatedBytes.length > 64) {
                  accumulatedBytes.removeRange(0, accumulatedBytes.length - 64);
                }
                final text = utf8.decode(
                  accumulatedBytes,
                  allowMalformed: true,
                );
                if (stopSequences.any((s) => text.endsWith(s))) {
                  shouldStop = true;
                }
              }
            }

            if (shouldStop || generatedTokens >= params.maxTokens) {
              break;
            }
          }

          if (!shouldStop && generatedTokens < params.maxTokens) {
            pendingSampledToken = acceptedPtr[acceptedCount - 1];
          }
        } finally {
          if (seqCheckpoint != nullptr) {
            malloc.free(seqCheckpoint);
          }
        }
      }
    } finally {
      malloc.free(draftPtr);
      malloc.free(idxPtr);
      malloc.free(acceptedPtr);
      evalStopwatch.stop();
      ctx.lastPerfEvalMs = evalMicros / 1000.0;
      ctx.lastPerfSampleMs = sampleMicros / 1000.0;
      ctx.lastPerfDecodeMs = evalMicros / 1000.0;
      ctx.lastPerfSpeculativeDraftMs = draftMicros / 1000.0;
      ctx.lastPerfSpeculativeVerifyMs = verifyMicros / 1000.0;
      ctx.lastPerfEvalTokens = generatedTokens;
      ctx.lastPerfSampleCount = generatedTokens;
      ctx.lastPerfSpeculativeDraftTokens = speculativeDraftTokens;
      ctx.lastPerfSpeculativeAcceptedDraftTokens =
          speculativeAcceptedDraftTokens;
      ctx.lastPerfSpeculativeDraftAttempts = speculativeDraftAttempts;
      ctx.lastPerfSpeculativeVerifyTokens = speculativeVerifyTokens;
      ctx.lastPerfSpeculativeReplayTokens = speculativeReplayTokens;
      ctx.lastPerfSpeculativeRan = true;
    }
  }

  _LazyGrammarConfig? _buildLazyGrammarConfig(GenerationParams params) {
    final triggerPatterns = <String>[];
    final triggerTokens = <int>[];

    for (final trigger in params.grammarTriggers) {
      switch (trigger.type) {
        case 0:
          triggerPatterns.add(_regexEscape(trigger.value));
          break;
        case 1:
          final token = trigger.token ?? int.tryParse(trigger.value);
          if (token != null) {
            triggerTokens.add(token);
          }
          break;
        case 2:
          triggerPatterns.add(trigger.value);
          break;
        case 3:
          final pattern = trigger.value;
          final anchored = pattern.isEmpty
              ? r'^$'
              : "${pattern.startsWith('^') ? '' : '^'}$pattern${pattern.endsWith(r'$') ? '' : r'$'}";
          triggerPatterns.add(anchored);
          break;
      }
    }

    if (triggerPatterns.isEmpty && triggerTokens.isEmpty) {
      return null;
    }

    final allocatedPatternPtrs = triggerPatterns
        .map((pattern) => pattern.toNativeUtf8())
        .toList(growable: false);

    final triggerPatternsPtr = allocatedPatternPtrs.isEmpty
        ? nullptr
        : malloc<Pointer<Char>>(allocatedPatternPtrs.length);

    if (triggerPatternsPtr != nullptr) {
      for (var i = 0; i < allocatedPatternPtrs.length; i++) {
        triggerPatternsPtr[i] = allocatedPatternPtrs[i].cast();
      }
    }

    final triggerTokensPtr = triggerTokens.isEmpty
        ? nullptr
        : malloc<llama_token>(triggerTokens.length);

    if (triggerTokensPtr != nullptr) {
      for (var i = 0; i < triggerTokens.length; i++) {
        triggerTokensPtr[i] = triggerTokens[i];
      }
    }

    return _LazyGrammarConfig(
      triggerPatterns: triggerPatternsPtr,
      numTriggerPatterns: allocatedPatternPtrs.length,
      triggerTokens: triggerTokensPtr,
      numTriggerTokens: triggerTokens.length,
      allocatedPatternPointers: allocatedPatternPtrs,
    );
  }

  Set<int> _resolvePreservedTokenIds(
    Pointer<llama_vocab> vocab,
    List<String> preservedTokens,
  ) {
    if (preservedTokens.isEmpty) {
      return const <int>{};
    }

    final ids = <int>{};
    for (final tokenText in preservedTokens) {
      if (tokenText.isEmpty) {
        continue;
      }

      final textPtr = tokenText.toNativeUtf8();
      try {
        final required = -llama_tokenize(
          vocab,
          textPtr.cast(),
          textPtr.length,
          nullptr,
          0,
          false,
          true,
        );

        if (required <= 0) {
          continue;
        }

        final tokenIds = malloc<Int32>(required);
        try {
          final actual = llama_tokenize(
            vocab,
            textPtr.cast(),
            textPtr.length,
            tokenIds,
            required,
            false,
            true,
          );

          if (actual > 0) {
            for (int i = 0; i < actual; i++) {
              ids.add(tokenIds[i]);
            }
          }
        } finally {
          malloc.free(tokenIds);
        }
      } finally {
        malloc.free(textPtr);
      }
    }

    return ids;
  }

  List<String> _effectiveStopSequences(
    List<String> stopSequences,
    List<String> preservedTokens,
  ) {
    if (stopSequences.isEmpty || preservedTokens.isEmpty) {
      return stopSequences;
    }

    final preservedSet = preservedTokens.toSet();
    return stopSequences
        .where((sequence) => !preservedSet.contains(sequence))
        .toList(growable: false);
  }

  String _regexEscape(String input) {
    final escaped = StringBuffer();
    const regexMeta = r'\^$.*+?()[]{}|';
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (regexMeta.contains(char)) {
        escaped.write('\\');
      }
      escaped.write(char);
    }
    return escaped.toString();
  }

  /// Tokenizes the given [text].
  List<int> tokenize(int modelHandle, String text, bool addSpecial) {
    final model = _models[modelHandle];
    if (model == null) return [];
    final vocab = llama_model_get_vocab(model.pointer);
    final textPtr = text.toNativeUtf8();
    final shouldAddSpecial =
        addSpecial && !_promptStartsWithBosToken(vocab, text);
    final n = -llama_tokenize(
      vocab,
      textPtr.cast(),
      textPtr.length,
      nullptr,
      0,
      shouldAddSpecial,
      true,
    );
    final tokensPtr = malloc<Int32>(n);
    final actual = llama_tokenize(
      vocab,
      textPtr.cast(),
      textPtr.length,
      tokensPtr,
      n,
      shouldAddSpecial,
      true,
    );
    final result = List.generate(actual, (i) => tokensPtr[i]);
    malloc.free(textPtr);
    malloc.free(tokensPtr);
    return result;
  }

  /// Detokenizes the given [tokens].
  String detokenize(int modelHandle, List<int> tokens, bool special) {
    final model = _models[modelHandle];
    if (model == null) return "";
    final vocab = llama_model_get_vocab(model.pointer);
    final buffer = malloc<Int8>(256);
    final bytes = <int>[];
    for (final t in tokens) {
      final n = llama_token_to_piece(vocab, t, buffer.cast(), 256, 0, special);
      if (n > 0) bytes.addAll(buffer.asTypedList(n));
    }
    malloc.free(buffer);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Persists the KV-cache state of [contextHandle] to [path] together
  /// with the producing token sequence so a later [stateLoadFile] can
  /// resume inference without paying the prompt-eval cost again.
  ///
  /// Wraps `llama_state_save_file`. Returns true on success.
  bool stateSaveFile(int contextHandle, String path, List<int> tokens) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw StateError('Unknown context handle: $contextHandle');
    }
    if (_generatingContexts.containsKey(contextHandle)) {
      throw StateError(
        'Cannot save state while generation is active on context $contextHandle',
      );
    }
    llama_synchronize(ctx.pointer);
    final pathPtr = path.toNativeUtf8();
    final tokensPtr = tokens.isEmpty ? nullptr : malloc<Int32>(tokens.length);
    try {
      for (int i = 0; i < tokens.length; i++) {
        tokensPtr[i] = tokens[i];
      }
      return llama_state_save_file(
        ctx.pointer,
        pathPtr.cast(),
        tokensPtr,
        tokens.length,
      );
    } finally {
      malloc.free(pathPtr);
      if (tokensPtr != nullptr) malloc.free(tokensPtr);
    }
  }

  /// Restores a previously saved KV-cache state into [contextHandle].
  /// [tokenCapacity] caps the number of tokens read back.
  ///
  /// Wraps `llama_state_load_file`. Throws on failure (corrupt file,
  /// schema mismatch, etc.).
  List<int> stateLoadFile(int contextHandle, String path, int tokenCapacity) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw StateError('Unknown context handle: $contextHandle');
    }
    if (_generatingContexts.containsKey(contextHandle)) {
      throw StateError(
        'Cannot load state while generation is active on context $contextHandle',
      );
    }
    if (tokenCapacity <= 0) {
      throw ArgumentError.value(
        tokenCapacity,
        'tokenCapacity',
        'must be positive',
      );
    }
    final contextCapacity = llama_n_ctx(ctx.pointer);
    if (tokenCapacity > contextCapacity) {
      throw ArgumentError.value(
        tokenCapacity,
        'tokenCapacity',
        'must not exceed context size ($contextCapacity)',
      );
    }
    llama_synchronize(ctx.pointer);
    final pathPtr = path.toNativeUtf8();
    final tokensPtr = malloc<Int32>(tokenCapacity);
    final countPtr = malloc<Size>();
    try {
      countPtr.value = 0;
      final ok = llama_state_load_file(
        ctx.pointer,
        pathPtr.cast(),
        tokensPtr,
        tokenCapacity,
        countPtr,
      );
      if (!ok) {
        throw StateError(
          'llama_state_load_file failed for "$path" '
          '(corrupt file, version mismatch, or capacity too small)',
        );
      }
      final actual = countPtr.value;
      if (actual > tokenCapacity) {
        throw StateError(
          'llama_state_load_file returned actual=$actual '
          'exceeding capacity=$tokenCapacity',
        );
      }
      final loaded = List<int>.generate(actual, (i) => tokensPtr[i]);
      ctx.cachedPromptTokens = loaded;
      ctx.kvFromStateLoad = true;
      return loaded;
    } finally {
      malloc.free(pathPtr);
      malloc.free(tokensPtr);
      malloc.free(countPtr);
    }
  }

  /// Returns metadata for the specified [modelHandle].
  Map<String, String> getMetadata(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) return {};
    final metadata = <String, String>{};
    final keyBuf = malloc<Int8>(1024);
    final valBuf = malloc<Int8>(1024 * 64);
    final n = llama_model_meta_count(model.pointer);
    for (int i = 0; i < n; i++) {
      llama_model_meta_key_by_index(model.pointer, i, keyBuf.cast(), 1024);
      llama_model_meta_val_str_by_index(
        model.pointer,
        i,
        valBuf.cast(),
        1024 * 64,
      );
      metadata[keyBuf.cast<Utf8>().toDartString()] = valBuf
          .cast<Utf8>()
          .toDartString();
    }
    malloc.free(keyBuf);
    malloc.free(valBuf);
    return metadata;
  }

  /// Returns model file type or quantization metadata for [modelHandle].
  ModelFileType? getModelFileType(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) return null;

    final ftype = raw_bindings.llama_model_ftype_raw(model.pointer);
    final namePtr = raw_bindings.llama_ftype_name_raw(ftype);
    if (namePtr == nullptr) return null;

    final name = namePtr.cast<Utf8>().toDartString();
    return ModelFileType(id: ftype, name: name);
  }

  /// Applies the configured or loaded model chat template to [messages].
  String applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) {
    if (!_models.containsKey(modelHandle)) {
      throw StateError('Invalid model handle for chat template: $modelHandle');
    }
    final metadata = getMetadata(modelHandle);
    final modelParamsTemplate = _nonEmptyTemplate(
      _modelLoadParams[modelHandle]?.chatTemplate,
    );
    final templateSource = customTemplate == null
        ? modelParamsTemplate ?? _modelChatTemplate(modelHandle)
        : null;
    final result = ChatTemplateEngine.render(
      templateSource: templateSource ?? metadata['tokenizer.chat_template'],
      messages: messages.map(_messageFromTemplateMap).toList(growable: false),
      metadata: metadata,
      addAssistant: addAssistant,
      customTemplate: customTemplate,
    );
    return result.prompt;
  }

  String? _nonEmptyTemplate(String? template) {
    if (template == null || template.isEmpty) {
      return null;
    }
    return template;
  }

  String? _modelChatTemplate(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) {
      return null;
    }
    final templatePtr = llama_model_chat_template(model.pointer, nullptr);
    if (templatePtr == nullptr) {
      return null;
    }
    final template = templatePtr.cast<Utf8>().toDartString();
    return template.isEmpty ? null : template;
  }

  LlamaChatMessage _messageFromTemplateMap(Map<String, dynamic> message) {
    final roleName = message['role']?.toString() ?? LlamaChatRole.user.name;
    final role = LlamaChatRole.values.byName(roleName);
    return LlamaChatMessage.fromText(
      role: role,
      text: _contentTextFromTemplateMap(message['content']),
    );
  }

  String _contentTextFromTemplateMap(Object? content) {
    if (content == null) {
      return '';
    }
    if (content is String) {
      return content;
    }
    if (content is Map) {
      if (_isUnsupportedTemplateContentPart(content)) {
        throw UnsupportedError(
          'LlamaCppBackend does not support multimodal chat-template content.',
        );
      }
      if (content['type']?.toString() == 'text' && content['text'] != null) {
        return content['text'].toString();
      }
      return content.toString();
    }
    if (content is Iterable) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map) {
          if (_isUnsupportedTemplateContentPart(part)) {
            throw UnsupportedError(
              'LlamaCppBackend does not support multimodal chat-template '
              'content.',
            );
          }
          final type = part['type']?.toString();
          if (type == 'text' && part['text'] != null) {
            buffer.write(part['text']);
            continue;
          }
        }
        buffer.write(part);
      }
      return buffer.toString();
    }
    return content.toString();
  }

  bool _isUnsupportedTemplateContentPart(Map<dynamic, dynamic> part) {
    final type = part['type']?.toString().toLowerCase();
    if (type == 'image' ||
        type == 'image_url' ||
        type == 'input_image' ||
        type == 'audio' ||
        type == 'input_audio' ||
        type == 'video' ||
        type == 'input_video') {
      return true;
    }
    return part.containsKey('image') ||
        part.containsKey('image_url') ||
        part.containsKey('input_audio') ||
        part.containsKey('audio') ||
        part.containsKey('video');
  }

  /// Handles LoRA adapter operations.
  void handleLora(int contextHandle, String? path, double? scale, String op) {
    final ctx = _contexts[contextHandle];
    final modelHandle = _contextToModel[contextHandle];
    if (ctx == null || modelHandle == null) return;

    final modelAdapters = _loraAdapters[modelHandle];
    final activeLoras = _activeLoras[contextHandle];
    if (modelAdapters == null || activeLoras == null) return;

    try {
      if (op == 'set') {
        if (path == null) {
          throw Exception('LoRA path is required for set operation');
        }
        if (scale == null) {
          throw Exception('LoRA scale is required for set operation');
        }

        var adapter = modelAdapters[path];
        if (adapter == null) {
          final pathPtr = path.toNativeUtf8();
          final adapterPtr = llama_adapter_lora_init(
            _models[modelHandle]!.pointer,
            pathPtr.cast(),
          );
          malloc.free(pathPtr);
          if (adapterPtr == nullptr) {
            throw Exception("Failed to load LoRA at $path");
          }
          adapter = _LlamaLoraWrapper(adapterPtr);
          modelAdapters[path] = adapter;
        }
        activeLoras[path] = scale;
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
        ctx.cachedPromptTokens = null;
      } else if (op == 'remove') {
        if (path == null) {
          throw Exception('LoRA path is required for remove operation');
        }
        activeLoras.remove(path);
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
        ctx.cachedPromptTokens = null;
      } else if (op == 'clear') {
        activeLoras.clear();
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
        ctx.cachedPromptTokens = null;
      } else {
        throw Exception('Unknown LoRA operation: $op');
      }
    } catch (e) {
      rethrow;
    }
  }

  void _applyActiveLoras(
    Pointer<llama_context> context,
    Map<String, _LlamaLoraWrapper> loadedAdapters,
    Map<String, double> activeLoras,
  ) {
    if (activeLoras.isEmpty) {
      final result = llama_set_adapters_lora(context, nullptr, 0, nullptr);
      if (result != 0) {
        throw Exception('Failed to clear LoRA adapters (code: $result)');
      }
      return;
    }

    final activeEntries = activeLoras.entries.toList(growable: false);
    final adapterPointers = malloc<Pointer<llama_adapter_lora>>(
      activeEntries.length,
    );
    final scalesPointer = malloc<Float>(activeEntries.length);

    try {
      for (var i = 0; i < activeEntries.length; i++) {
        final entry = activeEntries[i];
        final adapter = loadedAdapters[entry.key];
        if (adapter == null) {
          throw Exception(
            'LoRA adapter not loaded for active path: ${entry.key}',
          );
        }
        adapterPointers[i] = adapter.pointer;
        scalesPointer[i] = entry.value;
      }

      final result = llama_set_adapters_lora(
        context,
        adapterPointers,
        activeEntries.length,
        scalesPointer,
      );
      if (result != 0) {
        throw Exception('Failed to apply LoRA adapters (code: $result)');
      }
    } finally {
      malloc.free(adapterPointers);
      malloc.free(scalesPointer);
    }
  }

  /// Returns the currently active backend name.
  String getActiveBackendName() {
    return _activeBackendName;
  }

  /// Returns resolved GPU layers for the active model load.
  int? getResolvedGpuLayers() {
    if (_models.isEmpty) {
      return null;
    }
    return _activeResolvedGpuLayers;
  }

  /// Returns backend names available for selection.
  ///
  /// This path avoids optional GPU backend initialization and is intended for
  /// settings/selector UIs.
  List<String> getAvailableBackendInfo() {
    final available = <String>{};
    final backendModuleDirectory = _backendModuleDirectory;

    if (backendModuleDirectory != null) {
      const backendCandidates = <String>[
        'cpu',
        'vulkan',
        'opencl',
        'metal',
        'cuda',
        'hip',
        'blas',
      ];

      for (final backend in backendCandidates) {
        if (_isBackendModuleBundled(backend)) {
          available.add(_backendDisplayName(backend));
        }
      }
    }

    if (available.isEmpty) {
      available.addAll(getBackendInfo());
    }

    if (available.isEmpty) {
      available.add(_backendDisplayName('cpu'));
    }

    final ordered = available.toList(growable: false)
      ..sort((a, b) {
        final aOrder = _backendDisplaySortKey(a);
        final bOrder = _backendDisplaySortKey(b);
        if (aOrder != bOrder) {
          return aOrder.compareTo(bOrder);
        }
        return a.compareTo(b);
      });
    return ordered;
  }

  static int _backendDisplaySortKey(String backendName) {
    switch (backendName.toUpperCase()) {
      case 'CPU':
        return 0;
      case 'METAL':
        return 1;
      case 'VULKAN':
        return 2;
      case 'OPENCL':
        return 3;
      case 'HIP':
        return 4;
      case 'CUDA':
        return 5;
      case 'BLAS':
        return 6;
      default:
        return 99;
    }
  }

  /// Returns information about currently initialized backend devices.
  List<String> getBackendInfo() {
    final count = _ggmlBackendDevCount();
    final devices = <String>{};
    for (var i = 0; i < count; i++) {
      final dev = _ggmlBackendDevGet(i);
      if (dev == nullptr) continue;

      final devNamePtr = _ggmlBackendDevName(dev);
      if (devNamePtr == nullptr) continue;
      final devName = devNamePtr.cast<Utf8>().toDartString();

      String label = devName;
      final reg = _ggmlBackendDevBackendReg(dev);
      if (reg != nullptr) {
        final regNamePtr = _ggmlBackendRegName(reg);
        if (regNamePtr != nullptr) {
          final regName = regNamePtr.cast<Utf8>().toDartString();
          if (regName.toLowerCase() == devName.toLowerCase()) {
            label = regName;
          } else {
            label = '$regName ($devName)';
          }
        }
      }

      devices.add(label);
    }
    if (devices.isNotEmpty) {
      return devices.toList(growable: false);
    }

    // Fallback when device-enumeration symbols are unavailable: surface loaded
    // backend modules so UI can still present selectable backends.
    final moduleBackends =
        _loadedBackendModules
            .map(_backendDisplayName)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    return moduleBackends;
  }

  static String _backendDisplayName(String backend) {
    switch (backend.toLowerCase()) {
      case 'cpu':
        return 'CPU';
      case 'vulkan':
        return 'Vulkan';
      case 'opencl':
        return 'OpenCL';
      case 'metal':
        return 'Metal';
      case 'cuda':
        return 'CUDA';
      case 'hip':
        return 'HIP';
      case 'blas':
        return 'BLAS';
      default:
        return backend;
    }
  }

  /// Returns whether GPU offloading is supported.
  bool getGpuSupport() {
    return llama_supports_gpu_offload();
  }

  /// Disposes of all resources managed by the service.
  void dispose() {
    for (final c in _contexts.values) {
      c.dispose();
    }
    _contexts.clear();
    for (final m in _models.values) {
      m.dispose();
    }
    _models.clear();
    for (final m in _speculativeDraftModels.values) {
      m.dispose();
    }
    _speculativeDraftModels.clear();
    _modelToSpeculativeDraftModelKeys.clear();
    _modelBackendNames.clear();
    _modelResolvedGpuLayers.clear();
    _modelLoadParams.clear();
    _activeBackendName = _backendDisplayName('cpu');
    _activeResolvedGpuLayers = 0;
    for (final m in _mtmdContexts.values) {
      _mtmdFree(m);
    }
    _mtmdContexts.clear();
    _modelToMtmd.clear();
    _modelToMtmdUseGpu.clear();
    // llama_backend_free(); // DISABLED: Prevents race conditions with other isolates
  }

  /// Creates a multimodal context (projector) for the model.
  int createMultimodalContext(int modelHandle, String mmProjPath) {
    final model = _models[modelHandle];
    if (model == null) {
      throw Exception("Invalid model handle");
    }
    _applyConfiguredLogLevel();

    final mmProjPathPtr = mmProjPath.toNativeUtf8();
    Pointer<mtmd_context> mmCtx = nullptr;
    try {
      final ctxParams = _mtmdContextParamsDefault();
      ctxParams.use_gpu = _modelToMtmdUseGpu[modelHandle] ?? true;
      mmCtx = _mtmdInitFromFile(mmProjPathPtr.cast(), model.pointer, ctxParams);
    } finally {
      malloc.free(mmProjPathPtr);
    }

    if (mmCtx == nullptr) {
      throw Exception("Failed to load multimodal projector");
    }

    final handle = _getHandle();
    _mtmdContexts[handle] = mmCtx;
    _modelToMtmd[modelHandle] = handle;
    return handle;
  }

  /// Frees the multimodal context (projector).
  void freeMultimodalContext(int mmContextHandle) {
    final mmCtx = _mtmdContexts.remove(mmContextHandle);
    if (mmCtx != null) {
      _mtmdFree(mmCtx);
      _modelToMtmd.removeWhere((k, v) => v == mmContextHandle);
    }
  }

  Pointer<Char> _mtmdDefaultMarker() {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_default_marker();
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    return fallback?.defaultMarker() ?? nullptr;
  }

  mtmd_context_params _mtmdContextParamsDefault() {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_context_params_default();
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_context_params_default'));
    }
    return fallback.contextParamsDefault();
  }

  Pointer<mtmd_context> _mtmdInitFromFile(
    Pointer<Char> mmProjPath,
    Pointer<llama_model> model,
    mtmd_context_params ctxParams,
  ) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_init_from_file(mmProjPath, model, ctxParams);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_init_from_file'));
    }
    return fallback.initFromFile(mmProjPath, model, ctxParams);
  }

  void _mtmdFree(Pointer<mtmd_context> ctx) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        mtmd_free(ctx);
        return;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      return;
    }
    fallback.free(ctx);
  }

  Pointer<mtmd_input_chunks> _mtmdInputChunksInit() {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_input_chunks_init();
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_input_chunks_init'));
    }
    return fallback.inputChunksInit();
  }

  void _mtmdInputChunksFree(Pointer<mtmd_input_chunks> chunks) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        mtmd_input_chunks_free(chunks);
        return;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      return;
    }
    fallback.inputChunksFree(chunks);
  }

  Pointer<mtmd_bitmap> _mtmdHelperBitmapInitFromFile(
    Pointer<mtmd_context> ctx,
    Pointer<Char> pathPtr,
  ) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_helper_bitmap_init_from_file(ctx, pathPtr, false).bitmap;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(
        _mtmdUnavailableMessage('mtmd_helper_bitmap_init_from_file'),
      );
    }
    return fallback.helperBitmapInitFromFile(ctx, pathPtr, false).bitmap;
  }

  Pointer<mtmd_bitmap> _mtmdHelperBitmapInitFromBuf(
    Pointer<mtmd_context> ctx,
    Pointer<UnsignedChar> data,
    int size,
  ) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_helper_bitmap_init_from_buf(ctx, data, size, false).bitmap;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(
        _mtmdUnavailableMessage('mtmd_helper_bitmap_init_from_buf'),
      );
    }
    return fallback.helperBitmapInitFromBuf(ctx, data, size, false).bitmap;
  }

  Pointer<mtmd_bitmap> _mtmdBitmapInitFromAudio(int n, Pointer<Float> samples) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_bitmap_init_from_audio(n, samples);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_bitmap_init_from_audio'));
    }
    return fallback.bitmapInitFromAudio(n, samples);
  }

  void _mtmdBitmapFree(Pointer<mtmd_bitmap> bitmap) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        mtmd_bitmap_free(bitmap);
        return;
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      return;
    }
    fallback.bitmapFree(bitmap);
  }

  int _mtmdTokenize(
    Pointer<mtmd_context> ctx,
    Pointer<mtmd_input_chunks> output,
    Pointer<mtmd_input_text> text,
    Pointer<Pointer<mtmd_bitmap>> bitmaps,
    int nBitmaps,
  ) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_tokenize(ctx, output, text, bitmaps, nBitmaps);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_tokenize'));
    }
    return fallback.tokenize(ctx, output, text, bitmaps, nBitmaps);
  }

  int _mtmdHelperEvalChunks(
    Pointer<mtmd_context> ctx,
    Pointer<llama_context> lctx,
    Pointer<mtmd_input_chunks> chunks,
    int nPast,
    int seqId,
    int nBatch,
    bool logitsLast,
    Pointer<llama_pos> newNPast,
  ) {
    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_helper_eval_chunks(
          ctx,
          lctx,
          chunks,
          nPast,
          seqId,
          nBatch,
          logitsLast,
          newNPast,
        );
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }
    final fallback = _resolveMtmdFallbackApi();
    if (fallback == null) {
      throw Exception(_mtmdUnavailableMessage('mtmd_helper_eval_chunks'));
    }
    return fallback.helperEvalChunks(
      ctx,
      lctx,
      chunks,
      nPast,
      seqId,
      nBatch,
      logitsLast,
      newNPast,
    );
  }

  _MtmdApi? _resolveMtmdFallbackApi() {
    if (_mtmdFallbackLookupAttempted) {
      return _mtmdFallbackApi;
    }
    _mtmdFallbackLookupAttempted = true;

    final fileNameCandidates = _mtmdLibraryCandidateFileNames();
    final candidates = <String>{...fileNameCandidates};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory != null) {
      for (final fileName in fileNameCandidates) {
        candidates.add(path.join(backendModuleDirectory, fileName));
      }
    }

    DynamicLibrary? library;
    for (final candidate in candidates) {
      try {
        library = DynamicLibrary.open(candidate);
        break;
      } catch (_) {
        continue;
      }
    }
    if (library == null) {
      return null;
    }

    _mtmdFallbackApi = _MtmdApi.tryLoad(library);
    return _mtmdFallbackApi;
  }

  List<String> _mtmdLibraryCandidateFileNames() {
    final baseName = _mtmdLibraryFileName();
    final candidates = <String>{baseName};
    final backendModuleDirectory = _backendModuleDirectory;
    if (backendModuleDirectory == null) {
      return candidates.toList(growable: false);
    }

    final dynamicNames = _matchingLibraryNames(
      backendModuleDirectory,
      _mtmdLibraryPattern(),
    );
    candidates.addAll(dynamicNames);
    return candidates.toList(growable: false);
  }

  static String _mtmdLibraryFileName() {
    if (Platform.isWindows) {
      return 'mtmd.dll';
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libmtmd.dylib';
    }
    return 'libmtmd.so';
  }

  RegExp _mtmdLibraryPattern() {
    if (Platform.isWindows) {
      return RegExp(r'^mtmd(?:-[^.\\/]+)*\.dll$');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return RegExp(r'^libmtmd(?:-[^.\\/]+)*\.dylib$');
    }
    return RegExp(r'^libmtmd(?:-[^.\\/]+)*\.so$');
  }

  String _mtmdUnavailableMessage(String symbol) {
    return 'Multimodal support is unavailable in this native runtime bundle '
        '(missing `$symbol` in both primary and mtmd libraries).';
  }

  // --- Helper Getters ---

  /// Returns total and free VRAM (in bytes) of the first GPU-class ggml
  /// backend device. Backend-agnostic — works for Vulkan, CUDA, HIP,
  /// Metal, whichever the active backend(s) expose at runtime.
  ///
  /// Reads memory via `ggml_backend_dev_get_props` (the struct-filling
  /// API) first. The older `ggml_backend_dev_memory` is unreliable on
  /// the Vulkan backend in current llama.cpp — it can return all-zeros
  /// even when the GPU is fully free — so we use it only as a
  /// second-chance fallback per device, for backends that haven't moved
  /// their memory reporting to props yet.
  ///
  /// All ggml backend-device FFI calls are routed through registry
  /// fallback wrappers ([_ggmlBackendDevCount], [_ggmlBackendDevType],
  /// [_ggmlBackendDevGetProps], [_ggmlBackendDevMemory]) so the call
  /// lands on whichever runtime asset owns the device state on
  /// Windows split bundles. Returns `(0, 0)` only when no GPU-class
  /// device is reachable through either symbol path AND every
  /// reachable GPU device declines to report memory.
  ({int total, int free}) getVramInfo() {
    final count = _ggmlBackendDevCount();
    for (var i = 0; i < count; i++) {
      final dev = _ggmlBackendDevGet(i);
      if (dev == nullptr) continue;
      // Compare via raw int so a future llama.cpp adding a new
      // `ggml_backend_dev_type` variant doesn't crash here via the
      // high-level binding's `fromValue` ArgumentError — unknown
      // values just don't match any GPU-class check and we move on.
      final type = _ggmlBackendDevType(dev);
      if (type != ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value &&
          type != ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value &&
          type != ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value) {
        continue;
      }
      final propsPtr = calloc<ggml_backend_dev_props>();
      try {
        if (_ggmlBackendDevGetProps(dev, propsPtr)) {
          final props = propsPtr.ref;
          if (props.memory_total > 0) {
            return (total: props.memory_total, free: props.memory_free);
          }
        }
        // get_props unavailable or reported zero on this device —
        // fall back to the older dev_memory entry point.
        final freePtr = calloc<Size>();
        final totalPtr = calloc<Size>();
        try {
          if (_ggmlBackendDevMemory(dev, freePtr, totalPtr) &&
              totalPtr.value > 0) {
            return (total: totalPtr.value, free: freePtr.value);
          }
        } finally {
          calloc.free(freePtr);
          calloc.free(totalPtr);
        }
      } finally {
        calloc.free(propsPtr);
      }
    }
    return (total: 0, free: 0);
  }

  /// Enumerates GPU-class devices across registered backends.
  ///
  /// With an empty [probeBackends] only already-registered backends are
  /// inspected — no backend module is loaded, so an unsupported GPU runtime
  /// cannot crash the process during enumeration. Pass specific backends in
  /// [probeBackends] to opt into loading just those modules (guarded; CPU/auto
  /// are ignored) before enumerating. Walks the global device list
  /// (`ggml_backend_dev_count` / `ggml_backend_dev_get`) through the registry
  /// fallback wrappers so devices register on Windows split bundles, and reads
  /// each device's description/id/memory from `ggml_backend_dev_get_props`
  /// (with `ggml_backend_dev_memory` as a memory fallback). CPU devices are
  /// excluded. Returns an empty list when no GPU-class device is reachable.
  List<GpuDeviceInfo> listGpuDevices({
    List<GpuBackend> probeBackends = const [],
  }) {
    for (final backend in probeBackends) {
      if (backend == GpuBackend.auto || backend == GpuBackend.cpu) continue;
      _tryLoadBackendModuleIfBundled(backend.name);
    }

    final count = _ggmlBackendDevCount();
    final result = <GpuDeviceInfo>[];
    final perBackendOrdinal = <GpuBackend, int>{};
    for (var i = 0; i < count; i++) {
      final dev = _ggmlBackendDevGet(i);
      if (dev == nullptr) continue;

      final propsPtr = calloc<ggml_backend_dev_props>();
      try {
        final hasProps = _ggmlBackendDevGetProps(dev, propsPtr);
        final props = hasProps ? propsPtr.ref : null;

        // Prefer the standalone type probe; when its symbol is unavailable
        // (returns -1 -> unknown) fall back to the type carried in props, so a
        // device still enumerates on runtimes missing the standalone symbol.
        // Raw-int compares keep a future llama.cpp enum variant from crashing
        // the high-level binding's fromValue.
        var type = _mapGpuDeviceType(_ggmlBackendDevType(dev));
        if (type == GpuDeviceType.unknown && props != null) {
          type = _mapGpuDeviceType(props.typeAsInt);
        }
        if (type == GpuDeviceType.cpu || type == GpuDeviceType.unknown) {
          continue;
        }

        final backend = _gpuBackendForDevice(dev);
        final mainGpu = perBackendOrdinal[backend] ?? 0;
        perBackendOrdinal[backend] = mainGpu + 1;

        var name = '';
        var description = '';
        var deviceId = '';
        var free = 0;
        var total = 0;
        if (props != null) {
          name = _utf8OrEmpty(props.name);
          description = _utf8OrEmpty(props.description);
          deviceId = _utf8OrEmpty(props.device_id);
          free = props.memory_free;
          total = props.memory_total;
        }
        if (name.isEmpty) name = _utf8OrEmpty(_ggmlBackendDevName(dev));
        if (total <= 0) {
          final freePtr = calloc<Size>();
          final totalPtr = calloc<Size>();
          try {
            if (_ggmlBackendDevMemory(dev, freePtr, totalPtr)) {
              free = freePtr.value;
              total = totalPtr.value;
            }
          } finally {
            calloc.free(freePtr);
            calloc.free(totalPtr);
          }
        }

        result.add(
          GpuDeviceInfo(
            backend: backend,
            mainGpu: mainGpu,
            name: name,
            description: description.isEmpty ? name : description,
            deviceId: deviceId,
            type: type,
            memoryFreeBytes: free,
            memoryTotalBytes: total,
          ),
        );
      } finally {
        calloc.free(propsPtr);
      }
    }
    return result;
  }

  static String _utf8OrEmpty(Pointer<Char> ptr) =>
      ptr == nullptr ? '' : ptr.cast<Utf8>().toDartString();

  static GpuDeviceType _mapGpuDeviceType(int typeInt) {
    if (typeInt == ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value) {
      return GpuDeviceType.discreteGpu;
    }
    if (typeInt == ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value) {
      return GpuDeviceType.integratedGpu;
    }
    if (typeInt == ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value) {
      return GpuDeviceType.accelerator;
    }
    if (typeInt == ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value) {
      return GpuDeviceType.cpu;
    }
    return GpuDeviceType.unknown;
  }

  /// Maps a device's owning backend registry name to a [GpuBackend]. Returns
  /// [GpuBackend.auto] when the backend can't be resolved.
  GpuBackend _gpuBackendForDevice(ggml_backend_dev_t dev) {
    final reg = _ggmlBackendDevBackendReg(dev);
    if (reg == nullptr) return GpuBackend.auto;
    final namePtr = _ggmlBackendRegName(reg);
    if (namePtr == nullptr) return GpuBackend.auto;
    return gpuBackendFromRegName(namePtr.cast<Utf8>().toDartString());
  }

  /// Maps a ggml backend registry name to a [GpuBackend]; returns
  /// [GpuBackend.auto] when unrecognized. Match-by-substring because registry
  /// names vary by build (e.g. the Metal backend registers as `Metal` on some
  /// builds and `MTL` on others), mirroring [_backendInfoContainsBackendMarker].
  static GpuBackend gpuBackendFromRegName(String regName) {
    final name = regName.toLowerCase();
    if (name.contains('vulkan')) return GpuBackend.vulkan;
    if (name.contains('cuda')) return GpuBackend.cuda;
    if (name.contains('metal') || name.contains('mtl')) {
      return GpuBackend.metal;
    }
    if (name.contains('hip') || name.contains('rocm')) return GpuBackend.hip;
    if (name.contains('opencl')) return GpuBackend.opencl;
    if (name.contains('blas')) return GpuBackend.blas;
    if (name.contains('cpu')) return GpuBackend.cpu;
    return GpuBackend.auto;
  }

  /// Returns the context size for the given [contextHandle].
  int getContextSize(int contextHandle) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) return 0;
    return llama_n_ctx(ctx.pointer);
  }

  /// Returns native llama.cpp perf timings for [contextHandle].
  ({
    double loadMs,
    double promptEvalMs,
    double evalMs,
    double sampleMs,
    double? decodeMs,
    int promptEvalTokens,
    int evalTokens,
    int sampleCount,
    int reusedGraphs,
    int? speculativeDraftTokens,
    int? speculativeAcceptedDraftTokens,
    int? speculativeDraftAttempts,
    int? speculativeVerifyTokens,
    int? speculativeReplayTokens,
    double? speculativeDraftMs,
    double? speculativeVerifyMs,
  })
  getPerformanceContext(int contextHandle) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw Exception("Invalid context handle");
    }

    final perf = llama_perf_context(ctx.pointer);
    final sampler = _samplers[contextHandle];
    final samplerPerf = sampler != null ? llama_perf_sampler(sampler) : null;

    final promptEvalMs = ctx.lastPerfPromptEvalMs > 0
        ? ctx.lastPerfPromptEvalMs
        : perf.t_p_eval_ms;
    final evalMs = ctx.lastPerfEvalMs > 0 ? ctx.lastPerfEvalMs : perf.t_eval_ms;
    final sampleMs = ctx.lastPerfSampleMs > 0
        ? ctx.lastPerfSampleMs
        : (samplerPerf?.t_sample_ms ?? 0);
    final promptEvalTokens = perf.n_p_eval > 0
        ? perf.n_p_eval
        : ctx.lastPerfPromptEvalTokens;
    final evalTokens = ctx.lastPerfEvalTokens > 0
        ? ctx.lastPerfEvalTokens
        : perf.n_eval;
    final sampleCount = ctx.lastPerfSampleCount > 0
        ? ctx.lastPerfSampleCount
        : (samplerPerf?.n_sample ?? 0);
    final decodeMs = ctx.lastPerfDecodeMs > 0 ? ctx.lastPerfDecodeMs : null;
    final speculativeDraftTokens = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeDraftTokens
        : null;
    final speculativeAcceptedDraftTokens = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeAcceptedDraftTokens
        : null;
    final speculativeDraftAttempts = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeDraftAttempts
        : null;
    final speculativeVerifyTokens = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeVerifyTokens
        : null;
    final speculativeReplayTokens = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeReplayTokens
        : null;
    final speculativeDraftMs = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeDraftMs
        : null;
    final speculativeVerifyMs = ctx.lastPerfSpeculativeRan
        ? ctx.lastPerfSpeculativeVerifyMs
        : null;

    return (
      loadMs: perf.t_load_ms,
      promptEvalMs: promptEvalMs,
      evalMs: evalMs,
      sampleMs: sampleMs,
      decodeMs: decodeMs,
      promptEvalTokens: promptEvalTokens,
      evalTokens: evalTokens,
      sampleCount: sampleCount,
      reusedGraphs: perf.n_reused,
      speculativeDraftTokens: speculativeDraftTokens,
      speculativeAcceptedDraftTokens: speculativeAcceptedDraftTokens,
      speculativeDraftAttempts: speculativeDraftAttempts,
      speculativeVerifyTokens: speculativeVerifyTokens,
      speculativeReplayTokens: speculativeReplayTokens,
      speculativeDraftMs: speculativeDraftMs,
      speculativeVerifyMs: speculativeVerifyMs,
    );
  }

  /// Checks if a multimodal context exists.
  bool hasMultimodalContext(int mmContextHandle) {
    return _mtmdContexts.containsKey(mmContextHandle);
  }

  /// Returns whether the active multimodal projector supports vision input.
  bool supportsVision(int mmContextHandle) {
    final mmCtx = _mtmdContexts[mmContextHandle];
    if (mmCtx == null) {
      return false;
    }

    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_support_vision(mmCtx);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }

    final fallback = _resolveMtmdFallbackApi();
    return fallback?.supportsVision(mmCtx) ?? false;
  }

  /// Returns whether the active multimodal projector supports audio input.
  bool supportsAudio(int mmContextHandle) {
    final mmCtx = _mtmdContexts[mmContextHandle];
    if (mmCtx == null) {
      return false;
    }

    if (!_mtmdPrimarySymbolsUnavailable) {
      try {
        return mtmd_support_audio(mmCtx);
      } on ArgumentError {
        _mtmdPrimarySymbolsUnavailable = true;
      }
    }

    final fallback = _resolveMtmdFallbackApi();
    return fallback?.supportsAudio(mmCtx) ?? false;
  }
}

class _LazyGrammarConfig {
  final Pointer<Pointer<Char>> triggerPatterns;
  final int numTriggerPatterns;
  final Pointer<llama_token> triggerTokens;
  final int numTriggerTokens;
  final List<Pointer<Utf8>> allocatedPatternPointers;

  const _LazyGrammarConfig({
    required this.triggerPatterns,
    required this.numTriggerPatterns,
    required this.triggerTokens,
    required this.numTriggerTokens,
    required this.allocatedPatternPointers,
  });

  void dispose() {
    for (final pointer in allocatedPatternPointers) {
      malloc.free(pointer);
    }

    if (triggerPatterns != nullptr) {
      malloc.free(triggerPatterns);
    }
    if (triggerTokens != nullptr) {
      malloc.free(triggerTokens);
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

  static _ReasoningBudgetApi? tryLoad(DynamicLibrary library) {
    try {
      return _ReasoningBudgetApi(
        init: library
            .lookupFunction<
              _LlamaDartReasoningBudgetInitNative,
              _LlamaDartReasoningBudgetInitDart
            >('llama_dart_sampler_init_reasoning_budget'),
      );
    } catch (_) {
      return null;
    }
  }
}

class _SpeculativeApi {
  final _LlamaDartSpeculativeInitDart init;
  final _LlamaDartSpeculativeFreeDart free;
  final _LlamaDartSpeculativeGetDraftContextDart getDraftContext;
  final _LlamaDartSpeculativeNeedEmbdDart needEmbd;
  final _LlamaDartSpeculativeNeedEmbdDart needEmbdNextn;
  final _LlamaDartSpeculativeBeginDart begin;
  final _LlamaDartSpeculativeProcessBatchDart processBatch;
  final _LlamaDartSpeculativeDraftDart draft;
  final _LlamaDartSpeculativeAcceptDart accept;
  final _LlamaDartSamplerSampleAndAcceptNDart sampleAndAcceptN;

  const _SpeculativeApi({
    required this.init,
    required this.free,
    required this.getDraftContext,
    required this.needEmbd,
    required this.needEmbdNextn,
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
      getDraftContext: llama_dart_speculative_get_draft_context,
      needEmbd: llama_dart_speculative_need_embd,
      needEmbdNextn: llama_dart_speculative_need_embd_nextn,
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
    _llamadartWrapperSpeculativeFree(nullptr.cast<llama_dart_speculative>());
    return _SpeculativeApi(
      init: _llamadartWrapperSpeculativeInit,
      free: _llamadartWrapperSpeculativeFree,
      getDraftContext: _llamadartWrapperSpeculativeGetDraftContext,
      needEmbd: _llamadartWrapperSpeculativeNeedEmbd,
      needEmbdNextn: _llamadartWrapperSpeculativeNeedEmbdNextn,
      begin: _llamadartWrapperSpeculativeBegin,
      processBatch: _llamadartWrapperSpeculativeProcessBatch,
      draft: _llamadartWrapperSpeculativeDraft,
      accept: _llamadartWrapperSpeculativeAccept,
      sampleAndAcceptN: _llamadartWrapperSamplerSampleAndAcceptN,
    );
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
      needEmbd(nullSpeculative);
      needEmbdNextn(nullSpeculative);
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
        getDraftContext: library
            .lookupFunction<
              _LlamaDartSpeculativeGetDraftContextNative,
              _LlamaDartSpeculativeGetDraftContextDart
            >('llama_dart_speculative_get_draft_context'),
        needEmbd: library
            .lookupFunction<
              _LlamaDartSpeculativeNeedEmbdNative,
              _LlamaDartSpeculativeNeedEmbdDart
            >('llama_dart_speculative_need_embd'),
        needEmbdNextn: library
            .lookupFunction<
              _LlamaDartSpeculativeNeedEmbdNative,
              _LlamaDartSpeculativeNeedEmbdDart
            >('llama_dart_speculative_need_embd_nextn'),
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
        contextParams,
        params,
      );
    } finally {
      malloc.free(params);
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

class _MtpApi {
  final _LlamaDartMtpInitDart init;
  final _LlamaDartMtpInitDart? initWithDraftModel;
  final _LlamaDartMtpFreeDart free;
  final _LlamaDartMtpGetDraftContextDart getDraftContext;
  final _LlamaDartMtpBeginDart begin;
  final _LlamaDartMtpProcessBatchDart processBatch;
  final _LlamaDartMtpDraftDart draft;
  final _LlamaDartMtpAcceptDart accept;
  final _LlamaDartSamplerSampleAndAcceptNDart sampleAndAcceptN;

  const _MtpApi({
    required this.init,
    required this.initWithDraftModel,
    required this.free,
    required this.getDraftContext,
    required this.begin,
    required this.processBatch,
    required this.draft,
    required this.accept,
    required this.sampleAndAcceptN,
  });

  factory _MtpApi.direct() {
    final api = _MtpApi(
      init: llama_dart_mtp_init,
      initWithDraftModel: llama_dart_mtp_init_with_draft_model,
      free: llama_dart_mtp_free,
      getDraftContext: llama_dart_mtp_get_draft_context,
      begin: llama_dart_mtp_begin,
      processBatch: llama_dart_mtp_process_batch,
      draft: llama_dart_mtp_draft,
      accept: llama_dart_mtp_accept,
      sampleAndAcceptN: llama_dart_sampler_sample_and_accept_n,
    );
    api.probe();
    return api;
  }

  factory _MtpApi.windowsAsset() {
    _llamadartWrapperMtpFree(nullptr.cast<llama_dart_mtp>());
    return _MtpApi(
      init: _llamadartWrapperMtpInit,
      initWithDraftModel: _llamadartWrapperMtpInitWithDraftModel,
      free: _llamadartWrapperMtpFree,
      getDraftContext: _llamadartWrapperMtpGetDraftContext,
      begin: _llamadartWrapperMtpBegin,
      processBatch: _llamadartWrapperMtpProcessBatch,
      draft: _llamadartWrapperMtpDraft,
      accept: _llamadartWrapperMtpAccept,
      sampleAndAcceptN: _llamadartWrapperSamplerSampleAndAcceptN,
    );
  }

  void probe() {
    final nullMtp = nullptr.cast<llama_dart_mtp>();
    final nullModel = nullptr.cast<llama_model>();
    final nullContext = nullptr.cast<llama_context>();
    final nullSampler = nullptr.cast<llama_sampler>();
    final nullTokenArray = nullptr.cast<Int32>();
    final ctxParams = llama_context_default_params();
    final batch = llama_batch_init(1, 0, 1);
    try {
      init(nullModel, nullContext, ctxParams, 1, 0, 0.0, true);
      free(nullMtp);
      getDraftContext(nullMtp);
      begin(nullMtp, 0, nullTokenArray, 0);
      processBatch(nullMtp, batch);
      draft(nullMtp, 0, 0, 0, nullTokenArray, 0, 1, nullTokenArray, 0);
      accept(nullMtp, 0, 0);
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

  Pointer<llama_dart_mtp> initSession({
    required Pointer<llama_model> targetModel,
    required Pointer<llama_model>? draftModel,
    required Pointer<llama_context> targetContext,
    required llama_context_params contextParams,
    required int draftTokenMax,
    required int draftTokenMin,
    required double minProbability,
    required bool backendSampling,
  }) {
    final resolvedDraftModel = draftModel;
    if (resolvedDraftModel == null) {
      return init(
        targetModel,
        targetContext,
        contextParams,
        draftTokenMax,
        draftTokenMin,
        minProbability,
        backendSampling,
      );
    }
    final initWithDraft = initWithDraftModel;
    if (initWithDraft == null) {
      throw UnsupportedError(
        'llama.cpp MTP draftModelPath requires a native libllamadart build '
        'that exports llama_dart_mtp_init_with_draft_model.',
      );
    }
    try {
      return initWithDraft(
        resolvedDraftModel,
        targetContext,
        contextParams,
        draftTokenMax,
        draftTokenMin,
        minProbability,
        backendSampling,
      );
    } on Object catch (error) {
      throw UnsupportedError(
        'llama.cpp MTP draftModelPath requires a native libllamadart build '
        'that exports llama_dart_mtp_init_with_draft_model. Native lookup '
        'failed: $error',
      );
    }
  }

  static _MtpApi? tryLoad(DynamicLibrary library) {
    try {
      _LlamaDartMtpInitDart? initWithDraftModel;
      try {
        initWithDraftModel = library
            .lookupFunction<_LlamaDartMtpInitNative, _LlamaDartMtpInitDart>(
              'llama_dart_mtp_init_with_draft_model',
            );
      } catch (_) {
        initWithDraftModel = null;
      }
      return _MtpApi(
        init: library
            .lookupFunction<_LlamaDartMtpInitNative, _LlamaDartMtpInitDart>(
              'llama_dart_mtp_init',
            ),
        initWithDraftModel: initWithDraftModel,
        free: library
            .lookupFunction<_LlamaDartMtpFreeNative, _LlamaDartMtpFreeDart>(
              'llama_dart_mtp_free',
            ),
        getDraftContext: library
            .lookupFunction<
              _LlamaDartMtpGetDraftContextNative,
              _LlamaDartMtpGetDraftContextDart
            >('llama_dart_mtp_get_draft_context'),
        begin: library
            .lookupFunction<_LlamaDartMtpBeginNative, _LlamaDartMtpBeginDart>(
              'llama_dart_mtp_begin',
            ),
        processBatch: library
            .lookupFunction<
              _LlamaDartMtpProcessBatchNative,
              _LlamaDartMtpProcessBatchDart
            >('llama_dart_mtp_process_batch'),
        draft: library
            .lookupFunction<_LlamaDartMtpDraftNative, _LlamaDartMtpDraftDart>(
              'llama_dart_mtp_draft',
            ),
        accept: library
            .lookupFunction<_LlamaDartMtpAcceptNative, _LlamaDartMtpAcceptDart>(
              'llama_dart_mtp_accept',
            ),
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
}

class _NgramApi {
  final _LlamaDartNgramSimpleInitDart initSimple;
  final _LlamaDartNgramFreeDart free;
  final _LlamaDartNgramBeginDart begin;
  final _LlamaDartNgramProcessBatchDart processBatch;
  final _LlamaDartNgramDraftDart draft;
  final _LlamaDartNgramAcceptDart accept;
  final _LlamaDartSamplerSampleAndAcceptNDart sampleAndAcceptN;

  const _NgramApi({
    required this.initSimple,
    required this.free,
    required this.begin,
    required this.processBatch,
    required this.draft,
    required this.accept,
    required this.sampleAndAcceptN,
  });

  factory _NgramApi.direct() {
    final api = _NgramApi(
      initSimple: llama_dart_ngram_simple_init,
      free: llama_dart_ngram_free,
      begin: llama_dart_ngram_begin,
      processBatch: llama_dart_ngram_process_batch,
      draft: llama_dart_ngram_draft,
      accept: llama_dart_ngram_accept,
      sampleAndAcceptN: llama_dart_sampler_sample_and_accept_n,
    );
    api.probe();
    return api;
  }

  factory _NgramApi.windowsAsset() {
    _llamadartWrapperNgramFree(nullptr.cast<llama_dart_ngram>());
    return _NgramApi(
      initSimple: _llamadartWrapperNgramSimpleInit,
      free: _llamadartWrapperNgramFree,
      begin: _llamadartWrapperNgramBegin,
      processBatch: _llamadartWrapperNgramProcessBatch,
      draft: _llamadartWrapperNgramDraft,
      accept: _llamadartWrapperNgramAccept,
      sampleAndAcceptN: _llamadartWrapperSamplerSampleAndAcceptN,
    );
  }

  void probe() {
    final nullNgram = nullptr.cast<llama_dart_ngram>();
    final nullSampler = nullptr.cast<llama_sampler>();
    final nullContext = nullptr.cast<llama_context>();
    final nullTokenArray = nullptr.cast<Int32>();
    final batch = llama_batch_init(1, 0, 1);
    Pointer<llama_dart_ngram> probeSession = nullptr;
    try {
      probeSession = initSimple(12, 1);
      if (probeSession != nullptr) {
        free(probeSession);
        probeSession = nullptr;
      }
      free(nullNgram);
      begin(nullNgram, 0, nullTokenArray, 0);
      processBatch(nullNgram, batch);
      draft(nullNgram, 0, 0, 0, nullTokenArray, 0, 1, nullTokenArray, 0);
      accept(nullNgram, 0, 0);
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
      if (probeSession != nullptr) {
        free(probeSession);
      }
      llama_batch_free(batch);
    }
  }

  static _NgramApi? tryLoad(DynamicLibrary library) {
    try {
      return _NgramApi(
        initSimple: library
            .lookupFunction<
              _LlamaDartNgramSimpleInitNative,
              _LlamaDartNgramSimpleInitDart
            >('llama_dart_ngram_simple_init'),
        free: library
            .lookupFunction<_LlamaDartNgramFreeNative, _LlamaDartNgramFreeDart>(
              'llama_dart_ngram_free',
            ),
        begin: library
            .lookupFunction<
              _LlamaDartNgramBeginNative,
              _LlamaDartNgramBeginDart
            >('llama_dart_ngram_begin'),
        processBatch: library
            .lookupFunction<
              _LlamaDartNgramProcessBatchNative,
              _LlamaDartNgramProcessBatchDart
            >('llama_dart_ngram_process_batch'),
        draft: library
            .lookupFunction<
              _LlamaDartNgramDraftNative,
              _LlamaDartNgramDraftDart
            >('llama_dart_ngram_draft'),
        accept: library
            .lookupFunction<
              _LlamaDartNgramAcceptNative,
              _LlamaDartNgramAcceptDart
            >('llama_dart_ngram_accept'),
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
}

class _MtmdApi {
  final _MtmdDefaultMarkerDart defaultMarker;
  final _MtmdContextParamsDefaultDart contextParamsDefault;
  final _MtmdInitFromFileDart initFromFile;
  final _MtmdFreeDart free;
  final _MtmdInputChunksInitDart inputChunksInit;
  final _MtmdInputChunksFreeDart inputChunksFree;
  final _MtmdHelperBitmapInitFromFileDart helperBitmapInitFromFile;
  final _MtmdHelperBitmapInitFromBufDart helperBitmapInitFromBuf;
  final _MtmdBitmapInitFromAudioDart bitmapInitFromAudio;
  final _MtmdSupportVisionDart supportsVision;
  final _MtmdSupportAudioDart supportsAudio;
  final _MtmdBitmapFreeDart bitmapFree;
  final _MtmdTokenizeDart tokenize;
  final _MtmdHelperEvalChunksDart helperEvalChunks;
  final _MtmdLogSetDart? logSet;
  final _MtmdLogSetDart? helperLogSet;

  const _MtmdApi({
    required this.defaultMarker,
    required this.contextParamsDefault,
    required this.initFromFile,
    required this.free,
    required this.inputChunksInit,
    required this.inputChunksFree,
    required this.helperBitmapInitFromFile,
    required this.helperBitmapInitFromBuf,
    required this.bitmapInitFromAudio,
    required this.supportsVision,
    required this.supportsAudio,
    required this.bitmapFree,
    required this.tokenize,
    required this.helperEvalChunks,
    required this.logSet,
    required this.helperLogSet,
  });

  static _MtmdApi? tryLoad(DynamicLibrary library) {
    try {
      _MtmdLogSetDart? logSet;
      _MtmdLogSetDart? helperLogSet;
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

      return _MtmdApi(
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
        logSet: logSet,
        helperLogSet: helperLogSet,
      );
    } catch (_) {
      return null;
    }
  }
}

// --- Native Wrappers ---

class _LlamaLoraWrapper {
  final Pointer<llama_adapter_lora> pointer;
  _LlamaLoraWrapper(this.pointer);
  void dispose() {
    llama_adapter_lora_free(pointer);
  }
}

class _LlamaModelWrapper {
  final Pointer<llama_model> pointer;
  final String? sourcePath;
  final int vocabSize;
  final List<int> suppressedTokens;
  _LlamaModelWrapper(
    this.pointer, {
    this.sourcePath,
    required this.vocabSize,
    required this.suppressedTokens,
  });
  void dispose() {
    llama_model_free(pointer);
  }
}

class _LlamaContextWrapper {
  final Pointer<llama_context> pointer;
  final _LlamaModelWrapper? _modelKeepAlive;
  List<int>? cachedPromptTokens;

  /// Set by stateLoadFile, cleared by any decode. Gates the exact-prompt
  /// single-token resume path; without the gate, the in-process reuse path
  /// would diverge from the cleared+full-decode baseline (parity property).
  bool kvFromStateLoad = false;

  double lastPerfPromptEvalMs = 0;
  double lastPerfEvalMs = 0;
  double lastPerfSampleMs = 0;
  double lastPerfDecodeMs = 0;
  double lastPerfSpeculativeDraftMs = 0;
  double lastPerfSpeculativeVerifyMs = 0;
  int lastPerfPromptEvalTokens = 0;
  int lastPerfEvalTokens = 0;
  int lastPerfSampleCount = 0;
  int lastPerfSpeculativeDraftTokens = 0;
  int lastPerfSpeculativeAcceptedDraftTokens = 0;
  int lastPerfSpeculativeDraftAttempts = 0;
  int lastPerfSpeculativeVerifyTokens = 0;
  int lastPerfSpeculativeReplayTokens = 0;
  bool lastPerfSpeculativeRan = false;
  _LlamaContextWrapper(this.pointer, this._modelKeepAlive);
  void resetLastPerf() {
    lastPerfPromptEvalMs = 0;
    lastPerfEvalMs = 0;
    lastPerfSampleMs = 0;
    lastPerfDecodeMs = 0;
    lastPerfSpeculativeDraftMs = 0;
    lastPerfSpeculativeVerifyMs = 0;
    lastPerfPromptEvalTokens = 0;
    lastPerfEvalTokens = 0;
    lastPerfSampleCount = 0;
    lastPerfSpeculativeDraftTokens = 0;
    lastPerfSpeculativeAcceptedDraftTokens = 0;
    lastPerfSpeculativeDraftAttempts = 0;
    lastPerfSpeculativeVerifyTokens = 0;
    lastPerfSpeculativeReplayTokens = 0;
    lastPerfSpeculativeRan = false;
  }

  void dispose() {
    // ignore: unused_local_variable
    final _ = _modelKeepAlive;
    cachedPromptTokens = null;
    kvFromStateLoad = false;
    llama_free(pointer);
  }
}
