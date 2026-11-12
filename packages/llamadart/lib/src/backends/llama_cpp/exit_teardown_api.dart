import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../core/exceptions.dart';
import '../../hook/native_release_pins.dart';
import '../isolate_shutdown_releases.dart';
import 'bindings.dart';
import 'native_barrier_api.dart';
import 'llama_cpp_raw_bindings.dart' as raw_bindings;

const _llamadartAsset = 'package:llamadart/llamadart';
const _wrapperAsset = 'package:llamadart/llamadart_wrapper';

final int _statusException =
    llama_dart_status.LLAMA_DART_STATUS_EXCEPTION.value;

/// The embedding-batch callback of `llama_dart_mtmd_helper_decode_image_chunk`.
///
/// libllamadart keeps this signature; upstream's
/// `mtmd_helper_post_decode_callback` takes an `mtmd_helper_embd_batch` since
/// llama.cpp v0.6.0.
typedef LlamaDartPostDecodeCallback =
    Pointer<NativeFunction<Int32 Function(llama_batch, Pointer<Void>)>>;

typedef _FreeNative = Void Function(Pointer<Void>);
typedef _TrackNative =
    Bool Function(Pointer<Void>, Pointer<NativeFunction<_FreeNative>>, Int32);
typedef _UntrackNative = Bool Function(Pointer<Void>);
typedef _ModelLoadNative =
    Pointer<llama_model> Function(Pointer<Char>, llama_model_params);
typedef _InitFromModelNative =
    Pointer<llama_context> Function(Pointer<llama_model>, llama_context_params);
typedef _MtmdInitNative =
    Pointer<mtmd_context> Function(
      Pointer<Char>,
      Pointer<llama_model>,
      Pointer<mtmd_context_params>,
    );
typedef _DecodeNative = Int32 Function(Pointer<llama_context>, llama_batch);
typedef _SynchronizeNative = Void Function(Pointer<llama_context>);
typedef _SamplerSampleNative =
    llama_token Function(Pointer<llama_sampler>, Pointer<llama_context>, Int32);
typedef _StateSaveFileNative =
    Bool Function(
      Pointer<llama_context>,
      Pointer<Char>,
      Pointer<llama_token>,
      Size,
    );
typedef _StateLoadFileNative =
    Bool Function(
      Pointer<llama_context>,
      Pointer<Char>,
      Pointer<llama_token>,
      Size,
      Pointer<Size>,
    );
typedef _StateSeqSizeNative =
    Size Function(Pointer<llama_context>, llama_seq_id, Uint32);
typedef _StateSeqDataNative =
    Size Function(
      Pointer<llama_context>,
      Pointer<Uint8>,
      Size,
      llama_seq_id,
      Uint32,
    );
typedef _AdapterLoraInitNative =
    Pointer<llama_adapter_lora> Function(Pointer<llama_model>, Pointer<Char>);
typedef _MtmdTokenizeNative =
    Int32 Function(
      Pointer<mtmd_context>,
      Pointer<mtmd_input_chunks>,
      Pointer<mtmd_input_text>,
      Pointer<Pointer<mtmd_bitmap>>,
      Size,
    );
typedef _MtmdEncodeChunkNative =
    Int32 Function(Pointer<mtmd_context>, Pointer<mtmd_input_chunk>);
typedef _MtmdEvalChunksNative =
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
typedef _MtmdEvalChunkSingleNative =
    Int32 Function(
      Pointer<mtmd_context>,
      Pointer<llama_context>,
      Pointer<mtmd_input_chunk>,
      llama_pos,
      llama_seq_id,
      Int32,
      Bool,
      Pointer<llama_pos>,
    );
typedef _MtmdDecodeImageChunkNative =
    Int32 Function(
      Pointer<mtmd_context>,
      Pointer<llama_context>,
      Pointer<mtmd_input_chunk>,
      Pointer<Float>,
      llama_pos,
      llama_seq_id,
      Int32,
      Pointer<llama_pos>,
      LlamaDartPostDecodeCallback,
      Pointer<Void>,
    );
typedef _SchedGraphComputeNative =
    Int Function(ggml_backend_sched_t, Pointer<ggml_cgraph>);

/// The `llama_dart_exit_stage` value [stage] is tracked in.
int exitStageValue(ShutdownStage stage) => switch (stage) {
  ShutdownStage.session =>
    llama_dart_exit_stage.LLAMA_DART_EXIT_STAGE_SESSION.value,
  ShutdownStage.scheduler =>
    llama_dart_exit_stage.LLAMA_DART_EXIT_STAGE_SCHEDULER.value,
  ShutdownStage.context =>
    llama_dart_exit_stage.LLAMA_DART_EXIT_STAGE_CONTEXT.value,
  ShutdownStage.modelUser =>
    llama_dart_exit_stage.LLAMA_DART_EXIT_STAGE_MODEL_USER.value,
  ShutdownStage.backend =>
    llama_dart_exit_stage.LLAMA_DART_EXIT_STAGE_BACKEND.value,
  ShutdownStage.model =>
    llama_dart_exit_stage.LLAMA_DART_EXIT_STAGE_MODEL.value,
};

/// libllamadart's exit-teardown functions, resolved from one library.
///
/// The library keeps a registry of the objects created through these
/// functions and, on Apple platforms, frees what is left of it during C
/// `exit`, before ggml-metal's static destructor, which aborts while a Metal
/// buffer is still allocated. Teardown waits only for the calls made through
/// these functions, and for a short settle after the last one: any other
/// native call on a tracked object that is in flight when it runs is freed
/// under (`doc/llama_cpp_exit_teardown.md`).
///
/// Windows bundles export these functions from `llamadart.dll` rather than the
/// default `llama.dll` asset, so [tryResolve] resolves `@Native` declarations
/// bound to that asset on Windows. Elsewhere it resolves the generated
/// bindings.
///
/// `llama_dart_exit_call_begin`, `llama_dart_exit_call_end` and
/// `llama_dart_exit_teardown` are left unbound: an isolate killed between
/// begin and end never reaches end, and a Dart program that returns from
/// `main` after teardown waits forever for its blocked isolates.
final class ExitTeardownApi {
  /// Creates an API from resolved functions.
  const ExitTeardownApi({
    required this.track,
    required this.untrack,
    required this.free,
    required this.freeAddress,
    required this.modelLoadFromFile,
    required this.initFromModel,
    required this.mtmdInitFromFile,
    required this.decode,
    required this.encode,
    required this.synchronize,
    required this.samplerSample,
    required this.stateSaveFile,
    required this.stateLoadFile,
    required this.stateSeqGetSizeExt,
    required this.stateSeqGetDataExt,
    required this.stateSeqSetDataExt,
    required this.adapterLoraInit,
    required this.mtmdTokenize,
    required this.mtmdEncodeChunk,
    required this.mtmdHelperEvalChunks,
    required this.mtmdHelperEvalChunkSingle,
    required this.mtmdHelperDecodeImageChunk,
    required this.schedGraphCompute,
  });

  /// Optional v0.7.0-1 mixed-batch wrappers. Older runtimes retain text support.
  static LlamaCppMixedBatchApi? resolveMixedBatch({
    Pointer<NativeType> Function(String)? symbol,
    bool isWindows = false,
  }) => LlamaCppMixedBatchApi.tryResolve(symbol: symbol, isWindows: isWindows);

  /// The oldest `llamadart-native` release to use these functions with.
  ///
  /// `v0.5.0-1` exports them too, so [tryResolve] accepts it, but its
  /// teardown does not wait for a free that is in flight on the last tracked
  /// object.
  static const String minimumNativeRelease = 'v0.5.0-2';

