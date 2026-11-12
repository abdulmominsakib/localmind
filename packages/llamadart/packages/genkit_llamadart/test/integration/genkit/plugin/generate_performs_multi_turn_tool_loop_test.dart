import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';

final SchemanticType<Map<String, dynamic>> _weatherInputSchema =
    _WeatherInputSchema();

void main() {
  test('Genkit tool loop preserves delimiter text in arguments', () async {
    final runtime = FakeRuntime()
      ..createScripts.addAll(<List<llama.LlamaCompletionChunk>>[
        <llama.LlamaCompletionChunk>[
          textChunk(
            '<tool_call>{"name":"get_weather","arguments":{"location":"Seoul","note":"<tool_call>"}}</tool_call>',
          ),
          stopChunk(),
        ],
        <llama.LlamaCompletionChunk>[
          textChunk('The weather in Seoul is clear and 19C.'),
          stopChunk(),
        ],
        <llama.LlamaCompletionChunk>[
          textChunk('Bring sunglasses and a light jacket.'),
          stopChunk(),
        ],
      ]);

    final plugin = LlamaDartPlugin(
      models: const <LlamaModelDefinition>[
        LlamaModelDefinition(name: 'local', modelPath: '/tmp/model.gguf'),
      ],
      runtimeFactory: () => runtime,
    );
    final ai = Genkit(plugins: <LlamaDartPlugin>[plugin]);

    final weatherTool = ai.defineTool<Map<String, dynamic>, String>(
      name: 'get_weather',
      description:
          'Get current weather for a location. Input JSON key: location.',
      inputSchema: _weatherInputSchema,
      outputSchema: SchemanticType.string(),
      fn: (input, _) async {
        expect(input['location'], 'Seoul');
        expect(input['note'], '<tool_call>');
        return ToolResult.response('Seoul is clear and 19C.');
      },
    );

    final firstResponse = await ai.generate(
      model: llamaDart.model('local'),
      prompt: 'What is the weather in Seoul?',
      tools: <Tool<Map<String, dynamic>, String>>[weatherTool],
      maxTurns: 4,
      config: const LlamaDartGenerationConfig(enableThinking: false),
    );

    expect(firstResponse.text, 'The weather in Seoul is clear and 19C.');
    expect(firstResponse.messages, hasLength(4));
    expect(firstResponse.messages[1].toolRequests, hasLength(1));
    expect(firstResponse.messages[2].role, Role.tool);
    expect(runtime.createCallCount, 2);
    expect(
      runtime.recordedMessages[1].any(
        (message) => message.role == llama.LlamaChatRole.tool,
      ),
      isTrue,
    );

    final secondResponse = await ai.generate(
      model: llamaDart.model('local'),
      messages: <Message>[
        ...firstResponse.messages,
        Message(
          role: Role.user,
          content: <Part>[TextPart(text: 'What should I wear?')],
        ),
      ],
      tools: <Tool<Map<String, dynamic>, String>>[weatherTool],
      maxTurns: 4,
      config: const LlamaDartGenerationConfig(enableThinking: false),
    );

    expect(secondResponse.text, 'Bring sunglasses and a light jacket.');
    expect(runtime.createCallCount, 3);
    expect(
      runtime.recordedMessages[2].any(
        (message) => message.role == llama.LlamaChatRole.tool,
      ),
      isTrue,
    );

    await plugin.dispose();
    await ai.shutdown();
  });
}

final class _WeatherInputSchema extends SchemanticType<Map<String, dynamic>> {
  @override
  Map<String, dynamic> parse(Object? json) {
    if (json is Map<String, dynamic>) {
      return json;
    }
    if (json is Map) {
      return json.cast<String, dynamic>();
    }
    throw const FormatException('Expected a JSON object.');
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'WeatherInput',
    definition: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'location': <String, Object?>{
          'type': 'string',
          'description': 'Location to look up.',
        },
      },
      'required': <String>['location'],
    },
  );
}
