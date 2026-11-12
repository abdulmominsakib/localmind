import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import 'engine_test.dart' show MockLlamaBackend;

void main() {
  test(
    'public backend SPI rejects unsafe automatic loops before mutation',
    () async {
      final backend = _UnsupportedLimitBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('qwen-test.gguf');
      final session = ChatSession(engine, maxContextTokens: 0);
      final prior = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'prior',
      );
      session.addMessage(prior);
      var callbacks = 0;
      await expectLater(
        session.sendWithTools(
          'next',
          tools: const [],
          onMessageAdded: (_) => callbacks++,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('custom runtime has no terminal reason'),
          ),
        ),
      );
      expect(session.history, [same(prior)]);
      expect(callbacks, 0);
      expect(backend.lastGenerationPrompt, isNull);
    },
  );

  for (final backend in [
    _UnsupportedLimitBackend()..reason = null,
    MockLlamaBackend(),
  ]) {
    test(
      'public backend SPI preserves undeclared support ${backend.runtimeType}',
      () async {
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('qwen-test.gguf');
        final session = ChatSession(engine, maxContextTokens: 0);
        final reply = await session.sendWithTools('hello', tools: const []);
        expect(reply.stopReason, LlamaToolLoopStopReason.completed);
        expect(reply.completion.text, 'response');
        expect(session.history, hasLength(2));
      },
    );
  }
}

class _UnsupportedLimitBackend extends MockLlamaBackend
    implements BackendGenerationLimitSupport {
  String? reason = 'The custom runtime has no terminal reason.';

  @override
  String? get generationLimitUnsupportedReason => reason;
}