  /// Resolves every function from the loaded runtime, or returns `null` when
  /// it does not export all of them.
  ///
  /// [isWindows] selects the asset the functions are bound to. [symbol]
  /// replaces that lookup: it returns the address of the function exported
  /// under a name, and throws [ArgumentError] when there is none.
  static ExitTeardownApi? tryResolve({
    required bool isWindows,
    Pointer<NativeType> Function(String name)? symbol,
  }) {
    try {
      return ExitTeardownApi._fromSymbols(
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
  factory ExitTeardownApi._fromSymbols(
    Pointer<NativeType> Function(String name) symbol,
  ) {
    Pointer<NativeFunction<T>> function<T extends Function>(String name) =>
        symbol(name).cast();
    final free = function<_FreeNative>('llama_dart_exit_free');
    return ExitTeardownApi(
      track: function<_TrackNative>('llama_dart_exit_track').asFunction(),
      untrack: function<_UntrackNative>('llama_dart_exit_untrack').asFunction(),
      free: free.asFunction(),
      freeAddress: free.cast(),
      modelLoadFromFile: function<_ModelLoadNative>(
        'llama_dart_model_load_from_file',
      ).asFunction(),
      initFromModel: function<_InitFromModelNative>(
        'llama_dart_init_from_model',
      ).asFunction(),
      mtmdInitFromFile: function<_MtmdInitNative>(
        'llama_dart_mtmd_init_from_file',
      ).asFunction(),
      decode: function<_DecodeNative>('llama_dart_decode').asFunction(),
      encode: function<_DecodeNative>('llama_dart_encode').asFunction(),
      synchronize: function<_SynchronizeNative>(
        'llama_dart_synchronize',
      ).asFunction(),
      samplerSample: function<_SamplerSampleNative>(
        'llama_dart_sampler_sample',
      ).asFunction(),
      stateSaveFile: function<_StateSaveFileNative>(
        'llama_dart_state_save_file',
      ).asFunction(),
      stateLoadFile: function<_StateLoadFileNative>(
        'llama_dart_state_load_file',
      ).asFunction(),
      stateSeqGetSizeExt: function<_StateSeqSizeNative>(
        'llama_dart_state_seq_get_size_ext',
      ).asFunction(),
      stateSeqGetDataExt: function<_StateSeqDataNative>(
        'llama_dart_state_seq_get_data_ext',
      ).asFunction(),
      stateSeqSetDataExt: function<_StateSeqDataNative>(
        'llama_dart_state_seq_set_data_ext',
      ).asFunction(),
      adapterLoraInit: function<_AdapterLoraInitNative>(
        'llama_dart_adapter_lora_init',
      ).asFunction(),
      mtmdTokenize: function<_MtmdTokenizeNative>(
        'llama_dart_mtmd_tokenize',
      ).asFunction(),
      mtmdEncodeChunk: function<_MtmdEncodeChunkNative>(
        'llama_dart_mtmd_encode_chunk',
      ).asFunction(),
      mtmdHelperEvalChunks: function<_MtmdEvalChunksNative>(
        'llama_dart_mtmd_helper_eval_chunks',
      ).asFunction(),
      mtmdHelperEvalChunkSingle: function<_MtmdEvalChunkSingleNative>(
        'llama_dart_mtmd_helper_eval_chunk_single',
      ).asFunction(),
      mtmdHelperDecodeImageChunk: function<_MtmdDecodeImageChunkNative>(
        'llama_dart_mtmd_helper_decode_image_chunk',
      ).asFunction(),
      schedGraphCompute: function<_SchedGraphComputeNative>(
        'llama_dart_ggml_backend_sched_graph_compute',
      ).asFunction(),
    );
  }

  /// `llama_dart_exit_track`, with an [exitStageValue] as `stage`.
  final bool Function(
    Pointer<Void> object,
    Pointer<NativeFunction<Void Function(Pointer<Void>)>> free,
    int stage,
  )
  track;

  /// `llama_dart_exit_untrack`: stops tracking an object without freeing it,
  /// and returns whether it was tracked.
  final bool Function(Pointer<Void> object) untrack;

  /// `llama_dart_exit_free`: frees a tracked object with the function it was
  /// tracked with, and does nothing for any other pointer.
  final void Function(Pointer<Void> object) free;

  /// The address of [free], for `IsolateShutdownReleases`.
  final Pointer<NativeFinalizerFunction> freeAddress;

  /// `llama_dart_model_load_from_file`.
  final Pointer<llama_model> Function(
    Pointer<Char> path,
    llama_model_params params,
  )
  modelLoadFromFile;

  /// `llama_dart_init_from_model`.
  final Pointer<llama_context> Function(
    Pointer<llama_model> model,
    llama_context_params params,
  )
  initFromModel;

  /// `llama_dart_mtmd_init_from_file`.
  final Pointer<mtmd_context> Function(
    Pointer<Char> path,
    Pointer<llama_model> model,
    Pointer<mtmd_context_params> params,
  )
  mtmdInitFromFile;

  /// `llama_dart_decode`, which also waits for the backend.
  final int Function(Pointer<llama_context> ctx, llama_batch batch) decode;

  /// `llama_dart_encode`, which also waits for the backend.
  final int Function(Pointer<llama_context> ctx, llama_batch batch) encode;

  /// `llama_dart_synchronize`.
  final void Function(Pointer<llama_context> ctx) synchronize;

  /// `llama_dart_sampler_sample`.
  final int Function(
    Pointer<llama_sampler> sampler,
    Pointer<llama_context> ctx,
    int index,
  )
  samplerSample;

  /// `llama_dart_state_save_file`.
  final bool Function(
    Pointer<llama_context> ctx,
    Pointer<Char> path,
    Pointer<llama_token> tokens,
    int tokenCount,
  )
  stateSaveFile;

  /// `llama_dart_state_load_file`.
  final bool Function(
    Pointer<llama_context> ctx,
    Pointer<Char> path,
    Pointer<llama_token> tokensOut,
    int tokenCapacity,
    Pointer<Size> tokenCountOut,
  )
  stateLoadFile;

  /// `llama_dart_state_seq_get_size_ext`.
  final int Function(Pointer<llama_context> ctx, int seqId, int flags)
  stateSeqGetSizeExt;

  /// `llama_dart_state_seq_get_data_ext`.
  final int Function(
    Pointer<llama_context> ctx,
    Pointer<Uint8> dst,
    int size,
    int seqId,
    int flags,
  )
  stateSeqGetDataExt;

  /// `llama_dart_state_seq_set_data_ext`.
  final int Function(
    Pointer<llama_context> ctx,
    Pointer<Uint8> src,
    int size,
    int seqId,
    int flags,
  )
  stateSeqSetDataExt;

  /// `llama_dart_adapter_lora_init`.
  final Pointer<llama_adapter_lora> Function(
    Pointer<llama_model> model,
    Pointer<Char> path,
  )
  adapterLoraInit;

  /// `llama_dart_mtmd_tokenize`.
  final int Function(
    Pointer<mtmd_context> ctx,
    Pointer<mtmd_input_chunks> output,
    Pointer<mtmd_input_text> text,
    Pointer<Pointer<mtmd_bitmap>> bitmaps,
    int bitmapCount,
  )
  mtmdTokenize;

  /// `llama_dart_mtmd_encode_chunk`.
  final int Function(Pointer<mtmd_context> ctx, Pointer<mtmd_input_chunk> chunk)
  mtmdEncodeChunk;

  /// `llama_dart_mtmd_helper_eval_chunks`, which also waits for the backend.
  final int Function(
    Pointer<mtmd_context> ctx,
    Pointer<llama_context> lctx,
    Pointer<mtmd_input_chunks> chunks,
    int nPast,
    int seqId,
    int nBatch,
    bool logitsLast,
    Pointer<llama_pos> newNPast,
  )
  mtmdHelperEvalChunks;

  /// `llama_dart_mtmd_helper_eval_chunk_single`, which also waits for the
  /// backend.
  final int Function(
    Pointer<mtmd_context> ctx,
    Pointer<llama_context> lctx,
    Pointer<mtmd_input_chunk> chunk,
    int nPast,
    int seqId,
    int nBatch,
    bool logitsLast,
    Pointer<llama_pos> newNPast,
  )
  mtmdHelperEvalChunkSingle;

  /// `llama_dart_mtmd_helper_decode_image_chunk`, which also waits for the
  /// backend.
  final int Function(
    Pointer<mtmd_context> ctx,
    Pointer<llama_context> lctx,
    Pointer<mtmd_input_chunk> chunk,
    Pointer<Float> encodedEmbd,
    int nPast,
    int seqId,
    int nBatch,
    Pointer<llama_pos> newNPast,
    LlamaDartPostDecodeCallback callback,
    Pointer<Void> userData,
  )
  mtmdHelperDecodeImageChunk;

  /// `llama_dart_ggml_backend_sched_graph_compute`, as its raw `ggml_status`.
  final int Function(ggml_backend_sched_t sched, Pointer<ggml_cgraph> graph)
  schedGraphCompute;
}

/// How the service creates and frees models and contexts and makes its long
/// calls on them.
///
/// [LlamaCppObjectCalls.tracked] goes through an [ExitTeardownApi];
/// [upstream] calls llama.cpp directly, which is all a runtime older than
/// [ExitTeardownApi.minimumNativeRelease] offers. One service uses one of
/// them for all of its calls: exit teardown does not wait for an upstream
/// call on a tracked object.
///
/// With a [NativeBarrierApi], a call that caught a C++ exception throws the
/// typed error of its operation instead of returning its failure value, and
/// [failures] remembers the objects that call left free-only.
final class LlamaCppObjectCalls {
  /// Copies reranker metadata while the model is owned by this service.
  ///
  /// [classifierOutputs] reads the classifier output count; tests replace it
  /// to simulate a runtime without the symbol.
  ({
    bool encoder,
    bool decoder,
    Pointer<llama_vocab> vocab,
    List<String?> labels,
    String? template,
  })
  rerankingModelInfo(
    Pointer<llama_model> model, {
    int Function(Pointer<llama_model>) classifierOutputs =
        llama_model_n_cls_out,
  }) {
    failures.ensureUsable(model, 'This reranker model');
    return requireRerankingSymbols(() {
      final count = classifierOutputs(model);
      if (count <= 0) {
        throw LlamaUnsupportedException(
          'The reranker reports no classifier outputs.',
        );
      }
      final labels = <String?>[];
      for (var i = 0; i < count; i++) {
        final label = llama_model_cls_label(model, i);
        labels.add(label == nullptr ? null : label.cast<Utf8>().toDartString());
      }
      final name = 'rerank'.toNativeUtf8();
      final String? template;
      try {
        final text = llama_model_chat_template(model, name.cast());
        template = text == nullptr ? null : text.cast<Utf8>().toDartString();
      } finally {
        malloc.free(name);
      }
      return (
        encoder: llama_model_has_encoder(model),
        decoder: llama_model_has_decoder(model),
        vocab: llama_model_get_vocab(model),
        labels: labels,
        template: template,
      );
    });
  }

  /// Vocabulary framing for the upstream rerank fallback; no text is inserted.
  ({int? bos, int? eos, int? sep}) rerankingSpecialTokens(
    Pointer<llama_vocab> vocab,
  ) {
    final eos = llama_vocab_eos(vocab);
    final sep = llama_vocab_sep(vocab);
    return (
      bos: llama_vocab_get_add_bos(vocab) ? llama_vocab_bos(vocab) : null,
      eos: llama_vocab_get_add_eos(vocab)
          ? (eos == LLAMA_TOKEN_NULL ? sep : eos)
          : null,
      sep: llama_vocab_get_add_sep(vocab) ? sep : null,
    );
  }

  /// Enables classifier output, retaining the failed-context cleanup rule.
  void setRerankingOutput(Pointer<llama_context> context, bool enabled) {
    try {
      failures.ensureUsable(context, 'This reranking context');
    } on LlamaStateException {
      if (!enabled) return;
      rethrow;
    }
    llama_set_embeddings(context, enabled);
  }

  /// Copies exactly n_cls_out values; an embedding width must never be used.
  List<double> rerankingOutput(
    Pointer<llama_context> context,
    int sequence,
    int count,
  ) {
    failures.ensureUsable(context, 'This reranking context');
    final output = llama_get_embeddings_seq(context, sequence);
    if (output == nullptr) {
      throw LlamaInferenceException('Native reranking output is unavailable.');
    }
    return List<double>.of(output.asTypedList(count));
  }

  /// Mixed-batch support is independent of the legacy all-or-nothing exit API.
  late final LlamaCppMixedBatchApi? mixedBatch = _mixedBatchResolver != null
      ? _mixedBatchResolver()
      : exit == null
      ? null
      : ExitTeardownApi.resolveMixedBatch(isWindows: failures.isWindows);

  final LlamaCppMixedBatchApi? Function()? _mixedBatchResolver;

  final int Function(Pointer<llama_model>) _modelInputWidth;

  /// Reads model shape and pooling support without mutating inference state.
  ({
    bool encoder,
    bool decoder,
    int inputWidth,
    int outputWidth,
    Pointer<llama_vocab> vocab,
  })
  embeddingModelInfo(Pointer<llama_model> model) {
    failures.ensureUsable(model, 'This embedding model');
    return (
      encoder: llama_model_has_encoder(model),
      decoder: llama_model_has_decoder(model),
      inputWidth: _optionalEmbeddingInputWidth(model),
      outputWidth: llama_model_n_embd_out(model) > 0
          ? llama_model_n_embd_out(model)
          : llama_model_n_embd(model),
      vocab: llama_model_get_vocab(model),
    );
  }

  int _optionalEmbeddingInputWidth(Pointer<llama_model> model) {
    try {
      return _modelInputWidth(model);
    } on ArgumentError {
      return 0;
    }
  }

  /// Actual allocated limits, rather than the requested model parameters.
  ({
    llama_pooling_type pooling,
    int capacity,
    int sequenceCapacity,
    int sequences,
  })
  embeddingContextInfo(Pointer<llama_context> context) {
    failures.ensureUsable(context, 'This embedding context');
    final limits = [
      llama_n_ctx(context),
      llama_n_ctx_seq(context),
      llama_n_batch(context),
      llama_n_ubatch(context),
    ];
    return (
      pooling: llama_pooling_type$1(context),
      capacity: limits.reduce((a, b) => a < b ? a : b),
      sequenceCapacity: llama_n_ctx_seq(context),
      sequences: llama_n_seq_max(context),
    );
  }

  /// The adapter passes a single position for each mixed embedding row.
  bool embeddingProjectorUsesMrope(Pointer<mtmd_context> projector) =>
      mixedBatch!.projectorUsesMrope(projector);

  /// Runtime sample rate used to validate portable PCM.
  int embeddingAudioSampleRate(Pointer<mtmd_context> projector) =>
      mixedBatch!.audioSampleRate(projector);

  /// Enables pooled embedding output for a complete mixed pass.
  void setEmbeddingOutput(Pointer<llama_context> context, bool enabled) {
    try {
      failures.ensureUsable(context, 'This embedding context');
    } on LlamaStateException {
      // Caught native exceptions leave the context free-only, including cleanup.
      if (!enabled) return;
      rethrow;
    }
    mixedBatch!.setOutput(context, enabled);
  }

  /// Pooled output; callers copy it before the next context operation.
  Pointer<Float> embeddingSequenceOutput(Pointer<llama_context> context) =>
      llama_get_embeddings_seq(context, 0);

  /// Projector output; the next media encode overwrites it.
  Pointer<Float> embeddingMediaOutput(Pointer<mtmd_context> projector) =>
      mixedBatch!.mediaOutput(projector);

  /// Encodes one media chunk under the native exit and exception barriers.
  void encodeEmbeddingChunk(
    Pointer<mtmd_context> projector,
    Pointer<mtmd_input_chunk> chunk,
  ) {
    final api = exit;
    if (api == null) {
      throw LlamaUnsupportedException(
        'Native media embeddings require guarded mtmd encoding (v0.7.0-1).',
      );
    }
    final status = api.mtmdEncodeChunk(projector, chunk);
    if (status != 0) {
      failures.throwIfCaught(
        'mtmd_encode_chunk',
        LlamaInferenceException.new,
        freeOnly: [projector],
      );
      throw LlamaInferenceException('Media embedding encoding failed');
    }
  }

  /// Allocates an extended batch while protecting its context.
  Pointer<llama_batch_ext> createEmbeddingBatch(
    Pointer<llama_context> context,
  ) {
    final batch = mixedBatch!.init(context);
    if (batch == nullptr) {
      failures.throwIfCaught(
        'llama_batch_ext_init',
        LlamaInferenceException.new,
        freeOnly: [context],
      );
      throw LlamaInferenceException('Mixed embedding batch allocation failed');
    }
    return batch;
  }

  /// One guarded, synchronized DECODE of a complete noncausal input.
  void processEmbeddingBatch(
    Pointer<llama_context> context,
    Pointer<llama_batch_ext> batch,
  ) {
    final status = mixedBatch!.process(
      context,
      llama_dart_process_type.LLAMA_DART_PROCESS_TYPE_DECODE.value,
      batch,
    );
    if (status != 0) {
      failures.throwIfCaught(
        'llama_process',
        LlamaInferenceException.new,
        freeOnly: [context],
      );
      if (status ==
          llama_dart_process_status
              .LLAMA_DART_PROCESS_STATUS_UNSUPPORTED
              .value) {
        throw LlamaUnsupportedException(
          'Native mixed embedding DECODE requires v0.7.0-1.',
        );
      }
      throw LlamaInferenceException('Mixed embedding forward pass failed');
    }
  }

  LlamaCppObjectCalls._({
    required this.exit,
    required this.failures,
    required this.loadModel,
    required this.freeModel,
    required this.modelFreeAddress,
    required this.createContext,
    required this.freeContext,
    required this.contextFreeAddress,
    required this.decode,
    required this.encode,
    required this.synchronize,
    required this.samplerSample,
    required this.samplerAccept,
    required this.samplerInitGrammarLazyPatterns,
    required this.tokenize,
    required this.tokenToPiece,
    required this.memoryClear,
    required this.stateSaveFile,
    required this.stateLoadFile,
    required this.stateSeqGetSizeExt,
    required this.stateSeqGetDataExt,
    required this.stateSeqSetDataExt,
    required this.adapterLoraInit,
    LlamaCppMixedBatchApi? Function()? mixedBatchResolver,
    int Function(Pointer<llama_model>)? modelInputWidth,
  }) : _mixedBatchResolver = mixedBatchResolver,
       _modelInputWidth = modelInputWidth ?? llama_model_n_embd_inp;

  /// The tracked and guarded functions of [exit].
  ///
  /// With [barrier], the calls that used to reach an upstream function that
  /// throws go through its wrappers, and every call reports a caught
  /// exception as a typed error. [isWindows] selects the stricter rule for
  /// the objects of a failed call (see [NativeCallFailures]).
  factory LlamaCppObjectCalls.tracked(
    ExitTeardownApi exit, {
    NativeBarrierApi? barrier,
    bool isWindows = false,
    LlamaCppMixedBatchApi? Function()? mixedBatchResolver,
    int Function(Pointer<llama_model>)? modelInputWidth,
  }) {
    final failures = NativeCallFailures(barrier, isWindows: isWindows);
    return LlamaCppObjectCalls._(
      exit: exit,
      failures: failures,
      mixedBatchResolver: mixedBatchResolver,
      modelInputWidth: modelInputWidth,
      loadModel: (path, params) {
        final model = exit.modelLoadFromFile(path, params);
        if (model == nullptr) {
          failures.throwIfCaught(
            'llama_model_load_from_file',
            LlamaModelException.new,
          );
        }
        return model;
      },
      freeModel: (model) {
        failures.forget(model);
        exit.free(model.cast());
      },
      modelFreeAddress: exit.freeAddress,
      createContext: (model, params) {
        final context = exit.initFromModel(model, params);
        if (context == nullptr) {
          failures.throwIfCaught(
            'llama_init_from_model',
            LlamaContextException.new,
            windowsFreeOnly: [model],
          );
        }
        return context;
      },
      freeContext: (context) {
        failures.forget(context);
        exit.free(context.cast());
      },
      contextFreeAddress: exit.freeAddress,
      decode: (ctx, batch) {
        final status = exit.decode(ctx, batch);
        if (status == _statusException) {
          failures.throwIfCaught(
            'llama_decode',
            LlamaInferenceException.new,
            freeOnly: [ctx],
          );
        }
        return status;
      },
      encode: (ctx, batch) {
        final status = exit.encode(ctx, batch);
        if (status == _statusException) {
          failures.throwIfCaught(
            'llama_encode',
            LlamaInferenceException.new,
            freeOnly: [ctx],
          );
        }
        return status;
      },
      synchronize: (ctx) {
        exit.synchronize(ctx);
        failures.throwIfCaught(
          'llama_synchronize',
          LlamaInferenceException.new,
          freeOnly: [ctx],
        );
      },
      samplerSample: (sampler, ctx, index) {
        final token = exit.samplerSample(sampler, ctx, index);
        if (token == LLAMA_TOKEN_NULL) {
          failures.throwIfCaught(
            'llama_sampler_sample',
            LlamaInferenceException.new,
            windowsFreeOnly: [ctx],
          );
        }
        return token;
      },
      samplerAccept: barrier == null
          ? llama_sampler_accept
          : (sampler, token) {
              if (!barrier.samplerAccept(sampler, token)) {
                failures.throwIfCaught(
                  'llama_sampler_accept',
                  LlamaInferenceException.new,
                );
              }
            },
      samplerInitGrammarLazyPatterns: barrier == null
          ? llama_sampler_init_grammar_lazy_patterns
          : (
              vocab,
              grammar,
              grammarRoot,
              triggerPatterns,
              triggerPatternCount,
              triggerTokens,
              triggerTokenCount,
            ) {
              final sampler = barrier.samplerInitGrammarLazyPatterns(
                vocab,
                grammar,
                grammarRoot,
                triggerPatterns,
                triggerPatternCount,
                triggerTokens,
                triggerTokenCount,
              );
              if (sampler == nullptr) {
                failures.throwIfCaught(
                  'llama_sampler_init_grammar_lazy_patterns',
                  LlamaInferenceException.new,
                  windowsFreeOnly: [vocab],
                );
              }
              return sampler;
            },
      tokenize: barrier == null
          ? llama_tokenize
          : (
              vocab,
              text,
              textLength,
              tokens,
              tokenCapacity,
              addSpecial,
              parseSpecial,
            ) {
              final count = barrier.tokenize(
                vocab,
                text,
                textLength,
                tokens,
                tokenCapacity,
                addSpecial,
                parseSpecial,
              );
              if (count == _statusException) {
                failures.throwIfCaught(
                  'llama_tokenize',
                  LlamaInferenceException.new,
                  windowsFreeOnly: [vocab],
                );
              }
              return count;
            },
      tokenToPiece: barrier == null
          ? llama_token_to_piece
          : (vocab, token, buffer, length, lstrip, special) {
              final count = barrier.tokenToPiece(
                vocab,
                token,
                buffer,
                length,
                lstrip,
                special,
              );
              if (count == _statusException) {
                failures.throwIfCaught(
                  'llama_token_to_piece',
                  LlamaInferenceException.new,
                  windowsFreeOnly: [vocab],
                );
              }
              return count;
            },
      memoryClear: barrier == null
          ? (ctx, memory, data) => llama_memory_clear(memory, data)
          : (ctx, memory, data) {
              if (!barrier.memoryClear(memory, data)) {
                failures.throwIfCaught(
                  'llama_memory_clear',
                  LlamaInferenceException.new,
                  freeOnly: [ctx],
                );
              }
            },
      stateSaveFile: (ctx, path, tokens, tokenCount) {
        final saved = exit.stateSaveFile(ctx, path, tokens, tokenCount);
        if (!saved) {
          failures.throwIfCaught(
            'llama_state_save_file',
            LlamaStateException.new,
            freeOnly: [ctx],
          );
        }
        return saved;
      },
      stateLoadFile: (ctx, path, tokensOut, tokenCapacity, tokenCountOut) {
        final loaded = exit.stateLoadFile(
          ctx,
          path,
          tokensOut,
          tokenCapacity,
          tokenCountOut,
        );
        if (!loaded) {
          failures.throwIfCaught(
            'llama_state_load_file',
            LlamaStateException.new,
            freeOnly: [ctx],
          );
        }
        return loaded;
      },
      stateSeqGetSizeExt: (ctx, seqId, flags) {
        final size = exit.stateSeqGetSizeExt(ctx, seqId, flags);
        if (size == 0) {
          failures.throwIfCaught(
            'llama_state_seq_get_size_ext',
            LlamaStateException.new,
            freeOnly: [ctx],
          );
        }
        return size;
      },
      stateSeqGetDataExt: (ctx, dst, size, seqId, flags) {
        final written = exit.stateSeqGetDataExt(ctx, dst, size, seqId, flags);
        if (written == 0) {
          failures.throwIfCaught(
            'llama_state_seq_get_data_ext',
            LlamaStateException.new,
            freeOnly: [ctx],
          );
        }
        return written;
      },
      stateSeqSetDataExt: (ctx, src, size, seqId, flags) {
        final read = exit.stateSeqSetDataExt(ctx, src, size, seqId, flags);
        if (read == 0) {
          failures.throwIfCaught(
            'llama_state_seq_set_data_ext',
            LlamaStateException.new,
            freeOnly: [ctx],
          );
        }
        return read;
      },
      adapterLoraInit: (model, path) {
        final adapter = exit.adapterLoraInit(model, path);
        if (adapter == nullptr) {
          failures.throwIfCaught(
            'llama_adapter_lora_init',
            LlamaModelException.new,
            freeOnly: [model],
          );
        }
        return adapter;
      },
    );
  }

  /// The upstream llama.cpp functions; nothing is tracked.
  static final LlamaCppObjectCalls upstream = LlamaCppObjectCalls.untracked();

  /// Calls llama.cpp directly, as [upstream] does; tests replace its
  /// [decode], [encode] and [synchronize].
  ///
  /// An asynchronous backend such as Metal may still be computing when
  /// [decode] or [encode] returns. The calls made through these wait for it
  /// with [synchronize] before they return, as the tracked calls do, so the
  /// duration of an evaluation includes the backend's work.
  factory LlamaCppObjectCalls.untracked({
    int Function(Pointer<llama_context> ctx, llama_batch batch) decode =
        llama_decode,
    int Function(Pointer<llama_context> ctx, llama_batch batch) encode =
        llama_encode,
    void Function(Pointer<llama_context> ctx) synchronize = llama_synchronize,
  }) => LlamaCppObjectCalls._(
    exit: null,
    failures: NativeCallFailures(null, isWindows: false),
    loadModel: llama_model_load_from_file,
    freeModel: llama_model_free,
    modelFreeAddress:
        Native.addressOf<NativeFunction<Void Function(Pointer<llama_model>)>>(
          llama_model_free,
        ).cast(),
    createContext: llama_init_from_model,
    freeContext: llama_free,
    contextFreeAddress:
        Native.addressOf<NativeFunction<Void Function(Pointer<llama_context>)>>(
          llama_free,
        ).cast(),
    decode: (ctx, batch) {
      final status = decode(ctx, batch);
      synchronize(ctx);
      return status;
    },
    encode: (ctx, batch) {
      final status = encode(ctx, batch);
      synchronize(ctx);
      return status;
    },
    synchronize: synchronize,
    samplerSample: llama_sampler_sample,
    samplerAccept: llama_sampler_accept,
    samplerInitGrammarLazyPatterns: llama_sampler_init_grammar_lazy_patterns,
    tokenize: llama_tokenize,
    tokenToPiece: llama_token_to_piece,
    memoryClear: (ctx, memory, data) => llama_memory_clear(memory, data),
    stateSaveFile: llama_state_save_file,
    stateLoadFile: llama_state_load_file,
    stateSeqGetSizeExt: llama_state_seq_get_size_ext,
    stateSeqGetDataExt: llama_state_seq_get_data_ext,
    stateSeqSetDataExt: llama_state_seq_set_data_ext,
    adapterLoraInit: llama_adapter_lora_init,
  );

  /// [LlamaCppObjectCalls.tracked] when the loaded runtime exports the whole
  /// [ExitTeardownApi], with the [NativeBarrierApi] when it exports that too;
  /// otherwise [upstream].
  ///
  /// [isWindows] selects the asset the functions are bound to and the rule
  /// for the objects of a failed call. [symbol] replaces the lookup of both
  /// APIs, as in [ExitTeardownApi.tryResolve].
  static LlamaCppObjectCalls resolve({
    required bool isWindows,
    Pointer<NativeType> Function(String name)? symbol,
    LlamaCppMixedBatchApi? Function()? mixedBatchResolver,
  }) {
    final exit = ExitTeardownApi.tryResolve(
      isWindows: isWindows,
      symbol: symbol,
    );
    if (exit == null) return upstream;
    return LlamaCppObjectCalls.tracked(
      exit,
      barrier: NativeBarrierApi.tryResolve(
        isWindows: isWindows,
        symbol: symbol,
      ),
      isWindows: isWindows,
      mixedBatchResolver: mixedBatchResolver,
    );
  }

  /// The exit-teardown functions these calls go through, or `null` for
  /// [upstream].
  final ExitTeardownApi? exit;

  /// The C++ exceptions these calls caught and the objects they left
  /// free-only. Reports nothing without an exception barrier.
  final NativeCallFailures failures;

  /// Loads a model; `nullptr` on failure.
  final Pointer<llama_model> Function(
    Pointer<Char> path,
    llama_model_params params,
  )
  loadModel;

  /// Frees a model [loadModel] returned.
  final void Function(Pointer<llama_model> model) freeModel;

  /// The function `IsolateShutdownReleases` frees a model with.
  final Pointer<NativeFinalizerFunction> modelFreeAddress;

  /// Creates a context; `nullptr` on failure.
  final Pointer<llama_context> Function(
    Pointer<llama_model> model,
    llama_context_params params,
  )
  createContext;

  /// Frees a context [createContext] returned.
  final void Function(Pointer<llama_context> context) freeContext;

  /// The function `IsolateShutdownReleases` frees a context with.
  final Pointer<NativeFinalizerFunction> contextFreeAddress;

  /// `llama_decode`, returning once the backend has finished the batch.
  final int Function(Pointer<llama_context> ctx, llama_batch batch) decode;

  /// `llama_encode`, returning once the backend has finished the batch.
  final int Function(Pointer<llama_context> ctx, llama_batch batch) encode;

  /// `llama_synchronize`.
  final void Function(Pointer<llama_context> ctx) synchronize;

  /// `llama_sampler_sample`.
  final int Function(
    Pointer<llama_sampler> sampler,
    Pointer<llama_context> ctx,
    int index,
  )
  samplerSample;

  /// `llama_sampler_accept`.
  final void Function(Pointer<llama_sampler> sampler, int token) samplerAccept;

  /// `llama_sampler_init_grammar_lazy_patterns`; `nullptr` for a grammar that
  /// does not parse.
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

  /// `llama_tokenize`.
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

  /// `llama_token_to_piece`.
  final int Function(
    Pointer<llama_vocab> vocab,
    int token,
    Pointer<Char> buffer,
    int length,
    int lstrip,
    bool special,
  )
  tokenToPiece;

  /// `llama_memory_clear` on the memory of [ctx].
  final void Function(
    Pointer<llama_context> ctx,
    llama_memory_t memory,
    bool data,
  )
  memoryClear;

  /// `llama_state_save_file`.
  final bool Function(
    Pointer<llama_context> ctx,
    Pointer<Char> path,
    Pointer<llama_token> tokens,
    int tokenCount,
  )
  stateSaveFile;

  /// `llama_state_load_file`.
  final bool Function(
    Pointer<llama_context> ctx,
    Pointer<Char> path,
    Pointer<llama_token> tokensOut,
    int tokenCapacity,
    Pointer<Size> tokenCountOut,
  )
  stateLoadFile;

  /// `llama_state_seq_get_size_ext`.
  final int Function(Pointer<llama_context> ctx, int seqId, int flags)
  stateSeqGetSizeExt;

  /// `llama_state_seq_get_data_ext`.
  final int Function(
    Pointer<llama_context> ctx,
    Pointer<Uint8> dst,
    int size,
    int seqId,
    int flags,
  )
  stateSeqGetDataExt;

  /// `llama_state_seq_set_data_ext`.
  final int Function(
    Pointer<llama_context> ctx,
    Pointer<Uint8> src,
    int size,
    int seqId,
    int flags,
  )
  stateSeqSetDataExt;

  /// `llama_adapter_lora_init`.
  final Pointer<llama_adapter_lora> Function(
    Pointer<llama_model> model,
    Pointer<Char> path,
  )
  adapterLoraInit;
}

Pointer<NativeType> _bindingsSymbol(String symbol) => switch (symbol) {
  'llama_dart_exit_track' => Native.addressOf<NativeFunction<_TrackNative>>(
    llama_dart_exit_track,
  ),
  'llama_dart_exit_untrack' => Native.addressOf<NativeFunction<_UntrackNative>>(
    llama_dart_exit_untrack,
  ),
  'llama_dart_exit_free' => Native.addressOf<NativeFunction<_FreeNative>>(
    llama_dart_exit_free,
  ),
  'llama_dart_model_load_from_file' =>
    Native.addressOf<NativeFunction<_ModelLoadNative>>(
      llama_dart_model_load_from_file,
    ),
  'llama_dart_init_from_model' =>
    Native.addressOf<NativeFunction<_InitFromModelNative>>(
      llama_dart_init_from_model,
    ),
  'llama_dart_mtmd_init_from_file' =>
    Native.addressOf<NativeFunction<_MtmdInitNative>>(
      llama_dart_mtmd_init_from_file,
    ),
  'llama_dart_decode' => Native.addressOf<NativeFunction<_DecodeNative>>(
    llama_dart_decode,
  ),
  'llama_dart_encode' => Native.addressOf<NativeFunction<_DecodeNative>>(
    llama_dart_encode,
  ),
  'llama_dart_synchronize' =>
    Native.addressOf<NativeFunction<_SynchronizeNative>>(
      llama_dart_synchronize,
    ),
  'llama_dart_sampler_sample' =>
    Native.addressOf<NativeFunction<_SamplerSampleNative>>(
      llama_dart_sampler_sample,
    ),
  'llama_dart_state_save_file' =>
    Native.addressOf<NativeFunction<_StateSaveFileNative>>(
      llama_dart_state_save_file,
    ),
  'llama_dart_state_load_file' =>
    Native.addressOf<NativeFunction<_StateLoadFileNative>>(
      llama_dart_state_load_file,
    ),
  'llama_dart_state_seq_get_size_ext' =>
    Native.addressOf<NativeFunction<_StateSeqSizeNative>>(
      llama_dart_state_seq_get_size_ext,
    ),
  'llama_dart_state_seq_get_data_ext' =>
    Native.addressOf<NativeFunction<_StateSeqDataNative>>(
      llama_dart_state_seq_get_data_ext,
    ),
  'llama_dart_state_seq_set_data_ext' =>
    Native.addressOf<NativeFunction<_StateSeqDataNative>>(
      llama_dart_state_seq_set_data_ext,
    ),
  'llama_dart_adapter_lora_init' =>
    Native.addressOf<NativeFunction<_AdapterLoraInitNative>>(
      llama_dart_adapter_lora_init,
    ),
  'llama_dart_mtmd_tokenize' =>
    Native.addressOf<NativeFunction<_MtmdTokenizeNative>>(
      llama_dart_mtmd_tokenize,
    ),
  'llama_dart_mtmd_encode_chunk' =>
    Native.addressOf<NativeFunction<_MtmdEncodeChunkNative>>(
      llama_dart_mtmd_encode_chunk,
    ),
  'llama_dart_mtmd_helper_eval_chunks' =>
    Native.addressOf<NativeFunction<_MtmdEvalChunksNative>>(
      llama_dart_mtmd_helper_eval_chunks,
    ),
  'llama_dart_mtmd_helper_eval_chunk_single' =>
    Native.addressOf<NativeFunction<_MtmdEvalChunkSingleNative>>(
      llama_dart_mtmd_helper_eval_chunk_single,
    ),
  'llama_dart_mtmd_helper_decode_image_chunk' =>
    Native.addressOf<NativeFunction<_MtmdDecodeImageChunkNative>>(
      llama_dart_mtmd_helper_decode_image_chunk,
    ),
  'llama_dart_ggml_backend_sched_graph_compute' =>
    Native.addressOf<NativeFunction<_SchedGraphComputeNative>>(
      _schedGraphCompute,
    ),
  _ => throw ArgumentError.value(symbol, 'symbol', 'not bound'),
};

Pointer<NativeType> _wrapperAssetSymbol(String symbol) => switch (symbol) {
  'llama_dart_exit_track' => Native.addressOf<NativeFunction<_TrackNative>>(
    _wrapperTrack,
  ),
  'llama_dart_exit_untrack' => Native.addressOf<NativeFunction<_UntrackNative>>(
    _wrapperUntrack,
  ),
  'llama_dart_exit_free' => Native.addressOf<NativeFunction<_FreeNative>>(
    _wrapperFree,
  ),
  'llama_dart_model_load_from_file' =>
    Native.addressOf<NativeFunction<_ModelLoadNative>>(_wrapperModelLoad),
  'llama_dart_init_from_model' =>
    Native.addressOf<NativeFunction<_InitFromModelNative>>(
      _wrapperInitFromModel,
    ),
  'llama_dart_mtmd_init_from_file' =>
    Native.addressOf<NativeFunction<_MtmdInitNative>>(_wrapperMtmdInit),
  'llama_dart_decode' => Native.addressOf<NativeFunction<_DecodeNative>>(
    _wrapperDecode,
  ),
  'llama_dart_encode' => Native.addressOf<NativeFunction<_DecodeNative>>(
    _wrapperEncode,
  ),
  'llama_dart_synchronize' =>
    Native.addressOf<NativeFunction<_SynchronizeNative>>(_wrapperSynchronize),
  'llama_dart_sampler_sample' =>
    Native.addressOf<NativeFunction<_SamplerSampleNative>>(
      _wrapperSamplerSample,
    ),
  'llama_dart_state_save_file' =>
    Native.addressOf<NativeFunction<_StateSaveFileNative>>(
      _wrapperStateSaveFile,
    ),
  'llama_dart_state_load_file' =>
    Native.addressOf<NativeFunction<_StateLoadFileNative>>(
      _wrapperStateLoadFile,
    ),
  'llama_dart_state_seq_get_size_ext' =>
    Native.addressOf<NativeFunction<_StateSeqSizeNative>>(
      _wrapperStateSeqGetSizeExt,
    ),
  'llama_dart_state_seq_get_data_ext' =>
    Native.addressOf<NativeFunction<_StateSeqDataNative>>(
      _wrapperStateSeqGetDataExt,
    ),
  'llama_dart_state_seq_set_data_ext' =>
    Native.addressOf<NativeFunction<_StateSeqDataNative>>(
      _wrapperStateSeqSetDataExt,
    ),
  'llama_dart_adapter_lora_init' =>
    Native.addressOf<NativeFunction<_AdapterLoraInitNative>>(
      _wrapperAdapterLoraInit,
    ),
  'llama_dart_mtmd_tokenize' =>
    Native.addressOf<NativeFunction<_MtmdTokenizeNative>>(_wrapperMtmdTokenize),
  'llama_dart_mtmd_encode_chunk' =>
    Native.addressOf<NativeFunction<_MtmdEncodeChunkNative>>(
      _wrapperMtmdEncodeChunk,
    ),
  'llama_dart_mtmd_helper_eval_chunks' =>
    Native.addressOf<NativeFunction<_MtmdEvalChunksNative>>(
      _wrapperMtmdEvalChunks,
    ),
  'llama_dart_mtmd_helper_eval_chunk_single' =>
    Native.addressOf<NativeFunction<_MtmdEvalChunkSingleNative>>(
      _wrapperMtmdEvalChunkSingle,
    ),
  'llama_dart_mtmd_helper_decode_image_chunk' =>
    Native.addressOf<NativeFunction<_MtmdDecodeImageChunkNative>>(
      _wrapperMtmdDecodeImageChunk,
    ),
  'llama_dart_ggml_backend_sched_graph_compute' =>
    Native.addressOf<NativeFunction<_SchedGraphComputeNative>>(
      _wrapperSchedGraphCompute,
    ),
  _ => throw ArgumentError.value(symbol, 'symbol', 'not bound'),
};

// The generated binding converts the result to a `ggml_status`, which throws
// for a value this package does not know.
@Native<_SchedGraphComputeNative>(
  assetId: _llamadartAsset,
  symbol: 'llama_dart_ggml_backend_sched_graph_compute',
)
external int _schedGraphCompute(
  ggml_backend_sched_t sched,
  Pointer<ggml_cgraph> graph,
);

@Native<_TrackNative>(assetId: _wrapperAsset, symbol: 'llama_dart_exit_track')
external bool _wrapperTrack(
  Pointer<Void> object,
  Pointer<NativeFunction<_FreeNative>> free,
  int stage,
);

@Native<_FreeNative>(assetId: _wrapperAsset, symbol: 'llama_dart_exit_free')
external void _wrapperFree(Pointer<Void> object);

@Native<_UntrackNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_exit_untrack',
)
external bool _wrapperUntrack(Pointer<Void> object);

@Native<_ModelLoadNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_model_load_from_file',
)
external Pointer<llama_model> _wrapperModelLoad(
  Pointer<Char> path,
  llama_model_params params,
);

@Native<_InitFromModelNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_init_from_model',
)
external Pointer<llama_context> _wrapperInitFromModel(
  Pointer<llama_model> model,
  llama_context_params params,
);

