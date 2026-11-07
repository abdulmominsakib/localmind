import 'dart:convert';

import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/xml_tool_call_format.dart';
import 'package:test/test.dart';

void main() {
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

  test('Qwen3 Coder grammar accepts raw XML parameter values', () {
    final grammar = buildXmlToolCallGrammar(<ToolDefinition>[
      ToolDefinition(
        name: 'weather',
        description: 'Returns weather.',
        parameters: <ToolParam>[ToolParam.string('city', required: true)],
        handler: (_) async => null,
      ),
    ], XmlToolCallFormat.qwen3Coder);

    expect(grammar, isNotNull);
    expect(grammar, contains('qwen3-coder-value ::= raw-text | value'));
    expect(
      grammar,
      contains(
        'root ::= "<tool_call>" xml-space tool-call+ "</tool_call>" xml-space',
      ),
    );
    expect(grammar, contains(r'xml-space ::= [ \t\n\r]*'));
    expect(
      grammar,
      contains(
        'param ::= "<parameter=" param-name ">" qwen3-coder-value "</parameter>" xml-space',
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
}
