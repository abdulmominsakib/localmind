import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/core/engine/chat_completion_request_planner.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:test/test.dart';

void main() {
  group('ChatCompletionRequestPlanner', () {
    test('merges template grammar, stop sequences, and preserved tokens', () {
      final backend = _NativeChatBackend();
      final plan = ChatCompletionRequestPlanner.build(
        backend: backend,
        templateResult: const LlamaChatTemplateResult(
          prompt: 'prompt',
          grammar: 'template ::= "ok"',
          grammarLazy: true,
          additionalStops: ['</s>'],
          preservedTokens: ['<tool>'],
          grammarTriggers: [GrammarTrigger(type: 0, value: '<tool>')],
        ),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        params: const GenerationParams(
          stopSequences: ['STOP'],
          grammar: 'caller ::= "ignored"',
          preservedTokens: ['<caller>'],
        ),
        tools: [_weatherTool],
        toolChoice: ToolChoice.auto,
        parallelToolCalls: false,
      );

      expect(plan.generationParams.stopSequences, ['</s>', 'STOP']);
      expect(plan.generationParams.grammar, 'template ::= "ok"');
      expect(plan.generationParams.grammarLazy, isTrue);
      expect(plan.generationParams.grammarTriggers.single.value, '<tool>');
      expect(plan.generationParams.preservedTokens, ['<tool>', '<caller>']);
      expect(plan.nativeChatBackend, same(backend));
      expect(plan.parseToolCallsEnabled, isTrue);
    });

    test('rejects strict response format when backend cannot use grammar', () {
      expect(
        () => ChatCompletionRequestPlanner.build(
          backend: _NoGrammarBackend(),
          templateResult: const LlamaChatTemplateResult(
            prompt: 'prompt',
            grammar: 'root ::= "ok"',
          ),
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
          ],
          toolChoice: ToolChoice.auto,
          parallelToolCalls: false,
          responseFormat: const {'type': 'json_object'},
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('resolves omitted thinking-budget tags from the chat template', () {
      final plan = ChatCompletionRequestPlanner.build(
        backend: _NativeChatBackend(),
        templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        params: const GenerationParams(
          thinkingBudget: ThinkingBudget(maxTokens: 64),
        ),
        toolChoice: ToolChoice.auto,
        parallelToolCalls: false,
      );

      expect(plan.generationParams.thinkingBudget?.maxTokens, 64);
      expect(plan.generationParams.thinkingBudget?.startTag, '<think>');
      expect(plan.generationParams.thinkingBudget?.endTag, '</think>');
    });

    test(
      'falls back to rendered prompt when native chat cannot satisfy policy',
      () {
        final plan = ChatCompletionRequestPlanner.build(
          backend: _NativeChatBackend(),
          templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
          ],
          tools: [_weatherTool],
          toolChoice: ToolChoice.required,
          parallelToolCalls: false,
        );

        expect(plan.usesNativeChatGeneration, isFalse);
        expect(plan.parseToolCallsEnabled, isTrue);
      },
    );
  });
}

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'get_weather',
  description: 'Returns current weather for a city.',
  parameters: [ToolParam.string('location', description: 'City name')],
  handler: (_) async => 'Sunny',
);

class _NoGrammarBackend extends _BaseBackend
    implements BackendGrammarConstraintsSupport {
  @override
  bool get supportsGrammarConstraints => false;
}

class _NativeChatBackend extends _BaseBackend
    implements BackendGrammarConstraintsSupport, BackendNativeChatGeneration {
  @override
  bool get supportsGrammarConstraints => true;

  @override
  bool get supportsNativeChatGeneration => true;
}

class _BaseBackend implements LlamaBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
