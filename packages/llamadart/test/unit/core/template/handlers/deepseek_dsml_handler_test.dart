import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/deepseek_dsml_handler.dart';
import 'package:test/test.dart';

import 'specialized_handler_test_fixtures.dart';

void main() {
  group('DeepSeek V3.2 DSML', () {
    const actualUpstreamOutput =
        'Let me check the time</think>\n\n'
        '<｜DSML｜function_calls>\n'
        '<｜DSML｜invoke name="weather">\n'
        '<｜DSML｜parameter name="city" string="true">Tokyo'
        '</｜DSML｜parameter>\n'
        '</｜DSML｜invoke>\n'
        '</｜DSML｜function_calls>';

    test('parses the actual pinned-upstream function_calls emission', () {
      final parsed = DeepseekV32Handler().parse(
        actualUpstreamOutput,
        thinkingForcedOpen: true,
      );

      expect(parsed.reasoningContent, 'Let me check the time');
      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls.single.function?.name, 'weather');
      expect(arguments(parsed), {'city': 'Tokyo'});
    });

    test('uses the V3.2 envelope for grammar and lazy activation', () {
      final handler = DeepseekV32Handler();
      final grammar = handler.buildGrammar([attributeTool])!;

      expect(handler.grammarTriggerValues, ['<｜DSML｜function_calls>']);
      expect(handler.preservedTokens, contains('<｜DSML｜function_calls>'));
      expect(
        grammar.split('\n').first,
        r'root ::= "<｜DSML｜function_calls>" dsml-space dsml-tool+ "</｜DSML｜function_calls>"',
      );
      expect(grammar, contains(r'invoke name=\"weather&amp;&quot;alerts\">'));
      expect(grammar, isNot(contains('identifier ::=')));
      expect(grammar, isNot(contains('<｜DSML｜tool_calls>')));
    });

    test('round-trips escaped DSML tool and parameter attributes', () {
      final grammar = DeepseekV32Handler().buildGrammar([
        escapedAttributeSchemaTool,
      ])!;
      expect(grammar, contains(r'invoke name=\"weather&amp;&quot;alerts\"'));
      expect(grammar, contains(r'parameter name=\"city&amp;&quot;zone\"'));

      const output =
          '<｜DSML｜function_calls>'
          '<｜DSML｜invoke name="weather&amp;&quot;alerts">'
          '<｜DSML｜parameter name="city&amp;&quot;zone" string="true">Seoul'
          '</｜DSML｜parameter>'
          '</｜DSML｜invoke>'
          '</｜DSML｜function_calls>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.deepseekV32.index,
        output,
        tools: [escapedAttributeSchemaTool],
      );

      expect(parsed.toolCalls.single.function?.name, 'weather&"alerts');
      expect(arguments(parsed), {'city&"zone': 'Seoul'});

      for (final malformed in [
        output.replaceFirst('weather&amp;&quot;alerts', 'weather&&quot;alerts'),
        output.replaceFirst(
          'weather&amp;&quot;alerts',
          'weather&bogus;&quot;alerts',
        ),
        output.replaceFirst(
          'weather&amp;&quot;alerts',
          'weather&amp;amp;&quot;alerts',
        ),
        output.replaceFirst('city&amp;&quot;zone', 'city&&quot;zone'),
        output.replaceFirst('city&amp;&quot;zone', 'city&bogus;&quot;zone'),
        output.replaceFirst('city&amp;&quot;zone', 'city&amp;amp;&quot;zone'),
      ]) {
        final rejected = ChatTemplateEngine.parse(
          ChatFormat.deepseekV32.index,
          malformed,
          tools: [escapedAttributeSchemaTool],
        );
        expect(rejected.toolCalls, isEmpty);
        expect(rejected.content, malformed);
      }
    });

    test('forced-open reasoning terminates at the V3.2 envelope', () {
      const output =
          'Need the weather\n\n'
          '<｜DSML｜function_calls>\n'
          '<｜DSML｜invoke name="weather">\n'
          '<｜DSML｜parameter name="city" string="true">Seoul'
          '</｜DSML｜parameter>\n'
          '</｜DSML｜invoke>\n'
          '</｜DSML｜function_calls>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.deepseekV32.index,
        output,
        tools: [weatherWithCityTool],
        thinkingForcedOpen: true,
      );

      expect(parsed.reasoningContent, 'Need the weather');
      expect(parsed.content, isEmpty);
      expect(arguments(parsed), {'city': 'Seoul'});
    });

    test('production parse enforces the V3.2 schema and string flag', () {
      const valid =
          '<｜DSML｜function_calls>\n'
          '<｜DSML｜invoke name="weather">\n'
          '<｜DSML｜parameter name="city" string="true">x < 5'
          '</｜DSML｜parameter>\n'
          '</｜DSML｜invoke>\n'
          '</｜DSML｜function_calls>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.deepseekV32.index,
        valid,
        tools: [weatherWithCityTool],
      );
      expect(arguments(parsed), {'city': 'x < 5'});

      final duplicate = valid.replaceFirst(
        '</｜DSML｜parameter>',
        '</｜DSML｜parameter>\n'
            '<｜DSML｜parameter name="city" string="true">again'
            '</｜DSML｜parameter>',
      );
      for (final invalid in [
        valid.replaceFirst('name="weather"', 'name="unknown"'),
        valid.replaceFirst('name="city"', 'name="unknown"'),
        valid.replaceFirst('string="true"', 'string="false"'),
        duplicate,
      ]) {
        final rejected = ChatTemplateEngine.parse(
          ChatFormat.deepseekV32.index,
          invalid,
          tools: [weatherWithCityTool],
        );
        expect(rejected.toolCalls, isEmpty);
        expect(rejected.content, contains('<｜DSML｜function_calls>'));
      }
    });

    test('preserves the protocol block when tool parsing is disabled', () {
      final parsed = DeepseekV32Handler().parse(
        actualUpstreamOutput,
        parseToolCalls: false,
        thinkingForcedOpen: true,
      );

      expect(parsed.reasoningContent, 'Let me check the time');
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, startsWith('<｜DSML｜function_calls>'));
      expect(parsed.content, endsWith('</｜DSML｜function_calls>'));
    });

    test('preserves a forced-open protocol block when parsing is disabled', () {
      const output =
          'Need the weather\n\n'
          '<｜DSML｜function_calls>\n'
          '<｜DSML｜invoke name="weather">\n'
          '<｜DSML｜parameter name="city" string="true">Seoul'
          '</｜DSML｜parameter>\n'
          '</｜DSML｜invoke>\n'
          '</｜DSML｜function_calls>';
      final parsed = DeepseekV32Handler().parse(
        output,
        parseToolCalls: false,
        thinkingForcedOpen: true,
      );

      expect(parsed.reasoningContent, 'Need the weather');
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, startsWith('<｜DSML｜function_calls>'));
      expect(parsed.content, endsWith('</｜DSML｜function_calls>'));
    });

    test('hides an incomplete function call while streaming', () {
      const output =
          'Prelude\n<｜DSML｜function_calls>\n'
          '<｜DSML｜invoke name="weather">\n'
          '<｜DSML｜parameter name="city" string="true">Seo';
      final parsed = DeepseekV32Handler().parse(output, isPartial: true);

      expect(parsed.content, 'Prelude');
      expect(parsed.toolCalls, isEmpty);
    });

    test('keeps completed calls before a partial second invoke', () {
      const output =
          '<｜DSML｜function_calls>\n'
          '<｜DSML｜invoke name="weather">\n'
          '<｜DSML｜parameter name="city" string="true">Seoul'
          '</｜DSML｜parameter>\n'
          '</｜DSML｜invoke>\n'
          '<｜DSML｜invoke name="clock">\n'
          '<｜DSML｜parameter name="tz" string="true">UT';
      final parsed = DeepseekV32Handler().parse(output, isPartial: true);

      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, hasLength(1));
      expect(parsed.toolCalls.single.function?.name, 'weather');
      expect(arguments(parsed), {'city': 'Seoul'});
    });

    test('preserves a malformed completed payload', () {
      const output =
          '<｜DSML｜function_calls>\n'
          '<｜DSML｜invoke name="weather">\n'
          '<｜DSML｜parameter name="days" string="false">two'
          '</｜DSML｜parameter>\n'
          '</｜DSML｜invoke>\n'
          '</｜DSML｜function_calls>';
      final parsed = DeepseekV32Handler().parse(output);

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output);
    });

    test('preserves a truncated full output', () {
      const output =
          '<｜DSML｜function_calls>\n'
          '<｜DSML｜invoke name="weather">\n'
          '<｜DSML｜parameter name="city" string="true">Seoul'
          '</｜DSML｜parameter>\n'
          '</｜DSML｜invoke>';
      final parsed = DeepseekV32Handler().parse(output);

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output);
    });
  });

  group('DeepSeek V4 DSML', () {
    test('parses reasoning, raw strings, and JSON-typed values', () {
      const output =
          'reasoning</think>Done.\n\n'
          '<｜DSML｜tool_calls>\n'
          '<｜DSML｜invoke name="weather">\n'
          '<｜DSML｜parameter name="city" string="true"> New York '
          '</｜DSML｜parameter>\n'
          '<｜DSML｜parameter name="days" string="false">2'
          '</｜DSML｜parameter>\n'
          '</｜DSML｜invoke>\n'
          '</｜DSML｜tool_calls>';
      final parsed = DeepseekV4Handler().parse(
        output,
        thinkingForcedOpen: true,
      );
      expect(parsed.reasoningContent, 'reasoning');
      expect(parsed.content, 'Done.');
      expect(arguments(parsed), {'city': ' New York ', 'days': 2});
    });

    test('preserves malformed non-string values', () {
      const output =
          '<｜DSML｜tool_calls>\n'
          '<｜DSML｜invoke name="weather">\n'
          '<｜DSML｜parameter name="days" string="false">two'
          '</｜DSML｜parameter>\n'
          '</｜DSML｜invoke>\n</｜DSML｜tool_calls>';
      final parsed = DeepseekV4Handler().parse(output);
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output);
    });

    test('keeps the V4 tool_calls grammar and trigger', () {
      final handler = DeepseekV4Handler();
      final grammar = handler.buildGrammar([weatherTool])!;

      expect(handler.grammarTriggerValues, ['<｜DSML｜tool_calls>']);
      expect(
        grammar.split('\n').first,
        r'root ::= "<｜DSML｜tool_calls>" dsml-space dsml-tool+ "</｜DSML｜tool_calls>"',
      );
      expect(grammar, isNot(contains('<｜DSML｜function_calls>')));
    });
  });
}
