import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_embedding_runtime.dart';
import '../test_support/action_harness.dart';

genkit.MediaPart media(String url, String type) => genkit.MediaPart(
  media: genkit.Media(url: url, contentType: type),
);

void main() {
  test(
    'typed text respects embedding probes and keeps empty-document semantics',
    () async {
      final runtime = FakeEmbeddingRuntime()
        ..embeddings = [
          [1.0],
          [2.0],
        ];
      final action = testEmbedderAction(runtime: runtime);
      final request = genkit.EmbedRequest(
        input: [
          genkit.DocumentData(content: []),
          genkit.DocumentData(
            content: [genkit.ReasoningPart(reasoning: 'private')],
          ),
        ],
      );
      await action(request);
      expect(
        runtime.inputs!.map(
          (i) => (i.parts.single as llama.LlamaTextContent).text,
        ),
        ['', ''],
      );
      expect(runtime.lastNormalize, true);
      runtime.embeddingSnapshot = const LlamaEmbeddingCapabilities(image: true);
      await expectLater(
        action(request),
        throwsA(isA<genkit.GenkitException>()),
      );
      expect(runtime.contentCalls, 1);
    },
  );
  test(
    'Genkit preserves ordered mixed inputs, normalization and metadata',
    () async {
      final runtime = FakeEmbeddingRuntime()
        ..capabilitySnapshot = const llama.LlamaEngineCapabilities(
          isSupported: true,
        )
        ..embeddings = [
          [1, 0],
          [0, 1],
        ];
      final plugin = LlamaDartPlugin(
        models: [testModelDefinition()],
        runtimeFactory: () => runtime,
      );
      final ai = genkit.Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final listings = await plugin.list();
      final listing = listings.singleWhere((a) => a.actionType == .embedder);
      Map supports() => (listing.metadata['model'] as Map)['supports'] as Map;
      expect(supports()['media'], false);
      final response = await ai.embed(
        embedder: llamaDart.embedder('local'),
        documents: [
          genkit.DocumentData(
            content: [
              genkit.TextPart(text: 'before '),
              media('data:image/png;base64,AQID', 'image/png'),
              genkit.ReasoningPart(reasoning: 'private'),
              genkit.TextPart(text: ' between '),
              media('data:audio/wav;base64,BAUG', 'audio/wav'),
              genkit.TextPart(text: ' after'),
            ],
            metadata: {'id': 'mixed'},
          ),
          genkit.DocumentData(
            content: [genkit.TextPart(text: 'other')],
            metadata: {'id': 'text'},
          ),
        ],
        options: const LlamaDartEmbedConfig(normalize: false),
      );
      expect(response.map((e) => e.metadata?['id']), ['mixed', 'text']);
      expect(response.map((e) => e.embedding), [
        [1, 0],
        [0, 1],
      ]);
      expect(runtime.inputs!.first.partKinds, [
        LlamaEmbeddingModality.text,
        LlamaEmbeddingModality.image,
        LlamaEmbeddingModality.text,
        LlamaEmbeddingModality.audio,
        LlamaEmbeddingModality.text,
      ]);
      final parts = runtime.inputs!.first.parts;
      expect((parts[0] as llama.LlamaTextContent).text, 'before ');
      expect((parts[1] as llama.LlamaImageContent).bytes, [1, 2, 3]);
      expect((parts[2] as llama.LlamaTextContent).text, ' between ');
      expect((parts[3] as llama.LlamaAudioContent).bytes, [4, 5, 6]);
      expect((parts[4] as llama.LlamaTextContent).text, ' after');
      expect(runtime.lastNormalize, false);
      expect(runtime.embedBatchCallCount, 0);
      expect(supports()['media'], true);
      expect(supports()['embeddings'], true);
      final inspection = await plugin.inspectModel('local');
      expect(inspection.embeddingCapabilities!.audio, true);
      expect(inspection.capabilities!.supportsAudio, false);
      runtime.embeddingSnapshot = const LlamaEmbeddingCapabilities(
        text: true,
        mediaUnsupportedReason: '/private/model?secret',
      );
      final changed = await plugin.inspectModel('local');
      expect(changed.embeddingCapabilities!.mediaUnsupportedReason, isNull);
      expect(changed.embeddingCapabilities!.audio, false);
      expect(inspection.embeddingCapabilities!.audio, true);
      expect(supports()['media'], false);
    },
  );

  test('all modalities are checked before any batch inference', () async {
    final runtime = FakeEmbeddingRuntime()
      ..embeddingSnapshot = const LlamaEmbeddingCapabilities(
        text: true,
        image: true,
      );
    final action = testEmbedderAction(runtime: runtime);
    await expectLater(
      action(
        genkit.EmbedRequest(
          input: [
            genkit.DocumentData(content: [media('/image.png', 'image/png')]),
            genkit.DocumentData(content: [media('/audio.wav', 'audio/wav')]),
          ],
        ),
      ),
      throwsA(
        isA<genkit.GenkitException>().having(
          (e) => e.status,
          'status',
          genkit.StatusCode.unimplemented,
        ),
      ),
    );
    expect(runtime.contentCalls, 0);
    runtime.embeddingSnapshot = const LlamaEmbeddingCapabilities(image: true);
    await expectLater(
      action(
        genkit.EmbedRequest(
          input: [
            genkit.DocumentData(
              content: [
                genkit.TextPart(text: 'prefix'),
                media('/image.png', 'image/png'),
              ],
            ),
          ],
        ),
      ),
      throwsA(isA<genkit.GenkitException>()),
    );
    expect(runtime.embeddingProbeCount, 2);
    expect(runtime.contentCalls, 0);
  });

  test(
    'unsupported parts and malformed data reject before initialization',
    () async {
      for (final part in [
        media('file:///private/video.mp4?secret', 'video/mp4'),
        genkit.ToolResponsePart(
          toolResponse: genkit.ToolResponse(name: 'tool', output: 'secret'),
        ),
        genkit.MediaPart(
          media: genkit.Media(url: 'data:image/png;base64,%invalid'),
        ),
      ]) {
        final runtime = FakeEmbeddingRuntime();
        await expectLater(
          testEmbedderAction(runtime: runtime)(
            genkit.EmbedRequest(
              input: [
                genkit.DocumentData(content: [part]),
              ],
            ),
          ),
          throwsA(
            isA<genkit.GenkitException>().having(
              (e) => e.status,
              'status',
              genkit.StatusCode.invalidArgument,
            ),
          ),
        );
        expect(runtime.initializeCount, 0);
      }
    },
  );

  test(
    'probe failures are sanitized and incorrect vector counts are rejected',
    () async {
      final runtime = FakeEmbeddingRuntime()
        ..probeError = StateError('/private/secret?token=credential');
      final action = testEmbedderAction(runtime: runtime);
      final request = genkit.EmbedRequest(
        input: [
          genkit.DocumentData(content: [media('/image.png', 'image/png')]),
        ],
      );
      await expectLater(
        action(request),
        throwsA(
          isA<LlamaStateException>().having(
            (e) => '$e',
            'message',
            isNot(contains('secret')),
          ),
        ),
      );
      runtime.probeError = null;
      await expectLater(
        action(request),
        throwsA(
          isA<genkit.GenkitException>().having(
            (e) => e.status,
            'status',
            genkit.StatusCode.internal,
          ),
        ),
      );
    },
  );
}
