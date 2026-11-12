import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/template/handlers/glm45_handler.dart';
import 'package:llamadart/src/core/template/handlers/hunyuan_v3_handler.dart';
import 'package:llamadart/src/core/template/handlers/hermes_handler.dart';
import 'package:llamadart/src/core/template/handlers/llama_cpp_specialized_handlers.dart';
import 'package:llamadart/src/core/template/handlers/mistral_handler.dart';
import 'package:llamadart/src/core/template/tool_schema_utils.dart';
import 'package:test/test.dart';

import '../../../support/llama_cpp_grammar_load.dart';
import '../../../support/raw_tool_schema_fixture.dart';

void main() {
  for (final format in [ChatFormat.hermes, ChatFormat.mistralNemo]) {
    test('$format final answers preserve punctuation and code fences', () {
      for (final text in [
        'Here:\n```dart\nprint(1);\n```',
        'Use `x`',
        'A brace {',
        'Less than <',
        'An array [',
        'Prefix [T',
      ]) {
        final parsed = ChatTemplateEngine.parse(
          format.index,
          text,
          tools: [rawSchemaTool()],
        );
        expect(parsed.content, text);
        expect(parsed.toolCalls, isEmpty);
      }
      final malformed = format == ChatFormat.hermes
          ? '<tool_call>{"name":'
          : '[TOOL_CALLS][{"name":';
      expect(
        () => ChatTemplateEngine.parse(
          format.index,
          malformed,
          tools: [rawSchemaTool()],
        ),
        throwsA(isA<LlamaInferenceException>()),
      );
    });
  }

  test('Hermes builds nullable and constrained canonical argument grammar', () {
    final grammar = HermesHandler().buildGrammar([rawSchemaTool()])!;
    expect(grammar, contains('null'));
    expect(grammar, contains('code'));
    expect(grammar, isNot(contains('undefined')));
  });

  test('GLM integer properties use the strict integer rule', () {
    for (final tool in [
      rawScalarTool(),
      ToolDefinition(
        name: 'legacy',
        description: 'Legacy',
        parameters: [ToolParam.integer('count')],
      ),
    ]) {
      final grammar = Glm45Handler().buildGrammar([tool])!;
      expect(grammar, contains('integer ::= "-"? ("0" | [1-9] [0-9]*)'));
      expect(
        grammar,
        contains(RegExp(r'-arg-count-value ::= integer$', multiLine: true)),
      );
    }
  });

  test('canonical schema calls must name a declared tool', () {
    final args = jsonEncode(rawToolArguments);
    for (final (format, output) in [
      (ChatFormat.generic, '{"tool_call":{"name":"other","arguments":$args}}'),
      (
        ChatFormat.hermes,
        '<tool_call>{"name":"other","arguments":$args}</tool_call>',
      ),
      (
        ChatFormat.mistralNemo,
        '[TOOL_CALLS][{"id":"abcdefghi","name":"other","arguments":$args}]',
      ),
    ]) {
      ChatParseResult parse(String text) => ChatTemplateEngine.parse(
        format.index,
        text,
        tools: [rawSchemaTool()],
      );
      expect(
        parse(output.replaceFirst('"other"', '"inspect"')).toolCalls,
        hasLength(1),
      );
      expect(
        () => parse(output),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            contains('undeclared tool call'),
          ),
        ),
        reason: '$format',
      );
    }
  });

  group('Hermes schema tools in auto mode', () {
    ChatParseResult parse(
      String text, {
      bool isPartial = false,
      List<ToolDefinition>? tools,
    }) => ChatTemplateEngine.parse(
      ChatFormat.hermes.index,
      text,
      tools: tools ?? [rawSchemaTool()],
      isPartial: isPartial,
    );
    final call = jsonEncode({'name': 'inspect', 'arguments': rawToolArguments});

    test('keep name-keyed JSON outside a tool envelope as content', () {
      for (final text in [
        'User record: {"name": "Bob", "age": 3}',
        'Example JSON:\n```json\n{"name": "Bob"}\n```',
        'Broken: {"name": "Bob",',
        '<json>{"name": "Bob"}</json>',
        'Nested {"name": "x", "child": $call}',
      ]) {
        final parsed = parse(text);
        expect(parsed.content, text);
        expect(parsed.toolCalls, isEmpty);
      }
    });

    test('parse and validate a bare call to a declared tool', () {
      expect(parse('Calling $call').toolCalls.single.function!.name, 'inspect');
      expect(
        () => parse(call.replaceFirst('"mode":2', '"mode":"2"')),
        throwsA(isA<LlamaInferenceException>()),
      );
    });

    test('keep tool envelopes strict', () {
      for (final text in [
        '<tool_call>{"name": "Bob", "arguments": {}}</tool_call>',
        '<tool>{"name": "Bob", "arguments": {}}</tool>',
        '<function=Bob>{}</function>',
        '<tool_call>{"name": "inspect"',
      ]) {
        expect(
          () => parse(text),
          throwsA(isA<LlamaInferenceException>()),
          reason: text,
        );
      }
    });

    test('hold back an incomplete bare call while streaming', () {
      expect(parse('Answer {"name": "insp', isPartial: true).content, 'Answer');
    });

    test('leave legacy ToolParam parsing unchanged', () {
      final legacy = ToolDefinition(
        name: 'weather',
        description: 'Weather',
        parameters: [ToolParam.string('city')],
      );
      final parsed = parse('{"name": "Bob", "arguments": {}}', tools: [legacy]);
      expect(parsed.toolCalls.single.function!.name, 'Bob');
    });

    test('allow whitespace inside the tool_call tags', () {
      expect(
        HermesHandler().buildGrammar([rawSchemaTool()]),
        contains('root ::= ("<tool_call>" space ('),
      );
    });
  });

  test(
    'schema tools reject response grammars that replace tool constraints',
    () {
      expect(
        () => ChatTemplateEngine.render(
          templateSource: null,
          messages: const [],
          metadata: const {},
          tools: [rawSchemaTool()],
          responseFormat: {
            'type': 'json_schema',
            'json_schema': {
              'schema': {'type': 'object'},
            },
          },
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test('Hunyuan canonical strings retain JSON-looking raw values', () {
    final tool = ToolDefinition.fromJsonSchema(
      name: 'echo',
      description: 'Echo',
      schema: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
        'required': ['text'],
        'additionalProperties': false,
      },
    );
    for (final value in ['true', 'false', 'null', '123', '"true"']) {
      final output =
          '<tool_calls:opensource><tool_call:opensource>echo<tool_sep:opensource><arg_key:opensource>text</arg_key:opensource><arg_value:opensource>$value</arg_value:opensource></tool_call:opensource></tool_calls:opensource>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.hunyuanV3.index,
        output,
        tools: [tool],
      );
      expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
        'text': value == '"true"' ? 'true' : value,
      });
    }
  });

  test('schema numeric enums decode as numbers rather than strings', () {
    const schema = {
      'type': 'integer',
      'enum': [1, 2],
    };
    expect(decodeToolSchemaText('2', schema), (valid: true, value: 2));
    expect(decodeToolSchemaText('3', schema).valid, isFalse);
  });

  for (final format in [
    ChatFormat.generic,
    ChatFormat.mistralNemo,
    ChatFormat.hermes,
  ]) {
    test('canonical schema survives final $format parsing', () {
      final tool = rawSchemaTool();
      final args = jsonEncode(rawToolArguments);
      final output = switch (format) {
        ChatFormat.mistralNemo =>
          '[TOOL_CALLS][{"id":"abcdefghi","name":"inspect","arguments":$args}]',
        ChatFormat.hermes =>
          '<tool_call>{"name":"inspect","arguments":$args}</tool_call>',
        _ => '{"tool_call":{"name":"inspect","arguments":$args}}',
      };
      final parsed = ChatTemplateEngine.parse(
        format.index,
        output,
        tools: [tool],
      );
      expect(
        jsonDecode(parsed.toolCalls.single.function!.arguments!),
        rawToolArguments,
      );
      final malformed = output.replaceFirst('"mode":2', '"mode":"2"');
      expect(
        () => ChatTemplateEngine.parse(format.index, malformed, tools: [tool]),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(
        () => ChatTemplateEngine.parse(
          format.index,
          malformed,
          tools: [tool],
          isPartial: true,
        ),
        returnsNormally,
      );
    });
  }

  for (final format in [
    ChatFormat.generic,
    ChatFormat.mistralNemo,
    ChatFormat.hermes,
  ]) {
    test('$format requires keys that only additionalProperties describes', () {
      final tool = ToolDefinition.fromJsonSchema(
        name: 'lookup',
        description: 'Lookup',
        schema: {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
          'required': ['city', 'units'],
          'additionalProperties': {'type': 'string'},
        },
      );
      final grammar = switch (format) {
        ChatFormat.mistralNemo => MistralHandler().buildGrammar([tool])!,
        ChatFormat.hermes => HermesHandler().buildGrammar([tool])!,
        _ => ChatTemplateEngine.render(
          templateSource: null,
          messages: const [],
          metadata: const {},
          tools: [tool],
          toolChoice: ToolChoice.required,
        ).grammar!,
      };
      expect(grammar, contains(r'"\"units\"" space ":" space'));

      String output(Map<String, dynamic> args) {
        final encoded = jsonEncode(args);
        return switch (format) {
          ChatFormat.mistralNemo =>
            '[TOOL_CALLS][{"id":"abcdefghi","name":"lookup","arguments":$encoded}]',
          ChatFormat.hermes =>
            '<tool_call>{"name":"lookup","arguments":$encoded}</tool_call>',
          _ => '{"tool_call":{"name":"lookup","arguments":$encoded}}',
        };
      }

      final args = {'city': 'Seoul', 'units': 'c'};
      final parsed = ChatTemplateEngine.parse(
        format.index,
        output(args),
        tools: [tool],
      );
      expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), args);
      for (final invalid in [
        {'city': 'Seoul'},
        {'city': 'Seoul', 'units': 1},
      ]) {
        expect(
          () => ChatTemplateEngine.parse(
            format.index,
            output(invalid),
            tools: [tool],
          ),
          throwsA(isA<LlamaInferenceException>()),
          reason: '$invalid',
        );
      }
    });
  }

  test(
    'GLM/Laguna and Hunyuan grammar read properties from the canonical schema',
    () {
      final tool = rawScalarTool();
      expect(tool.parameters, isEmpty);
      for (final handler in <ChatTemplateHandler>[
        Glm45Handler(),
        LagunaHandler(),
        HunyuanV3Handler(),
      ]) {
        final grammar = handler.buildGrammar([tool])!;
        expect(grammar, contains('city'));
        expect(grammar, contains('count'));
        expect(grammar, contains('integer'));
      }
    },
  );

  test(
    'fixed-argument formats reject open objects and richer constraints early',
    () {
      final open = ToolDefinition.fromJsonSchema(
        name: 'open',
        description: 'Open',
        schema: {
          'type': 'object',
          'properties': {
            'x': {'type': 'string'},
          },
        },
      );
      for (final handler in <ChatTemplateHandler>[
        Glm45Handler(),
        LagunaHandler(),
        HunyuanV3Handler(),
      ]) {
        expect(
          () => handler.buildGrammar([open]),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(
          () => handler.buildGrammar([rawSchemaTool()]),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      }
    },
  );

  group('schema tool grammars stay within llama.cpp repetition limits', () {
    Map<String, String> grammars(ToolDefinition tool) => {
      'Hermes': HermesHandler().buildGrammar([tool])!,
      'Mistral Nemo': MistralHandler().buildGrammar([tool])!,
      for (final choice in [ToolChoice.auto, ToolChoice.required])
        'generic $choice': ChatTemplateEngine.render(
          templateSource: null,
          messages: const [],
          metadata: const {},
          tools: [tool],
          toolChoice: choice,
        ).grammar!,
    };

    final schemas = <String, Map<String, dynamic>>{
      for (final MapEntry(key: label, value: names) in largeKeySets.entries)
        'open object with $label': {
          'type': 'object',
          'properties': {
            for (final name in names) name: {'type': 'integer'},
          },
        },
      'open object beyond the key budget': {
        'type': 'object',
        'properties': {
          for (final name in overBudgetKeySet) name: {'type': 'integer'},
        },
      },
      for (final item in boundedArrayItemSchemas)
        for (final minItems in [0, 1999])
          'maxItems 1999 minItems $minItems of $item': {
            'type': 'object',
            'properties': {
              'list': {
                'type': 'array',
                'items': item,
                'minItems': minItems,
                'maxItems': 1999,
              },
            },
            'required': ['list'],
          },
    };
    for (final MapEntry(key: label, value: schema) in schemas.entries) {
      test(label, () {
        final tool = ToolDefinition.fromJsonSchema(
          name: 'spec',
          description: 'Spec',
          schema: schema,
        );
        for (final MapEntry(key: format, value: grammar) in grammars(
          tool,
        ).entries) {
          expect(llamaCppRepetitionRejection(grammar), isNull, reason: format);
        }
      });
    }
  });
}