@Native<_MtmdInitNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_mtmd_init_from_file',
)
external Pointer<mtmd_context> _wrapperMtmdInit(
  Pointer<Char> path,
  Pointer<llama_model> model,
  Pointer<mtmd_context_params> params,
);

@Native<_DecodeNative>(assetId: _wrapperAsset, symbol: 'llama_dart_decode')
external int _wrapperDecode(Pointer<llama_context> ctx, llama_batch batch);

@Native<_DecodeNative>(assetId: _wrapperAsset, symbol: 'llama_dart_encode')
external int _wrapperEncode(Pointer<llama_context> ctx, llama_batch batch);

@Native<_SynchronizeNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_synchronize',
)
external void _wrapperSynchronize(Pointer<llama_context> ctx);

@Native<_SamplerSampleNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_sampler_sample',
)
external int _wrapperSamplerSample(
  Pointer<llama_sampler> sampler,
  Pointer<llama_context> ctx,
  int index,
);

@Native<_StateSaveFileNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_state_save_file',
)
external bool _wrapperStateSaveFile(
  Pointer<llama_context> ctx,
  Pointer<Char> path,
  Pointer<llama_token> tokens,
  int tokenCount,
);

@Native<_StateLoadFileNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_state_load_file',
)
external bool _wrapperStateLoadFile(
  Pointer<llama_context> ctx,
  Pointer<Char> path,
  Pointer<llama_token> tokensOut,
  int tokenCapacity,
  Pointer<Size> tokenCountOut,
);

