@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

import '../../../support/fake_mtmd.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _params = ModelParams(gpuLayers: 0, contextSize: 64);

// Runs the real llama.cpp runtime on the CPU and watches the native memory a
// service owns besides its tracked objects: a context's sampler chain, token
// batches and media bitmaps.
void main() {
  late Directory dir;
  late String modelPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_native_release_');
    addTearDown(() => dir.deleteSync(recursive: true));
    modelPath = writeSyntheticLlamaGguf('${dir.path}/model.gguf').path;
  });

  test('dispose frees the sampler chain and the batch of a context that is '
      'still open', () {
    final samplerFrees = _SamplerFrees();
    addTearDown(samplerFrees.close);
    final batches = _LiveBlocks();
    final service = LlamaCppService(contextBatchAllocator: batches)
      ..initializeBackend();
    addTearDown(service.dispose);
    final context = service.createContext(
      service.loadModel(modelPath, _params),
      _params,
    );
    samplerFrees.watch(_samplerChain(service, context));
    expect(batches.live, hasLength(1));

    service.dispose();

    expect(samplerFrees.count, 1);
    expect(batches.live, isEmpty);
    expect(batches.frees, 1);
  });

  test('frees only the bitmaps it created when a later media part '
      'fails', () async {
    // Part i has i + 1 samples, which is how the fake tells the parts apart.
    const failingPart = 1;
    Pointer<mtmd_bitmap> bitmapOf(int part) =>
        Pointer.fromAddress(0x1000 + part);
    final parts = [
      for (var part = 0; part < 8; part++)
        LlamaAudioContent(samples: Float32List(part + 1)),
    ];
    final service = LlamaCppService(objectCalls: LlamaCppObjectCalls.upstream)
      ..initializeBackend();
    final fake = FakeMtmd.install(
      service,
      tokens: const [],
      audioBitmap: (sampleCount) =>
          sampleCount - 1 == failingPart ? nullptr : bitmapOf(sampleCount - 1),
    );
    addTearDown(fake.dispose);
    addTearDown(service.dispose);
    final model = service.loadModel(modelPath, _params);
    final context = service.createContext(model, _params);
    final projectorPath = '${dir.path}/mmproj.gguf';
    File(projectorPath).writeAsStringSync('GGUF');
    service.createMultimodalContext(model, projectorPath);
    _scribbleFreedBlocks(parts.length * sizeOf<Pointer<mtmd_bitmap>>());

    await expectLater(
      _generate(service, context, '<__media__>' * parts.length, parts),
      throwsA(
        predicate(
          (error) =>
              '$error'.contains('Failed to load media part $failingPart'),
        ),
      ),
    );

    expect(fake.freedBitmaps, [bitmapOf(0).address]);
  });

  test('embed leaves no batch allocated when the model reports no embedding '
      'size', () {
    final real = ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!;
    final batches = _LiveBatches();
    final service = LlamaCppService(
      objectCalls: LlamaCppObjectCalls.tracked(
        _withModelLoad(
          real,
          // A vocabulary-only load reads no embedding size from the file.
          (path, params) =>
              real.modelLoadFromFile(path, params..vocab_only = true),
        ),
      ),
      batchInit: batches.init,
      batchFree: batches.free,
    )..initializeBackend();
    addTearDown(service.dispose);
    final context = service.createContext(
      service.loadModel(modelPath, _params),
      _params,
    );
    final liveBefore = batches.live.toList();

    expect(
      () => service.embed(context, 'no embedding size'),
      throwsA(
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          'Failed to resolve embedding dimension',
        ),
      ),
    );

    expect(batches.live, liveBefore);
  });
}

/// Token batches that were allocated and not freed yet, by the address of
/// their token array.
final class _LiveBatches {
  final List<int> live = <int>[];

  llama_batch init(int tokens, int embd, int sequences) {
    final batch = llama_batch_init(tokens, embd, sequences);
    live.add(batch.token.address);
    return batch;
  }

