@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/native_barrier_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/worker_messages.dart';
import 'package:test/test.dart';

import '../../../support/fake_native_barrier.dart';
import '../../../support/fake_mtmd.dart';
import '../../../support/recording_exit_teardown.dart';
import '../../../support/synthetic_embedding_gguf.dart';

void main() {
  test(
    'unstarted and unknown contexts have no capabilities or worker startup',
    () async {
      final backend = NativeLlamaBackend();
      addTearDown(backend.dispose);
      final caps = await backend.getEmbeddingCapabilities(99);
      expect([caps.text, caps.image, caps.audio], [false, false, false]);
      expect(await backend.embedContentBatch(99, []), isEmpty);
      expect(backend.isReady, isFalse);
      final service = LlamaCppService();
      final unloaded = service.getEmbeddingCapabilities(99);
      expect(
        [unloaded.text, unloaded.image, unloaded.audio],
        [false, false, false],
      );
    },
  );

  test(
    'content RPC copies media, preserves normalization, cancels and keeps typed errors',
    () async {
      final port = ReceivePort();
      late NativeLlamaBackend backend;
      var mode = 'ok';
      final subscription = port.listen((message) {
        if (message is EmbeddingCapabilitiesRequest) {
          message.sendPort.send(
            mode == 'error'
                ? ErrorResponse(
                    'unsupported',
                    kind: WorkerErrorKind.unsupported,
                  )
                : mode == 'unknown'
                ? 'invalid'
                : EmbeddingCapabilitiesResponse(
                    const LlamaEmbeddingCapabilities(
                      text: true,
                      mediaUnsupportedReason:
                          'guarded mixed-batch ABI v0.7.0-1',
                    ),
                  ),
          );
        } else if (message is EmbedContentBatchRequest) {
          expect(message.normalize, isFalse);
          expect(
            (message.inputs.single.parts.single as LlamaImageContent).bytes,
            [1, 2],
          );
          expect(
            Pointer<Int8>.fromAddress(message.cancelTokenAddress).value,
            mode == 'cancel' ? 1 : 0,
          );
          message.sendPort.send(
            mode == 'error'
                ? ErrorResponse('failed', kind: WorkerErrorKind.inference)
                : mode == 'unknown'
                ? 'invalid'
                : EmbedBatchResponse([
                    [1, 2],
                  ]),
          );
        } else if (message is WorkerRequest) {
          message.sendPort.send(null);
        }
      });
      backend = NativeLlamaBackend(initialSendPort: port.sendPort);
      addTearDown(() async {
        await backend.dispose();
        await subscription.cancel();
        port.close();
      });
      final capabilities = await backend.getEmbeddingCapabilities(7);
      expect(capabilities.text, isTrue);
      expect(capabilities.mediaUnsupportedReason, contains('v0.7.0-1'));
      for (final next in ['ok', 'cancel', 'error', 'unknown']) {
        mode = next;
        final bytes = Uint8List.fromList([1, 2]);
        final future = backend.embedContentBatch(7, [
          LlamaEmbeddingInput([LlamaImageContent(bytes: bytes)]),
        ], normalize: false);
        bytes[0] = 9;
        if (mode == 'cancel') backend.cancelGeneration();
        if (mode == 'error' || mode == 'unknown') {
          await expectLater(future, throwsA(isA<LlamaInferenceException>()));
        } else {
          expect(await future, [
            [1, 2],
          ]);
        }
      }
      mode = 'error';
      await expectLater(
        backend.getEmbeddingCapabilities(7),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      mode = 'unknown';
      await expectLater(
        backend.getEmbeddingCapabilities(7),
        throwsA(isA<LlamaInferenceException>()),
      );
    },
  );

  test('prepared media cleanup frees chunks before bitmaps exactly once', () {
    final library = reflectClass(LlamaCppService).owner as LibraryMirror;
    final type =
        library.declarations[MirrorSystem.getSymbol(
              '_PreparedEmbedding',
              library,
            )]
            as ClassMirror;
    final freed = <int>[];
    final object = type.newInstance(Symbol.empty, [], {
      #freeChunks: (Pointer<mtmd_input_chunks> p) => freed.add(p.address),
      #freeBitmap: (Pointer<mtmd_bitmap> p) => freed.add(p.address),
    });
    object.setField(
      MirrorSystem.getSymbol('chunks', library),
      Pointer<mtmd_input_chunks>.fromAddress(1),
    );
    (object.getField(MirrorSystem.getSymbol('bitmaps', library)).reflectee
            as List<Pointer<mtmd_bitmap>>)
        .addAll([Pointer.fromAddress(2), Pointer.fromAddress(3)]);
    object.invoke(#dispose, []);
    object.invoke(#dispose, []);
    expect(freed, [1, 2, 3]);
  });

  test('mixed ABI is optional and rejects each missing required symbol', () {
    final names = <String>[];
    final api = LlamaCppMixedBatchApi.tryResolve(
      symbol: (name) {
        names.add(name);
        return Pointer<NativeType>.fromAddress(1);
      },
    );
    expect(api, isNotNull);
    expect(
      names,
      containsAll([
        'llama_dart_process',
        'llama_dart_batch_ext_init',
        'llama_batch_ext_add_embd',
        'mtmd_decode_use_mrope',
      ]),
    );
    for (final missing in names) {
      expect(
        LlamaCppMixedBatchApi.tryResolve(
          symbol: (name) {
            if (name == missing) throw ArgumentError('missing');
            return Pointer<NativeType>.fromAddress(1);
          },
        ),
        isNull,
        reason: missing,
      );
    }
    expect(
      LlamaCppMixedBatchApi.tryResolve(isWindows: Platform.isWindows),
      isNotNull,
    );
  });

  test('Windows mixed lookup uses the split DLL export tables', () {
    final library = reflectClass(LlamaCppMixedBatchApi).owner as LibraryMirror;
    final lookup = MirrorSystem.getSymbol('_mixedSymbol', library);
    final seen = <String>[];
    const exports = {
      'llamadart.dll': {'llama_dart_batch_ext_init', 'llama_dart_process'},
      'llama.dll': {
        'llama_batch_ext_add_token',
        'llama_batch_ext_add_embd',
        'llama_batch_ext_set_pos',
        'llama_batch_ext_set_output_embd',
        'llama_batch_ext_free',
        'llama_set_embeddings',
      },
      'mtmd.dll': {
        'mtmd_get_output_embd',
        'mtmd_decode_use_mrope',
        'mtmd_get_audio_sample_rate',
        'mtmd_helper_get_n_tokens',
        'mtmd_input_chunks_size',
        'mtmd_input_chunks_get',
        'mtmd_input_chunk_get_type',
        'mtmd_input_chunk_get_n_tokens',
        'mtmd_input_chunk_get_tokens_text',
        'mtmd_bitmap_is_audio',
      },
    };
    for (final windows in [false, true]) {
      seen.clear();
      Pointer<NativeType> route(String name) =>
          library
                  .invoke(
                    lookup,
                    [name],
                    {
                      #isWindows: windows,
                      #lookup: (String dll, String symbol) {
                        seen.add('$dll:$symbol');
                        if (!(windows
                                ? exports[dll]!
                                : exports.values.expand((names) => names))
                            .contains(symbol)) {
                          throw ArgumentError('missing');
                        }
                        return Pointer<NativeType>.fromAddress(1);
                      },
                    },
                  )
                  .reflectee
              as Pointer<NativeType>;
      final api = LlamaCppMixedBatchApi.tryResolve(symbol: route);
      expect(api, isNotNull, reason: 'Windows: $windows');
      expect(seen, isNotEmpty);
      final resolved = List<String>.of(seen);
      expect(
        resolved.map((entry) => entry.split(':')[1]),
        unorderedEquals(exports.values.expand((names) => names)),
      );
      for (final missing in resolved.map((entry) => entry.split(':')[1])) {
        expect(
          LlamaCppMixedBatchApi.tryResolve(
            symbol: (name) {
              if (name == missing) throw ArgumentError('missing');
              return route(name);
            },
          ),
          isNull,
          reason: 'Windows: $windows, missing: $missing',
        );
      }
      for (final entry in resolved) {
        final fields = entry.split(':');
        final name = fields[1];
        final expected = !windows
            ? 'llamadart.dll'
            : name.startsWith('mtmd_')
            ? 'mtmd.dll'
            : name.startsWith('llama_dart_')
            ? 'llamadart.dll'
            : 'llama.dll';
        expect(fields[0], expected, reason: name);
      }
    }
  });

  test('Windows mixed lookup rejects unknown mtmd accessors', () {
    final library = reflectClass(LlamaCppMixedBatchApi).owner as LibraryMirror;
    expect(
      () => library.invoke(
        MirrorSystem.getSymbol('_windowsMixedSymbol', library),
        ['missing_mixed_symbol'],
      ),
      throwsArgumentError,
    );
  });

  test(
    'Windows mtmd mixed lookup uses the service fallback and rejects absence',
    () {
      final library = reflectClass(LlamaCppService).owner as LibraryMirror;
      final service = LlamaCppService()..initializeBackend();
      addTearDown(service.dispose);
      final mirror = reflect(service);
      final lookup = MirrorSystem.getSymbol('_mixedMtmdSymbol', library);
      final attempted = MirrorSystem.getSymbol(
        '_mtmdFallbackLookupAttempted',
        library,
      );
      setMtmdFallbackForTesting(service, null);
      expect(
        () => mirror.invoke(lookup, ['mtmd_get_output_embd']),
        throwsArgumentError,
      );
      mirror.setField(attempted, false);
      if (!Platform.isWindows) {
        expect(
          service.debugUseWrapperMtmdFallbackForTesting(chunkEval: true),
          isTrue,
        );
      }
      final output =
          mirror.invoke(lookup, ['mtmd_get_output_embd']).reflectee as Pointer;
      expect(output.address, isNonZero);
      expect(
        () => mirror.invoke(lookup, ['missing_mixed_symbol']),
        throwsArgumentError,
      );
    },
  );

  test('mixed lookup rejects an mtmd fallback without a library handle', () {
    final service = LlamaCppService();
    addTearDown(service.dispose);
    final fake = FakeMtmd.install(service, tokens: const []);
    addTearDown(fake.dispose);
    final library = reflectClass(LlamaCppService).owner as LibraryMirror;
    expect(
      () => reflect(service).invoke(
        MirrorSystem.getSymbol('_mixedMtmdSymbol', library),
        ['mtmd_get_output_embd'],
      ),
      throwsArgumentError,
    );
  });

  test('Windows mtmd resolver is used only for mtmd on Windows', () {
    final library = reflectClass(LlamaCppMixedBatchApi).owner as LibraryMirror;
    final lookup = MirrorSystem.getSymbol('_mixedSymbol', library);
    // Non-Windows routing binds mtmd from the default asset, which a Windows
    // host's split bundle does not export.
    for (final windows in [if (!Platform.isWindows) false, true]) {
      final seen = <String>[];
      for (final name in ['mtmd_get_output_embd', 'mtmd_decode_use_mrope']) {
        final pointer =
            library
                    .invoke(
                      lookup,
                      [name],
                      {
                        #isWindows: windows,
                        #mtmdSymbol: (String symbol) {
                          seen.add(symbol);
                          return Pointer<NativeType>.fromAddress(42);
                        },
                      },
                    )
                    .reflectee
                as Pointer;
        expect(pointer.address == 42, windows);
      }
      expect(seen.length, windows ? 2 : 0);
    }
  });

  test(
    'mixed API calls every probed address without returning to default assets',
    () {
      final seen = <String>[];
      final symbols = <String, Pointer<NativeType>>{};
      final embd = calloc<llama_embd>();
      addTearDown(() => calloc.free(embd));
      final setOutput =
          NativeCallable<
            Void Function(Pointer<llama_context>, Bool)
          >.isolateLocal((Pointer<llama_context> arg0, bool arg1) {
            seen.add('llama_set_embeddings');
            expect(arg0.address, 100);
            expect(arg1, true);
          });
      addTearDown(setOutput.close);
      symbols['llama_set_embeddings'] = setOutput.nativeFunction;
      final setOutputRow =
          NativeCallable<
            Bool Function(Pointer<llama_batch_ext>, Int32, Bool)
          >.isolateLocal((Pointer<llama_batch_ext> arg0, int arg1, bool arg2) {
            seen.add('llama_batch_ext_set_output_embd');
            expect(arg0.address, 100);
            expect(arg1, 9);
            expect(arg2, true);
            return true;
          }, exceptionalReturn: false);
      addTearDown(setOutputRow.close);
      symbols['llama_batch_ext_set_output_embd'] = setOutputRow.nativeFunction;
      final addToken =
          NativeCallable<
            Int32 Function(Pointer<llama_batch_ext>, Int32, Int32)
          >.isolateLocal((Pointer<llama_batch_ext> arg0, int arg1, int arg2) {
            seen.add('llama_batch_ext_add_token');
            expect(arg0.address, 100);
            expect(arg1, 9);
            expect(arg2, 9);
            return 7;
          }, exceptionalReturn: 0);
      addTearDown(addToken.close);
      symbols['llama_batch_ext_add_token'] = addToken.nativeFunction;
      final addEmbedding =
          NativeCallable<
            Int32 Function(Pointer<llama_batch_ext>, Int32, llama_embd)
          >.isolateLocal((
            Pointer<llama_batch_ext> arg0,
            int arg1,
            llama_embd arg2,
          ) {
            seen.add('llama_batch_ext_add_embd');
            expect(arg0.address, 100);
            expect(arg1, 9);
            expect(arg2.n_rows, 0);
            return 7;
          }, exceptionalReturn: 0);
      addTearDown(addEmbedding.close);
      symbols['llama_batch_ext_add_embd'] = addEmbedding.nativeFunction;
      final setPosition =
          NativeCallable<
            Bool Function(Pointer<llama_batch_ext>, Int32, Pointer<llama_pos>)
          >.isolateLocal((
            Pointer<llama_batch_ext> arg0,
            int arg1,
            Pointer<llama_pos> arg2,
          ) {
            seen.add('llama_batch_ext_set_pos');
            expect(arg0.address, 100);
            expect(arg1, 9);
            expect(arg2.address, 100);
            return true;
          }, exceptionalReturn: false);
      addTearDown(setPosition.close);
      symbols['llama_batch_ext_set_pos'] = setPosition.nativeFunction;
      final free =
          NativeCallable<Void Function(Pointer<llama_batch_ext>)>.isolateLocal((
            Pointer<llama_batch_ext> arg0,
          ) {
            seen.add('llama_batch_ext_free');
            expect(arg0.address, 100);
          });
      addTearDown(free.close);
      symbols['llama_batch_ext_free'] = free.nativeFunction;
      final projectorUsesMrope =
          NativeCallable<Bool Function(Pointer<mtmd_context>)>.isolateLocal((
            Pointer<mtmd_context> arg0,
          ) {
            seen.add('mtmd_decode_use_mrope');
            expect(arg0.address, 100);
            return true;
          }, exceptionalReturn: false);
      addTearDown(projectorUsesMrope.close);
      symbols['mtmd_decode_use_mrope'] = projectorUsesMrope.nativeFunction;
      final audioSampleRate =
          NativeCallable<Int Function(Pointer<mtmd_context>)>.isolateLocal((
            Pointer<mtmd_context> arg0,
          ) {
            seen.add('mtmd_get_audio_sample_rate');
            expect(arg0.address, 100);
            return 7;
          }, exceptionalReturn: 0);
      addTearDown(audioSampleRate.close);
      symbols['mtmd_get_audio_sample_rate'] = audioSampleRate.nativeFunction;
      final mediaOutput =
          NativeCallable<
            Pointer<Float> Function(Pointer<mtmd_context>)
          >.isolateLocal((Pointer<mtmd_context> arg0) {
            seen.add('mtmd_get_output_embd');
            expect(arg0.address, 100);
            return Pointer<Float>.fromAddress(303);
          });
      addTearDown(mediaOutput.close);
      symbols['mtmd_get_output_embd'] = mediaOutput.nativeFunction;
      final tokenCount =
          NativeCallable<
            Size Function(Pointer<mtmd_input_chunks>)
          >.isolateLocal((Pointer<mtmd_input_chunks> arg0) {
            seen.add('mtmd_helper_get_n_tokens');
            expect(arg0.address, 100);
            return 7;
          }, exceptionalReturn: 0);
      addTearDown(tokenCount.close);
      symbols['mtmd_helper_get_n_tokens'] = tokenCount.nativeFunction;
      final chunksSize =
          NativeCallable<
            Size Function(Pointer<mtmd_input_chunks>)
          >.isolateLocal((Pointer<mtmd_input_chunks> arg0) {
            seen.add('mtmd_input_chunks_size');
            expect(arg0.address, 100);
            return 7;
          }, exceptionalReturn: 0);
      addTearDown(chunksSize.close);
      symbols['mtmd_input_chunks_size'] = chunksSize.nativeFunction;
      final chunksGet =
          NativeCallable<
            Pointer<mtmd_input_chunk> Function(Pointer<mtmd_input_chunks>, Size)
          >.isolateLocal((Pointer<mtmd_input_chunks> arg0, int arg1) {
            seen.add('mtmd_input_chunks_get');
            expect(arg0.address, 100);
            expect(arg1, 9);
            return Pointer<mtmd_input_chunk>.fromAddress(303);
          });
      addTearDown(chunksGet.close);
      symbols['mtmd_input_chunks_get'] = chunksGet.nativeFunction;
      final chunkType =
          NativeCallable<
            UnsignedInt Function(Pointer<mtmd_input_chunk>)
          >.isolateLocal((Pointer<mtmd_input_chunk> arg0) {
            seen.add('mtmd_input_chunk_get_type');
            expect(arg0.address, 100);
            return 7;
          }, exceptionalReturn: 0);
      addTearDown(chunkType.close);
      symbols['mtmd_input_chunk_get_type'] = chunkType.nativeFunction;
      final chunkTokenCount =
          NativeCallable<Size Function(Pointer<mtmd_input_chunk>)>.isolateLocal(
            (Pointer<mtmd_input_chunk> arg0) {
              seen.add('mtmd_input_chunk_get_n_tokens');
              expect(arg0.address, 100);
              return 7;
            },
            exceptionalReturn: 0,
          );
      addTearDown(chunkTokenCount.close);
      symbols['mtmd_input_chunk_get_n_tokens'] = chunkTokenCount.nativeFunction;
      final chunkTokens =
          NativeCallable<
            Pointer<llama_token> Function(
              Pointer<mtmd_input_chunk>,
              Pointer<Size>,
            )
          >.isolateLocal((Pointer<mtmd_input_chunk> arg0, Pointer<Size> arg1) {
            seen.add('mtmd_input_chunk_get_tokens_text');
            expect(arg0.address, 100);
            expect(arg1.address, 100);
            return Pointer<llama_token>.fromAddress(303);
          });
      addTearDown(chunkTokens.close);
      symbols['mtmd_input_chunk_get_tokens_text'] = chunkTokens.nativeFunction;
      final bitmapIsAudio =
          NativeCallable<Bool Function(Pointer<mtmd_bitmap>)>.isolateLocal((
            Pointer<mtmd_bitmap> arg0,
          ) {
            seen.add('mtmd_bitmap_is_audio');
            expect(arg0.address, 100);
            return true;
          }, exceptionalReturn: false);
      addTearDown(bitmapIsAudio.close);
      symbols['mtmd_bitmap_is_audio'] = bitmapIsAudio.nativeFunction;
      final init =
          NativeCallable<
            Pointer<llama_batch_ext> Function(Pointer<llama_context>)
          >.isolateLocal((Pointer<llama_context> arg0) {
            seen.add('llama_dart_batch_ext_init');
            expect(arg0.address, 100);
            return Pointer<llama_batch_ext>.fromAddress(303);
          });
      addTearDown(init.close);
      symbols['llama_dart_batch_ext_init'] = init.nativeFunction;
      final process =
          NativeCallable<
            Int32 Function(
              Pointer<llama_context>,
              Int32,
              Pointer<llama_batch_ext>,
            )
          >.isolateLocal((
            Pointer<llama_context> arg0,
            int arg1,
            Pointer<llama_batch_ext> arg2,
          ) {
            seen.add('llama_dart_process');
            expect(arg0.address, 100);
            expect(arg1, 9);
            expect(arg2.address, 100);
            return 7;
          }, exceptionalReturn: 0);
      addTearDown(process.close);
      symbols['llama_dart_process'] = process.nativeFunction;
      final api = LlamaCppMixedBatchApi.tryResolve(
        symbol: (name) => symbols[name]!,
      )!;
      api.setOutput(Pointer.fromAddress(100), true);
      expect(api.setOutputRow(Pointer.fromAddress(100), 9, true), true);
      expect(api.addToken(Pointer.fromAddress(100), 9, 9), 7);
      expect(api.addEmbedding(Pointer.fromAddress(100), 9, embd.ref), 7);
      expect(
        api.setPosition(Pointer.fromAddress(100), 9, Pointer.fromAddress(100)),
        true,
      );
      api.free(Pointer.fromAddress(100));
      expect(api.projectorUsesMrope(Pointer.fromAddress(100)), true);
      expect(api.audioSampleRate(Pointer.fromAddress(100)), 7);
      expect(api.mediaOutput(Pointer.fromAddress(100)).address, 303);
      expect(api.tokenCount(Pointer.fromAddress(100)), 7);
      expect(api.chunksSize(Pointer.fromAddress(100)), 7);
      expect(api.chunksGet(Pointer.fromAddress(100), 9).address, 303);
      expect(api.chunkType(Pointer.fromAddress(100)), 7);
      expect(api.chunkTokenCount(Pointer.fromAddress(100)), 7);
      expect(
        api
            .chunkTokens(Pointer.fromAddress(100), Pointer.fromAddress(100))
            .address,
        303,
      );
      expect(api.bitmapIsAudio(Pointer.fromAddress(100)), true);
      expect(api.init(Pointer.fromAddress(100)).address, 303);
      expect(
        api.process(Pointer.fromAddress(100), 9, Pointer.fromAddress(100)),
        7,
      );
      expect(seen, symbols.keys.toList());
      final calls = LlamaCppObjectCalls.resolve(
        isWindows: Platform.isWindows,
        mixedBatchResolver: () => api,
      );
      expect(calls.mixedBatch, same(api));
      expect(calls.embeddingMediaOutput(Pointer.fromAddress(100)).address, 303);
    },
  );

  test(
    'native text-only model preserves raw and normalized adjacent-text parity',
    () {
      final dir = Directory.systemTemp.createTempSync(
        'native_content_embedding_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final modelFile = writeSyntheticLlamaGguf(
        '${dir.path}/model.gguf',
        poolingType: 1,
        causalAttention: false,
      );
      final service = LlamaCppService()..initializeBackend();
      addTearDown(service.dispose);
      const params = ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        gpuLayers: 0,
        preferredBackend: GpuBackend.cpu,
        contextSize: 64,
        batchSize: 64,
        microBatchSize: 32,
      );
      final model = service.loadModel(modelFile.path, params);
      final context = service.createContext(model, params);
      expect(service.embedContentBatch(-1, []), isEmpty);
      final caps = service.getEmbeddingCapabilities(context);
      expect([caps.text, caps.image, caps.audio], [true, false, false]);
      for (final normalize in [true, false]) {
        final expected = service.embed(context, 'a \nbé', normalize: normalize);
        final actual = service.embedContentBatch(context, [
          LlamaEmbeddingInput([
            const LlamaTextContent('a '),
            const LlamaTextContent(''),
            const LlamaTextContent('\nbé'),
          ]),
        ], normalize: normalize);
        expect(actual.single, orderedEquals(expected));
      }
      expect(
        () => service.embedContentBatch(context, [
          LlamaEmbeddingInput([LlamaAudioContent(samples: Float32List(4))]),
        ]),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(
        () => service.embedContentBatch(context, [
          LlamaEmbeddingInput([LlamaTextContent('a ' * 100)]),
        ]),
        throwsA(isA<LlamaInferenceException>()),
      );
      final cancel = calloc<Int8>()..value = 1;
      addTearDown(() => calloc.free(cancel));
      expect(
        () => service.embedContentBatch(context, [
          LlamaEmbeddingInput([const LlamaTextContent('a')]),
        ], cancelToken: cancel),
        throwsA(isA<LlamaInferenceException>()),
      );
      cancel.value = 0;
      expect(
        service.embedContentBatch(context, [
          LlamaEmbeddingInput([const LlamaTextContent('a')]),
        ], cancelToken: cancel).single,
        service.embed(context, 'a'),
      );
    },
  );

  test(
    'causal unpooled content preserves string acceptance and rank stays unsupported',
    () {
      final dir = Directory.systemTemp.createTempSync(
        'native_embedding_probe_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final service = LlamaCppService()..initializeBackend();
      addTearDown(service.dispose);
      const params = ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        gpuLayers: 0,
        preferredBackend: GpuBackend.cpu,
        contextSize: 64,
        batchSize: 64,
        microBatchSize: 64,
      );
      for (final pooling in [0, 4]) {
        final path = writeSyntheticLlamaGguf(
          '${dir.path}/model$pooling.gguf',
          poolingType: pooling,
          causalAttention: true,
        ).path;
        final model = service.loadModel(path, params);
        final context = service.createContext(model, params);
        final caps = service.getEmbeddingCapabilities(context);
        expect(
          [caps.text, caps.image, caps.audio],
          [pooling == 0, false, false],
        );
        if (pooling == 0) {
          for (final normalize in [false, true]) {
            expect(
              service.embedContentBatch(context, [
                LlamaEmbeddingInput([const LlamaTextContent('a b')]),
              ], normalize: normalize).single,
              orderedEquals(
                service.embed(context, 'a b', normalize: normalize),
              ),
            );
          }
        } else {
          expect(
            () => service.embed(context, 'a'),
            throwsA(isA<LlamaUnsupportedException>()),
          );
        }
        service.freeContext(context);
        service.freeModel(model);
      }
    },
  );

  test(
    'mixed wrapper dispatch pins DECODE, failures, exception poisoning and allocation',
    () {
      final recorder = RecordingExitTeardown(
        ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
      );
      final barrier = FakeNativeBarrier();
      addTearDown(barrier.dispose);
      final context = Pointer<llama_context>.fromAddress(100);
      final batch = Pointer<llama_batch_ext>.fromAddress(200);
      final projector = Pointer<mtmd_context>.fromAddress(300);
      var result = 0;
      var allocationFails = false;
      final seen = <Object>[];
      final outputModes = <bool>[];
      final calls = LlamaCppObjectCalls.tracked(
        recorder.api,
        barrier: barrier.api,
        mixedBatchResolver: () => LlamaCppMixedBatchApi(
          init: (ctx) {
            expect(ctx, context);
            return allocationFails ? nullptr : batch;
          },
          setOutput: (_, enabled) => outputModes.add(enabled),
          process: (ctx, type, b) {
            seen.addAll([ctx, type, b]);
            return result;
          },
        ),
      );
      expect(calls.createEmbeddingBatch(context), batch);
      calls.processEmbeddingBatch(context, batch);
      expect(seen, [context, 1, batch]);
      for (final status in [-4]) {
        result = status;
        expect(
          () => calls.processEmbeddingBatch(context, batch),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      }
      result = -1;
      expect(
        () => calls.processEmbeddingBatch(context, batch),
        throwsA(isA<LlamaInferenceException>()),
      );
      result = 2;
      expect(
        () => calls.processEmbeddingBatch(context, batch),
        throwsA(isA<LlamaInferenceException>()),
      );
      allocationFails = true;
      expect(
        () => calls.createEmbeddingBatch(context),
        throwsA(isA<LlamaInferenceException>()),
      );
      barrier.catchException();
      expect(
        () => calls.createEmbeddingBatch(context),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(
        () => calls.failures.ensureUsable(context, 'context'),
        throwsA(isA<LlamaStateException>()),
      );
      calls.failures.forget(context);
      barrier.clear();
      result = -2147483648;
      barrier.catchException();
      expect(
        () => calls.processEmbeddingBatch(context, batch),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(
        () => calls.failures.ensureUsable(context, 'context'),
        throwsA(isA<LlamaStateException>()),
      );
      calls.setEmbeddingOutput(context, false);
      expect(
        outputModes,
        isEmpty,
        reason: 'free-only contexts cannot be touched during error cleanup',
      );
      expect(
        () => calls.setEmbeddingOutput(context, true),
        throwsA(isA<LlamaStateException>()),
      );
      calls.failures.forget(context);
      calls.setEmbeddingOutput(context, true);
      calls.setEmbeddingOutput(context, false);
      expect(outputModes, [true, false]);
      barrier.clear();
      calls.encodeEmbeddingChunk(projector, nullptr);
      expect(recorder.calls, contains('llama_dart_mtmd_encode_chunk'));
      final failedEncode = LlamaCppObjectCalls.tracked(
        _withFailedEncoder(recorder.api),
        barrier: barrier.api,
      );
      expect(
        () => failedEncode.encodeEmbeddingChunk(projector, nullptr),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(
        () => LlamaCppObjectCalls.upstream.encodeEmbeddingChunk(
          projector,
          nullptr,
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(LlamaCppObjectCalls.upstream.mixedBatch, isNull);
    },
  );

  test('mixed special tokens follow string rules even when BOS equals EOS', () {
    final dir = Directory.systemTemp.createTempSync('embedding_special_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = writeSyntheticLlamaGguf(
      '${dir.path}/model.gguf',
      poolingType: 1,
      causalAttention: false,
      eosTokenId: 1,
    );
    final service = LlamaCppService()..initializeBackend();
    addTearDown(service.dispose);
    const params = ModelParams(
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
      gpuLayers: 0,
      preferredBackend: GpuBackend.cpu,
      contextSize: 64,
      batchSize: 64,
      microBatchSize: 64,
    );
    final model = service.loadModel(file.path, params);
    final models = _privateField(service, '_models') as Map;
    final pointer =
        reflect(models[model]).getField(#pointer).reflectee
            as Pointer<llama_model>;
    final vocab = llama_model_get_vocab(pointer);
    expect(llama_vocab_bos(vocab), llama_vocab_eos(vocab));
    final library = reflectClass(LlamaCppService).owner as LibraryMirror;
    for (final text in ['a', '<s>a']) {
      final addSpecial = reflect(service).invoke(
        MirrorSystem.getSymbol('_embeddingAddsSpecial', library),
        [vocab, text],
      ).reflectee;
      expect(addSpecial, !text.startsWith('<s>'));
      expect(
        service.tokenize(model, text, addSpecial as bool),
        service.tokenize(model, text, true),
      );
    }
  });

  for (final gate in ['mean', 'causal', 'abi', 'inputWidth']) {
    test('projector cannot bypass the $gate media gate', () {
      final dir = Directory.systemTemp.createTempSync('embedding_gate_');
      addTearDown(() => dir.deleteSync(recursive: true));
      var mropeProbes = 0;
      final barrier = FakeNativeBarrier(
        real: NativeBarrierApi.tryResolve(isWindows: Platform.isWindows),
      );
      addTearDown(barrier.dispose);
      final calls = LlamaCppObjectCalls.tracked(
        ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
        barrier: barrier.api,
        mixedBatchResolver: () => gate == 'abi'
            ? null
            : LlamaCppMixedBatchApi(
                init: (_) => throw StateError('unexpected allocation'),
                process: (_, _, _) => throw StateError('unexpected process'),
                projectorUsesMrope: (_) {
                  mropeProbes++;
                  return true;
                },
              ),
        modelInputWidth: gate == 'inputWidth'
            ? (_) => throw ArgumentError('missing llama_model_n_embd_inp')
            : null,
      );
      final service = LlamaCppService(objectCalls: calls)..initializeBackend();
      addTearDown(service.dispose);
      final file = writeSyntheticLlamaGguf(
        '${dir.path}/model.gguf',
        poolingType: gate == 'mean' ? 0 : 1,
        causalAttention: gate == 'causal',
      );
      const params = ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        gpuLayers: 0,
        preferredBackend: GpuBackend.cpu,
        contextSize: 64,
        batchSize: 64,
        microBatchSize: 64,
      );
      final model = service.loadModel(file.path, params);
      final context = service.createContext(model, params);
      expect(service.getEmbeddingCapabilities(context).text, isTrue);
      final map = _privateField(service, '_mtmdContexts') as Map;
      final models = _privateField(service, '_modelToMtmd') as Map;
      map[123] = Pointer<mtmd_context>.fromAddress(123);
      models[model] = 123;
      try {
        final caps = service.getEmbeddingCapabilities(context);
        expect([caps.text, caps.image, caps.audio], [true, false, false]);
        expect(
          caps.mediaUnsupportedReason,
          allOf(contains('llama_model_n_embd_inp'), contains('v0.7.0-1')),
        );
        expect(
          mropeProbes,
          0,
          reason: 'must stop before dereferencing the projector',
        );
        expect(
          service.embedContentBatch(context, [
            LlamaEmbeddingInput([const LlamaTextContent('a')]),
          ]).single,
          orderedEquals(service.embed(context, 'a')),
        );
        expect(
          () => service.embedContentBatch(context, [
            LlamaEmbeddingInput([LlamaAudioContent(samples: Float32List(4))]),
          ]),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'native floor',
              contains('v0.7.0-1'),
            ),
          ),
        );
      } finally {
        map.clear();
        models.clear();
      }
    });
  }

  test(
    'direct SPI text rejection names rank and encoder-decoder restrictions',
    () {
      final dir = Directory.systemTemp.createTempSync('embedding_rank_reason_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = writeSyntheticLlamaGguf(
        '${dir.path}/rank.gguf',
        poolingType: 4,
      );
      final service = LlamaCppService()..initializeBackend();
      addTearDown(service.dispose);
      const params = ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        gpuLayers: 0,
        preferredBackend: GpuBackend.cpu,
        contextSize: 64,
        batchSize: 64,
        microBatchSize: 64,
      );
      final model = service.loadModel(file.path, params);
      final context = service.createContext(model, params);
      expect(
        () => service.embedContentBatch(context, [
          LlamaEmbeddingInput([const LlamaTextContent('text')]),
        ]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'text restriction',
            allOf(
              contains('RANK'),
              contains('encoder-decoder'),
              isNot(contains('projector')),
              isNot(contains('mixed-batch')),
            ),
          ),
        ),
      );
    },
  );

  test(
    'mixed call sites preserve BOS equals EOS and use resolved API pointers',
    () {
      final h = _MixedEmbeddingHarness();
      for (final text in ['a', '<s>a']) {
        final vectors = h.service.embedContentBatch(h.context, [
          h.input(text),
        ], normalize: false);
        expect(vectors.single, hasLength(16));
        expect(vectors.single.every((v) => v.isFinite), isTrue);
      }
      expect(h.addSpecial, [true, false]);
      expect(
        h.calls,
        containsAll([
          'mrope',
          'bitmapIsAudio',
          'tokenCount',
          'init',
          'chunksSize',
          'chunksGet',
          'chunkType',
          'chunkTokenCount',
          'chunkTokens',
          'encode',
          'mediaOutput',
          'addToken',
          'addEmbedding',
          'setPosition',
          'setOutputRow',
          'setOutput',
          'process',
          'free',
        ]),
      );
      expect(h.chunksFreed, 2);
      expect(h.bitmapsFreed, 2);
      expect(h.batchesFreed, 2);
      expect(h.outputModes, [true, false, true, false]);
      expect(h.positions, [0, 1, 0, 1]);
      expect(h.outputRows, [0, 1, 0, 1]);
    },
  );

  test(
    'mixed audio call site uses the probed sample rate and modality pointers',
    () {
      final h = _MixedEmbeddingHarness()..bitmapAudio = true;
      h.service.embedContentBatch(h.context, [
        LlamaEmbeddingInput([LlamaAudioContent(samples: Float32List(4))]),
      ]);
      expect(
        h.calls,
        containsAll(['audioSampleRate', 'bitmapIsAudio', 'free']),
      );
      expect(h.bitmapsFreed, 1);
      expect(h.chunksFreed, 1);
      expect(h.batchesFreed, 1);
    },
  );

  test('mixed cleanup honors an explicit batch releaser', () {
    final h = _MixedEmbeddingHarness(overrideBatchFree: true);
    h.service.embedContentBatch(h.context, [h.input('a')]);
    expect(h.batchesFreed, 1);
    expect(h.calls, contains('overrideFree'));
    expect(h.calls, isNot(contains('free')));
  });

  for (final failure in [
    'tokenize',
    'modality',
    'later-prepare',
    'capacity',
    'process',
  ]) {
    test(
      'mixed cleanup balances resources after $failure failure and permits reuse',
      () {
        final h = _MixedEmbeddingHarness();
        h.tokenizeFails = failure == 'tokenize';
        h.bitmapAudio = failure == 'modality';
        h.expandedRows = failure == 'capacity' ? 65 : 2;
        h.processFails = failure == 'process';
        final inputs = [h.input('a')];
        if (failure == 'later-prepare') {
          inputs.add(
            LlamaEmbeddingInput([
              const LlamaTextContent('bad <__media__> marker'),
              LlamaImageContent(bytes: Uint8List.fromList([1])),
            ]),
          );
        }
        expect(
          () => h.service.embedContentBatch(h.context, inputs),
          failure == 'capacity'
              ? throwsA(
                  isA<LlamaEmbeddingInputTooLongException>()
                      .having((e) => e.maxInputTokens, 'capacity', 64)
                      .having((e) => e.actualTokens, 'expanded rows', 65)
                      .having(
                        (e) => e.message,
                        'actionable guidance',
                        contains('Shorten the input'),
                      ),
                )
              : throwsA(isA<LlamaException>()),
        );
        expect(h.chunksFreed, failure == 'later-prepare' ? 2 : 1);
        expect(h.bitmapsFreed, 1);
        expect(h.batchesFreed, failure == 'process' ? 1 : 0);
        expect(h.outputModes, failure == 'process' ? [true, false] : isEmpty);
        h.tokenizeFails = h.bitmapAudio = h.processFails = false;
        h.expandedRows = 2;
        final before = (h.chunksFreed, h.bitmapsFreed, h.batchesFreed);
        expect(
          h.service.embedContentBatch(h.context, [h.input('a')]).single,
          hasLength(16),
        );
        expect(
          (h.chunksFreed, h.bitmapsFreed, h.batchesFreed),
          (before.$1 + 1, before.$2 + 1, before.$3 + 1),
        );
      },
    );
  }

  test('native backend implements both embedding contracts', () {
    final backend = NativeLlamaBackend();
    expect(backend, isA<BackendEmbeddings>());
    expect(backend, isA<BackendMultimodalEmbeddings>());
  });
}

ExitTeardownApi _withFailedEncoder(ExitTeardownApi real) => ExitTeardownApi(
  track: real.track,
  untrack: real.untrack,
  free: real.free,
  freeAddress: real.freeAddress,
  modelLoadFromFile: real.modelLoadFromFile,
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
  mtmdHelperEvalChunks: real.mtmdHelperEvalChunks,
  mtmdHelperEvalChunkSingle: real.mtmdHelperEvalChunkSingle,
  mtmdHelperDecodeImageChunk: real.mtmdHelperDecodeImageChunk,
  schedGraphCompute: real.schedGraphCompute,
  mtmdEncodeChunk: (_, _) => 1,
);

Object? _privateField(Object target, String name) {
  final library = reflectClass(LlamaCppService).owner as LibraryMirror;
  return reflect(
    target,
  ).getField(MirrorSystem.getSymbol(name, library)).reflectee;
}

/// A synthetic CPU model with fake projector/chunks and recorded mixed accessors.
/// Real extended batches exercise row construction without a media model or GPU.
final class _MixedEmbeddingHarness {
  final List<String> calls = [];
  final List<bool> addSpecial = [];
  final List<bool> outputModes = [];
  final List<int> positions = [];
  final List<int> outputRows = [];
  int chunksFreed = 0;
  int bitmapsFreed = 0;
  int batchesFreed = 0;
  int expandedRows = 2;
  bool tokenizeFails = false;
  bool bitmapAudio = false;
  bool processFails = false;
  late final LlamaCppService service;
  late final int context;

  _MixedEmbeddingHarness({bool overrideBatchFree = false}) {
    final dir = Directory.systemTemp.createTempSync('mixed_embedding_calls_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final tokens = calloc<llama_token>()..value = 3;
    final media = calloc<Float>(16);
    media.asTypedList(16).fillRange(0, 16, 0.125);
    addTearDown(() {
      calloc.free(tokens);
      calloc.free(media);
    });
    final realExit = ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!;
    final recorder = RecordingExitTeardown(realExit);
    final barrier = FakeNativeBarrier(
      real: NativeBarrierApi.tryResolve(isWindows: Platform.isWindows),
    );
    addTearDown(barrier.dispose);
    final exit = _copyMixedExit(recorder.api, {
      #mtmdTokenize:
          (
            Pointer<mtmd_context> _,
            Pointer<mtmd_input_chunks> _,
            Pointer<mtmd_input_text> text,
            Pointer<Pointer<mtmd_bitmap>> _,
            int _,
          ) {
            addSpecial.add(text.ref.add_special);
            return tokenizeFails ? 1 : 0;
          },
      #mtmdEncodeChunk: (Pointer<mtmd_context> _, Pointer<mtmd_input_chunk> _) {
        calls.add('encode');
        return 0;
      },
    });
    final real = LlamaCppMixedBatchApi.tryResolve(
      isWindows: Platform.isWindows,
    )!;
    final api = LlamaCppMixedBatchApi(
      init: (ctx) {
        calls.add('init');
        return real.init(ctx);
      },
      process: (ctx, type, batch) {
        calls.add('process');
        expect(type, 1);
        return processFails ? -1 : real.process(ctx, type, batch);
      },
      setOutput: (ctx, enabled) {
        calls.add('setOutput');
        outputModes.add(enabled);
        real.setOutput(ctx, enabled);
      },
      free: (batch) {
        calls.add('free');
        batchesFreed++;
        real.free(batch);
      },
      projectorUsesMrope: (_) {
        calls.add('mrope');
        return false;
      },
      audioSampleRate: (_) {
        calls.add('audioSampleRate');
        return 16000;
      },
      bitmapIsAudio: (_) {
        calls.add('bitmapIsAudio');
        return bitmapAudio;
      },
      tokenCount: (_) {
        calls.add('tokenCount');
        return expandedRows;
      },
      chunksSize: (_) {
        calls.add('chunksSize');
        return 2;
      },
      chunksGet: (_, index) {
        calls.add('chunksGet');
        return Pointer.fromAddress(100 + index);
      },
      chunkType: (chunk) {
        calls.add('chunkType');
        return chunk.address == 100 ? 0 : 1;
      },
      chunkTokenCount: (_) {
        calls.add('chunkTokenCount');
        return 1;
      },
      chunkTokens: (_, count) {
        calls.add('chunkTokens');
        count.value = 1;
        return tokens;
      },
      mediaOutput: (_) {
        calls.add('mediaOutput');
        return media;
      },
      addToken: (batch, seq, token) {
        calls.add('addToken');
        expect(token, 3);
        return real.addToken(batch, seq, token);
      },
      addEmbedding: (batch, seq, embd) {
        calls.add('addEmbedding');
        expect(embd.n_embd, 16);
        expect(embd.n_rows, 1);
        expect(embd.data.asTypedList(16), everyElement(0.125));
        return real.addEmbedding(batch, seq, embd);
      },
      setPosition: (batch, index, pos) {
        calls.add('setPosition');
        positions.add(pos.value);
        return real.setPosition(batch, index, pos);
      },
      setOutputRow: (batch, index, enabled) {
        calls.add('setOutputRow');
        outputRows.add(index);
        expect(enabled, isTrue);
        return real.setOutputRow(batch, index, enabled);
      },
    );
    service = LlamaCppService(
      objectCalls: LlamaCppObjectCalls.tracked(
        exit,
        barrier: barrier.api,
        isWindows: true,
        mixedBatchResolver: () => api,
      ),
      embeddingBatchFree: overrideBatchFree
          ? (batch) {
              calls.add('overrideFree');
              batchesFreed++;
              real.free(batch);
            }
          : null,
      embeddingChunksFree: (_) {
        chunksFreed++;
      },
      embeddingBitmapFree: (_) {
        bitmapsFreed++;
      },
    )..initializeBackend();
    addTearDown(service.dispose);
    FakeMtmd.install(service, tokens: [1], vision: true);
    final file = writeSyntheticLlamaGguf(
      '${dir.path}/model.gguf',
      poolingType: 1,
      causalAttention: false,
      eosTokenId: 1,
    );
    const params = ModelParams(
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
      gpuLayers: 0,
      preferredBackend: GpuBackend.cpu,
      contextSize: 64,
      batchSize: 64,
      microBatchSize: 64,
    );
    final model = service.loadModel(file.path, params);
    context = service.createContext(model, params);
    final projectors = _privateField(service, '_mtmdContexts') as Map;
    final modelProjectors = _privateField(service, '_modelToMtmd') as Map;
    projectors[999] = FakeMtmd.projector;
    modelProjectors[model] = 999;
    addTearDown(() {
      projectors.clear();
      modelProjectors.clear();
    });
  }

  LlamaEmbeddingInput input(String text) => LlamaEmbeddingInput([
    LlamaTextContent(text),
    LlamaImageContent(bytes: Uint8List.fromList([1])),
  ]);
}

ExitTeardownApi _copyMixedExit(
  ExitTeardownApi source,
  Map<Symbol, dynamic> overrides,
) {
  final type = reflectClass(ExitTeardownApi);
  final constructor = type.declarations.values
      .whereType<MethodMirror>()
      .singleWhere((m) => m.isConstructor && m.constructorName == Symbol.empty);
  return type.newInstance(Symbol.empty, [], {
        for (final parameter in constructor.parameters)
          parameter.simpleName: reflect(
            source,
          ).getField(parameter.simpleName).reflectee,
        ...overrides,
      }).reflectee
      as ExitTeardownApi;
}
