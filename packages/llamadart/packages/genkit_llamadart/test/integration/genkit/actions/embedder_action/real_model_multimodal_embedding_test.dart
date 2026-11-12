@TestOn('vm')
@Tags(['real-model', 'multimodal-embedding-model'])
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:image/image.dart' as image;
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../test_support/embedding_media.dart';

void main() {
  for (final liteRt in [false, true]) {
    test(
      'EmbeddingGemma-2 ${liteRt ? 'LiteRT-LM' : 'GGUF'} CPU matches ordered core embeddings',
      () async {
        final root = Platform.environment['GENKIT_MULTIMODAL_EMBED_MODELS'];
        if (root == null) {
          markTestSkipped(
            'Set GENKIT_MULTIMODAL_EMBED_MODELS to the pinned local fixture directory; no downloads.',
          );
          return;
        }
        final model = liteRt
            ? '$root/litert/embeddinggemma-2-740m.litertlm'
            : '$root/gguf/embeddinggemma-2-BF16.gguf';
        final projector = liteRt
            ? null
            : '$root/gguf/mmproj-embeddinggemma-2-BF16.gguf';
        Future<void> verify(String path, String digest) async => expect(
          (await sha256.bind(File(path).openRead()).first).toString(),
          digest,
        );
        await verify(
          model,
          liteRt
              ? 'e7a8a2204b91e0f96e92960e84a09a89212e1633dcb7575a9bf3378b4df77f4c'
              : '68bae29d62fb8c7d23e98d21fd4662753ddd636e6b62b8a70dfe059a9844f216',
        );
        if (projector != null) {
          await verify(
            projector,
            'd2033b3cd0223cfb2e7a2b50dc80a664c78c816d375f5b017ec3ef80ee0bc766',
          );
        }
        final cache = await Directory.systemTemp.createTemp(
          'genkit-embedding-proof-',
        );
        addTearDown(() => cache.delete(recursive: true));
        final params = liteRt
            ? LiteRtLmModelParams(
                device: ComputeDevice.cpu,
                embeddingEngine: true,
                cacheDir: cache.path,
                contextSize: 2048,
                numberOfThreads: 4,
              )
            : const LlamaCppModelParams(
                device: ComputeDevice.cpu,
                contextSize: 2048,
                batchSize: 2048,
                microBatchSize: 2048,
                numberOfThreads: 4,
                numberOfThreadsBatch: 4,
              );
        final png = Uint8List.fromList(
          image.encodePng(image.Image(width: 224, height: 224)),
        );
        final wav = embeddingToneWav();
        const text = 'The Eiffel Tower is in Paris.';
        final inputs = [
          LlamaEmbeddingInput([const llama.LlamaTextContent(text)]),
          LlamaEmbeddingInput([llama.LlamaImageContent(bytes: png)]),
          LlamaEmbeddingInput([llama.LlamaAudioContent(bytes: wav)]),
          LlamaEmbeddingInput([
            const llama.LlamaTextContent('first '),
            llama.LlamaImageContent(bytes: png),
            const llama.LlamaTextContent(' between '),
            llama.LlamaAudioContent(bytes: wav),
            const llama.LlamaTextContent(' last'),
          ]),
        ];
        final engine = await llama.LlamaEngine.load(
          llama.LlamaModel(
            ModelSource.path(model),
            projector: projector == null ? null : ModelSource.path(projector),
          ),
          params: params,
        );
        final List<List<double>> reference;
        try {
          final capabilities = await engine.embeddingCapabilities;
          expect(
            [capabilities.text, capabilities.image, capabilities.audio],
            [true, true, true],
          );
          reference = await engine.embedContentBatch(inputs);
        } finally {
          await engine.dispose();
        }
        MediaPart media(List<int> bytes, String type) => MediaPart(
          media: Media(
            url: UriData.fromBytes(bytes, mimeType: type).toString(),
            contentType: type,
          ),
        );
        final documents = [
          DocumentData(
            content: [TextPart(text: text)],
            metadata: {'id': 'text'},
          ),
          DocumentData(
            content: [media(png, 'image/png')],
            metadata: {'id': 'image'},
          ),
          DocumentData(
            content: [media(wav, 'audio/wav')],
            metadata: {'id': 'audio'},
          ),
          DocumentData(
            content: [
              TextPart(text: 'first '),
              media(png, 'image/png'),
              TextPart(text: ' between '),
              media(wav, 'audio/wav'),
              TextPart(text: ' last'),
            ],
            metadata: {'id': 'mixed'},
          ),
        ];
        final plugin = llamaDart(
          models: [
            LlamaModelDefinition(
              name: 'embed',
              modelPath: model,
              mmprojPath: projector,
              modelParams: params,
              supportsTools: false,
              supportsConstrainedOutput: false,
            ),
          ],
        );
        final ai = Genkit(plugins: [plugin], isDevEnv: false);
        try {
          final inspection = await plugin.inspectModel('embed');
          expect(inspection.embeddingCapabilities!.image, true);
          print(
            'Embedding proof: ${liteRt ? 'LiteRT-LM' : 'GGUF'}, ${inspection.capabilities?.backendName}, ${Platform.operatingSystem}/${Abi.current()}',
          );
          final embeddings = await ai.embed(
            embedder: llamaDart.embedder('embed'),
            documents: documents,
          );
          expect(embeddings.map((e) => e.metadata?['id']), [
            'text',
            'image',
            'audio',
            'mixed',
          ]);
          for (var i = 0; i < embeddings.length; i++) {
            final vector = embeddings[i].embedding;
            expect(vector, hasLength(768));
            expect(vector.every((v) => v.isFinite), true);
            final norm = math.sqrt(
              vector.fold<double>(0, (sum, v) => sum + v * v),
            );
            expect(norm, closeTo(1, 0.0001));
            final difference = [
              for (var j = 0; j < vector.length; j++)
                (vector[j] - reference[i][j]).abs(),
            ].reduce(math.max);
            expect(
              difference,
              lessThan(0.00001),
              reason:
                  'Adapter input ${documents[i].metadata?['id']} must match direct core.',
            );
          }
        } finally {
          await plugin.dispose();
          await ai.shutdown();
        }
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
