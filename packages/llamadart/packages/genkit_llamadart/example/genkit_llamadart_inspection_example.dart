import 'package:genkit_llamadart/genkit_llamadart.dart';

import 'support/chat_model.dart';

Future<void> main() async {
  final prepared = await prepareExampleChat('inspection');
  try {
    final snapshot = await prepared.inspect();
    print('Backend: ${snapshot.capabilities?.backendName}');
    print('Loaded context capacity: ${snapshot.contextSize} tokens');
    const prompt = 'Once upon a time';
    print(
      'Raw text tokens (excluding chat template): ${await prepared.countTokens(prompt)}',
    );
    final scores = await prepared.plugin.scorer(prepared.definition.name)(
      LlamaDartScoringRequest(prompt: prompt, topK: 5),
    );
    for (final token in scores.top) {
      print('${token.token}: ${token.text} (${token.probability})');
    }
  } finally {
    await prepared.dispose();
  }
}
