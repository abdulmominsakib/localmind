import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';

import 'support/chat_model.dart';

Future<void> main() async {
  final prepared = await prepareExampleChat('agent');
  final ai = prepared.createGenkit();
  final temperature = ai.defineTool<Map<String, dynamic>, String>(
    name: 'lookup_demo_temperature',
    description:
        'Look up a city temperature from demo fixtures, not live weather.',
    inputSchema: SchemanticType.from(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'city': {
            'type': 'string',
            'enum': ['Seoul', 'Tokyo', 'San Francisco'],
          },
        },
        'required': ['city'],
      },
      parse: (json) => (json as Map).cast<String, dynamic>(),
    ),
    outputSchema: SchemanticType.string(),
    fn: (input, _) async {
      print('Tool: lookup_demo_temperature(${input['city']})');
      const values = {'Seoul': 19, 'Tokyo': 22, 'San Francisco': 14};
      return ToolResult.response(
        '${input['city']}: ${values[input['city']]} °C (demo data)',
      );
    },
  );
  final system = Message(
    role: Role.system,
    content: [
      TextPart(
        text:
            'Use the lookup tool for demo temperatures. Call it once per city. '
            'After the result, answer briefly and identify it as demo data.',
      ),
    ],
  );
  var history = <Message>[system];
  final oneShot = Platform.environment['LLAMADART_PROMPT'];
  try {
    if (oneShot == null) {
      print('Ask for a demo temperature in Seoul, Tokyo or San Francisco.');
      print('Type clear to reset history or quit to exit.');
    }
    while (true) {
      if (oneShot == null) stdout.write('user> ');
      final prompt = oneShot ?? stdin.readLineSync();
      if (prompt == null || prompt == 'quit') break;
      if (prompt == 'clear') {
        history = [system];
        if (oneShot != null) break;
        continue;
      }
      if (prompt.trim().isEmpty) {
        if (oneShot != null) break;
        continue;
      }
      final response = await ai.generate(
        messages: history,
        prompt: prompt,
        tools: [temperature],
        maxTurns: 4,
        config: const LlamaDartGenerationConfig(
          temperature: 0,
          seed: 42,
          maxTokens: 256,
        ),
      );
      if (response.finishReason == FinishReason.failed ||
          response.finishReason == FinishReason.aborted) {
        throw response.cause ?? StateError('Agent did not complete.');
      }
      print(response.text);
      history = response.messages;
      if (oneShot != null) break;
    }
  } finally {
    try {
      await prepared.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
