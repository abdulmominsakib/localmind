@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import '../../../test_helper.dart';

void main() async {
  late File modelFile;
  late LlamaEngine engine;
  late LlamaBackend backend;
  late ChatSession session;

  setUpAll(() async {
    modelFile = await TestHelper.getTestModel();
    backend = LlamaBackend();
    engine = LlamaEngine(backend);
    await engine.loadModel(
      modelFile.path,
      modelParams: const ModelParams(
        contextSize: 256,
        gpuLayers: 0, // Disable GPU for stability on CI
      ),
    );
  });

  setUp(() {
    session = ChatSession(engine);
  });

  tearDownAll(() async {
    await engine.dispose();
  });

  group('ChatSession Integration Tests', () {
    test('Initial state', () {
      expect(session.history, isEmpty);
      expect(session.systemPrompt, isNull);
    });

    test('Add message to history', () {
      session.addMessage(
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'hello',
        ),
      );
      expect(session.history.length, 1);
      expect(session.history.first.content, 'hello');
    });

    test('Chat updates history', () async {
      final response = await session.create([
        const LlamaTextContent('Once upon a time'),
      ], params: const GenerationParams(maxTokens: 50)).join();

      expect(response, isNotEmpty);
      expect(session.history.length, 2);
      expect(session.history[0].role, LlamaChatRole.user);
      expect(session.history[0].content, 'Once upon a time');
      expect(session.history[1].role, LlamaChatRole.assistant);
      expect(session.history[1].content, isNotEmpty);
    });

    test('System prompt persistence', () async {
      session.systemPrompt = "You are a helpful assistant.";
      expect(session.systemPrompt, "You are a helpful assistant.");

      await session.create([
        const LlamaTextContent('Hi'),
      ], params: const GenerationParams(maxTokens: 50)).drain();
      // History should only contain user/assistant messages, system prompt is handled internally
      expect(session.history.length, 2);
    });

    test('Reset clears history', () {
      session.addMessage(
        const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'test'),
      );
      session.reset();
      expect(session.history, isEmpty);
    });

    test('Reset session', () {
      session.systemPrompt = "System";
      session.addMessage(
        const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'test'),
      );

      // Default reset (keeps system prompt)
      session.reset();
      expect(session.history, isEmpty);
      expect(session.systemPrompt, "System");

      // Full reset
      session.reset(keepSystemPrompt: false);
      expect(session.systemPrompt, isNull);
    });

    test('History immutability via getter', () {
      expect(
        () => session.history.add(
          const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'x'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
