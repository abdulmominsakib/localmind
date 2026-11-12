import 'dart:convert';

import 'package:llamadart/src/core/template/handlers/apriel15_handler.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:test/test.dart';

void main() {
  test('Apriel15Handler emits xml-style grammar for tools', () {
    final handler = Apriel15Handler();
    final tools = [
      ToolDefinition(
        name: 'lookup',
        description: 'Lookup data',
        parameters: [ToolParam.string('query', required: true)],
        handler: _noop,
      ),
    ];

    final grammar = handler.buildGrammar(tools);
    expect(grammar, isNotNull);
    expect(grammar, contains('root ::='));
    expect(grammar, contains('"<tool_calls>["'));
    expect(grammar, contains('"]</tool_calls>"'));
    expect(grammar, contains('last-tool-call ::='));
    expect(grammar, contains('arguments ::= (param (", " param)*)? "}"'));
  });

  test('parses nested JSON values and multiple tool calls', () {
    final handler = Apriel15Handler();
    const output =
        '<thinking>checking</thinking>'
        '<tool_calls>['
        '{"name": "first", "arguments": {'
        '"payload": {"items": [1, 2], "label": "a, b"}, '
        '"enabled": true}}, '
        '{"name": "second", "arguments": {"nothing": null}}'
        ']</tool_calls>';

    final parsed = handler.parse(output);

    expect(parsed.reasoningContent, 'checking');
    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(2));
    expect(jsonDecode(parsed.toolCalls[0].function!.arguments!), {
      'payload': {
        'items': [1, 2],
        'label': 'a, b',
      },
      'enabled': true,
    });
    expect(jsonDecode(parsed.toolCalls[1].function!.arguments!), {
      'nothing': null,
    });
  });

  test('keeps malformed or truncated legacy payloads as content', () {
    final handler = Apriel15Handler();
    const rawValue =
        '<tool_calls>['
        '{"name": "weather", "arguments": {"city": Seoul}}'
        ']</tool_calls>';
    const truncated =
        '<tool_calls>['
        '{"name": "weather", "arguments": {"city": "Seoul"}';

    final malformed = handler.parse(rawValue);
    final partial = handler.parse(truncated);

    expect(malformed.content, rawValue);
    expect(malformed.toolCalls, isEmpty);
    expect(partial.content, truncated);
    expect(partial.toolCalls, isEmpty);
  });

  test('Apriel15Handler returns a forced-open thought as reasoning', () {
    const call =
        '<tool_calls>[{"name": "weather", '
        '"arguments": {"city": "Paris"}}]</tool_calls>';
    for (final (output, reasoning, calls) in [
      ('Plan.', 'Plan.', 0),
      ('Plan. $call', 'Plan. $call', 0),
      ('Plan.</thinking>\n$call', 'Plan.', 1),
    ]) {
      final parsed = Apriel15Handler().parse(output, thinkingForcedOpen: true);
      expect(parsed.content, isEmpty, reason: output);
      expect(parsed.reasoningContent, reasoning, reason: output);
      expect(parsed.toolCalls, hasLength(calls), reason: output);
    }
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
