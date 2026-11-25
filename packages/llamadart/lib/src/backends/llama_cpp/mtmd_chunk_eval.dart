import 'dart:ffi';

import 'bindings.dart';
import 'exit_teardown_api.dart';
import 'llama_cpp_raw_bindings.dart' as raw_bindings;

typedef _ChunksSizeNative = Size Function(Pointer<mtmd_input_chunks>);
typedef _ChunksSizeDart = int Function(Pointer<mtmd_input_chunks>);
typedef _ChunksGetNative =
    Pointer<mtmd_input_chunk> Function(Pointer<mtmd_input_chunks>, Size);
typedef _ChunksGetDart =
    Pointer<mtmd_input_chunk> Function(Pointer<mtmd_input_chunks>, int);
typedef _ChunkTypeNative = UnsignedInt Function(Pointer<mtmd_input_chunk>);
typedef _ChunkTypeDart = int Function(Pointer<mtmd_input_chunk>);
typedef _ChunkTokenCountNative = Size Function(Pointer<mtmd_input_chunk>);
typedef _ChunkTokenCountDart = int Function(Pointer<mtmd_input_chunk>);
typedef _DecodeUseNonCausalNative =
    Bool Function(Pointer<mtmd_context>, Pointer<mtmd_input_chunk>);
typedef _DecodeUseNonCausalDart =
    bool Function(Pointer<mtmd_context>, Pointer<mtmd_input_chunk>);
typedef _EvalChunkSingleNative =
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
typedef _EvalChunkSingleDart =
    int Function(
      Pointer<mtmd_context>,
      Pointer<llama_context>,
      Pointer<mtmd_input_chunk>,
      int,
      int,
      int,
      bool,
      Pointer<llama_pos>,
    );
typedef _EncodeChunkNative =
    Int32 Function(Pointer<mtmd_context>, Pointer<mtmd_input_chunk>);
typedef _EncodeChunkDart =
    int Function(Pointer<mtmd_context>, Pointer<mtmd_input_chunk>);
typedef _OutputEmbdNative = Pointer<Float> Function(Pointer<mtmd_context>);
typedef _OutputEmbdDart = Pointer<Float> Function(Pointer<mtmd_context>);
typedef _DecodeImageChunkNative =
    Int32 Function(
      Pointer<mtmd_context>,
      Pointer<llama_context>,
      Pointer<mtmd_input_chunk>,
      Pointer<Float>,
      llama_pos,
      llama_seq_id,
      Int32,
      Pointer<llama_pos>,
      mtmd_helper_post_decode_callback,
      Pointer<Void>,
    );
typedef _DecodeImageChunkDart =
    int Function(
      Pointer<mtmd_context>,
      Pointer<llama_context>,
      Pointer<mtmd_input_chunk>,
      Pointer<Float>,
      int,
      int,
      int,
      Pointer<llama_pos>,
      mtmd_helper_post_decode_callback,
      Pointer<Void>,
    );

int _primaryDecodeImageChunk(
  Pointer<mtmd_context> ctx,
  Pointer<llama_context> lctx,
  Pointer<mtmd_input_chunk> chunk,
  Pointer<Float> encodedEmbd,
  int nPast,
  int seqId,
  int nBatch,
  Pointer<llama_pos> newNPast,
) => mtmd_helper_decode_image_chunk(
  ctx,
  lctx,
  chunk,
  encodedEmbd,
  nPast,
  seqId,
  nBatch,
  newNPast,
  nullptr,
  nullptr,
);

/// The mtmd functions [evalMtmdChunksUntilCancelled] and
/// [findMtmdChunkAboveMicroBatch] call, resolved from one library.
final class MtmdChunkEvalApi {
  /// Creates an API from resolved functions.
  const MtmdChunkEvalApi({
    required this.chunksSize,
    required this.chunksGet,
    required this.chunkType,
    required this.chunkTokenCount,
    required this.decodeUseNonCausal,
    required this.evalChunkSingle,
    required this.encodeChunk,
    required this.outputEmbd,
    required this.decodeImageChunk,
  });

  /// The `package:llamadart/llamadart` asset's bindings.
  static const MtmdChunkEvalApi primary = MtmdChunkEvalApi(
    chunksSize: mtmd_input_chunks_size,
    chunksGet: mtmd_input_chunks_get,
    chunkType: raw_bindings.mtmd_input_chunk_get_type_raw,
    chunkTokenCount: mtmd_input_chunk_get_n_tokens,
    decodeUseNonCausal: mtmd_decode_use_non_causal,
    evalChunkSingle: mtmd_helper_eval_chunk_single,
    encodeChunk: mtmd_encode_chunk,
    outputEmbd: mtmd_get_output_embd,
    decodeImageChunk: _primaryDecodeImageChunk,
  );

