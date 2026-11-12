@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/native_barrier_api.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';

import '../../support/embedding_contract.dart';

const _text = 'The Eiffel Tower is in Paris.';

Uint8List _image(bool checker) {
  final bytes = <int>[...ascii.encode('P6\n224 224\n255\n')];
  for (var y = 0; y < 224; y++) {
    for (var x = 0; x < 224; x++) {
      final value = checker && (x ~/ 16 + y ~/ 16).isOdd ? 255 : 0;
      bytes.addAll([value, value, value]);
    }
  }
  return Uint8List.fromList(bytes);
}

List<LlamaEmbeddingInput> _inputs() {
  final black = LlamaImageContent(bytes: _image(false));
  final checker = LlamaImageContent(bytes: _image(true));
  final silence = LlamaAudioContent(samples: Float32List(16000));
  final tone = LlamaAudioContent(
    samples: Float32List.fromList([
      for (var i = 0; i < 16000; i++)
        0.2 * math.sin(2 * math.pi * 440 * i / 16000),
    ]),
  );
  return [
    LlamaEmbeddingInput([const LlamaTextContent(_text)]),
    LlamaEmbeddingInput([black]),
    LlamaEmbeddingInput([checker]),
    LlamaEmbeddingInput([silence]),
    LlamaEmbeddingInput([tone]),
    LlamaEmbeddingInput([
      const LlamaTextContent('first '),
      black,
      const LlamaTextContent(' between '),
      tone,
      const LlamaTextContent(' last '),
      checker,
    ]),
  ];
}

Uint8List _wav(Float32List pcm) {
  final header = ByteData(44);
  void label(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      header.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  label(0, 'RIFF');
  header.setUint32(4, 36 + pcm.lengthInBytes, Endian.little);
  label(8, 'WAVE');
  label(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 3, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 16000, Endian.little);
  header.setUint32(28, 64000, Endian.little);
  header.setUint16(32, 4, Endian.little);
  header.setUint16(34, 32, Endian.little);
  label(36, 'data');
  header.setUint32(40, pcm.lengthInBytes, Endian.little);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
  ]);
}

void _compare(List<double> actual, List<double> reference, String label) {
  expect(actual, hasLength(768));
  expect(reference, hasLength(768));
  var dot = 0.0, aa = 0.0, bb = 0.0, error = 0.0;
  for (var i = 0; i < actual.length; i++) {
    expect(actual[i].isFinite, isTrue);
    dot += actual[i] * reference[i];
    aa += actual[i] * actual[i];
    bb += reference[i] * reference[i];
    error += math.pow(actual[i] - reference[i], 2);
  }
  final cosine = dot / math.sqrt(aa * bb);
  final relativeL2 = math.sqrt(error / bb);
  // Kept in local qualification logs, without input payloads.
  print('$label cosine=$cosine relativeL2=$relativeL2');
  expect(cosine, greaterThanOrEqualTo(0.9998));
  expect(relativeL2, lessThan(0.02));
}

