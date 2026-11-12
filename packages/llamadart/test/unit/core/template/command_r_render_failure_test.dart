@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/raw_tool_schema_fixture.dart';

void main() {
  const messages = [
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
  ];

  final tools = <String, ToolDefinition>{
    'raw null': rawScalarTool(),
    'raw nullable union': rawSchemaTool(),
    'helper null': ToolDefinition(
      name: 'inspect',
      description: 'Inspect',
      parameters: [ToolParam.nullType('nothing')],
    ),
  };

  for (final fixture in const {
    'Command R+': 'CohereForAI-c4ai-command-r-plus-tool_use.jinja',
    'Hermes-2-Pro-Llama-3-8B':
        'NousResearch-Hermes-2-Pro-Llama-3-8B-tool_use.jinja',
  }.entries) {
    final template = File(
      'test/fixtures/llama_cpp_templates/${fixture.value}',
    ).readAsStringSync();
    for (final entry in tools.entries) {
      for (final source in ['templateSource', 'customTemplate', 'tool_use']) {
        test(
          '${fixture.key} ${entry.key} reports typed failure from $source',
          () {
            expect(
              () => ChatTemplateEngine.render(
                templateSource: source == 'templateSource'
                    ? template
                    : '{{ "ok" }}',
                customTemplate: source == 'customTemplate' ? template : null,
                messages: messages,
                metadata: source == 'tool_use'
                    ? {'tokenizer.chat_template.tool_use': template}
                    : const {},
                tools: [entry.value],
              ),
              throwsA(
                isA<LlamaInferenceException>().having(
                  (error) => error.message,
                  'message',
                  allOf(
                    contains(source),
                    contains('failed to render'),
                    contains('Stack Overflow'),
                  ),
                ),
              ),
            );
          },
        );
      }
    }

    test('${fixture.key} legacy scalar tools still render', () {
      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: messages,
        metadata: const {},
        tools: [
          ToolDefinition(
            name: 'weather',
            description: 'Weather',
            parameters: [ToolParam.string('city', required: true)],
          ),
        ],
      );
      expect(result.prompt, contains('weather(city: str)'));
      expect(result.prompt, contains('hi'));
    });

    test('${fixture.key} null tools remain disabled by tool choice none', () {
      LlamaChatTemplateResult render(List<ToolDefinition>? tools) =>
          ChatTemplateEngine.render(
            templateSource: '{{ messages[0].content }}',
            messages: messages,
            metadata: {'tokenizer.chat_template.tool_use': template},
            tools: tools,
            toolChoice: ToolChoice.none,
          );
      expect(render([rawScalarTool()]).prompt, 'hi');
      expect(render([rawScalarTool()]).prompt, render(null).prompt);
    });
  }
}
