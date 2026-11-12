@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_handler.dart';
import 'package:test/test.dart';

void main() {
  final reasoningFixture =
      jsonDecode(
            File(
              'test/fixtures/lfm2_reasoning_boundary_upstream.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  test('reasoning oracle retains its exact upstream template', () {
    expect(
      sha256
          .convert(
            File(
              'test/fixtures/${reasoningFixture['template']}',
            ).readAsBytesSync(),
          )
          .toString(),
      reasoningFixture['template_sha256'],
    );
  });
  for (final entry in reasoningFixture['cases'] as List) {
    test('reasoning boundary matches pinned upstream ${entry['input']}', () {
      final parsed = Lfm2Handler().parseWithTools(
        entry['input'] as String,
        tools: [
          ToolDefinition(
            name: 'get_weather',
            description: 'Weather',
            parameters: [ToolParam.string('city', required: true)],
          ),
        ],
      );
      final expected = entry['expected'] as Map;
      expect(parsed.content, expected['content']);
      expect(parsed.reasoningContent, expected['reasoning_content']);
      expect(
        [
          for (final call in parsed.toolCalls)
            {
              'name': call.function!.name,
              'arguments': call.function!.arguments,
            },
        ],
        [
          for (final call in expected['tool_calls'] as List? ?? const [])
            call['function'],
        ],
      );
    });
  }
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/lfm2_quoted_tool_delimiter_compat.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final weather = ToolDefinition(
    name: 'weather',
    description: 'Weather',
    parameters: [ToolParam.string('city')],
  );
  final cases = fixture['cases'] as List;
  for (var i = 0; i < cases.length; i++) {
    final input = (cases[i] as Map)['input'] as String;
    test('schema dispatch preserves delimiter compatibility case $i', () {
      final baseline = Lfm2Handler().parse(input);
      final candidate = Lfm2Handler().parseWithTools(input, tools: [weather]);
      expect(candidate.content, baseline.content);
      expect(candidate.reasoningContent, baseline.reasoningContent);
      expect(
        [
          for (final call in candidate.toolCalls)
            [call.function?.name, call.function?.arguments],
        ],
        [
          for (final call in baseline.toolCalls)
            [call.function?.name, call.function?.arguments],
        ],
      );
    });
  }

  Map<String, dynamic> arguments(String payload, ToolDefinition tool) {
    final parsed = Lfm2Handler().parseWithTools(
      '<|tool_call_start|>[$payload]<|tool_call_end|>',
      tools: [tool],
    );
    return jsonDecode(parsed.toolCalls.single.function!.arguments!)
        as Map<String, dynamic>;
  }

  test('raw schema retains explicitly allowed additional properties', () {
    expect(
      arguments(
        'f(extra=True)',
        ToolDefinition.fromJsonSchema(
          name: 'f',
          description: 'Test',
          schema: {'type': 'object', 'properties': <String, dynamic>{}},
        ),
      ),
      {'extra': true},
    );
  });

  test('raw schema preserves string values in type alternatives', () {
    expect(
      arguments(
        'f(value=False)',
        ToolDefinition.fromJsonSchema(
          name: 'f',
          description: 'Test',
          schema: {
            'type': 'object',
            'properties': {
              'value': {
                'type': ['string', 'null'],
              },
            },
          },
        ),
      ),
      {'value': 'False'},
    );
  });

  test('open schemas retain non-map additional wrapper-named values', () {
    expect(
      arguments(
        'f(input="text")',
        ToolDefinition.fromJsonSchema(
          name: 'f',
          description: 'Test',
          schema: {'type': 'object', 'properties': <String, dynamic>{}},
        ),
      ),
      {'input': 'text'},
    );
  });

  test('nested JSON object strings preserve baseline escape decoding', () {
    const output =
        r'<|tool_call_start|>[f(config={"text":"line\nnext"})]<|tool_call_end|>';
    final tool = ToolDefinition(
      name: 'f',
      description: 'Test',
      parameters: [
        ToolParam.object('config', properties: [ToolParam.string('text')]),
      ],
    );
    final baseline = Lfm2Handler().parse(output);
    final candidate = Lfm2Handler().parseWithTools(output, tools: [tool]);
    // The schema repairs the lost config key, while the pre-existing JSON
    // string decoding within the object must remain the same.
    final oldValue =
        jsonDecode(baseline.toolCalls.single.function!.arguments!) as Map;
    final newValue =
        jsonDecode(candidate.toolCalls.single.function!.arguments!) as Map;
    expect((newValue['config'] as Map)['text'], oldValue['text']);
  });
}
