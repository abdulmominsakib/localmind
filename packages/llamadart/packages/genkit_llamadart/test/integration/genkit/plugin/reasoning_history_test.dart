import 'dart:convert';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';

const _template =
    '''{% for message in messages %}{{ message['role'] }}:{{ message['content'] }}{% if message['reasoning_content'] is defined %}{{ message['reasoning_content'] }}{% endif %}
{% endfor %}''';

void main() {
  test('reasoning is omitted in every role without mutating history', () {
    final messages = [
      for (final (role, label) in [
        (Role.system, 'system'),
        (Role.user, 'user'),
        (Role.model, 'model'),
      ])
        Message(
          role: role,
          content: [
            ReasoningPart(reasoning: 'PRIVATE_$label'),
            TextPart(text: 'visible_$label'),
          ],
        ),
      Message(
        role: Role.tool,
        content: [
          ReasoningPart(reasoning: 'TOOL_PRIVATE'),
          ToolResponsePart(
            toolResponse: ToolResponse(
              name: 'lookup',
              ref: 'call',
              output: 'visible tool result',
            ),
          ),
        ],
      ),
      Message(
        role: Role.model,
        content: [ReasoningPart(reasoning: 'ONLY')],
      ),
    ];
    final before = jsonEncode(messages.map((m) => m.toJson()).toList());
    final converted = toLlamaMessages(messages);
    expect(converted.map((m) => m.role), [
      llama.LlamaChatRole.system,
      llama.LlamaChatRole.user,
      llama.LlamaChatRole.assistant,
      llama.LlamaChatRole.tool,
      llama.LlamaChatRole.assistant,
    ]);
    expect(converted.last.content, isEmpty);
    expect(
      converted.expand((m) => m.parts).whereType<llama.LlamaThinkingContent>(),
      isEmpty,
    );
    final rendered = llama.ChatTemplateEngine.render(
      templateSource: _template,
      messages: converted,
      metadata: const {},
      addAssistant: false,
    ).prompt;
    expect(rendered, contains('visible_model'));
    expect(rendered, isNot(contains('PRIVATE')));
    expect(rendered, isNot(contains('ONLY')));
    expect(rendered, contains('visible tool result'));
    expect(jsonEncode(messages.map((m) => m.toJson()).toList()), before);
  });

  test('ordinary turns retain output reasoning but never replay it', () async {
    final runtime = FakeRuntime()
      ..createScripts.addAll([
        [
          thinkingChunk('PRIVATE_REASONING'),
          textChunk('first answer'),
          stopChunk(),
        ],
        [textChunk('second answer'), stopChunk()],
      ]);
    final plugin = LlamaDartPlugin(
      models: const [LlamaModelDefinition(name: 'local', modelPath: '/unused')],
      runtimeFactory: () => runtime,
    );
    final ai = Genkit(plugins: [plugin], isDevEnv: false);
    addTearDown(() async {
      await plugin.dispose();
      await ai.shutdown();
    });
    final stream = ai.generateStream(
      model: llamaDart.model('local'),
      prompt: 'first',
    );
    final chunks = await stream.toList();
    expect(
      chunks
          .expand((chunk) => chunk.content)
          .where((p) => p.isReasoning)
          .single
          .reasoning,
      'PRIVATE_REASONING',
    );
    final first = await stream.onResult;
    expect(
      first.messages.last.content.where((p) => p.isReasoning).single.reasoning,
      'PRIVATE_REASONING',
    );
    final second = await ai.generate(
      model: llamaDart.model('local'),
      messages: first.messages,
      prompt: 'second',
    );
    expect(second.text, 'second answer');
    expect(
      second.messages
          .expand((m) => m.content)
          .where((p) => p.isReasoning)
          .single
          .reasoning,
      'PRIVATE_REASONING',
    );
    final rendered = llama.ChatTemplateEngine.render(
      templateSource: _template,
      messages: runtime.recordedMessages.last,
      metadata: const {},
      addAssistant: false,
    ).prompt;
    expect(rendered, contains('first answer'));
    expect(rendered, contains('second'));
    expect(rendered, isNot(contains('PRIVATE_REASONING')));
  });

  test(
    'constrained output omits reasoning before rendering the prompt',
    () async {
      final runtime = FakeRuntime()..generatedTokens = ['"done"'];
      final plugin = LlamaDartPlugin(
        models: const [
          LlamaModelDefinition(name: 'local', modelPath: '/unused'),
        ],
        runtimeFactory: () => runtime,
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final result = await ai.generate<String, LlamaDartGenerationConfig>(
        model: llamaDart.model('local'),
        messages: [
          Message(
            role: Role.model,
            content: [
              ReasoningPart(reasoning: 'PRIVATE'),
              TextPart(text: 'visible'),
            ],
          ),
        ],
        prompt: 'Return a JSON string.',
        outputSchema: SchemanticType.string(),
        outputFormat: 'json',
        outputConstrained: true,
      );
      expect(
        result.finishReason,
        FinishReason.stop,
        reason: '${result.error} ${result.cause}',
      );
      expect(result.output, 'done');
      expect(runtime.chatTemplateCallCount, 1);
      expect(runtime.lastMessages!.first.content, 'visible');
      expect(
        runtime.lastMessages!
            .expand((m) => m.parts)
            .whereType<llama.LlamaThinkingContent>(),
        isEmpty,
      );
    },
  );
}
