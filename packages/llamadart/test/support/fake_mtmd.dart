import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/mtmd_chunk_eval.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';

/// Records a completed mtmd fallback lookup in the service's current directory.
///
/// A null [api] simulates absence without reopening a real library against fake
/// projector pointers when backend initialization has discovered a directory.
void setMtmdFallbackForTesting(LlamaCppService service, Object? api) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  final mirror = reflect(service);
  Symbol private(String name) => MirrorSystem.getSymbol(name, owner);
  mirror.setField(private('_mtmdFallbackLookupAttempted'), true);
  mirror.setField(
    private('_mtmdFallbackLookupDirectory'),
    mirror.getField(private('_backendModuleDirectory')).reflectee,
  );
  mirror.setField(private('_mtmdFallbackApi'), api);
}

/// What a [FakeMtmd] with chunk-level functions presents its media part as.
enum FakeMtmdChunk {
  /// A text chunk.
  text,

  /// An image chunk the projector decodes causally.
  causalImage,

  /// An image chunk the projector decodes non-causally.
  nonCausalImage,
}

/// Stands in for libmtmd through [service]'s fallback API: a projector whose
/// one media part evaluates [tokens] as text. It reports an audio encoder and
/// no vision encoder unless told otherwise.
///
/// With an image [chunk] the chunk-level functions present the part as an
/// image chunk of [tokens]. A non-causal one is decoded with causal attention
/// off, as `mtmd_helper_decode_image_chunk` does.
///
/// It records the upstream mtmd function behind each call that creates,
/// tokenizes with, evaluates with or frees the projector. A service on the
/// tracked calls makes those through its `ExitTeardownApi` instead, so they
/// do not reach this fake.
final class FakeMtmd {
  /// Puts [service] on a fallback API backed by this fake. With [chunkEval]
  /// the fallback has the chunk-level functions and presents the prompt as
  /// one text chunk; without it the service evaluates all chunks in one call.
  FakeMtmd.install(
    this.service, {
    required this.tokens,
    this.chunkEval = false,
    this.chunk = FakeMtmdChunk.text,
    this.chunkTokenCount,
    this.chunkCount = 1,
    this.decode = llama_decode,
    this.audioBitmap = _audioBitmap,
    this.vision = false,
    this.audio = true,
  }) {
    final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
    final apiClass =
        owner.declarations[MirrorSystem.getSymbol('_MtmdApi', owner)]
            as ClassMirror;
    mtmd_helper_bitmap_wrapper encodedBitmap() {
      final wrapper = Struct.create<mtmd_helper_bitmap_wrapper>();
      if (encodedBitmapLoads) wrapper.bitmap = _encodedBitmap;
      return wrapper;
    }

    _api = apiClass.newInstance(Symbol.empty, const [], {
      #defaultMarker: () => _marker.cast<Char>(),
      #contextParamsDefault: () => Struct.create<mtmd_context_params>(),
      #initFromFile:
          (Pointer<Char> _, Pointer<llama_model> _, mtmd_context_params _) {
            calls.add('mtmd_init_from_file');
            return projector;
          },
      #free: (Pointer<mtmd_context> _) {
        calls.add('mtmd_free');
      },
      // llama_dart_exit_free ignores a pointer that is not tracked, so a
      // projector still held when its isolate ends is left alone.
      #freeAddress: ExitTeardownApi.tryResolve(
        isWindows: Platform.isWindows,
      )!.freeAddress,
      #inputChunksInit: () => Pointer<mtmd_input_chunks>.fromAddress(0x10),
      #inputChunksFree: (Pointer<mtmd_input_chunks> _) {},
      #helperInitOptDefault: () => Struct.create<mtmd_helper_init_opt>(),
      #helperBitmapInitFromFile:
          (
            Pointer<mtmd_context> _,
            Pointer<Char> _,
            bool _,
            mtmd_helper_init_opt _,
          ) => encodedBitmap(),
      #helperBitmapInitFromBuf:
          (
            Pointer<mtmd_context> _,
            Pointer<UnsignedChar> _,
            int _,
            bool _,
            mtmd_helper_init_opt _,
          ) => encodedBitmap(),
      #bitmapInitFromAudio: (int sampleCount, Pointer<Float> _) =>
          audioBitmap(sampleCount),
      #supportsVision: (Pointer<mtmd_context> _) => vision,
      #supportsAudio: (Pointer<mtmd_context> _) => audio,
      #supportsVideo: (Pointer<mtmd_context> _) => false,
      #bitmapFree: (Pointer<mtmd_bitmap> bitmap) {
        freedBitmaps.add(bitmap.address);
      },
      #tokenize:
          (
            Pointer<mtmd_context> _,
            Pointer<mtmd_input_chunks> _,
            Pointer<mtmd_input_text> text,
            Pointer<Pointer<mtmd_bitmap>> _,
            int _,
          ) {
            calls.add('mtmd_tokenize');
            prompts.add(
              text.ref.text.cast<Utf8>().toDartString(
                length: text.ref.text_len,
              ),
            );
            return tokenizeResult;
          },
      #helperEvalChunks:
          (
            Pointer<mtmd_context> _,
            Pointer<llama_context> context,
            Pointer<mtmd_input_chunks> _,
            int nPast,
            int _,
            int nBatch,
            bool _,
            Pointer<llama_pos> newNPast,
          ) {
            calls.add('mtmd_helper_eval_chunks');
            return evalMedia(context, nPast, nBatch, newNPast);
          },
      #chunkEval: chunkEval ? _chunkEvalApi : null,
      #logSet: null,
      #helperLogSet: null,
    }).reflectee;
    _setPrivate('_mtmdPrimarySymbolsUnavailable', true);
    setMtmdFallbackForTesting(service, _api);
  }

  late final Object _api;

  /// The projector the fake `mtmd_init_from_file` returns.
  static final Pointer<mtmd_context> projector = Pointer.fromAddress(0x30);

  /// The service this fake is installed in.
  final LlamaCppService service;

  /// The token ids the media part evaluates to.
  final List<int> tokens;

  /// Whether the fallback has the chunk-level functions.
  final bool chunkEval;

  /// What the chunk-level functions present the media part as.
  final FakeMtmdChunk chunk;

  /// The token count the chunk-level functions report for the media part,
  /// otherwise the length of [tokens], its positions. A larger count stands
  /// in for an M-RoPE image, which has fewer positions than tokens.
  final int? chunkTokenCount;

  /// How many chunks the chunk-level functions present the media part as,
  /// each evaluating [tokens].
  final int chunkCount;

  /// The decode call the media evaluation makes.
  final int Function(Pointer<llama_context> context, llama_batch batch) decode;

  /// The bitmap the fake `mtmd_bitmap_init_from_audio` returns for an audio
  /// part of a sample count; a null pointer fails that part.
  final Pointer<mtmd_bitmap> Function(int sampleCount) audioBitmap;

  /// Whether the fake `mtmd_support_vision` reports a vision encoder.
  final bool vision;

  /// Whether the fake `mtmd_support_audio` reports an audio encoder.
  final bool audio;

  /// Whether the fake bitmap helpers load a path or encoded bytes; when
  /// false they return a null bitmap, as mtmd does for a source it cannot
  /// decode and for audio on a projector without an audio encoder.
  bool encodedBitmapLoads = true;

  /// What the fake `mtmd_tokenize` returns; mtmd returns 2 for a bitmap the
  /// projector has no encoder for.
  int tokenizeResult = 0;

  /// Upstream mtmd functions called on the projector so far, in order.
  final List<String> calls = <String>[];

  /// Addresses passed to the fake `mtmd_bitmap_free` so far, in order.
  final List<int> freedBitmaps = <int>[];

  /// The prompt text of each fake `mtmd_tokenize` call so far, in order.
  final List<String> prompts = <String>[];

  /// Media evaluations so far, through this fake or an `ExitTeardownApi`
  /// given [evalMedia].
  int evaluations = 0;

  final Pointer<Utf8> _marker = '<__media__>'.toNativeUtf8();

  /// One media part for a prompt holding the media marker.
  List<LlamaContentPart> get parts => [
    LlamaAudioContent(samples: Float32List(1)),
  ];

  late final MtmdChunkEvalApi _chunkEvalApi = MtmdChunkEvalApi(
    chunksSize: (_) => chunkCount,
    chunksGet: (_, _) => Pointer<mtmd_input_chunk>.fromAddress(0x40),
    chunkType: (_) => chunk == FakeMtmdChunk.text
        ? mtmd_input_chunk_type.MTMD_INPUT_CHUNK_TYPE_TEXT.value
        : mtmd_input_chunk_type.MTMD_INPUT_CHUNK_TYPE_IMAGE.value,
    chunkTokenCount: (_) => chunkTokenCount ?? tokens.length,
    decodeUseNonCausal: (_, _) => chunk == FakeMtmdChunk.nonCausalImage,
    evalChunkSingle: (_, context, _, nPast, _, nBatch, _, newNPast) {
      calls.add('mtmd_helper_eval_chunk_single');
      return evalMedia(context, nPast, nBatch, newNPast);
    },
    encodeChunk: (_, _) {
      calls.add('mtmd_encode_chunk');
      return 0;
    },
    outputEmbd: (_) => nullptr,
    decodeImageChunk: (_, context, _, _, nPast, _, nBatch, newNPast) {
      calls.add('mtmd_helper_decode_image_chunk');
      final nonCausal = chunk == FakeMtmdChunk.nonCausalImage;
      if (nonCausal) llama_set_causal_attn(context, false);
      try {
        return evalMedia(context, nPast, nBatch, newNPast);
      } finally {
        if (nonCausal) llama_set_causal_attn(context, true);
      }
    },
  );

  /// Decodes [tokens] on [context] from [nPast] in batches of [nBatch].
  int evalMedia(
    Pointer<llama_context> context,
    int nPast,
    int nBatch,
    Pointer<llama_pos> newNPast,
  ) {
    evaluations++;
    final ids = malloc<llama_token>(tokens.length);
    try {
      ids.asTypedList(tokens.length).setAll(0, tokens);
      for (var start = 0; start < tokens.length; start += nBatch) {
        final count = min(nBatch, tokens.length - start);
        final result = decode(context, llama_batch_get_one(ids + start, count));
        if (result != 0) return result;
      }
      newNPast.value = nPast + tokens.length;
      return 0;
    } finally {
      malloc.free(ids);
    }
  }

  static Pointer<mtmd_bitmap> _audioBitmap(int _) => Pointer.fromAddress(0x20);

  /// The bitmap the fake gives an encoded image or audio part.
  static final Pointer<mtmd_bitmap> _encodedBitmap = Pointer.fromAddress(0x21);

  /// Leaves [service] with neither its own mtmd functions nor a fallback
  /// library, as a native runtime that lacks them does, when [present] is
  /// false; puts this fake back when it is true.
  void setFallback({required bool present}) =>
      setMtmdFallbackForTesting(service, present ? _api : null);

  /// Frees the marker text; call after the service is disposed.
  void dispose() => malloc.free(_marker);

  void _setPrivate(String field, Object? value) {
    final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
    reflect(service).setField(MirrorSystem.getSymbol(field, owner), value);
  }
}