@Native<_StateSeqSizeNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_state_seq_get_size_ext',
)
external int _wrapperStateSeqGetSizeExt(
  Pointer<llama_context> ctx,
  int seqId,
  int flags,
);

@Native<_StateSeqDataNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_state_seq_get_data_ext',
)
external int _wrapperStateSeqGetDataExt(
  Pointer<llama_context> ctx,
  Pointer<Uint8> dst,
  int size,
  int seqId,
  int flags,
);

@Native<_StateSeqDataNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_state_seq_set_data_ext',
)
external int _wrapperStateSeqSetDataExt(
  Pointer<llama_context> ctx,
  Pointer<Uint8> src,
  int size,
  int seqId,
  int flags,
);

@Native<_AdapterLoraInitNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_adapter_lora_init',
)
external Pointer<llama_adapter_lora> _wrapperAdapterLoraInit(
  Pointer<llama_model> model,
  Pointer<Char> path,
);

@Native<_MtmdTokenizeNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_mtmd_tokenize',
)
external int _wrapperMtmdTokenize(
  Pointer<mtmd_context> ctx,
  Pointer<mtmd_input_chunks> output,
  Pointer<mtmd_input_text> text,
  Pointer<Pointer<mtmd_bitmap>> bitmaps,
  int bitmapCount,
);

