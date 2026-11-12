@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

// Gemma chat templates raise on consecutive user turns, so a cancelled turn
// that left its user message unanswered broke every later turn.
void main() {
  test(
    'a ChatSession turn cancelled mid-stream keeps roles alternating',
    () async {
      final model = Platform.environment['CHAT_SESSION_MODEL'];
      expect(
        model,
        isNotNull,
        reason:
            'Set CHAT_SESSION_MODEL to a GGUF with an alternating-role '
            'template, such as gemma-3-1b-it',
      );
      final engine = LlamaEngine(LlamaBackend());
      addTearDown(engine.dispose);
      await engine.loadModel(
        model!,
        modelParams: const ModelParams(contextSize: 1024, gpuLayers: 0),
      );
      final session = ChatSession(engine);
      const params = GenerationParams(temp: 0, seed: 1, maxTokens: 64);

      final partial = StringBuffer();
      await for (final chunk in session.create([
        const LlamaTextContent('Count from 1 to 40, separated by commas.'),
      ], params: params)) {
        partial.write(chunk.choices.firstOrNull?.delta.content ?? '');
        if (partial.length >= 8) break;
      }
      final next = StringBuffer();
      await for (final chunk in session.create([
        const LlamaTextContent('Reply with one short sentence saying hello.'),
      ], params: params)) {
        next.write(chunk.choices.firstOrNull?.delta.content ?? '');
      }
      final roles = [for (final message in session.history) message.role.name];
      print(
        jsonEncode({
          'partial': partial.toString(),
          'recorded': session.history[1].content,
          'roles': roles,
          'next': next.toString(),
        }),
      );

      expect(roles, ['user', 'assistant', 'user', 'assistant']);
      expect(session.history[1].content, isNotEmpty);
      expect(session.history[1].content, partial.toString());
      expect(next.toString().trim(), isNotEmpty);
    },
  );
}