void main() {
  final root = Platform.environment['LLAMADART_EMBEDDING_MODELS_DIR'];
  for (final backend in [GpuBackend.cpu, GpuBackend.metal]) {
    group(
      'EmbeddingGemma-2 ${backend.name}',
      () {
        late LlamaEngine engine;
        late List<LlamaEmbeddingInput> inputs;
        late List<List<double>> reference;
        setUpAll(() async {
          engine = await LlamaEngine.load(
            LlamaModel(
              ModelSource.path('$root/gguf/embeddinggemma-2-BF16.gguf'),
              projector: ModelSource.path(
                '$root/gguf/mmproj-embeddinggemma-2-BF16.gguf',
              ),
            ),
            params: ModelParams(
              contextSize: 2048,
              batchSize: 2048,
              microBatchSize: 2048,
              numberOfThreads: 8,
              numberOfThreadsBatch: 8,
              preferredBackend: backend,
              gpuLayers: backend == GpuBackend.cpu
                  ? 0
                  : ModelParams.maxGpuLayers,
            ),
          );
          expect(
            (await engine.getBackendName()).toLowerCase(),
            contains(backend.name),
          );
          expect(
            await engine.getResolvedGpuLayers(),
            backend == GpuBackend.cpu ? 0 : greaterThan(0),
          );
          inputs = _inputs();
          final path = Platform
              .environment['LLAMADART_EMBEDDING_REFERENCE_${backend.name.toUpperCase()}'];
          expect(
            path,
            isNotNull,
            reason:
                'Build the pinned upstream reference per doc/multimodal_embeddings_native.md.',
          );
          reference = (jsonDecode(File(path!).readAsStringSync()) as List)
              .map(
                (row) =>
                    (row as List).map((v) => (v as num).toDouble()).toList(),
              )
              .toList();
          expect(reference, hasLength(inputs.length));
        });
        tearDownAll(() async => engine.dispose());

        test('capabilities and pinned reference vectors', () async {
          final caps = await engine.embeddingCapabilities;
          expect([caps.text, caps.image, caps.audio], [true, true, true]);
          final legacy = await engine.embed(_text);
          final vectors = await engine.embedContentBatch(inputs);
          expect(vectors, hasLength(inputs.length));
          expect(vectors.first, orderedEquals(legacy));
          for (var i = 0; i < vectors.length; i++) {
            _compare(vectors[i], reference[i], '${backend.name} input $i');
          }
          expect(vectors[1], isNot(orderedEquals(vectors[2])));
          expect(vectors[3], isNot(orderedEquals(vectors[4])));
        });
        test('batch order and raw output', () async {
          final reversed = await engine.embedContentBatch([
            inputs[4],
            inputs[1],
            inputs[0],
          ]);
          for (var i = 0; i < reversed.length; i++) {
            _compare(
              reversed[i],
              reference[[4, 1, 0][i]],
              '${backend.name} order $i',
            );
          }
          final raw = await engine.embedContent(inputs.last, normalize: false);
          final norm = math.sqrt(raw.fold(0.0, (s, v) => s + v * v));
          expect(norm, greaterThan(0));
          expect(norm, isNot(closeTo(1, 1e-4)));
          _compare(
            raw.map((v) => v / norm).toList(),
            reference.last,
            '${backend.name} raw',
          );
        });
        test(
          'encoded audio and local image/audio files preserve source vectors',
          () async {
            final dir = Directory.systemTemp.createTempSync(
              'embedding_sources_',
            );
            addTearDown(() => dir.deleteSync(recursive: true));
            final image = File('${dir.path}/image.ppm')
              ..writeAsBytesSync(_image(false));
            final audioBytes = _wav(
              (inputs[4].parts.single as LlamaAudioContent).samples!,
            );
            final audio = File('${dir.path}/audio.wav')
              ..writeAsBytesSync(audioBytes);
            final vectors = await engine.embedContentBatch([
              LlamaEmbeddingInput([LlamaImageContent(path: image.path)]),
              LlamaEmbeddingInput([LlamaAudioContent(path: audio.path)]),
              LlamaEmbeddingInput([LlamaAudioContent(bytes: audioBytes)]),
            ]);
            for (var i = 0; i < vectors.length; i++) {
              _compare(
                vectors[i],
                reference[i == 0 ? 1 : 4],
                '${backend.name} file/bytes $i',
              );
            }
            await expectLater(
              engine.embedContent(
                LlamaEmbeddingInput([LlamaImageContent(bytes: audioBytes)]),
              ),
              throwsA(isA<LlamaUnsupportedException>()),
            );
          },
        );
        test('adjacent text contract with and without media', () async {
          await expectAdjacentTextEmbeddingEquivalence(engine.embedContent);
          await expectAdjacentTextEmbeddingEquivalence(
            engine.embedContent,
            before: [inputs[1].parts.single],
            after: [inputs[4].parts.single],
          );
        });
        test(
          'source and capacity preflight rejects before inference',
          () async {
            expect(await engine.embedContentBatch([]), isEmpty);
            final invalid = <(LlamaContentPart, Type)>[
              (
                const LlamaImageContent(url: 'https://invalid.example/private'),
                LlamaUnsupportedException,
              ),
              (
                LlamaImageContent(
                  url: 'https://invalid.example/private',
                  bytes: _image(false),
                ),
                LlamaUnsupportedException,
              ),
              (const LlamaImageContent(), LlamaUnsupportedException),
              (
                LlamaImageContent(
                  bytes: _image(false),
                  path: '/private/ambiguous',
                ),
                LlamaUnsupportedException,
              ),
              (const LlamaAudioContent(), LlamaUnsupportedException),
              (
                LlamaAudioContent(samples: Float32List(4), bytes: Uint8List(2)),
                LlamaUnsupportedException,
              ),
              (
                const LlamaImageContent(
                  path: '/invalid-embedding-source/private',
                ),
                LlamaInferenceException,
              ),
              (LlamaImageContent(bytes: Uint8List(0)), LlamaInferenceException),
              (
                LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
                LlamaInferenceException,
              ),
              (
                LlamaAudioContent(samples: Float32List(0)),
                LlamaInferenceException,
              ),
              (
                LlamaAudioContent(samples: Float32List.fromList([double.nan])),
                LlamaInferenceException,
              ),
              (
                LlamaAudioContent(bytes: _image(false)),
                LlamaUnsupportedException,
              ),
            ];
            for (final (part, type) in invalid) {
              await expectLater(
                engine.embedContentBatch([
                  inputs[1],
                  LlamaEmbeddingInput([part]),
                ]),
                throwsA(
                  predicate(
                    (e) =>
                        e.runtimeType == type &&
                        !e.toString().contains('/private'),
                  ),
                ),
              );
            }
            await expectLater(
              engine.embedContentBatch([
                inputs[1],
                LlamaEmbeddingInput([
                  LlamaTextContent('a ' * 10000),
                  inputs[1].parts.single,
                ]),
              ]),
              throwsA(isA<LlamaInferenceException>()),
            );
            await expectLater(
              engine.embedContent(
                LlamaEmbeddingInput([
                  const LlamaTextContent('<__media__>'),
                  inputs[1].parts.single,
                ]),
              ),
              throwsA(isA<LlamaUnsupportedException>()),
            );
          },
        );
        test(
          'cancellation settles then permits text and media reuse',
          () async {
            final legacy = await engine.embed(_text);
            final cancelled = engine.embedContentBatch(
              List.filled(4, inputs.last),
            );
            await Future<void>.delayed(const Duration(milliseconds: 100));
            engine.cancelGeneration();
            await expectLater(
              cancelled,
              throwsA(isA<LlamaInferenceException>()),
            );
            expect(await engine.embed(_text), orderedEquals(legacy));
            _compare(
              await engine.embedContent(inputs[1]),
              reference[1],
              '${backend.name} reuse',
            );
          },
        );
      },
      skip: root == null
          ? 'Set LLAMADART_EMBEDDING_MODELS_DIR; no downloads.'
          : backend == GpuBackend.metal && !Platform.isMacOS
          ? 'Metal needs macOS.'
          : false,
    );
  }
  test(
    'native guarded preflight, M-RoPE and PCM rate leave inference untouched',
    () {
      final exit = ExitTeardownApi.tryResolve(isWindows: false)!;
      var encodes = 0, processes = 0;
      var outputRows = 0, expandedRows = 0;
      var mrope = false, tokenizeFails = false;
      var sampleRate = 16000;
      var outputEnabled = false;
      var encodeFails = false, processFails = false, missingWidth = false;
      var failWidthAfterAllocation = false;
      var chunksFreed = 0,
          bitmapsFreed = 0,
          batchesCreated = 0,
          batchesFreed = 0;
      void expectFreed(int chunks, int bitmaps, int batches) {
        expect(
          [chunksFreed, bitmapsFreed, batchesFreed],
          [chunks, bitmaps, batches],
        );
        expect(batchesFreed, batchesCreated);
        chunksFreed = bitmapsFreed = batchesCreated = batchesFreed = 0;
      }

      final guarded = _recordEmbeddingExit(
        exit,
        onEncode: () => encodes++,
        onTokenize: (rows) => expandedRows += rows,
        tokenizeFails: () => tokenizeFails,
        encodeFails: () => encodeFails,
        onSpecial: (enabled) => expect(enabled, isTrue),
      );
      final mixed = LlamaCppMixedBatchApi.tryResolve()!;
      final calls = LlamaCppObjectCalls.tracked(
        guarded,
        barrier: NativeBarrierApi.tryResolve(isWindows: false),
        modelInputWidth: (model) {
          if (missingWidth) {
            throw ArgumentError('missing llama_model_n_embd_inp');
          }
          return llama_model_n_embd_inp(model);
        },
        mixedBatchResolver: () => LlamaCppMixedBatchApi(
          init: (ctx) {
            final batch = mixed.init(ctx);
            if (batch != nullptr) batchesCreated++;
            missingWidth = failWidthAfterAllocation;
            return batch;
          },
          process: (context, type, batch) {
            processes++;
            return processFails ? -1 : mixed.process(context, type, batch);
          },
          projectorUsesMrope: (_) => mrope,
          audioSampleRate: (_) => sampleRate,
          setOutputRow: (batch, row, enabled) {
            outputRows++;
            expect(enabled, isTrue);
            return mixed.setOutputRow(batch, row, enabled);
          },
          setOutput: (ctx, enabled) {
            outputEnabled = enabled;
            llama_set_embeddings(ctx, enabled);
          },
        ),
      );
      final service = LlamaCppService(
        objectCalls: calls,
        embeddingChunksFree: (chunks) {
          chunksFreed++;
          mtmd_input_chunks_free(chunks);
        },
        embeddingBitmapFree: (bitmap) {
          bitmapsFreed++;
          mtmd_bitmap_free(bitmap);
        },
        embeddingBatchFree: (batch) {
          batchesFreed++;
          llama_batch_ext_free(batch);
        },
      )..initializeBackend();
      service.setLogLevel(LlamaLogLevel.error);
      addTearDown(service.dispose);
      const params = ModelParams(
        preferredBackend: GpuBackend.metal,
        gpuLayers: ModelParams.maxGpuLayers,
        contextSize: 2048,
        batchSize: 2048,
        microBatchSize: 128,
      );
      final model = service.loadModel(
        '$root/gguf/embeddinggemma-2-BF16.gguf',
        params,
      );
      final context = service.createContext(model, params);
      expect(service.getActiveBackendName().toLowerCase(), contains('metal'));
      expect(service.getResolvedGpuLayers(), greaterThan(0));
      expect(service.getEmbeddingCapabilities(context).image, isFalse);
      service.createMultimodalContext(
        model,
        '$root/gguf/mmproj-embeddinggemma-2-BF16.gguf',
      );
      expect(service.getEmbeddingCapabilities(context).image, isTrue);
      mrope = true;
      expect(service.getEmbeddingCapabilities(context).image, isFalse);
      expect(service.getEmbeddingCapabilities(context).audio, isFalse);
      expect(
        () => service.embedContentBatch(context, [_inputs()[1]]),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      mrope = false;
      final inputs = _inputs();
      expect(
        () => service.embedContentBatch(context, [
          inputs[1],
          LlamaEmbeddingInput([
            LlamaTextContent('a ' * 300),
            inputs[1].parts.single,
          ]),
        ]),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect([encodes, processes], [0, 0]);
      expectFreed(2, 2, 0);
      expect(
        () => service.embedContentBatch(context, [
          inputs[1],
          LlamaEmbeddingInput([LlamaTextContent('a ' * 300)]),
        ]),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(
        [encodes, processes],
        [0, 0],
        reason: 'text-item pass-limit preflight precedes all inference',
      );
      expectFreed(1, 1, 0);
      expect(
        () => service.embedContentBatch(context, [
          inputs[1],
          LlamaEmbeddingInput([
            LlamaImageContent(
              url: 'https://invalid.example',
              bytes: _image(false),
            ),
          ]),
        ]),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect([encodes, processes], [0, 0]);
      expectFreed(2, 1, 0);
      expect(
        () => service.embedContentBatch(context, [
          LlamaEmbeddingInput([LlamaAudioContent(bytes: _image(false))]),
        ]),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expectFreed(1, 1, 0);
      sampleRate = 8000;
      expect(
        () => service.embedContentBatch(context, [inputs[3]]),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expectFreed(1, 0, 0);
      sampleRate = 16000;
      tokenizeFails = true;
      expect(
        () => service.embedContentBatch(context, [inputs[1]]),
        throwsA(isA<LlamaInferenceException>()),
      );
      tokenizeFails = false;
      expectFreed(1, 1, 0);
      expect([encodes, processes], [0, 0]);
      expandedRows = 0;
      expect(
        service.embedContentBatch(context, [inputs[1]]).single,
        hasLength(768),
      );
      expect([encodes, processes], [1, 1]);
      expect(outputEnabled, isFalse);
      expect(expandedRows, greaterThan(0));
      expect(outputRows, expandedRows);
      expectFreed(1, 1, 1);
      for (final failure in ['encode', 'process', 'width']) {
        encodeFails = failure == 'encode';
        processFails = failure == 'process';
        failWidthAfterAllocation = failure == 'width';
        expect(
          () => service.embedContentBatch(context, [inputs[1]]),
          throwsA(
            failure == 'width'
                ? isA<LlamaUnsupportedException>()
                : isA<LlamaInferenceException>(),
          ),
        );
        expect(outputEnabled, isFalse);
        expectFreed(1, 1, 1);
        missingWidth = false;
      }
    },
    skip: root == null || !Platform.isMacOS
        ? 'Requires local BF16 weights and macOS Metal.'
        : false,
  );
}

ExitTeardownApi _recordEmbeddingExit(
  ExitTeardownApi real, {
  required void Function() onEncode,
  required bool Function() tokenizeFails,
  required void Function(int) onTokenize,
  required void Function(bool) onSpecial,
  bool Function()? encodeFails,
}) => ExitTeardownApi(
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
  mtmdHelperEvalChunks: real.mtmdHelperEvalChunks,
  mtmdHelperEvalChunkSingle: real.mtmdHelperEvalChunkSingle,
  mtmdHelperDecodeImageChunk: real.mtmdHelperDecodeImageChunk,
  schedGraphCompute: real.schedGraphCompute,
  mtmdEncodeChunk: (context, chunk) {
    onEncode();
    return encodeFails?.call() == true
        ? 1
        : real.mtmdEncodeChunk(context, chunk);
  },
  mtmdTokenize: (context, chunks, text, bitmaps, count) {
    onSpecial(text.ref.add_special);
    final status = tokenizeFails()
        ? 2
        : real.mtmdTokenize(context, chunks, text, bitmaps, count);
    if (status == 0) onTokenize(mtmd_helper_get_n_tokens(chunks));
    return status;
  },
);
