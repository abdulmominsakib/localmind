@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/raw_tool_schema_fixture.dart';

String _template(String path) => File('test/fixtures/$path').readAsStringSync();

LlamaChatTemplateResult _render(
  String template,
  List<ToolDefinition> tools, {
  ToolChoice choice = ToolChoice.auto,
  bool thinking = true,
}) => ChatTemplateEngine.render(
  templateSource: template,
  messages: [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi')],
  metadata: const {},
  tools: tools,
  toolChoice: choice,
  enableThinking: thinking,
);

void main() {
  final legacy = ToolDefinition(
    name: 'inspect',
    description: 'Inspect',
    parameters: [ToolParam.string('code')],
  );

  for (final (path, format) in [
    ('templates/Llama-3_2-3B-Instruct.jinja', ChatFormat.llama3),
    ('templates/Qwen3_5-0_8B.jinja', ChatFormat.qwen3CoderXml),
    ('templates/gemma-4-E2B-it.jinja', ChatFormat.gemma4),
    ('templates/functiongemma-270m-it.jinja', ChatFormat.functionGemma),
    ('templates/Ministral-3-3B-Reasoning.jinja', ChatFormat.ministral),
    (
      'llama_cpp_templates/deepseek-ai-DeepSeek-V3.1.jinja',
      ChatFormat.deepseekV3,
    ),
    ('llama_cpp_templates/moonshotai-Kimi-K2.jinja', ChatFormat.kimiK2),
    ('llama_cpp_templates/openai-gpt-oss-120b.jinja', ChatFormat.gptOss),
  ]) {
    test('$format rejects canonical schema tools before generation', () {
      final template = _template(path);
      expect(ChatFormat.values[_render(template, [legacy]).format], format);
      expect(
        () => _render(template, [rawSchemaTool()]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('not qualified for $format'),
          ),
        ),
      );
    });
  }

  group('QwQ forced-open thinking', () {
    final template = _template('llama_cpp_templates/Qwen-QwQ-32B.jinja');
    final call = jsonEncode({'name': 'inspect', 'arguments': rawToolArguments});

    for (final (label, tool) in [
      ('schema', rawSchemaTool()),
      ('legacy', legacy),
    ]) {
      for (final choice in [ToolChoice.auto, ToolChoice.required]) {
        for (final thinking in [true, false]) {
          test('$label $choice grammar with thinking=$thinking', () {
            final result = _render(
              template,
              [tool],
              choice: choice,
              thinking: thinking,
            );
            expect(ChatFormat.values[result.format], ChatFormat.hermes);
            expect(result.thinkingForcedOpen, thinking);
            expect(result.grammarLazy, choice == ToolChoice.auto);
            expect(
              result.grammar,
              thinking && choice == ToolChoice.required
                  ? startsWith('root ::= think-body "</think>" think-space (')
                  : matches(r'^root ::= \(?"<tool_call>"'),
            );
          });
        }
      }
    }

    test('parses a required call only after the reasoning closes', () {
      ChatParseResult parse(String output) => ChatTemplateEngine.parse(
        ChatFormat.hermes.index,
        output,
        tools: [rawSchemaTool()],
        thinkingForcedOpen: true,
      );
      final parsed = parse(
        'Need to inspect.\n</think>\n\n<tool_call>\n$call\n</tool_call>',
      );
      expect(parsed.reasoningContent, 'Need to inspect.');
      expect(parsed.content, isEmpty);
      expect(
        jsonDecode(parsed.toolCalls.single.function!.arguments!),
        rawToolArguments,
      );
      // Without the close tag the whole reply is reasoning, so the grammar
      // requires it.
      final unclosed = parse('<tool_call>\n$call\n</tool_call>');
      expect(unclosed.toolCalls, isEmpty);
      expect(unclosed.reasoningContent, contains('<tool_call>'));
    });
  });

  group('Qwen3 thinking template with schema tools', () {
    final template = _template('templates/Qwen3-4B.jinja');
    final call = jsonEncode({'name': 'inspect', 'arguments': rawToolArguments});

    for (final choice in ToolChoice.values) {
      for (final thinking in [true, false]) {
        test('$choice renders with thinking=$thinking', () {
          final result = _render(
            template,
            [rawSchemaTool()],
            choice: choice,
            thinking: thinking,
          );
          expect(ChatFormat.values[result.format], ChatFormat.hermes);
          expect(result.thinkingForcedOpen, isFalse);
          expect(result.prompt.endsWith('<think>\n\n</think>\n\n'), !thinking);
          if (choice == ToolChoice.none) {
            expect(result.grammar, isNull);
            return;
          }
          expect(result.prompt, contains('"inspect"'));
          expect(result.grammarLazy, choice == ToolChoice.auto);
          expect(result.grammar, contains('"<tool_call>" space'));
        });
      }
    }

    test('parses a reasoning prefix before the validated call', () {
      ChatParseResult parse(String output) => ChatTemplateEngine.parse(
        ChatFormat.hermes.index,
        output,
        tools: [rawSchemaTool()],
      );
      final parsed = parse(
        '<think>Need to inspect.</think>\n<tool_call>\n$call\n</tool_call>',
      );
      expect(parsed.reasoningContent, 'Need to inspect.');
      expect(parsed.content, isEmpty);
      expect(
        jsonDecode(parsed.toolCalls.single.function!.arguments!),
        rawToolArguments,
      );
      final answer = parse(
        '<think>Plain.</think>\nThe user is {"name": "Bob"}.',
      );
      expect(answer.reasoningContent, 'Plain.');
      expect(answer.content, 'The user is {"name": "Bob"}.');
      expect(answer.toolCalls, isEmpty);
      expect(
        () => parse(
          '<think>x</think><tool_call>${call.replaceFirst('"mode":2', '"mode":"2"')}</tool_call>',
        ),
        throwsA(isA<LlamaInferenceException>()),
      );
    });
  });
}
