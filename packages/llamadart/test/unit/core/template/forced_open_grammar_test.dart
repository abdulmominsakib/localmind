@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/tool_call_grammar_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../support/forced_open_required_calls.dart';

const Map<String, dynamic> _schema = {
  'type': 'json_schema',
  'json_schema': {
    'schema': {
      'type': 'object',
      'properties': {
        'answer': {'type': 'integer'},
      },
      'required': ['answer'],
    },
  },
};

final ToolDefinition _tool = ToolDefinition(
  name: 'get_weather',
  description: 'Weather',
  parameters: [ToolParam.string('location', required: true)],
);

// Required-call grammars that end a forced-open thought themselves: the
// DeepSeek R1 grammar may start with `</think>`, and a Qwen3-Coder XML
// `<tool_call>` ends the thought in its parse.
const Set<ChatFormat> _closesThoughtItself = {
  ChatFormat.deepseekR1,
  ChatFormat.qwen3CoderXml,
};

// Required-call grammars that take any text before the calls, so a thought and
// its end tag as well.
const Set<ChatFormat> _takesTextBeforeCalls = {
  ChatFormat.deepseekV32,
  ChatFormat.deepseekV4,
  ChatFormat.kimiK3,
  ChatFormat.laguna,
  ChatFormat.ling3,
  ChatFormat.minimaxM3,
};

// A grammar applies from the first token, so after a forced-open thought it
// must take the rest of the thought and its end tag first, or the response
// format or tool call is parsed as reasoning.
void main() {
  final templates = [
    for (final dir in const [
      'test/fixtures/llama_cpp_templates',
      'test/fixtures/media_templates',
      'test/fixtures/templates',
    ])
      ...Directory(dir).listSync().whereType<File>().where(
        (file) => file.path.endsWith('.jinja'),
      ),
  ]..sort((a, b) => a.path.compareTo(b.path));

  final requests =
      <
        ({
          String name,
          bool schema,
          List<ToolDefinition>? tools,
          ToolChoice choice,
        })
      >[
        (name: 'schema', schema: true, tools: null, choice: ToolChoice.auto),
        (name: 'tools', schema: false, tools: [_tool], choice: ToolChoice.auto),
        (
          name: 'required tools',
          schema: false,
          tools: [_tool],
          choice: ToolChoice.required,
        ),
        (
          name: 'schema and tools',
          schema: true,
          tools: [_tool],
          choice: ToolChoice.auto,
        ),
      ];

  test('an eager grammar after a forced-open thought takes the thought first, '
      'and a response format after it parses as content', () {
    var forcedOpenEager = 0;
    final failures = <String>[];
    for (final file in templates) {
      final source = file.readAsStringSync();
      for (final request in requests) {
        for (final enableThinking in [true, false]) {
          for (final media in [false, true]) {
            final LlamaChatTemplateResult result;
            try {
              result = ChatTemplateEngine.render(
                templateSource: source,
                messages: [
                  LlamaChatMessage.withContent(
                    role: LlamaChatRole.user,
                    content: [
                      if (media) const LlamaImageContent(path: '/tmp/a.png'),
                      const LlamaTextContent('What is 2+2?'),
                    ],
                  ),
                ],
                metadata: const {},
                tools: request.tools,
                toolChoice: request.choice,
                enableThinking: enableThinking,
                responseFormat: request.schema ? _schema : null,
              );
            } on Exception {
              continue;
            }
            final grammar = result.grammar;
            if (!result.thinkingForcedOpen ||
                grammar == null ||
                result.grammarLazy) {
              continue;
            }
            forcedOpenEager++;
            final label =
                '${p.basename(file.path)} ${request.name} '
                'thinking: $enableThinking media: $media';
            final root = grammar
                .split('\n')
                .firstWhere((line) => line.startsWith('root ::= '));
            final format = ChatFormat.values[result.format];
            if (!root.startsWith('root ::= think-body ')) {
              if (!request.schema &&
                  (_closesThoughtItself.contains(format) ||
                      _takesTextBeforeCalls.contains(format))) {
                continue;
              }
              failures.add('$label: grammar forbids the thought');
              continue;
            }
            if ('think-body '.allMatches(root).length != 1) {
              failures.add('$label: thought taken twice');
            }
            final endTag = ChatTemplateEngine.handlerFor(format).thinkingEndTag;
            if (!root.startsWith(
              'root ::= think-body ${ToolCallGrammarUtils.literal(endTag)} ',
            )) {
              failures.add('$label: thought not ended by $endTag');
            }
            if (request.schema && request.tools == null) {
              final parsed = ChatTemplateEngine.parse(
                result.format,
                'plan$endTag{"answer": 4}',
                thinkingForcedOpen: true,
                parser: result.parser,
              );
              if (parsed.content.trim() != '{"answer": 4}') {
                failures.add('$label: content ${parsed.content}');
              }
            }
          }
        }
      }
    }

    expect(failures, isEmpty);
    expect(forcedOpenEager, greaterThan(0));
  });

  test('a required GLM-4.7-Flash call after a forced-open thought parses as '
      'a tool call', () {
    final result = ChatTemplateEngine.render(
      templateSource: File(
        'test/fixtures/llama_cpp_templates/GLM-4.7-Flash.jinja',
      ).readAsStringSync(),
      messages: [
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Weather in Paris?',
        ),
      ],
      metadata: const {},
      tools: [_tool],
      toolChoice: ToolChoice.required,
    );
    expect(result.format, ChatFormat.glm45.index);
    expect(result.thinkingForcedOpen, isTrue);
    expect(
      result.grammar,
      startsWith('root ::= think-body "</think>" think-space ('),
    );

    final parsed = ChatTemplateEngine.parse(
      result.format,
      'plan</think><tool_call>get_weather\n<arg_key>location</arg_key>\n'
      '<arg_value>Paris</arg_value>\n</tool_call>',
      thinkingForcedOpen: true,
      tools: [_tool],
    );
    expect(parsed.reasoningContent, 'plan');
    expect(parsed.toolCalls.map((call) => call.function?.name), [
      'get_weather',
    ]);
  });
  for (final (:template, :format, :output) in forcedOpenRequiredCalls) {
    test('a required ${format.name} call after a forced-open thought in '
        '$template parses as a tool call', () {
      final result = renderForcedOpenRequiredCall(template);
      final endTag = ChatTemplateEngine.handlerFor(format).thinkingEndTag;
      expect(result.format, format.index);
      expect(result.thinkingForcedOpen, isTrue);
      expect(result.grammarLazy, isFalse);
      expect(
        result.grammar,
        startsWith(
          'root ::= think-body ${ToolCallGrammarUtils.literal(endTag)} '
          'think-space (',
        ),
      );

      final parsed = ChatTemplateEngine.parse(
        result.format,
        output,
        thinkingForcedOpen: true,
        tools: [forcedOpenRequiredTool],
        parser: result.parser,
      );
      expect(parsed.reasoningContent?.trim(), 'plan');
      expect(parsed.toolCalls.map((call) => call.function?.name), [
        'get_weather',
      ]);
    });

    test('a required ${format.name} grammar in $template takes no thought '
        'with thinking off', () {
      final result = renderForcedOpenRequiredCall(
        template,
        enableThinking: false,
      );
      expect(result.format, format.index);
      expect(result.thinkingForcedOpen, isFalse);
      expect(result.grammar, isNot(contains('think-body')));
    });
  }
}
