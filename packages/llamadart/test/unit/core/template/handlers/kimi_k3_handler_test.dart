import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/kimi_k3_handler.dart';
import 'package:test/test.dart';

import 'specialized_handler_test_fixtures.dart';

void main() {
  group('Kimi K3', () {
    const call =
        '<|open|>response<|sep|>On it.<|close|>response<|sep|>'
        '<|open|>tools<|sep|>'
        '<|open|>call tool="weather&amp;alerts" index="1"<|sep|>'
        '<|open|>argument key="city" type="string"<|sep|>'
        ' New York <|close|>argument<|sep|>'
        '<|open|>argument key="days" type="number"<|sep|>'
        '2<|close|>argument<|sep|>'
        '<|close|>call<|sep|><|close|>tools<|sep|>'
        '<|close|>message<|sep|>';

    test('parses forced-open reasoning, content, and typed raw arguments', () {
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.kimiK3.index,
        'check first<|close|>think<|sep|>$call',
        thinkingForcedOpen: true,
      );

      expect(parsed.reasoningContent, 'check first');
      expect(parsed.content, 'On it.');
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.single.function?.name, 'weather&alerts');
      expect(arguments(parsed), {'city': ' New York ', 'days': 2});
    });

    test('parses a raw JSON argument block', () {
      const output =
          '<|open|>response<|sep|><|close|>response<|sep|>'
          '<|open|>tools<|sep|>'
          '<|open|>call tool="weather" index="1"<|sep|>'
          '<|open|>json type="object"<|sep|>{"city":"Seoul"}'
          '<|close|>json<|sep|><|close|>call<|sep|>'
          '<|close|>tools<|sep|><|close|>message<|sep|>';
      final parsed = KimiK3Handler().parse(output);
      expect(arguments(parsed), {'city': 'Seoul'});
    });

    test('grammar permits the upstream raw JSON argument block', () {
      final grammar = KimiK3Handler().buildGrammar([weatherTool])!;

      expect(grammar, contains('(kimi-empty-arguments | kimi-json-0)'));
      expect(grammar, contains(r'(" index=\"" [0-9]+ "\"")? "<|sep|>"'));
      expect(
        grammar,
        contains(r'"<|open|>json type=\"object\"<|sep|>" kimi-tool-0-json'),
      );
      expect(grammar, contains('kimi-tool-0-json ::= '));
    });

    test('grammar HTML-escapes tool names like the upstream XTML macro', () {
      final grammar = KimiK3Handler().buildGrammar([attributeTool])!;

      expect(grammar, contains(r'call tool=\"weather&amp;&quot;alerts\"'));
      expect(grammar, isNot(contains(r'call tool=\"weather&\"alerts\"')));
    });

    test('grammar emits exact escaped schema keys and their declared type', () {
      final grammar = KimiK3Handler().buildGrammar([escapedSchemaTool])!;

      expect(
        grammar,
        contains(r'argument key=\"city&amp;&quot;zone\" type=\"string\"'),
      );
      expect(grammar, isNot(contains('identifier ::=')));
    });

    test('zero-parameter grammar uses an explicit empty production', () {
      final grammar = KimiK3Handler().buildGrammar([zeroArgTool])!;

      expect(grammar, contains('kimi-raw-0 ::= ""'));
      expect(grammar, isNot(contains(RegExp(r'kimi-raw-0 ::=\s*\n'))));
    });

    test('grammar rejects ambiguous or empty protocol identities', () {
      final duplicate = ToolDefinition(
        name: weatherTool.name,
        description: 'Duplicate weather',
        parameters: [ToolParam.integer('days')],
        handler: (_) async => null,
      );
      final emptyTool = ToolDefinition(
        name: '',
        description: 'Empty name',
        parameters: const [],
        handler: (_) async => null,
      );
      final emptyParameter = ToolDefinition(
        name: 'empty_parameter',
        description: 'Empty parameter',
        parameters: [ToolParam.string('')],
        handler: (_) async => null,
      );

      for (final tools in [
        [weatherTool, duplicate],
        [emptyTool],
        [emptyParameter],
      ]) {
        expect(
          () => KimiK3Handler().buildGrammar(tools),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      }
    });

    test('production parse validates escaped Kimi names against schemas', () {
      const valid =
          '<|open|>tools<|sep|>'
          '<|open|>call tool="weather"<|sep|>'
          '<|open|>argument key="city&amp;&quot;zone" type="string"<|sep|>'
          '123<|close|>argument<|sep|><|close|>call<|sep|>'
          '<|close|>tools<|sep|><|close|>message<|sep|>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.kimiK3.index,
        valid,
        tools: [escapedSchemaTool],
      );

      expect(arguments(parsed), {'city&"zone': '123'});

      final duplicate = valid.replaceFirst(
        '<|close|>argument<|sep|><|close|>call<|sep|>',
        '<|close|>argument<|sep|>'
            '<|open|>argument key="city&amp;&quot;zone" type="string"<|sep|>'
            'again<|close|>argument<|sep|><|close|>call<|sep|>',
      );

      for (final invalid in [
        valid.replaceFirst('tool="weather"', 'tool="unknown"'),
        valid.replaceFirst('tool="weather"', 'tool="weather" index="invalid"'),
        valid.replaceFirst('city&amp;&quot;zone', 'unknown'),
        valid.replaceFirst('city&amp;&quot;zone', 'city&&quot;zone'),
        valid.replaceFirst('city&amp;&quot;zone', 'city&bogus;&quot;zone'),
        valid.replaceFirst('city&amp;&quot;zone', 'city&amp;amp;&quot;zone'),
        valid.replaceFirst('type="string"', 'type="number"'),
        duplicate,
      ]) {
        final rejected = ChatTemplateEngine.parse(
          ChatFormat.kimiK3.index,
          invalid,
          tools: [escapedSchemaTool],
        );
        expect(rejected.toolCalls, isEmpty);
        expect(rejected.content, contains('<|open|>tools<|sep|>'));
      }
    });

    test(
      'parses a tool call without the optional upstream index attribute',
      () {
        const output =
            '<|open|>tools<|sep|>'
            '<|open|>call tool="weather"<|sep|>'
            '<|open|>argument key="city" type="string"<|sep|>Seoul'
            '<|close|>argument<|sep|><|close|>call<|sep|>'
            '<|close|>tools<|sep|><|close|>message<|sep|>';

        final parsed = KimiK3Handler().parse(output);

        expect(parsed.content, isEmpty);
        expect(parsed.toolCalls.single.function?.name, 'weather');
        expect(arguments(parsed), {'city': 'Seoul'});
      },
    );

    test('preserves trailing output when tool parsing is disabled', () {
      final parsed = KimiK3Handler().parse(call, parseToolCalls: false);

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, startsWith('On it.'));
      expect(parsed.content, contains('<|open|>tools<|sep|>'));
      expect(
        parsed.content,
        contains('<|open|>call tool="weather&amp;alerts"'),
      );
    });

    test('preserves malformed tool markup instead of silently dropping it', () {
      const malformed =
          '<|open|>response<|sep|>On it.<|close|>response<|sep|>'
          '<|open|>tools<|sep|><|open|>call tool="weather" index="1"'
          '<|sep|><|open|>argument key="days" type="number"<|sep|>oops'
          '<|close|>argument<|sep|><|close|>call<|sep|>'
          '<|close|>tools<|sep|>';
      final parsed = KimiK3Handler().parse(malformed);
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, contains('<|open|>tools<|sep|>'));
      expect(parsed.content, contains('On it.'));
    });

    test('keeps protocol channel markers out of content and reasoning', () {
      final handler = KimiK3Handler();
      final thought = handler.parse(
        '<|open|>think<|sep|>Plan.<|close|>think<|sep|>Answer.',
      );
      expect(thought.reasoningContent, 'Plan.');
      expect(thought.content, 'Answer.');

      final unclosed = handler.parse('<|open|>think<|sep|>Still planning');
      expect(unclosed.reasoningContent, 'Still planning');
      expect(unclosed.content, isEmpty);

      expect(
        handler.parse('Hi <|open|>response<|sep|>unterminated').content,
        'Hi unterminated',
      );
      expect(
        handler
            .parse('<|open|>response<|sep|>Body<|close|>mess', isPartial: true)
            .content,
        'Body',
      );
      expect(
        handler
            .parse('<|open|>response<|sep|>Body<|close|>message<|sep|>')
            .content,
        'Body',
      );
      expect(
        handler.parse('\n<|open|>think<|sep|>Plan.').reasoningContent,
        'Plan.',
      );
    });

    test('ends an unclosed thought at a tool block', () {
      const call =
          '<|open|>tools<|sep|><|open|>call tool="weather" index="1"<|sep|>'
          '<|open|>argument key="city" type="string"<|sep|>Paris'
          '<|close|>argument<|sep|><|close|>call<|sep|><|close|>tools<|sep|>';
      for (final (output, forcedOpen) in [
        ('<|open|>think<|sep|>Plan.$call', false),
        ('Plan.$call', true),
      ]) {
        final parsed = KimiK3Handler().parseWithTools(
          output,
          tools: [weatherWithCityTool],
          thinkingForcedOpen: forcedOpen,
        );
        expect(parsed.reasoningContent, 'Plan.');
        expect(parsed.content, isEmpty);
        expect(parsed.toolCalls.single.function?.name, 'weather');
      }
      final withoutTools = KimiK3Handler().parse(
        'Plan.$call',
        parseToolCalls: false,
        thinkingForcedOpen: true,
      );
      expect(withoutTools.reasoningContent, 'Plan.$call');
      final beforeResponse = KimiK3Handler().parseWithTools(
        'Plan.$call<|open|>response<|sep|>Done.<|close|>response<|sep|>',
        tools: [weatherWithCityTool],
        thinkingForcedOpen: true,
      );
      expect(beforeResponse.reasoningContent, 'Plan.$call');
      expect(beforeResponse.content, 'Done.');
    });
  });
}
