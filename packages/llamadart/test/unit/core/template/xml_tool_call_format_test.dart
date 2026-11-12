import 'dart:convert';

import 'package:llamadart/src/core/models/chat/completion_chunk.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:llamadart/src/core/template/xml_tool_call_format.dart';
import 'package:test/test.dart';

void main() {
  test(
    'toolCallOpening finds the scope start, or the tool start without one',
    () {
      expect(XmlToolCallFormat.qwen3Coder.toolCallOpening('Hi <tool_call>'), 3);
      expect(XmlToolCallFormat.qwen3Coder.toolCallOpening('Hi <tool_c'), 3);
      expect(XmlToolCallFormat.qwen3Coder.toolCallOpening('Hi <function='), 13);
      expect(
        XmlToolCallFormat.minicpm5.toolCallOpening('Hi <function name="f">'),
        3,
      );
      expect(XmlToolCallFormat.minicpm5.toolCallOpening('Hi <tool_call>'), 14);
    },
  );

  test('parseXmlToolCalls parses a simple XML-like tool call', () {
    const output =
        '<tool_call>\n'
        '<function=weather>\n'
        '<parameter=city>\n"Seoul"\n</parameter>\n'
        '</function>\n'
        '</tool_call>';
    final parsed = parseXmlToolCalls(output, XmlToolCallFormat.qwen3Coder);

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, 'weather');
    expect(jsonDecode(parsed.toolCalls.first.function!.arguments!), {
      'city': 'Seoul',
    });
  });

  test('parseXmlToolCalls preserves raw argument strings when not JSON', () {
    const output =
        '<tool_call>\n'
        '<function=weather>\n'
        '<parameter=city>\nSeoul\n</parameter>\n'
        '</function>\n'
        '</tool_call>';
    final parsed = parseXmlToolCalls(output, XmlToolCallFormat.qwen3Coder);

    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, 'weather');
    expect(jsonDecode(parsed.toolCalls.first.function!.arguments!), {
      'city': 'Seoul',
    });
  });

  test('honors raw-only values and the final value delimiter', () {
    const format = XmlToolCallFormat(
      scopeStart: '<calls>',
      toolStart: '<call=',
      toolSep: '>',
      keyStart: '<arg=',
      keyValSep: '>',
      valEnd: '</arg>',
      lastValEnd: '</last>',
      toolEnd: '</call>',
      scopeEnd: '</calls>',
      rawArgval: true,
    );
    const output =
        '<calls><call=sample>'
        '<arg=count>42</arg>'
        '<arg=enabled>false</last>'
        '</call></calls>';

    final parsed = parseXmlToolCalls(output, format);

    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
      'count': '42',
      'enabled': 'false',
    });
  });

  test('rejects raw values when a format requires JSON', () {
    const format = XmlToolCallFormat(
      scopeStart: '<calls>',
      toolStart: '<call=',
      toolSep: '>{',
      keyStart: '"',
      keyValSep: '":',
      valEnd: ',',
      lastValEnd: '}',
      toolEnd: '</call>',
      scopeEnd: '</calls>',
      rawArgval: false,
    );
    const output = '<calls><call=sample>{"city":Seoul}</call></calls>';

    final parsed = parseXmlToolCalls(output, format);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, output);
  });

  test('accept-either grammar permits raw and JSON values', () {
    const format = XmlToolCallFormat(
      scopeStart: '<calls>',
      toolStart: '<call=',
      toolSep: '>',
      keyStart: '<arg=',
      keyValSep: '>',
      valEnd: '</arg>',
      toolEnd: '</call>',
      scopeEnd: '</calls>',
    );
    final grammar = buildXmlToolCallGrammar(<ToolDefinition>[
      ToolDefinition(
        name: 'sample',
        description: 'Samples values.',
        parameters: <ToolParam>[ToolParam.string('value', required: true)],
        handler: (_) async => null,
      ),
    ], format);

    expect(grammar, contains('param-name ::= "value"\nraw-text ::= ([^<])*'));
    expect(
      grammar,
      contains('param ::= "<arg=" param-name ">" argument-value'),
    );
    expect(grammar, contains('argument-value ::= raw-text | value'));
  });

  test('accept-either parsing preserves a JSON null value', () {
    const format = XmlToolCallFormat(
      scopeStart: '<calls>',
      toolStart: '<call=',
      toolSep: '>',
      keyStart: '<arg=',
      keyValSep: '>',
      valEnd: '</arg>',
      toolEnd: '</call>',
      scopeEnd: '</calls>',
    );
    const output =
        '<calls><call=sample>'
        '<arg=value>null</arg>'
        '</call></calls>';

    final parsed = parseXmlToolCalls(output, format);

    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
      'value': null,
    });
  });

  test('CDATA values honor the configured final delimiter', () {
    const format = XmlToolCallFormat(
      scopeStart: '<calls>',
      toolStart: '<call=',
      toolSep: '>',
      keyStart: '<arg=',
      keyValSep: '>',
      valEnd: '</arg>',
      lastValEnd: '</last>',
      toolEnd: '</call>',
      scopeEnd: '</calls>',
      rawArgval: true,
    );
    const output =
        '<calls><call=sample>'
        '<arg=value><![CDATA[raw <value>]]></last>'
        '</call></calls>';

    final parsed = parseXmlToolCalls(output, format);

    expect(parsed.content, isEmpty);
    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
      'value': 'raw <value>',
    });
  });

  test('Qwen3 Coder grammar accepts raw XML parameter values', () {
    final grammar = buildXmlToolCallGrammar(<ToolDefinition>[
      ToolDefinition(
        name: 'weather',
        description: 'Returns weather.',
        parameters: <ToolParam>[ToolParam.string('city', required: true)],
        handler: (_) async => null,
      ),
    ], XmlToolCallFormat.qwen3Coder);

    expect(grammar, contains('xml-value ::= raw-text | value'));
    expect(grammar, contains('root ::= tool-call-scope+'));
    expect(
      grammar,
      contains(
        'tool-call-scope ::= "<tool_call>" xml-space tool-call "</tool_call>" xml-space',
      ),
    );
    expect(grammar, contains(r'xml-space ::= [ \t\n\r]*'));
    expect(
      grammar,
      contains(
        'param ::= "<parameter=" param-name ">" xml-value "</parameter>" xml-space',
      ),
    );
  });

  test('parses a forced-open Qwen tool call without a think close', () {
    const output =
        'I should look up the weather.\n'
        '<tool_call>\n'
        '<function=weather>\n'
        '<parameter=city>\nSeoul\n</parameter>\n'
        '</function>\n'
        '</tool_call>';
    final parsed = parseXmlToolCalls(
      output,
      XmlToolCallFormat.qwen3Coder,
      thinkingForcedOpen: true,
    );

    expect(parsed.reasoningContent, 'I should look up the weather.');
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.single.function?.name, 'weather');
    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
      'city': 'Seoul',
    });
  });

  test('keeps a literal tool scope inside a disabled forced thought', () {
    const output = 'I might write <tool_call> as an example.';
    final parsed = parseXmlToolCalls(
      output,
      XmlToolCallFormat.qwen3Coder,
      parseToolCalls: false,
      thinkingForcedOpen: true,
    );

    expect(parsed.reasoningContent, output);
    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, isEmpty);
  });

  test(
    'defers an incomplete Qwen tool scope while streaming a forced thought',
    () {
      const output = 'I should look this up.<tool_ca';
      final parsed = parseXmlToolCalls(
        output,
        XmlToolCallFormat.qwen3Coder,
        isPartial: true,
        thinkingForcedOpen: true,
      );

      expect(parsed.reasoningContent, 'I should look this up.');
      expect(parsed.content, isEmpty);
      expect(parsed.toolCalls, isEmpty);
    },
  );

  test('parseXmlToolCalls keeps malformed scoped XML payload as content', () {
    const output =
        '<tool_call>\n'
        '<function=weather>\n'
        '<parameter=city>\n"Seoul"\n'
        '</tool_call>';
    final parsed = parseXmlToolCalls(output, XmlToolCallFormat.qwen3Coder);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, output);
  });

  test('parseXmlToolCalls keeps malformed scoped prelude as content', () {
    const output =
        '<tool_call>\n'
        'oops\n'
        '<function=weather>\n'
        '<parameter=city>\n"Seoul"\n</parameter>\n'
        '</function>\n'
        '</tool_call>';
    final parsed = parseXmlToolCalls(output, XmlToolCallFormat.qwen3Coder);

    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, output);
  });

  test('raw-only grammar uses the configured final delimiter', () {
    const format = XmlToolCallFormat(
      scopeStart: '<calls>',
      toolStart: '<call=',
      toolSep: '>',
      keyStart: '<arg=',
      keyValSep: '>',
      valEnd: '</arg>',
      lastValEnd: '</last>',
      toolEnd: '</call>',
      scopeEnd: '</calls>',
      rawArgval: true,
    );
    final grammar = buildXmlToolCallGrammar(<ToolDefinition>[
      ToolDefinition(
        name: 'sample',
        description: 'Samples values.',
        parameters: <ToolParam>[ToolParam.string('value', required: true)],
        handler: (_) async => null,
      ),
    ], format);

    expect(grammar, contains('raw-text ::= ([^<])*'));
    expect(
      grammar,
      contains('arguments ::= (param ("</arg>" param)*)? "</last>"'),
    );
  });

  test('empty final delimiter ends directly at the tool delimiter', () {
    final grammar = buildXmlToolCallGrammar(<ToolDefinition>[
      ToolDefinition(
        name: 'sample',
        description: 'Samples values.',
        parameters: <ToolParam>[ToolParam.string('value', required: true)],
        handler: (_) async => null,
      ),
    ], XmlToolCallFormat.xiaomiMimo);

    expect(grammar, contains('arguments ::= (param (", " param)*)?'));
    expect(grammar, isNot(contains('arguments ::= (param (", " param)*)? ""')));
  });

  test('parallelToolCalls only changes the root of repeated scopes', () {
    final tools = <ToolDefinition>[
      ToolDefinition(
        name: 'sample',
        description: 'Samples values.',
        parameters: <ToolParam>[ToolParam.string('value', required: true)],
        handler: (_) async => null,
      ),
    ];

    for (final format in <XmlToolCallFormat>[
      XmlToolCallFormat.minicpm5,
      XmlToolCallFormat.xiaomiMimo,
      XmlToolCallFormat.generic,
    ]) {
      final unset = buildXmlToolCallGrammar(tools, format);
      expect(unset, contains('tool-call+'));
      expect(
        buildXmlToolCallGrammar(tools, format, parallelToolCalls: false),
        equals(unset),
      );
      expect(
        buildXmlToolCallGrammar(tools, format, parallelToolCalls: true),
        equals(unset),
      );
    }

    for (final format in <XmlToolCallFormat>[
      XmlToolCallFormat.qwen3Coder,
      XmlToolCallFormat.seedOss,
    ]) {
      final repeated = buildXmlToolCallGrammar(tools, format);
      expect(repeated, contains('root ::= tool-call-scope+\n'));
      expect(
        repeated,
        contains(
          'tool-call-scope ::= "${format.scopeStart.replaceAll('\n', r'\n')}" '
          'xml-space tool-call '
          '"${format.scopeEnd}" xml-space',
        ),
      );
      expect(
        buildXmlToolCallGrammar(tools, format, parallelToolCalls: true),
        equals(repeated),
      );
      expect(
        buildXmlToolCallGrammar(tools, format, parallelToolCalls: false),
        equals(repeated!.replaceFirst('tool-call-scope+', 'tool-call-scope')),
      );
    }
  });

  for (final (name, format, startThink, endThink) in [
    ('Qwen3-Coder', XmlToolCallFormat.qwen3Coder, '<think>', '</think>'),
    ('Seed-OSS', XmlToolCallFormat.seedOss, '<seed:think>', '</seed:think>'),
  ]) {
    group('consecutive $name scopes', () {
      String call(String city) =>
          '${format.scopeStart}\n'
          '<function=weather>\n'
          '<parameter=city>\n$city\n</parameter>\n'
          '</function>\n'
          '${format.scopeEnd}';
      final schemas = {
        'weather': {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
          'required': ['city'],
        },
      };
      // Qwen3-Coder trims raw values; Seed-OSS keeps their line breaks.
      List<Object?> cities(List<LlamaCompletionChunkToolCall> calls) => [
        for (final call in calls)
          ((jsonDecode(call.function!.arguments!) as Map)['city'] as String),
      ];
      List<String> values(List<String> names) => [
        for (final name in names) format.trimRawArgval ? name : '\n$name\n',
      ];

      for (final separator in ['', '\n', '\n\n', ' ', '\t', '\n  ']) {
        test('parse one call per scope with ${jsonEncode(separator)} between '
            'them', () {
          for (final names in [
            ['Paris', 'Rome'],
            ['Paris', 'Rome', 'Tokyo'],
          ]) {
            final output = names.map(call).join(separator);
            for (final withSchemas in [false, true]) {
              final parsed = parseXmlToolCalls(
                output,
                format,
                schemas: withSchemas ? schemas : null,
              );

              expect(cities(parsed.toolCalls), values(names), reason: output);
              expect(
                parsed.toolCalls.map((call) => call.index),
                List.generate(names.length, (index) => index),
              );
              expect(parsed.content, isEmpty, reason: output);
            }
          }
        });
      }

      test('parse after a thought and before trailing text', () {
        final calls = '${call('Paris')}\n${call('Rome')}\nDone.';
        for (final forcedOpen in [true, false]) {
          final parsed = parseXmlToolCalls(
            '${forcedOpen ? '' : startThink}Plan$endThink\nLet me check.\n'
            '$calls',
            format,
            startThink: startThink,
            endThink: endThink,
            thinkingForcedOpen: forcedOpen,
            verbatimForcedThought: forcedOpen,
            schemas: schemas,
          );

          expect(parsed.reasoningContent, 'Plan', reason: '$forcedOpen');
          expect(cities(parsed.toolCalls), values(['Paris', 'Rome']));
          expect(parsed.content, 'Let me check.\n\nDone.');
        }
      });

      test('end at text between scopes, which stays content', () {
        final rest = 'Then ${call('Rome')}';
        final parsed = parseXmlToolCalls(
          '${call('Paris')}\n$rest',
          format,
          schemas: schemas,
        );

        expect(cities(parsed.toolCalls), values(['Paris']));
        expect(parsed.content, rest);
      });

      test('keep a later scope without a valid call as content', () {
        final unknownTool = call('Rome').replaceFirst('weather', 'unknown');
        final unclosed = call(
          'Rome',
        ).substring(0, call('Rome').length - '\n${format.scopeEnd}'.length);
        for (final later in [
          unknownTool,
          unclosed,
          '${format.scopeStart}\noops ${call('Rome').substring('${format.scopeStart}\n'.length)}',
          call('Rome').replaceFirst('</function>\n', '</function>\noops\n'),
          '${format.scopeStart}\nRome\n${format.scopeEnd}',
          '${format.scopeStart}\n<function=weather>\n<parameter=city>\nRo',
          '${call('Rome')}\n$unclosed',
        ]) {
          final output = '${call('Paris')}\n$later';
          final kept = later.startsWith(call('Rome'))
              ? ['Paris', 'Rome']
              : ['Paris'];
          // Without schemas, any tool name is valid.
          for (final withSchemas in [true, if (later != unknownTool) false]) {
            final parsed = parseXmlToolCalls(
              output,
              format,
              schemas: withSchemas ? schemas : null,
            );

            expect(cities(parsed.toolCalls), values(kept), reason: later);
            expect(
              parsed.content,
              later.startsWith(call('Rome')) ? unclosed : later,
              reason: later,
            );
          }
        }
      });

      test('still reject an unclosed first scope', () {
        final unclosed = call(
          'Paris',
        ).substring(0, call('Paris').length - format.scopeEnd.length);
        final output = '$unclosed\n${call('Rome')}';
        final parsed = parseXmlToolCalls(output, format);

        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, output);
      });
    });
  }

  // llama.cpp 620d2225 returns no call for either Qwen3-Coder output, and
  // empty content where this scan keeps the output as text (the Qwen3-Coder
  // handler parses with endsAtLastCall, below). Seed-OSS differs there: a
  // scope without a line break is text to llama.cpp.
  test('an empty first Qwen3-Coder scope starts no later calls', () {
    const call =
        '<tool_call>\n<function=weather>\n<parameter=city>\nParis\n'
        '</parameter>\n</function>\n</tool_call>';
    for (final empty in [
      '<tool_call></tool_call>',
      '<tool_call>\n</tool_call>',
    ]) {
      final output = '$empty\n$call';
      final parsed = parseXmlToolCalls(output, XmlToolCallFormat.qwen3Coder);

      expect(parsed.toolCalls, isEmpty, reason: output);
      expect(parsed.content, output);
    }
  });

  group('endsAtLastCall', () {
    String call(String city) =>
        '<tool_call>\n<function=weather>\n<parameter=city>\n$city\n'
        '</parameter>\n</function>\n</tool_call>';
    List<String> cities(ChatParseResult parsed) => [
      for (final call in parsed.toolCalls)
        (jsonDecode(call.function!.arguments!) as Map)['city'] as String,
    ];
    ChatParseResult parse(
      String output, {
      int? maxToolCalls,
      bool isPartial = false,
    }) => parseXmlToolCalls(
      output,
      XmlToolCallFormat.qwen3Coder,
      endsAtLastCall: true,
      maxToolCalls: maxToolCalls,
      isPartial: isPartial,
    );

    test('keeps the text before the first scope and drops the rest', () {
      final parsed = parse('Checking.\n${call('Paris')}\nDone.');

      expect(parsed.content, 'Checking.');
      expect(cities(parsed), ['Paris']);
    });

    test('takes consecutive scopes up to maxToolCalls', () {
      final output = '${call('Paris')}\n${call('Rome')}';

      expect(cities(parse(output)), ['Paris', 'Rome']);
      expect(cities(parse(output, maxToolCalls: 1)), ['Paris']);
    });

    test('stops at a scope that is empty or holds two calls', () {
      const twoCalls =
          '<tool_call>\n<function=weather>\n<parameter=city>\nRome\n'
          '</parameter>\n</function>\n<function=weather>\n'
          '<parameter=city>\nOslo\n</parameter>\n</function>\n</tool_call>';
      for (final (output, expected) in [
        ('<tool_call>\n</tool_call>\n${call('Paris')}', <String>[]),
        ('$twoCalls\n${call('Paris')}', <String>[]),
        ('${call('Paris')}\n$twoCalls', ['Paris']),
      ]) {
        final parsed = parse('Hi $output');

        expect(cities(parsed), expected, reason: output);
        expect(parsed.content, 'Hi', reason: output);
      }
    });

    test('takes a call that ends a finished reply without its scope end', () {
      for (final cut in ['</tool_call>', 'tool_call>', '>']) {
        final output = '${call('Paris')}\n${call('Rome')}';
        final truncated = output.substring(0, output.length - cut.length);

        expect(cities(parse(truncated)), ['Paris', 'Rome'], reason: cut);
        expect(cities(parse(truncated, isPartial: true)), ['Paris']);
      }
      final cutInValue = '${call('Paris')}\n${call('Rome')}'.substring(
        0,
        call('Paris').length + 40,
      );
      expect(cities(parse(cutInValue)), ['Paris']);
    });
  });
}
