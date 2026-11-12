import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/minimax_m1_m3_handler.dart';
import 'package:test/test.dart';

import 'specialized_handler_test_fixtures.dart';

void main() {
  group('MiniMax M1', () {
    test('parses parallel newline-delimited calls and surrounding content', () {
      const output =
          'Checking.\n<tool_calls>\n'
          '{"name":"weather","arguments":{"city":"Seoul"}}\n'
          '{"name":"clock","arguments":{"tz":"UTC"}}\n'
          '</tool_calls>';
      final parsed = MinimaxM1Handler().parse(output);
      expect(parsed.content, 'Checking.');
      expect(parsed.toolCalls.map((call) => call.function?.name), [
        'weather',
        'clock',
      ]);
      expect(arguments(parsed), {'city': 'Seoul'});
    });

    test('preserves malformed completed call envelopes', () {
      const output = '<tool_calls>\n{"name":"weather"\n</tool_calls>';
      final parsed = MinimaxM1Handler().parse(output);
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output);
    });

    test('keeps ordinary JSON-looking prose as content', () {
      const output = 'Example: {"name":"weather"}';
      expect(MinimaxM1Handler().parse(output).content, output);
    });

    test('grammar uses schema-aware JSON string and escape rules', () {
      final grammar = MinimaxM1Handler().buildGrammar([weatherWithCityTool])!;
      final rootRule = grammar
          .split('\n')
          .singleWhere((line) => line.startsWith('root ::='));
      final callRule = grammar
          .split('\n')
          .singleWhere((line) => line.startsWith('tool-0-call ::='));

      expect(rootRule, contains('tool-call+'));
      expect(callRule, contains(' tool-0-arguments '));
      expect(grammar, contains('char ::= '));
      expect(grammar, contains(r'[^"\\\x7F\x00-\x1F]'));
      expect(grammar, contains(r'[\\] (["\\bfnrt] | "u"'));
      expect(grammar, isNot(contains('json-char ::=')));
    });

    test('grammar JSON-encodes the upstream tool-name value', () {
      final grammar = MinimaxM1Handler().buildGrammar([weatherTool])!;
      final callRule = grammar
          .split('\n')
          .singleWhere((line) => line.startsWith('tool-0-call ::='));

      expect(callRule, contains(r'\"weather\"'));
      expect(callRule, isNot(contains(' space "weather" space')));
    });

    test('production parse rejects MiniMax M1 schema mismatches', () {
      const valid =
          '<tool_calls>\n'
          '{"name":"weather","arguments":{"city":"Seoul"}}\n'
          '</tool_calls>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.minimaxM1.index,
        valid,
        tools: [weatherWithCityTool],
      );
      expect(arguments(parsed), {'city': 'Seoul'});

      for (final invalid in [
        valid.replaceFirst('"weather"', '"unknown"'),
        valid.replaceFirst('"city"', '"unknown"'),
        valid.replaceFirst('"Seoul"', '7'),
        valid.replaceFirst(
          '"name":"weather"',
          '"name":"weather","unexpected":true',
        ),
      ]) {
        final rejected = ChatTemplateEngine.parse(
          ChatFormat.minimaxM1.index,
          invalid,
          tools: [weatherWithCityTool],
        );
        expect(rejected.toolCalls, isEmpty);
        expect(rejected.content, invalid);
      }
    });

    test('production parse preserves duplicate MiniMax M1 JSON keys', () {
      const duplicateTopLevel =
          '<tool_calls>\n'
          '{"name":"weather","name":"clock","arguments":{}}\n'
          '</tool_calls>';
      const duplicateArgument =
          '<tool_calls>\n'
          '{"name":"weather","arguments":'
          '{"city":"Seoul","c\\u0069ty":"Tokyo"}}\n'
          '</tool_calls>';

      for (final output in [duplicateTopLevel, duplicateArgument]) {
        final parsed = ChatTemplateEngine.parse(
          ChatFormat.minimaxM1.index,
          output,
          tools: [weatherWithCityTool],
        );
        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, output);
      }
    });

    test('grammar and parse reject ambiguous MiniMax M1 tool schemas', () {
      const output =
          '<tool_calls>\n'
          '{"name":"weather","arguments":{}}\n'
          '</tool_calls>';
      final duplicate = ToolDefinition(
        name: 'weather',
        description: 'Duplicate weather tool',
        parameters: const [],
        handler: (_) async => null,
      );
      final empty = ToolDefinition(
        name: '',
        description: 'Empty tool identity',
        parameters: const [],
        handler: (_) async => null,
      );

      for (final tools in [
        [weatherTool, duplicate],
        [empty],
      ]) {
        expect(
          () => MinimaxM1Handler().buildGrammar(tools),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(
          () => ChatTemplateEngine.parse(
            ChatFormat.minimaxM1.index,
            output,
            tools: tools,
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      }
    });
  });

  group('MiniMax M3', () {
    const ns = MinimaxM3Handler.namespace;

    test('parses reasoning and namespaced raw arguments', () {
      const output =
          '<mm:think>check</mm:think>'
          '$ns<tool_call>\n'
          '$ns<invoke name="weather">'
          '$ns<city> New York $ns</city>'
          '$ns<days>2$ns</days>'
          '$ns<options>$ns<units>metric$ns</units>'
          '$ns<alerts>$ns<item>true$ns</item>$ns<item>false$ns</item>'
          '$ns</alerts>$ns</options>'
          '$ns</invoke>\n$ns</tool_call>';
      final parsed = MinimaxM3Handler().parse(output);
      expect(parsed.reasoningContent, 'check');
      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls.single.function?.name, 'weather');
      expect(arguments(parsed), {
        'city': ' New York ',
        'days': 2,
        'options': {
          'units': 'metric',
          'alerts': [true, false],
        },
      });
    });

    test('preserves malformed namespace scopes', () {
      const output = '$ns<tool_call>$ns<invoke name="weather">broken';
      final parsed = MinimaxM3Handler().parse(output);
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output);
    });

    test('preserves literal namespace tokens outside a parsed tool scope', () {
      const output =
          'Before $ns literal\n'
          '$ns<tool_call>$ns<invoke name="weather">'
          '$ns<city>Seoul$ns</city>$ns</invoke>$ns</tool_call>'
          '\nAfter $ns literal';
      final parsed = MinimaxM3Handler().parse(output);

      expect(parsed.content, 'Before $ns literal\n\nAfter $ns literal');
      expect(arguments(parsed), {'city': 'Seoul'});
    });

    test('keeps non-tool content after a disabled-thinking prefix', () {
      expect(MinimaxM3Handler().parse('</mm:think>Hello').content, 'Hello');
    });

    test('does not validate schemas when MiniMax M3 parsing is disabled', () {
      final duplicate = ToolDefinition(
        name: 'weather',
        description: 'Duplicate weather tool',
        parameters: const [],
        handler: (_) async => null,
      );
      const output = '$ns<tool_call>unparsed</tool_call>';

      final parsed = MinimaxM3Handler().parseWithTools(
        output,
        tools: [weatherTool, duplicate],
        parseToolCalls: false,
      );

      expect(parsed.content, output);
      expect(parsed.toolCalls, isEmpty);
    });

    test('hides an incomplete invoke while streaming', () {
      const output =
          'Prelude$ns<tool_call>\n'
          '$ns<invoke name="weather">$ns<city>Seo';
      final parsed = MinimaxM3Handler().parse(output, isPartial: true);

      expect(parsed.content, 'Prelude');
      expect(parsed.toolCalls, isEmpty);
    });

    test('keeps completed calls before a partial invoke', () {
      const output =
          'Prelude$ns<tool_call>\n'
          '$ns<invoke name="weather">$ns<city>Seoul$ns</city>'
          '$ns</invoke>\n'
          '$ns<invoke name="clock">$ns<tz>UT';
      final parsed = MinimaxM3Handler().parse(output, isPartial: true);

      expect(parsed.content, 'Prelude');
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.single.function?.name, 'weather');
      expect(arguments(parsed), {'city': 'Seoul'});
    });

    test('production parse accepts a zero-parameter invoke as empty args', () {
      const output =
          '$ns<tool_call>$ns<invoke name="ping">'
          '$ns</invoke>$ns</tool_call>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.minimaxM3.index,
        output,
        tools: [zeroArgTool],
      );

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls.single.function?.name, 'ping');
      expect(arguments(parsed), isEmpty);
    });

    test('production parse preserves schema types and empty containers', () {
      const output =
          '$ns<tool_call>$ns<invoke name="inspect">'
          '$ns<code>123$ns</code>'
          '$ns<options>$ns</options>'
          '$ns<items>$ns</items>'
          '$ns<count>7$ns</count>'
          '$ns<active>true$ns</active>'
          '$ns<empty>null$ns</empty>'
          '$ns</invoke>$ns</tool_call>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.minimaxM3.index,
        output,
        tools: [schemaTool],
      );

      expect(arguments(parsed), {
        'code': '123',
        'options': <String, dynamic>{},
        'items': <Object?>[],
        'count': 7,
        'active': true,
        'empty': null,
      });
    });

    test('production schema rejects unknown and mismatched arguments', () {
      const unknown =
          '$ns<tool_call>$ns<invoke name="inspect">'
          '$ns<unknown>x$ns</unknown>$ns</invoke>$ns</tool_call>';
      const mismatch =
          '$ns<tool_call>$ns<invoke name="inspect">'
          '$ns<code>x$ns</code>$ns<options>$ns</options>'
          '$ns<items>$ns</items>$ns<count>oops$ns</count>'
          '$ns<active>true$ns</active>$ns<empty>null$ns</empty>'
          '$ns</invoke>$ns</tool_call>';

      for (final output in [unknown, mismatch]) {
        final parsed = ChatTemplateEngine.parse(
          ChatFormat.minimaxM3.index,
          output,
          tools: [schemaTool],
        );
        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, output);
      }
    });

    test('production schema rejects duplicate MiniMax M3 properties', () {
      const duplicateTopLevel =
          '$ns<tool_call>$ns<invoke name="inspect">'
          '$ns<code>first$ns</code>$ns<code>second$ns</code>'
          '$ns<options>$ns</options>$ns<items>$ns</items>'
          '$ns<count>7$ns</count>$ns<active>true$ns</active>'
          '$ns<empty>null$ns</empty>$ns</invoke>$ns</tool_call>';
      const duplicateNested =
          '$ns<tool_call>$ns<invoke name="weather">'
          '$ns<city>Seoul$ns</city>'
          '$ns<options>$ns<units>metric$ns</units>'
          '$ns<units>imperial$ns</units>$ns</options>'
          '$ns</invoke>$ns</tool_call>';

      for (final output in [duplicateTopLevel, duplicateNested]) {
        final parsed = ChatTemplateEngine.parse(
          ChatFormat.minimaxM3.index,
          output,
          tools: output == duplicateTopLevel
              ? [schemaTool]
              : [weatherNestedTool],
        );
        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, output);
      }
    });

    test('production schema rejects an unknown MiniMax M3 tool name', () {
      const output =
          '$ns<tool_call>$ns<invoke name="unknown">'
          '$ns</invoke>$ns</tool_call>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.minimaxM3.index,
        output,
        tools: [zeroArgTool],
      );

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output);
    });

    test('preserves namespace-like text inside MiniMax M3 strings', () {
      const output =
          '$ns<tool_call>$ns<invoke name="inspect">'
          '$ns<code>a${ns}literal$ns</code>'
          '$ns<options>$ns</options>$ns<items>$ns</items>'
          '$ns<count>7$ns</count>$ns<active>true$ns</active>'
          '$ns<empty>null$ns</empty>$ns</invoke>$ns</tool_call>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.minimaxM3.index,
        output,
        tools: [schemaTool],
      );

      expect(arguments(parsed)['code'], 'a${ns}literal');
    });

    test('grammar binds literal closing tags and permits ] in strings', () {
      final grammar = MinimaxM3Handler().buildGrammar([schemaTool])!;

      expect(grammar, contains('$ns<code>'));
      expect(grammar, contains('$ns</code>'));
      expect(grammar, isNot(contains('identifier ::=')));
      expect(grammar, isNot(contains(r'raw ::= [^]]*')));
    });

    test('round-trips escaped tool attributes and rejects unsafe tag keys', () {
      final grammar = MinimaxM3Handler().buildGrammar([attributeTool])!;
      expect(grammar, contains(r'invoke name=\"weather&amp;&quot;alerts\"'));

      const output =
          '$ns<tool_call>$ns<invoke name="weather&amp;&quot;alerts">'
          '$ns</invoke>$ns</tool_call>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.minimaxM3.index,
        output,
        tools: [attributeTool],
      );
      expect(parsed.toolCalls.single.function?.name, 'weather&"alerts');

      for (final malformedName in [
        'weather&&quot;alerts',
        'weather&bogus;&quot;alerts',
        'weather&amp;amp;&quot;alerts',
      ]) {
        final malformed = output.replaceFirst(
          'weather&amp;&quot;alerts',
          malformedName,
        );
        final rejected = ChatTemplateEngine.parse(
          ChatFormat.minimaxM3.index,
          malformed,
          tools: [attributeTool],
        );
        expect(rejected.toolCalls, isEmpty);
        expect(rejected.content, malformed);
      }

      expect(
        () => MinimaxM3Handler().buildGrammar([escapedSchemaTool]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('cannot represent tool parameter "city&"zone"'),
          ),
        ),
      );
    });
  });
}
