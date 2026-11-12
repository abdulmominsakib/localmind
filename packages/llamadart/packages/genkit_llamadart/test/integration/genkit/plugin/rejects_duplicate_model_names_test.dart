import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('plugin rejects duplicate model names', () {
    expect(
      () => LlamaDartPlugin(
        models: const <LlamaModelDefinition>[
          LlamaModelDefinition(name: 'local', modelPath: '/tmp/a.gguf'),
          LlamaModelDefinition(name: 'local', modelPath: '/tmp/b.gguf'),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