  /// Resolves every function from [library], or returns `null` if any symbol
  /// is missing.
  static MtmdChunkEvalApi? tryLoad(DynamicLibrary library) {
    try {
      final decodeImageChunk = library
          .lookupFunction<_DecodeImageChunkNative, _DecodeImageChunkDart>(
            'mtmd_helper_decode_image_chunk',
          );
      return MtmdChunkEvalApi(
        chunksSize: library.lookupFunction<_ChunksSizeNative, _ChunksSizeDart>(
          'mtmd_input_chunks_size',
        ),
        chunksGet: library.lookupFunction<_ChunksGetNative, _ChunksGetDart>(
          'mtmd_input_chunks_get',
        ),
        chunkType: library.lookupFunction<_ChunkTypeNative, _ChunkTypeDart>(
          'mtmd_input_chunk_get_type',
        ),
        chunkTokenCount: library
            .lookupFunction<_ChunkTokenCountNative, _ChunkTokenCountDart>(
              'mtmd_input_chunk_get_n_tokens',
            ),
        decodeUseNonCausal: library
            .lookupFunction<_DecodeUseNonCausalNative, _DecodeUseNonCausalDart>(
              'mtmd_decode_use_non_causal',
            ),
        evalChunkSingle: library
            .lookupFunction<_EvalChunkSingleNative, _EvalChunkSingleDart>(
              'mtmd_helper_eval_chunk_single',
            ),
        encodeChunk: library
            .lookupFunction<_EncodeChunkNative, _EncodeChunkDart>(
              'mtmd_encode_chunk',
            ),
        outputEmbd: library.lookupFunction<_OutputEmbdNative, _OutputEmbdDart>(
          'mtmd_get_output_embd',
        ),
        decodeImageChunk:
            (ctx, lctx, chunk, encodedEmbd, nPast, seqId, nBatch, newNPast) =>
                decodeImageChunk(
                  ctx,
                  lctx,
                  chunk,
                  encodedEmbd,
                  nPast,
                  seqId,
                  nBatch,
                  newNPast,
                  nullptr,
                  nullptr,
                ),
      );
    } on ArgumentError {
      return null;
    }
  }

  /// This API with its encode, decode and eval calls made through [exit], so
  /// exit teardown waits for them.
  MtmdChunkEvalApi withExitTeardown(ExitTeardownApi exit) => MtmdChunkEvalApi(
    chunksSize: chunksSize,
    chunksGet: chunksGet,
    chunkType: chunkType,
    chunkTokenCount: chunkTokenCount,
    decodeUseNonCausal: decodeUseNonCausal,
    evalChunkSingle: exit.mtmdHelperEvalChunkSingle,
    encodeChunk: exit.mtmdEncodeChunk,
    outputEmbd: outputEmbd,
    decodeImageChunk:
        (ctx, lctx, chunk, encodedEmbd, nPast, seqId, nBatch, newNPast) =>
            exit.mtmdHelperDecodeImageChunk(
              ctx,
              lctx,
              chunk,
              encodedEmbd,
              nPast,
              seqId,
              nBatch,
              newNPast,
              nullptr,
              nullptr,
            ),
  );

  /// `mtmd_input_chunks_size`.
  final int Function(Pointer<mtmd_input_chunks> chunks) chunksSize;

  /// `mtmd_input_chunks_get`.
  final Pointer<mtmd_input_chunk> Function(
    Pointer<mtmd_input_chunks> chunks,
    int index,
  )
  chunksGet;

  /// `mtmd_input_chunk_get_type`, as its raw enum value.
  final int Function(Pointer<mtmd_input_chunk> chunk) chunkType;

  /// `mtmd_input_chunk_get_n_tokens`.
  final int Function(Pointer<mtmd_input_chunk> chunk) chunkTokenCount;

  /// `mtmd_decode_use_non_causal`.
  final bool Function(
    Pointer<mtmd_context> ctx,
    Pointer<mtmd_input_chunk> chunk,
  )
  decodeUseNonCausal;

  /// `mtmd_helper_eval_chunk_single`.
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
  evalChunkSingle;

  /// `mtmd_encode_chunk`.
  final int Function(Pointer<mtmd_context> ctx, Pointer<mtmd_input_chunk> chunk)
  encodeChunk;

  /// `mtmd_get_output_embd`.
  final Pointer<Float> Function(Pointer<mtmd_context> ctx) outputEmbd;

  /// `mtmd_helper_decode_image_chunk` without a post-decode callback, whose
  /// type differs between upstream and libllamadart.
  final int Function(
    Pointer<mtmd_context> ctx,
    Pointer<llama_context> lctx,
    Pointer<mtmd_input_chunk> chunk,
    Pointer<Float> encodedEmbd,
    int nPast,
    int seqId,
    int nBatch,
    Pointer<llama_pos> newNPast,
  )
  decodeImageChunk;
}

/// The native call that failed for one prompt chunk.
enum MtmdChunkEvalStage {
  /// `mtmd_encode_chunk` on an image or audio chunk.
  encode,

  /// `mtmd_helper_decode_image_chunk` on an image or audio chunk.
  decode,

  /// `mtmd_helper_eval_chunk_single` on any other chunk.
  eval,
}

/// A nonzero native result for one prompt chunk.
final class MtmdChunkEvalFailure {
  /// Creates a failure of [stage] on chunk [chunkIndex].
  const MtmdChunkEvalFailure({
    required this.stage,
    required this.chunkIndex,
    required this.chunkType,
    required this.result,
  });