@Native<_MtmdEncodeChunkNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_mtmd_encode_chunk',
)
external int _wrapperMtmdEncodeChunk(
  Pointer<mtmd_context> ctx,
  Pointer<mtmd_input_chunk> chunk,
);

@Native<_MtmdEvalChunksNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_mtmd_helper_eval_chunks',
)
external int _wrapperMtmdEvalChunks(
  Pointer<mtmd_context> ctx,
  Pointer<llama_context> lctx,
  Pointer<mtmd_input_chunks> chunks,
  int nPast,
  int seqId,
  int nBatch,
  bool logitsLast,
  Pointer<llama_pos> newNPast,
);

@Native<_MtmdEvalChunkSingleNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_mtmd_helper_eval_chunk_single',
)
external int _wrapperMtmdEvalChunkSingle(
  Pointer<mtmd_context> ctx,
  Pointer<llama_context> lctx,
  Pointer<mtmd_input_chunk> chunk,
  int nPast,
  int seqId,
  int nBatch,
  bool logitsLast,
  Pointer<llama_pos> newNPast,
);

@Native<_MtmdDecodeImageChunkNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_mtmd_helper_decode_image_chunk',
)
external int _wrapperMtmdDecodeImageChunk(
  Pointer<mtmd_context> ctx,
  Pointer<llama_context> lctx,
  Pointer<mtmd_input_chunk> chunk,
  Pointer<Float> encodedEmbd,
  int nPast,
  int seqId,
  int nBatch,
  Pointer<llama_pos> newNPast,
  LlamaDartPostDecodeCallback callback,
  Pointer<Void> userData,
);

