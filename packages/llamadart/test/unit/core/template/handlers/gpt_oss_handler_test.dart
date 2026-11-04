import 'dart:convert';

import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

void main() {
  group('New format handlers', () {
    test('parses GPT-OSS analysis, tool call, and final content', () {
      const output =
          '<|start|>assistant<|channel|>analysis<|message|>plan<|end|>'
          '<|start|>assistant to=functions.weather<|channel|>commentary<|message|>{"city":"Seoul"}<|end|>'
          '<|start|>assistant<|channel|>final<|message|>done<|end|>';

      final result = ChatTemplateEngine.parse(ChatFormat.gptOss.index, output);

      expect(result.reasoningContent, equals('plan'));
      expect(result.content, equals('done'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
      expect(
        jsonDecode(result.toolCalls.first.function!.arguments!),
        equals({'city': 'Seoul'}),
      );
    });

    test('parses Seed-OSS reasoning and XML tool call', () {
      const output =
          '<seed:think>reasoning</seed:think>'
          '<seed:tool_call><function=weather><parameter=city>"Seoul"</parameter></function></seed:tool_call>';

      final result = ChatTemplateEngine.parse(ChatFormat.seedOss.index, output);

      expect(result.reasoningContent, equals('reasoning'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
    });

    test('parses Nemotron V2 TOOLCALL blocks', () {
      const output =
          '<think>reasoning</think><TOOLCALL>[{"name":"weather","arguments":{"city":"Seoul"}}]</TOOLCALL>';

      final result = ChatTemplateEngine.parse(
        ChatFormat.nemotronV2.index,
        output,
      );

      expect(result.reasoningContent, equals('reasoning'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
    });

    test('parses Apertus short-form tool call arrays', () {
      const output =
          '<|inner_prefix|>reasoning<|inner_suffix|>'
          '<|tools_prefix|>[{"weather":{"city":"Seoul"}}]<|tools_suffix|>';

      final result = ChatTemplateEngine.parse(ChatFormat.apertus.index, output);

      expect(result.reasoningContent, equals('reasoning'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
      expect(
        jsonDecode(result.toolCalls.first.function!.arguments!),
        equals({'city': 'Seoul'}),
      );
    });

    test('parses Xiaomi MiMo tool call blocks', () {
      const output =
          'hello<tool_call>\n{"name": "weather", "arguments": {"city": "Seoul"}\n</tool_call>';

      final result = ChatTemplateEngine.parse(
        ChatFormat.xiaomiMimo.index,
        output,
      );

      expect(result.content, equals('hello'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
    });

    test('parses Apriel 1.5 tool call arrays', () {
      const output =
          '<thinking>reasoning</thinking>'
          '<tool_calls>[{"name": "weather", "arguments": {"city": "Seoul"}}]</tool_calls>';

      final result = ChatTemplateEngine.parse(
        ChatFormat.apriel15.index,
        output,
      );

      expect(result.reasoningContent, equals('reasoning'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
    });

    test('parses Solar Open reasoning/content boundary', () {
      const output =
          '<|think|>reasoning<|end|><|begin|>assistant<|content|>final answer';

      final result = ChatTemplateEngine.parse(
        ChatFormat.solarOpen.index,
        output,
      );

      expect(result.reasoningContent, equals('reasoning'));
      expect(result.content, equals('final answer'));
    });

    test('parses EXAONE MoE tool calls', () {
      const output =
          '<think>reasoning</think>'
          '<tool_call>{"name":"weather","arguments":{"city":"Seoul"}}</tool_call>';

      final result = ChatTemplateEngine.parse(
        ChatFormat.exaoneMoe.index,
        output,
      );

      expect(result.reasoningContent, equals('reasoning'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
    });

    test('treats forced-open EXAONE output as content when no end tag', () {
      const output =
          '<tool_call>{"name":"weather","arguments":{"city":"Seoul"}}</tool_call>';

      final result = ChatTemplateEngine.parse(
        ChatFormat.exaoneMoe.index,
        output,
        thinkingForcedOpen: true,
      );

      expect(result.reasoningContent, isNull);
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
    });

    test('parses Kimi K2 tool call and strips function prefix/index', () {
      const output =
          '<|tool_calls_section_begin|><|tool_call_begin|>functions.weather:0<|tool_call_argument_begin|>{"city":"Seoul"}<|tool_call_end|><|tool_calls_section_end|>';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.content, isEmpty);
      expect(result.reasoningContent, isNull);
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
      expect(
        jsonDecode(result.toolCalls.first.function!.arguments!),
        equals({'city': 'Seoul'}),
      );
    });

    test('parses Kimi K2 tool call inside think block', () {
      const output =
          '<think>I am thinking<|tool_calls_section_begin|><|tool_call_begin|>functions.weather:0<|tool_call_argument_begin|>{"city":"Seoul"}<|tool_call_end|><|tool_calls_section_end|>still thinking</think>Hello';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.content, equals('Hello'));
      expect(result.reasoningContent, equals('I am thinkingstill thinking'));
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
    });

    test('parses multiple Kimi K2 tool calls in one section', () {
      const output =
          '<|tool_calls_section_begin|>'
          '<|tool_call_begin|>functions.weather:0<|tool_call_argument_begin|>{"city":"Seoul"}<|tool_call_end|>'
          '<|tool_call_begin|>functions.search:1<|tool_call_argument_begin|>{"query":"rain"}<|tool_call_end|>'
          '<|tool_calls_section_end|>';

      final result = ChatTemplateEngine.parse(ChatFormat.kimiK2.index, output);

      expect(result.toolCalls, hasLength(2));
      expect(result.toolCalls[0].function?.name, equals('weather'));
      expect(result.toolCalls[1].function?.name, equals('search'));
      expect(
        jsonDecode(result.toolCalls[1].function!.arguments!),
        equals({'query': 'rain'}),
      );
    });

    test('supports partial Kimi K2 tool call parsing', () {
      const output =
          '<|tool_calls_section_begin|><|tool_call_begin|>functions.weather:0<|tool_call_argument_begin|>{"city":"Seoul"}';

      final result = ChatTemplateEngine.parse(
        ChatFormat.kimiK2.index,
        output,
        isPartial: true,
      );

      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('weather'));
      expect(
        jsonDecode(result.toolCalls.first.function!.arguments!),
        equals({'city': 'Seoul'}),
      );
    });
  });
}
