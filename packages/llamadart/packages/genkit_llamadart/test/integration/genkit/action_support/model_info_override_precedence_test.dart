import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/integration/genkit/action_support.dart';
import 'package:test/test.dart';

void main() {
  test('modelInfo cannot override unverified or disabled capabilities', () {
    final modelInfo = modelInfoFor(
      LlamaModelDefinition(
        name: 'local',
        modelPath: '/tmp/model.gguf',
        supportsTools: false,
        modelInfo: genkit.ModelInfo(
          label: 'Custom label',
          supports: <String, dynamic>{'tools': true, 'customCapability': true},
        ),
      ),
    );

    expect(modelInfo.label, 'Custom label');
    expect(modelInfo.supports, containsPair('tools', false));
    expect(modelInfo.supports, containsPair('toolChoice', false));
    expect(modelInfo.supports, containsPair('customCapability', true));
  });
}