@Native<_SchedGraphComputeNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_ggml_backend_sched_graph_compute',
)
external int _wrapperSchedGraphCompute(
  ggml_backend_sched_t sched,
  Pointer<ggml_cgraph> graph,
);

typedef _MixedInitNative =
    Pointer<llama_batch_ext> Function(Pointer<llama_context>);
typedef _MixedProcessNative =
    Int32 Function(Pointer<llama_context>, Int32, Pointer<llama_batch_ext>);

/// Optional guarded mixed-batch ABI, resolved without weakening the old ABI probe.
final class LlamaCppMixedBatchApi {
  /// Creates resolved functions (also usable by recording tests).
  const LlamaCppMixedBatchApi({
    required this.init,
    required this.process,
    this.setOutput = llama_set_embeddings,
    this.setOutputRow = llama_batch_ext_set_output_embd,
    this.addToken = llama_batch_ext_add_token,
    this.addEmbedding = llama_batch_ext_add_embd,
    this.setPosition = llama_batch_ext_set_pos,
    this.free = llama_batch_ext_free,
    this.projectorUsesMrope = mtmd_decode_use_mrope,
    this.audioSampleRate = mtmd_get_audio_sample_rate,
    this.mediaOutput = mtmd_get_output_embd,
    this.tokenCount = mtmd_helper_get_n_tokens,
    this.chunksSize = mtmd_input_chunks_size,
    this.chunksGet = mtmd_input_chunks_get,
    this.chunkType = raw_bindings.mtmd_input_chunk_get_type_raw,
    this.chunkTokenCount = mtmd_input_chunk_get_n_tokens,
    this.chunkTokens = mtmd_input_chunk_get_tokens_text,
    this.bitmapIsAudio = mtmd_bitmap_is_audio,
  });

  /// `llama_set_embeddings`.
  final void Function(Pointer<llama_context>, bool) setOutput;

