import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/muse_glimmer_handler.dart';
import 'package:test/test.dart';

import 'specialized_handler_test_fixtures.dart';

void main() {
  group('Muse Glimmer', () {
    const atem =
        '<atem:function_calls>\n'
        '<atem:invoke name="weather">\n'
        '<atem:parameter name="city"> New York </atem:parameter>\n'
        '</atem:invoke>\n'
        '</atem:function_calls>';

    test('separates reasoning, user content, and recipient tool channels', () {
      const output =
          ' to=self<|message|>check first<|eom|>'
          '<|start|>assistant to=user<|message|>On it.<|eom|>'
          '<|start|>assistant to=weather<|message|>$atem';
      final parsed = MuseGlimmerHandler().parse(output);
      expect(parsed.reasoningContent, 'check first');
      expect(parsed.content, 'On it.');
      expect(parsed.toolCalls.single.function?.name, 'weather');
      expect(arguments(parsed), {'city': ' New York '});
    });

    test('round-trips escaped attributes and rejects reserved recipients', () {
      final grammar = MuseGlimmerHandler().buildGrammar([
        escapedAttributeSchemaTool,
      ])!;
      expect(grammar, contains(r'invoke name=\"weather&amp;&quot;alerts\"'));
      expect(grammar, contains(r'parameter name=\"city&amp;&quot;zone\"'));

      const output =
          ' to=weather&"alerts<|message|>'
          '<atem:function_calls>'
          '<atem:invoke name="weather&amp;&quot;alerts">'
          '<atem:parameter name="city&amp;&quot;zone">Seoul</atem:parameter>'
          '</atem:invoke>'
          '</atem:function_calls><|eot|>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.museGlimmer.index,
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
          ChatFormat.museGlimmer.index,
          malformed,
          tools: [escapedAttributeSchemaTool],
        );
        expect(rejected.toolCalls, isEmpty);
        expect(rejected.content, malformed.trim());
      }

      for (final reserved in ['self', 'user', ' leading', 'bad<route']) {
        final tool = ToolDefinition(
          name: reserved,
          description: 'Invalid Muse recipient',
          parameters: const [],
          handler: (_) async => null,
        );
        expect(
          () => MuseGlimmerHandler().buildGrammar([tool]),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      }
    });

    test('requires one invoke matching the Muse recipient route', () {
      const valid =
          ' to=weather<|message|>'
          '<atem:function_calls>'
          '<atem:invoke name="weather"></atem:invoke>'
          '</atem:function_calls><|eot|>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.museGlimmer.index,
        valid,
        tools: [weatherTool],
      );
      expect(parsed.toolCalls.single.function?.name, 'weather');
      expect(parsed.content, isEmpty);

      for (final malformed in [
        valid.replaceFirst('to=weather', 'to=other'),
        valid.replaceFirst('to=weather', 'to= weather '),
        valid
            .replaceFirst('to=weather', 'to=other')
            .replaceFirst('name="weather"', 'name="other"'),
        valid.replaceFirst(
          '</atem:function_calls>',
          '<atem:invoke name="weather"></atem:invoke>'
              '</atem:function_calls>',
        ),
      ]) {
        final rejected = ChatTemplateEngine.parse(
          ChatFormat.museGlimmer.index,
          malformed,
          tools: [weatherTool],
        );
        expect(rejected.toolCalls, isEmpty);
        expect(rejected.content, malformed.trim());
      }
    });

    test('does not parse quoted ATEM markup in the user channel', () {
      const output = ' to=user<|message|>Use this example:\n$atem<|eot|>';
      final parsed = MuseGlimmerHandler().parse(output);
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, contains('<atem:function_calls>'));
    });

    test('does not validate schemas when Muse parsing is disabled', () {
      final duplicate = ToolDefinition(
        name: 'weather',
        description: 'Duplicate weather tool',
        parameters: const [],
        handler: (_) async => null,
      );
      const output = ' to=weather<|message|>$atem<|eot|>';

      final parsed = MuseGlimmerHandler().parseWithTools(
        output,
        tools: [weatherTool, duplicate],
        parseToolCalls: false,
      );

      expect(parsed.content, atem);
      expect(parsed.toolCalls, isEmpty);
    });

    test('preserves malformed tool-channel markup as content', () {
      const output = ' to=weather<|message|><atem:function_calls>broken<|eot|>';
      final parsed = MuseGlimmerHandler().parse(output);
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output.trim());
    });

    test('rolls a truncated final Muse tool channel back verbatim', () {
      const output = 'Before. to=weather<|message|><atem:function_calls>broken';
      final parsed = MuseGlimmerHandler().parse(output);

      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, output);
    });

    test('hides an incomplete tool channel while streaming', () {
      const output =
          ' to=user<|message|>On it.<|eom|>'
          '<|start|>assistant to=weather<|message|>'
          '<atem:function_calls>\n<atem:invoke name="weather">\n'
          '<atem:parameter name="city">Seo';
      final parsed = MuseGlimmerHandler().parse(output, isPartial: true);

      expect(parsed.content, 'On it.');
      expect(parsed.toolCalls, isEmpty);
    });

    test('hides a partial Muse routing envelope before the message body', () {
      const output = 'Visible answer.<|start|>assistant to=weather<|mess';
      final parsed = MuseGlimmerHandler().parse(output, isPartial: true);

      expect(parsed.content, 'Visible answer.');
      expect(parsed.toolCalls, isEmpty);
    });

    test('preserves unmatched content around parsed Muse channels', () {
      const output =
          'Before.'
          ' to=user<|message|>User channel.<|eom|>'
          'Between.'
          '<|start|>assistant to=weather<|message|>$atem<|eot|>'
          'After.';
      final parsed = MuseGlimmerHandler().parse(output);

      expect(parsed.content, contains('Before.'));
      expect(parsed.content, contains('User channel.'));
      expect(parsed.content, contains('Between.'));
      expect(parsed.content, contains('After.'));
      expect(
        parsed.content.indexOf('Before.'),
        lessThan(parsed.content.indexOf('User channel.')),
      );
      expect(
        parsed.content.indexOf('User channel.'),
        lessThan(parsed.content.indexOf('Between.')),
      );
      expect(
        parsed.content.indexOf('Between.'),
        lessThan(parsed.content.indexOf('After.')),
      );
      expect(parsed.toolCalls.single.function?.name, 'weather');
    });

    test('restores an incomplete Muse route as final assistant content', () {
      const output = 'Visible.<|start|>assistant to=weather<|mess';
      final parsed = MuseGlimmerHandler().parse(output);

      expect(parsed.content, output);
      expect(parsed.toolCalls, isEmpty);
    });

    test('lazy grammar activates only at the ATEM tool-call envelope', () {
      final handler = MuseGlimmerHandler();
      final grammar = handler.buildGrammar([weatherTool])!;

      expect(handler.grammarTriggerValues, ['<atem:function_calls>']);
      expect(
        grammar.split('\n').first,
        r'root ::= "<atem:function_calls>" muse-space muse-tool+ "</atem:function_calls>"',
      );
      expect(grammar, isNot(contains('identifier ::=')));
      expect(grammar.split('\n').first, isNot(contains(' to=')));
    });

    test('production parse preserves schema-directed Muse values', () {
      const output =
          ' to=inspect<|message|><atem:function_calls>'
          '<atem:invoke name="inspect">'
          '<atem:parameter name="code">123</atem:parameter>'
          '<atem:parameter name="options">{}</atem:parameter>'
          '<atem:parameter name="items">[]</atem:parameter>'
          '<atem:parameter name="count">7</atem:parameter>'
          '<atem:parameter name="active">true</atem:parameter>'
          '<atem:parameter name="empty">null</atem:parameter>'
          '</atem:invoke></atem:function_calls><|eot|>';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.museGlimmer.index,
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

      final duplicate = output.replaceFirst(
        '</atem:parameter><atem:parameter name="options">',
        '</atem:parameter>'
            '<atem:parameter name="code">again</atem:parameter>'
            '<atem:parameter name="options">',
      );
      final rejected = ChatTemplateEngine.parse(
        ChatFormat.museGlimmer.index,
        duplicate,
        tools: [schemaTool],
      );
      expect(rejected.toolCalls, isEmpty);
      expect(rejected.content, contains('<atem:function_calls>'));
    });
  });
}
