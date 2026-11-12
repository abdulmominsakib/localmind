import 'package:genkit/plugin.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('plugin init and list skip embedder actions when disabled', () async {
    final plugin = LlamaDartPlugin(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(
          name: 'local',
          modelPath: '/tmp/model.gguf',
          supportsEmbeddings: false,
          supportsTools: false,
          supportsConstrainedOutput: false,
        ),
      ],
    );

    final actions = await plugin.init();
    final metadata = await plugin.list();

    expect(actions.map((a) => a.actionType), [
      ActionType.model,
      LlamaDartPlugin.scoringActionType,
    ]);
    expect(metadata.map((a) => a.actionType), [
      ActionType.model,
      LlamaDartPlugin.scoringActionType,
    ]);

    final model = metadata.first.metadata['model']! as Map<String, dynamic>;
    final supports = model['supports']! as Map<String, dynamic>;
    expect(supports['tools'], isFalse);
    expect(supports['toolChoice'], isFalse);
    expect(supports['constrained'], isFalse);
    expect(supports['constrainedWithTools'], isFalse);
    expect(supports['embeddings'], isFalse);
  });
}
