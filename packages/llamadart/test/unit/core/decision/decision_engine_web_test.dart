@TestOn('browser')
library;

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  const reason = 'Load a model first.';

  test('the Web backend asks for a model before probing', () async {
    final engine = LlamaEngine(LlamaBackend());
    addTearDown(engine.dispose);

    final capabilities = await DecisionEngine.capabilitiesFor(engine);

    expect(capabilities.isSupported, isFalse);
    expect(capabilities.unsupportedReason, reason);
  });

  test('attach without a model throws before fetching', () async {
    final engine = LlamaEngine(LlamaBackend());
    addTearDown(engine.dispose);

    await expectLater(
      DecisionEngine.attach(
        engine,
        head: ModelSource.path('laya-head.safetensors'),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          reason,
        ),
      ),
    );
  });

  test('load rejects download options the browser fetch cannot apply '
      'before loading anything', () async {
    await expectLater(
      DecisionEngine.load(
        DecisionModel(
          encoder: ModelSource.parse('https://example.com/laya-Q8_0.gguf'),
          head: ModelSource.path('laya-head.safetensors'),
        ),
        download: ModelLoadOptions(bearerToken: 'secret'),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          allOf(
            'Authenticated decision model URL loading requires the native '
            'download/cache manager.',
            isNot(contains('secret')),
          ),
        ),
      ),
    );
  });
}