  /// `llama_batch_ext_set_output_embd`.
  final bool Function(Pointer<llama_batch_ext>, int, bool) setOutputRow;

  /// `llama_batch_ext_add_token`.
  final int Function(Pointer<llama_batch_ext>, int, int) addToken;

  /// `llama_batch_ext_add_embd`.
  final int Function(Pointer<llama_batch_ext>, int, llama_embd) addEmbedding;

  /// `llama_batch_ext_set_pos`.
  final bool Function(Pointer<llama_batch_ext>, int, Pointer<llama_pos>)
  setPosition;

  /// `llama_batch_ext_free`.
  final void Function(Pointer<llama_batch_ext>) free;

  /// `mtmd_decode_use_mrope`.
  final bool Function(Pointer<mtmd_context>) projectorUsesMrope;

  /// `mtmd_get_audio_sample_rate`.
  final int Function(Pointer<mtmd_context>) audioSampleRate;

  /// `mtmd_get_output_embd`.
  final Pointer<Float> Function(Pointer<mtmd_context>) mediaOutput;

  /// `mtmd_helper_get_n_tokens`.
  final int Function(Pointer<mtmd_input_chunks>) tokenCount;

  /// `mtmd_input_chunks_size`.
  final int Function(Pointer<mtmd_input_chunks>) chunksSize;

  /// `mtmd_input_chunks_get`.
  final Pointer<mtmd_input_chunk> Function(Pointer<mtmd_input_chunks>, int)
  chunksGet;

  /// `mtmd_input_chunk_get_type`.
  final int Function(Pointer<mtmd_input_chunk>) chunkType;

  /// `mtmd_input_chunk_get_n_tokens`.
  final int Function(Pointer<mtmd_input_chunk>) chunkTokenCount;

  /// `mtmd_input_chunk_get_tokens_text`.
  final Pointer<llama_token> Function(Pointer<mtmd_input_chunk>, Pointer<Size>)
  chunkTokens;

  /// `mtmd_bitmap_is_audio`.
  final bool Function(Pointer<mtmd_bitmap>) bitmapIsAudio;

  /// Guarded extended-batch allocation.
  final Pointer<llama_batch_ext> Function(Pointer<llama_context>) init;

  /// Guarded and synchronized mixed processing.
  final int Function(Pointer<llama_context>, int, Pointer<llama_batch_ext>)
  process;

  /// Resolves both wrappers and all upstream mixed/mtmd accessors used with them.
  ///
  /// On Windows, [mtmdSymbol] reuses the service's resolved mtmd library;
  /// standalone probes use the hook's mtmd asset. Calls retain the probed
  /// addresses so split-library resolution also applies during execution.
  static LlamaCppMixedBatchApi? tryResolve({
    Pointer<NativeType> Function(String)? symbol,
    bool isWindows = false,
    Pointer<NativeType> Function(String)? mtmdSymbol,
  }) {
    try {
      final resolve =
          symbol ??
          (name) =>
              _mixedSymbol(name, isWindows: isWindows, mtmdSymbol: mtmdSymbol);
      final init = resolve('llama_dart_batch_ext_init')
          .cast<NativeFunction<_MixedInitNative>>()
          .asFunction<
            Pointer<llama_batch_ext> Function(Pointer<llama_context>)
          >();
      final process = resolve('llama_dart_process')
          .cast<NativeFunction<_MixedProcessNative>>()
          .asFunction<
            int Function(Pointer<llama_context>, int, Pointer<llama_batch_ext>)
          >();
      return LlamaCppMixedBatchApi(
        init: init,
        process: process,
        setOutput: resolve('llama_set_embeddings')
            .cast<NativeFunction<Void Function(Pointer<llama_context>, Bool)>>()
            .asFunction<void Function(Pointer<llama_context>, bool)>(),
        setOutputRow: resolve('llama_batch_ext_set_output_embd')
            .cast<
              NativeFunction<
                Bool Function(Pointer<llama_batch_ext>, Int32, Bool)
              >
            >()
            .asFunction<bool Function(Pointer<llama_batch_ext>, int, bool)>(),
        addToken: resolve('llama_batch_ext_add_token')
            .cast<
              NativeFunction<
                Int32 Function(Pointer<llama_batch_ext>, Int32, Int32)
              >
            >()
            .asFunction<int Function(Pointer<llama_batch_ext>, int, int)>(),
        addEmbedding: resolve('llama_batch_ext_add_embd')
            .cast<
              NativeFunction<
                Int32 Function(Pointer<llama_batch_ext>, Int32, llama_embd)
              >
            >()
            .asFunction<
              int Function(Pointer<llama_batch_ext>, int, llama_embd)
            >(),
        setPosition: resolve('llama_batch_ext_set_pos')
            .cast<
              NativeFunction<
                Bool Function(
                  Pointer<llama_batch_ext>,
                  Int32,
                  Pointer<llama_pos>,
                )
              >
            >()
            .asFunction<
              bool Function(Pointer<llama_batch_ext>, int, Pointer<llama_pos>)
            >(),
        free: resolve('llama_batch_ext_free')
            .cast<NativeFunction<Void Function(Pointer<llama_batch_ext>)>>()
            .asFunction<void Function(Pointer<llama_batch_ext>)>(),
        projectorUsesMrope: resolve('mtmd_decode_use_mrope')
            .cast<NativeFunction<Bool Function(Pointer<mtmd_context>)>>()
            .asFunction<bool Function(Pointer<mtmd_context>)>(),
        audioSampleRate: resolve('mtmd_get_audio_sample_rate')
            .cast<NativeFunction<Int Function(Pointer<mtmd_context>)>>()
            .asFunction<int Function(Pointer<mtmd_context>)>(),
        mediaOutput: resolve('mtmd_get_output_embd')
            .cast<
              NativeFunction<Pointer<Float> Function(Pointer<mtmd_context>)>
            >()
            .asFunction<Pointer<Float> Function(Pointer<mtmd_context>)>(),
        tokenCount: resolve('mtmd_helper_get_n_tokens')
            .cast<NativeFunction<Size Function(Pointer<mtmd_input_chunks>)>>()
            .asFunction<int Function(Pointer<mtmd_input_chunks>)>(),
        chunksSize: resolve('mtmd_input_chunks_size')
            .cast<NativeFunction<Size Function(Pointer<mtmd_input_chunks>)>>()
            .asFunction<int Function(Pointer<mtmd_input_chunks>)>(),
        chunksGet: resolve('mtmd_input_chunks_get')
            .cast<
              NativeFunction<
                Pointer<mtmd_input_chunk> Function(
                  Pointer<mtmd_input_chunks>,
                  Size,
                )
              >
            >()
            .asFunction<
              Pointer<mtmd_input_chunk> Function(
                Pointer<mtmd_input_chunks>,
                int,
              )
            >(),
        chunkType: resolve('mtmd_input_chunk_get_type')
            .cast<
              NativeFunction<UnsignedInt Function(Pointer<mtmd_input_chunk>)>
            >()
            .asFunction<int Function(Pointer<mtmd_input_chunk>)>(),
        chunkTokenCount: resolve('mtmd_input_chunk_get_n_tokens')
            .cast<NativeFunction<Size Function(Pointer<mtmd_input_chunk>)>>()
            .asFunction<int Function(Pointer<mtmd_input_chunk>)>(),
        chunkTokens: resolve('mtmd_input_chunk_get_tokens_text')
            .cast<
              NativeFunction<
                Pointer<llama_token> Function(
                  Pointer<mtmd_input_chunk>,
                  Pointer<Size>,
                )
              >
            >()
            .asFunction<
              Pointer<llama_token> Function(
                Pointer<mtmd_input_chunk>,
                Pointer<Size>,
              )
            >(),
        bitmapIsAudio: resolve('mtmd_bitmap_is_audio')
            .cast<NativeFunction<Bool Function(Pointer<mtmd_bitmap>)>>()
            .asFunction<bool Function(Pointer<mtmd_bitmap>)>(),
      );
    } on ArgumentError {
      return null;
    }
  }
}

