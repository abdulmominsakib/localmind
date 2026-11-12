@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/integration/genkit/actions/embedder_action.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_embedding_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  final request = genkit.EmbedRequest(
    input: [
      genkit.DocumentData(
        content: [
          genkit.TextPart(text: 'describe'),
          genkit.MediaPart(
            media: genkit.Media(
              url: 'https://private.example/audio.wav?secret',
              contentType: 'audio/wav',
            ),
          ),
        ],
      ),
    ],
  );
  test(
    'native remote media uses the plugin resolver and preserves encoded bytes',
    () async {
      final runtime = FakeEmbeddingRuntime()
        ..embeddings = [
          [1.0],
        ];
      final resolver = _Resolver();
      final plugin = LlamaDartPlugin(
        models: [testModelDefinition()],
        runtimeFactory: () => runtime,
        mediaResolver: resolver,
      );
      final ai = genkit.Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      await ai.embed(
        embedder: llamaDart.embedder('local'),
        document: request.input.single,
      );
      expect(resolver.calls, 1);
      expect(
        (runtime.inputs!.single.parts.last as llama.LlamaAudioContent).bytes,
        [1, 2, 3],
      );
      runtime.embeddingSnapshot = const LlamaEmbeddingCapabilities(text: true);
      await expectLater(
        ai.embed(
          embedder: llamaDart.embedder('local'),
          document: request.input.single,
        ),
        throwsA(isA<genkit.GenkitException>()),
      );
      expect(
        resolver.calls,
        1,
        reason: 'Reject unsupported audio before downloading.',
      );
      expect(runtime.contentCalls, 1);
    },
  );

  test('resolver failure is sanitized and cannot enter inference', () async {
    final runtime = FakeEmbeddingRuntime();
    final resolver = _Resolver()
      ..error = StateError('https://private.example/?secret');
    final registry = testRegistry(runtime: runtime);
    addTearDown(registry.dispose);
    final action = buildEmbedderAction(
      definition: testModelDefinition(),
      registry: registry,
      mediaResolver: resolver,
    );
    await expectLater(
      action(request),
      throwsA(
        isA<genkit.GenkitException>().having(
          (e) => '$e',
          'message',
          isNot(contains('secret')),
        ),
      ),
    );
    expect(runtime.contentCalls, 0);
  });

  test(
    'cancellation during resolution never cancels the idle backend',
    () async {
      final runtime = FakeEmbeddingRuntime();
      final resolver = _Resolver()..block = true;
      final registry = testRegistry(runtime: runtime);
      addTearDown(() async {
        if (!resolver.release.isCompleted) resolver.release.complete();
        await registry.dispose();
      });
      final action = buildEmbedderAction(
        definition: testModelDefinition(),
        registry: registry,
        mediaResolver: resolver,
      );
      final controller = genkit.CancellationController();
      final cancelled = expectLater(
        action(request, cancel: controller.token),
        throwsA(isA<genkit.CancelledException>()),
      );
      await resolver.started.future;
      controller.cancel();
      resolver.release.complete();
      await cancelled;
      expect(runtime.contentCalls, 0);
      expect(runtime.cancelGenerationCount, 0);
    },
  );
}

class _Resolver implements LlamaDartMediaResolver {
  int calls = 0;
  bool block = false;
  Object? error;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<Uint8List> resolve(
    Uri uri, {
    required String contentType,
    genkit.CancellationToken? cancel,
  }) async {
    calls++;
    if (!started.isCompleted) started.complete();
    if (block) await release.future;
    if (error != null) throw error!;
    return Uint8List.fromList([1, 2, 3]);
  }
}