  /// The call that returned [result].
  final MtmdChunkEvalStage stage;

  /// The chunk's index in the prompt.
  final int chunkIndex;

  /// The chunk's raw `mtmd_input_chunk_type` value.
  final int chunkType;

  /// The nonzero native result.
  final int result;

  /// Names the failed call and the chunk, as `failed to decode image chunk 7`
  /// or `failed to eval chunk 3`.
  @override
  String toString() => stage == MtmdChunkEvalStage.eval
      ? 'failed to eval chunk $chunkIndex'
      : 'failed to ${stage.name} $_media chunk $chunkIndex';

  String get _media => mtmdMediaChunkName(chunkType);
}

/// `image` or `audio`, for the raw `mtmd_input_chunk_type` of a media chunk.
String mtmdMediaChunkName(int chunkType) =>
    chunkType == mtmd_input_chunk_type.MTMD_INPUT_CHUNK_TYPE_IMAGE.value
    ? 'image'
    : 'audio';

bool _isMediaChunk(int chunkType) =>
    chunkType == mtmd_input_chunk_type.MTMD_INPUT_CHUNK_TYPE_IMAGE.value ||
    chunkType == mtmd_input_chunk_type.MTMD_INPUT_CHUNK_TYPE_AUDIO.value;

/// Returns the first image or audio chunk of [chunks] that [ctx] decodes with
/// non-causal attention and that has more than [maxTokens] tokens, as its
/// raw `mtmd_input_chunk_type` and token count, otherwise `null`.
///
/// llama.cpp cannot split such a chunk across micro-batches:
/// `mtmd_helper_decode_image_chunk` turns causal attention off and splits the
/// chunk only by its `n_batch` argument, and `llama_context::decode` aborts
/// on a non-causal batch above `n_ubatch`. Pass `n_ubatch` as [maxTokens].
({int chunkType, int tokenCount})? findMtmdChunkAboveMicroBatch(
  MtmdChunkEvalApi api,
  Pointer<mtmd_context> ctx,
  Pointer<mtmd_input_chunks> chunks,
  int maxTokens,
) {
  final nChunks = api.chunksSize(chunks);
  for (var i = 0; i < nChunks; i++) {
    final chunk = api.chunksGet(chunks, i);
    final type = api.chunkType(chunk);
    if (!_isMediaChunk(type)) continue;
    final tokenCount = api.chunkTokenCount(chunk);
    if (tokenCount > maxTokens && api.decodeUseNonCausal(ctx, chunk)) {
      return (chunkType: type, tokenCount: tokenCount);
    }
  }
  return null;
}

/// Evaluates [chunks] as `mtmd_helper_eval_chunks` does for `n_past` 0,
/// `seq_id` 0 and `logits_last` true, but stops early once [cancelToken]
/// reads 1.
///
/// The token is read before each chunk. An image or audio chunk's encode and
/// embedding decode are separate calls, and the token is read between them.
/// Returns the first nonzero native result as an [MtmdChunkEvalFailure],
/// otherwise `null`. After a `null`, [newNPast] holds the position after the
/// last fully evaluated chunk.
///
/// [onChunkEvaluated] receives the token count of each fully evaluated chunk,
/// which differs from its positions on M-RoPE projectors.
MtmdChunkEvalFailure? evalMtmdChunksUntilCancelled(
  MtmdChunkEvalApi api,
  Pointer<mtmd_context> ctx,
  Pointer<llama_context> lctx,
  Pointer<mtmd_input_chunks> chunks,
  int nBatch,
  Pointer<llama_pos> newNPast,
  Pointer<Int8> cancelToken, {
  void Function(int tokenCount)? onChunkEvaluated,
}) {
  final nChunks = api.chunksSize(chunks);
  var nPast = 0;
  for (var i = 0; i < nChunks; i++) {
    if (cancelToken.value == 1) break;
    final chunk = api.chunksGet(chunks, i);
    final type = api.chunkType(chunk);
    MtmdChunkEvalStage stage;
    int result;
    if (_isMediaChunk(type)) {
      stage = MtmdChunkEvalStage.encode;
      result = api.encodeChunk(ctx, chunk);
      if (result == 0) {
        if (cancelToken.value == 1) break;
        stage = MtmdChunkEvalStage.decode;
        result = api.decodeImageChunk(
          ctx,
          lctx,
          chunk,
          api.outputEmbd(ctx),
          nPast,
          0,
          nBatch,
          newNPast,
        );
      }
    } else {
      stage = MtmdChunkEvalStage.eval;
      newNPast.value = nPast;
      result = api.evalChunkSingle(
        ctx,
        lctx,
        chunk,
        nPast,
        0,
        nBatch,
        i == nChunks - 1,
        newNPast,
      );
    }
    if (result != 0) {
      return MtmdChunkEvalFailure(
        stage: stage,
        chunkIndex: i,
        chunkType: type,
        result: result,
      );
    }
    nPast = newNPast.value;
    onChunkEvaluated?.call(api.chunkTokenCount(chunk));
  }
  newNPast.value = nPast;
  return null;
}
