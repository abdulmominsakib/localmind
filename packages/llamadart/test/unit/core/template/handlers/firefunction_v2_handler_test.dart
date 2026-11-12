@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

void main() {
  final templatesDir = _resolveTemplatesDir();

  group('FirefunctionV2Handler', () {
    test('parses prefixed tool-call array', () {
      const output =
          ' functools[{"name":"get_weather","arguments":{"city":"Seoul"},"id":"abc"}]';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.firefunctionV2.index,
        output,
      );

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
      expect(parsed.toolCalls.first.id, equals('abc'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'city': 'Seoul'}),
      );

      const malformed = ' functools[{"arguments":{"city":"Seoul"}}]';
      final malformedParsed = ChatTemplateEngine.parse(
        ChatFormat.firefunctionV2.index,
        malformed,
      );

      expect(malformedParsed.toolCalls, isEmpty);
      expect(malformedParsed.content, equals(malformed.trim()));
    });

    test('renders with firefunction format when tools are present', () {
      const template = '{{ functions }}\n{{ datetime }}\n functools[';
      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        tools: [
          ToolDefinition(
            name: 'get_weather',
            description: 'Get weather',
            parameters: [ToolParam.string('city')],
            handler: _noopHandler,
          ),
        ],
        addAssistant: false,
      );

      expect(result.format, equals(ChatFormat.firefunctionV2.index));
      expect(result.prompt, contains('get_weather'));
      expect(result.prompt, contains('GMT'));
    });

    test('renders datetime with llama.cpp localtime formatting', () {
      const template = '{{ datetime }}\n functools[';
      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        tools: [
          ToolDefinition(
            name: 'get_weather',
            description: 'Get weather',
            parameters: [ToolParam.string('city')],
            handler: _noopHandler,
          ),
        ],
        addAssistant: false,
        now: DateTime(2026, 2, 17, 13, 5, 9),
      );

      expect(result.prompt, startsWith('Feb 17 2026 13:05:09 GMT'));
    });

    test('falls back to content-only format when tools are absent', () {
      const template = '{{ functions }}\n{{ datetime }}\n functools[';
      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        addAssistant: false,
      );

      expect(result.format, equals(ChatFormat.contentOnly.index));
    });

    test('renders llama.cpp firefunction template with tool context', () {
      final source = File(
        '${templatesDir.path}/fireworks-ai-llama-3-firefunction-v2.jinja',
      ).readAsStringSync();

      final result = ChatTemplateEngine.render(
        templateSource: source,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        tools: [
          ToolDefinition(
            name: 'get_weather',
            description: 'Get weather',
            parameters: [ToolParam.string('city')],
            handler: _noopHandler,
          ),
        ],
      );

      expect(result.format, equals(ChatFormat.firefunctionV2.index));
      expect(result.prompt, contains('functools'));
      expect(result.prompt, contains('Today is'));
    });

    test('required tool grammar leaves the call id undeclared', () {
      final result = ChatTemplateEngine.render(
        templateSource: File(
          '${templatesDir.path}/fireworks-ai-llama-3-firefunction-v2.jinja',
        ).readAsStringSync(),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        tools: [
          ToolDefinition(
            name: 'get_weather',
            description: 'Get weather',
            parameters: [ToolParam.string('city')],
            handler: _noopHandler,
          ),
        ],
        toolChoice: ToolChoice.required,
      );

      expect(result.format, equals(ChatFormat.firefunctionV2.index));
      expect(result.grammarLazy, isFalse);
      expect(
        result.grammar,
        contains(
          'root-item ::= "{" space root-item-name-kv "," space '
          'root-item-arguments-kv "}" space',
        ),
      );
      expect(result.grammar, isNot(contains('"\\"id\\""')));
    });
  });

  group('FunctionaryV32Handler', () {
    test('parses >>>all content with subsequent tool call', () {
      const output =
          '>>>all\nLet me call a tool\n>>>special_function\n{"arg1":1}';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.functionaryV32.index,
        output,
      );

      expect(parsed.content, equals('Let me call a tool'));
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('special_function'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'arg1': 1}),
      );
    });

    test('parses start-only call form without >>> prefix', () {
      const output = 'special_function\n{"arg1":1}';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.functionaryV32.index,
        output,
      );

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('special_function'));
    });

    test('parses raw python body as code argument', () {
      const output = '>>>python\nprint("hello")';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.functionaryV32.index,
        output,
      );

      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('python'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'code': 'print("hello")'}),
      );
    });

    test('renders llama.cpp functionary v3.2 template', () {
      final source = File(
        '${templatesDir.path}/meetkai-functionary-medium-v3.2.jinja',
      ).readAsStringSync();

      final result = ChatTemplateEngine.render(
        templateSource: source,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        tools: [
          ToolDefinition(
            name: 'special_function',
            description: 'Call me',
            parameters: [ToolParam.integer('arg1')],
            handler: _noopHandler,
          ),
        ],
      );

      expect(result.format, equals(ChatFormat.functionaryV32.index));
      expect(result.prompt, contains('>>>'));
    });
  });

  group('FunctionaryV31Llama31Handler', () {
    test('parses function tag tool calls', () {
      const output = '<function=special_function>{"arg1":1}</function>';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.functionaryV31Llama31.index,
        output,
      );

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('special_function'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'arg1': 1}),
      );
    });

    test('parses python tag fallback body', () {
      const output = '<|python_tag|>print("hello")';

      final parsed = ChatTemplateEngine.parse(
        ChatFormat.functionaryV31Llama31.index,
        output,
      );

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('python'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'code': 'print("hello")'}),
      );
    });

    test('renders llama.cpp functionary v3.1 template', () {
      final source = File(
        '${templatesDir.path}/meetkai-functionary-medium-v3.1.jinja',
      ).readAsStringSync();

      final result = ChatTemplateEngine.render(
        templateSource: source,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        tools: [
          ToolDefinition(
            name: 'special_function',
            description: 'Call me',
            parameters: [ToolParam.integer('arg1')],
            handler: _noopHandler,
          ),
        ],
      );

      expect(result.format, equals(ChatFormat.functionaryV31Llama31.index));
      expect(result.prompt, contains('<function='));
    });
  });

  group('Llama3Handler builtin python tag', () {
    test('parses builtin tool calls from <|python_tag|> syntax', () {
      const output =
          '<|python_tag|>web_search.call(query="weather in seoul", limit=3)';

      final parsed = ChatTemplateEngine.parse(ChatFormat.llama3.index, output);

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.first.function?.name, equals('web_search'));
      expect(
        jsonDecode(parsed.toolCalls.first.function!.arguments!),
        equals({'query': 'weather in seoul', 'limit': 3}),
      );
    });
  });
}

Future<Object?> _noopHandler(_) async {
  return 'ok';
}

/// Vendored fixtures, deliberately not overridable: this is a unit test and
/// must not depend on a fetched llama.cpp checkout.
Directory _resolveTemplatesDir() =>
    Directory('test/fixtures/llama_cpp_templates');