  void free(llama_batch batch) {
    live.remove(batch.token.address);
    llama_batch_free(batch);
  }
}

/// [malloc] blocks that were allocated and not freed yet, by address.
final class _LiveBlocks implements Allocator {
  final List<int> live = <int>[];
  int frees = 0;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final block = malloc.allocate<T>(byteCount, alignment: alignment);
    live.add(block.address);
    return block;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    expect(live.remove(pointer.address), isTrue, reason: 'freed once');
    frees++;
    malloc.free(pointer);
  }
}

/// Counts the frees of the sampler chains it watches. llama.cpp frees a chain
/// by freeing each sampler in it, so a sampler added to the chain sees it.
final class _SamplerFrees {
  _SamplerFrees() {
    _interface.ref.free = _onFree.nativeFunction;
  }

  int count = 0;

  final Pointer<llama_sampler_i> _interface = calloc<llama_sampler_i>();

  late final _onFree =
      NativeCallable<Void Function(Pointer<llama_sampler>)>.isolateLocal(
        (Pointer<llama_sampler> _) => count++,
      );

  void watch(Pointer<llama_sampler> chain) =>
      llama_sampler_chain_add(chain, llama_sampler_init(_interface, nullptr));

  void close() {
    _onFree.close();
    calloc.free(_interface);
  }
}

Pointer<llama_sampler> _samplerChain(LlamaCppService service, int context) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  final samplers =
      reflect(
            service,
          ).getField(MirrorSystem.getSymbol('_samplers', owner)).reflectee
          as Map<int, Pointer<llama_sampler>>;
  return samplers[context]!;
}

// Leaves non-null words in freed blocks of [byteCount]. An allocator that
// hands such a block out again as it is, as glibc does, then shows an array
// slot the service never wrote as a pointer. On macOS the slot reads as null
// unless the test runs with MallocScribble=1.
void _scribbleFreedBlocks(int byteCount) {
  final blocks = [
    for (var block = 0; block < 64; block++) malloc<Uint8>(byteCount),
  ];
  for (final block in blocks) {
    block.asTypedList(byteCount).fillRange(0, byteCount, 0x5a);
  }
  blocks.forEach(malloc.free);
}

Future<void> _generate(
  LlamaCppService service,
  int context,
  String prompt,
  List<LlamaContentPart> parts,
) async {
  final cancel = calloc<Int8>();
  try {
    await service
        .generate(
          context,
          prompt,
          const GenerationParams(maxTokens: 1),
          cancel.address,
          parts: parts,
        )
        .drain<void>();
  } finally {
    calloc.free(cancel);
  }
}

ExitTeardownApi _withModelLoad(
  ExitTeardownApi real,
  Pointer<llama_model> Function(Pointer<Char> path, llama_model_params params)
  modelLoadFromFile,
) => ExitTeardownApi(
  track: real.track,
  untrack: real.untrack,
  free: real.free,
  freeAddress: real.freeAddress,
  modelLoadFromFile: modelLoadFromFile,
  initFromModel: real.initFromModel,
  mtmdInitFromFile: real.mtmdInitFromFile,
  decode: real.decode,
  encode: real.encode,
  synchronize: real.synchronize,
  samplerSample: real.samplerSample,
  stateSaveFile: real.stateSaveFile,
  stateLoadFile: real.stateLoadFile,
  stateSeqGetSizeExt: real.stateSeqGetSizeExt,
  stateSeqGetDataExt: real.stateSeqGetDataExt,
  stateSeqSetDataExt: real.stateSeqSetDataExt,
  adapterLoraInit: real.adapterLoraInit,
  mtmdTokenize: real.mtmdTokenize,
  mtmdEncodeChunk: real.mtmdEncodeChunk,
  mtmdHelperEvalChunks: real.mtmdHelperEvalChunks,
  mtmdHelperEvalChunkSingle: real.mtmdHelperEvalChunkSingle,
  mtmdHelperDecodeImageChunk: real.mtmdHelperDecodeImageChunk,
  schedGraphCompute: real.schedGraphCompute,
);