Pointer<NativeType> _mixedSymbol(
  String name, {
  required bool isWindows,
  Pointer<NativeType> Function(String)? mtmdSymbol,
  Pointer<NativeType> Function(String library, String name)? lookup,
}) {
  final library = !isWindows || name.startsWith('llama_dart_')
      ? 'llamadart.dll'
      : name.startsWith('mtmd_')
      ? 'mtmd.dll'
      : 'llama.dll';
  if (lookup != null) return lookup(library, name);
  if (library == 'mtmd.dll') {
    return (mtmdSymbol ?? _windowsMixedSymbol)(name);
  }
  return switch (name) {
    'llama_dart_batch_ext_init' =>
      isWindows
          ? Native.addressOf<NativeFunction<_MixedInitNative>>(
              _wrapperMixedInit,
            )
          : Native.addressOf<NativeFunction<_MixedInitNative>>(
              llama_dart_batch_ext_init,
            ),
    'llama_dart_process' =>
      isWindows
          ? Native.addressOf<NativeFunction<_MixedProcessNative>>(
              _wrapperMixedProcess,
            )
          : Native.addressOf<NativeFunction<_MixedProcessNative>>(
              llama_dart_process,
            ),
    'llama_set_embeddings' =>
      Native.addressOf<
        NativeFunction<Void Function(Pointer<llama_context>, Bool)>
      >(llama_set_embeddings),
    'llama_batch_ext_set_output_embd' =>
      Native.addressOf<
        NativeFunction<Bool Function(Pointer<llama_batch_ext>, Int32, Bool)>
      >(llama_batch_ext_set_output_embd),
    'llama_batch_ext_add_token' =>
      Native.addressOf<
        NativeFunction<Int32 Function(Pointer<llama_batch_ext>, Int32, Int32)>
      >(llama_batch_ext_add_token),
    'llama_batch_ext_add_embd' =>
      Native.addressOf<
        NativeFunction<
          Int32 Function(Pointer<llama_batch_ext>, Int32, llama_embd)
        >
      >(llama_batch_ext_add_embd),
    'llama_batch_ext_set_pos' =>
      Native.addressOf<
        NativeFunction<
          Bool Function(Pointer<llama_batch_ext>, Int32, Pointer<llama_pos>)
        >
      >(llama_batch_ext_set_pos),
    'llama_batch_ext_free' =>
      Native.addressOf<NativeFunction<Void Function(Pointer<llama_batch_ext>)>>(
        llama_batch_ext_free,
      ),
    'mtmd_decode_use_mrope' =>
      Native.addressOf<NativeFunction<Bool Function(Pointer<mtmd_context>)>>(
        mtmd_decode_use_mrope,
      ),
    'mtmd_get_audio_sample_rate' =>
      Native.addressOf<NativeFunction<Int Function(Pointer<mtmd_context>)>>(
        mtmd_get_audio_sample_rate,
      ),
    'mtmd_get_output_embd' =>
      Native.addressOf<
        NativeFunction<Pointer<Float> Function(Pointer<mtmd_context>)>
      >(mtmd_get_output_embd),
    'mtmd_helper_get_n_tokens' =>
      Native.addressOf<
        NativeFunction<Size Function(Pointer<mtmd_input_chunks>)>
      >(mtmd_helper_get_n_tokens),
    'mtmd_input_chunks_size' =>
      Native.addressOf<
        NativeFunction<Size Function(Pointer<mtmd_input_chunks>)>
      >(mtmd_input_chunks_size),
    'mtmd_input_chunks_get' =>
      Native.addressOf<
        NativeFunction<
          Pointer<mtmd_input_chunk> Function(Pointer<mtmd_input_chunks>, Size)
        >
      >(mtmd_input_chunks_get),
    'mtmd_input_chunk_get_type' =>
      Native.addressOf<
        NativeFunction<UnsignedInt Function(Pointer<mtmd_input_chunk>)>
      >(raw_bindings.mtmd_input_chunk_get_type_raw),
    'mtmd_input_chunk_get_n_tokens' =>
      Native.addressOf<
        NativeFunction<Size Function(Pointer<mtmd_input_chunk>)>
      >(mtmd_input_chunk_get_n_tokens),
    'mtmd_input_chunk_get_tokens_text' =>
      Native.addressOf<
        NativeFunction<
          Pointer<llama_token> Function(
            Pointer<mtmd_input_chunk>,
            Pointer<Size>,
          )
        >
      >(mtmd_input_chunk_get_tokens_text),
    'mtmd_bitmap_is_audio' =>
      Native.addressOf<NativeFunction<Bool Function(Pointer<mtmd_bitmap>)>>(
        mtmd_bitmap_is_audio,
      ),
    _ => throw ArgumentError('Unknown mixed embedding symbol'),
  };
}

Pointer<NativeType> _windowsMixedSymbol(String name) => switch (name) {
  'mtmd_decode_use_mrope' =>
    Native.addressOf<NativeFunction<Bool Function(Pointer<mtmd_context>)>>(
      _windowsMixedProjectorUsesMrope,
    ),
  'mtmd_get_audio_sample_rate' =>
    Native.addressOf<NativeFunction<Int Function(Pointer<mtmd_context>)>>(
      _windowsMixedAudioSampleRate,
    ),
  'mtmd_get_output_embd' =>
    Native.addressOf<
      NativeFunction<Pointer<Float> Function(Pointer<mtmd_context>)>
    >(_windowsMixedMediaOutput),
  'mtmd_helper_get_n_tokens' =>
    Native.addressOf<NativeFunction<Size Function(Pointer<mtmd_input_chunks>)>>(
      _windowsMixedTokenCount,
    ),
  'mtmd_input_chunks_size' =>
    Native.addressOf<NativeFunction<Size Function(Pointer<mtmd_input_chunks>)>>(
      _windowsMixedChunksSize,
    ),
  'mtmd_input_chunks_get' =>
    Native.addressOf<
      NativeFunction<
        Pointer<mtmd_input_chunk> Function(Pointer<mtmd_input_chunks>, Size)
      >
    >(_windowsMixedChunksGet),
  'mtmd_input_chunk_get_type' =>
    Native.addressOf<
      NativeFunction<UnsignedInt Function(Pointer<mtmd_input_chunk>)>
    >(_windowsMixedChunkType),
  'mtmd_input_chunk_get_n_tokens' =>
    Native.addressOf<NativeFunction<Size Function(Pointer<mtmd_input_chunk>)>>(
      _windowsMixedChunkTokenCount,
    ),
  'mtmd_input_chunk_get_tokens_text' =>
    Native.addressOf<
      NativeFunction<
        Pointer<llama_token> Function(Pointer<mtmd_input_chunk>, Pointer<Size>)
      >
    >(_windowsMixedChunkTokens),
  'mtmd_bitmap_is_audio' =>
    Native.addressOf<NativeFunction<Bool Function(Pointer<mtmd_bitmap>)>>(
      _windowsMixedBitmapIsAudio,
    ),
  _ => throw ArgumentError('Unknown Windows mtmd embedding symbol'),
};

@Native<Bool Function(Pointer<mtmd_context>)>(
  assetId: 'package:llamadart/mtmd',
  symbol: 'mtmd_decode_use_mrope',
)
external bool _windowsMixedProjectorUsesMrope(Pointer<mtmd_context> arg0);

@Native<Int Function(Pointer<mtmd_context>)>(
  assetId: 'package:llamadart/mtmd',
  symbol: 'mtmd_get_audio_sample_rate',
)
external int _windowsMixedAudioSampleRate(Pointer<mtmd_context> arg0);

@Native<Pointer<Float> Function(Pointer<mtmd_context>)>(
  assetId: 'package:llamadart/mtmd',
  symbol: 'mtmd_get_output_embd',
)
external Pointer<Float> _windowsMixedMediaOutput(Pointer<mtmd_context> arg0);

@Native<Size Function(Pointer<mtmd_input_chunks>)>(
  assetId: 'package:llamadart/mtmd',
  symbol: 'mtmd_helper_get_n_tokens',
)
external int _windowsMixedTokenCount(Pointer<mtmd_input_chunks> arg0);

@Native<Size Function(Pointer<mtmd_input_chunks>)>(
  assetId: 'package:llamadart/mtmd',
  symbol: 'mtmd_input_chunks_size',
)
external int _windowsMixedChunksSize(Pointer<mtmd_input_chunks> arg0);

@Native<Pointer<mtmd_input_chunk> Function(Pointer<mtmd_input_chunks>, Size)>(
  assetId: 'package:llamadart/mtmd',
  symbol: 'mtmd_input_chunks_get',
)
external Pointer<mtmd_input_chunk> _windowsMixedChunksGet(
  Pointer<mtmd_input_chunks> arg0,
  int arg1,
);

@Native<UnsignedInt Function(Pointer<mtmd_input_chunk>)>(
  assetId: 'package:llamadart/mtmd',
  symbol: 'mtmd_input_chunk_get_type',
)
external int _windowsMixedChunkType(Pointer<mtmd_input_chunk> arg0);

@Native<Size Function(Pointer<mtmd_input_chunk>)>(
  assetId: 'package:llamadart/mtmd',
  symbol: 'mtmd_input_chunk_get_n_tokens',
)
external int _windowsMixedChunkTokenCount(Pointer<mtmd_input_chunk> arg0);

@Native<
  Pointer<llama_token> Function(Pointer<mtmd_input_chunk>, Pointer<Size>)
>(assetId: 'package:llamadart/mtmd', symbol: 'mtmd_input_chunk_get_tokens_text')
external Pointer<llama_token> _windowsMixedChunkTokens(
  Pointer<mtmd_input_chunk> arg0,
  Pointer<Size> arg1,
);

@Native<Bool Function(Pointer<mtmd_bitmap>)>(
  assetId: 'package:llamadart/mtmd',
  symbol: 'mtmd_bitmap_is_audio',
)
external bool _windowsMixedBitmapIsAudio(Pointer<mtmd_bitmap> arg0);

@Native<_MixedInitNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_batch_ext_init',
)
external Pointer<llama_batch_ext> _wrapperMixedInit(
  Pointer<llama_context> context,
);

@Native<_MixedProcessNative>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_process',
)
external int _wrapperMixedProcess(
  Pointer<llama_context> context,
  int type,
  Pointer<llama_batch_ext> batch,
);

/// Runs [read], which calls the reranker symbols, and turns the
/// [ArgumentError] of a runtime that does not export them into a
/// [LlamaUnsupportedException] naming the runtime that does.
T requireRerankingSymbols<T>(T Function() read) {
  try {
    return read();
  } on ArgumentError {
    throw LlamaUnsupportedException(
      'Native reranking requires classifier metadata and named-template symbols from the pinned llama.cpp runtime ($llamaCppTag).',
    );
  }
}
