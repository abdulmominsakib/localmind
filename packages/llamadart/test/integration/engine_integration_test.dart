@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import '../test_helper.dart';

void main() async {
  late File modelFile;
  late LlamaEngine engine;
  late LlamaBackend backend;

  setUpAll(() async {
    modelFile = await TestHelper.getTestModel();
    backend = LlamaBackend();
    engine = LlamaEngine(backend);
  });

  tearDownAll(() async {
    await engine.dispose();
  });

  group('LlamaEngine Integration', () {
    test('full lifecycle: load, tokenize, generate, metadata', () async {
      // 1. Load Model
      await engine.loadModel(
        modelFile.path,
        modelParams: const ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          contextSize: 256,
        ),
      );
      expect(engine.isReady, isTrue);
      expect(engine.modelHandle, isNotNull);
      expect(engine.contextHandle, isNotNull);

      // 2. Tokenize
      final tokens = await engine.tokenize('Once upon a time');
      expect(tokens, isNotEmpty);

      // 3. Detokenize
      final text = await engine.detokenize(tokens);
      expect(text, contains('Once upon a time'));

      // 4. Create (Chat)
      final messages = [
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'The dog',
        ),
      ];
      final result = await engine
          .create(messages, params: const GenerationParams(maxTokens: 10))
          .map((chunk) => chunk.choices.first.delta.content ?? '')
          .join();
      expect(result, isNotEmpty);
      print('Generated: "$result"');

      // 5. Metadata
      final metadata = await engine.getMetadata();
      expect(metadata, isNotEmpty);
      expect(metadata['general.architecture'], 'llama');

      final modelFileType = await engine.getModelFileType();
      expect(modelFileType, isNotNull);
      final fileType = modelFileType!;
      expect(fileType.id, greaterThanOrEqualTo(0));
      expect(fileType.name, isNotEmpty);

      // 6. Backend Info
      expect(await engine.getBackendName(), isNotEmpty);
      expect(await engine.isGpuSupported(), isA<bool>());

      // 7. Context Size
      final ctxSize = await engine.getContextSize();
      expect(ctxSize, 256);

      // 8. Chat Template
      final chatMessages = [
        const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
      ];
      final templateResult = await engine.chatTemplate(chatMessages);
      expect(templateResult.prompt, isNotEmpty);
      expect(templateResult.tokenCount, greaterThan(0));

      // 9. Token Count
      final count = await engine.getTokenCount('Once upon a time');
      expect(count, greaterThan(0));
    });

    test('Chat interface via ChatSession', () async {
      if (!engine.isReady) {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(
            numberOfThreads: 2,
            numberOfThreadsBatch: 2,
            contextSize: 256,
          ),
        );
      }

      final messages = [
        const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
      ];
      final result = await engine
          .create(messages, params: const GenerationParams(maxTokens: 10))
          .map((chunk) => chunk.choices.first.delta.content ?? '')
          .join();
      expect(result, isNotEmpty);
      print('Chat Response: "$result"');
    });

    test('Cancel generation', () async {
      if (!engine.isReady) {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(
            numberOfThreads: 2,
            numberOfThreadsBatch: 2,
            contextSize: 256,
          ),
        );
      }

      // The grammar has no way to end, so only cancellation or the token
      // limit stops the stream; a model's own end-of-text cannot.
      const maxTokens = 200;
      final stream = engine.create(
        [
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Long story about a cat',
          ),
        ],
        params: const GenerationParams(
          maxTokens: maxTokens,
          streamBatchTokenThreshold: 1,
          grammar: 'root ::= "a" root',
        ),
      );

      var deltas = 0;
      final firstToken = Completer<void>();
      final streamDone = Completer<void>();
      final subscription = stream.listen(
        (chunk) {
          if ((chunk.choices.first.delta.content ?? '').isNotEmpty) {
            deltas++;
          }
          if (deltas > 0 && !firstToken.isCompleted) {
            firstToken.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!firstToken.isCompleted) {
            firstToken.completeError(error, stackTrace);
          }
          if (!streamDone.isCompleted) {
            streamDone.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!firstToken.isCompleted) {
            firstToken.completeError(
              StateError('Stream closed before the first token'),
            );
          }
          if (!streamDone.isCompleted) {
            streamDone.complete();
          }
        },
      );

      try {
        await firstToken.future.timeout(const Duration(seconds: 60));
        engine.cancelGeneration();
        await streamDone.future.timeout(const Duration(seconds: 30));
      } finally {
        await subscription.cancel();
      }

      expect(deltas, lessThan(maxTokens));
    });

    test(
      'loadModelFromUrl throws LlamaUnsupportedException on Native',
      () async {
        final freshBackend = LlamaBackend();
        final freshEngine = LlamaEngine(freshBackend);
        try {
          await expectLater(
            freshEngine.loadModelFromUrl('http://test'),
            throwsA(isA<LlamaUnsupportedException>()),
          );
        } finally {
          await freshEngine.dispose();
        }
      },
    );

    test('getContextSize prefers active context over metadata', () async {
      // Use a fresh engine to avoid disrupting the shared one and to test cleanup
      final tempBackend = LlamaBackend();
      final tempEngine = LlamaEngine(tempBackend);

      try {
        await tempEngine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(
            numberOfThreads: 2,
            numberOfThreadsBatch: 2,
            contextSize: 512,
          ),
        );
        final size = await tempEngine.getContextSize();
        expect(size, 512);
      } finally {
        await tempEngine.dispose();
      }
    });

    test('Error when not initialized', () async {
      final freshBackend = LlamaBackend();
      final freshEngine = LlamaEngine(freshBackend);
      await expectLater(
        freshEngine.create([
          const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ]),
        emitsError(isA<LlamaContextException>()),
      );
      await freshEngine.dispose();
    });
  });
}
