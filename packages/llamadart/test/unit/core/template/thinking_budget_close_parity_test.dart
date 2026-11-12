@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/core/engine/chat_completion_request_planner.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/thinking_budget_close_upstream.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  for (final entry in (fixture['templates'] as List).cast<Map>()) {
    final path = entry['template'] as String;
    test('closes the thought of $path as llama.cpp does', () {
      final format = ChatTemplateEngine.detectFormat(
        File(path).readAsStringSync(),
      );
      final plan = ChatCompletionRequestPlanner.build(
        backend: _PromptBackend(),
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: format.index,
        ),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        params: const GenerationParams(
          thinkingBudget: ThinkingBudget(maxTokens: 4),
        ),
        toolChoice: ToolChoice.auto,
        parallelToolCalls: false,
      );
      final budget = plan.generationParams.thinkingBudget!;

      expect(
        '${budget.forcedMessage ?? ''}${budget.endTag}',
        (entry['thinking_end_tags'] as List).first,
      );
      expect(budget.startTag, entry['thinking_start_tag']);
    });
  }
}

class _PromptBackend implements LlamaBackend, BackendGrammarConstraintsSupport {
  @override
  bool get supportsGrammarConstraints => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
