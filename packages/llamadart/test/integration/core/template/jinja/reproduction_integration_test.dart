@TestOn('vm')
library;

import 'dart:io';

import 'package:dinja/dinja.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:test/test.dart';

void main() {
  test('Reproduce ToolParam enumType rendering issue', () {
    // 1. Load template
    final templateFile = File(
      'test/fixtures/templates/functiongemma-270m-it.jinja',
    );
    final templateContent = templateFile.readAsStringSync();
    final template = Template(templateContent);

    // 2. Define tool
    final weatherTool = ToolDefinition(
      name: 'get_current_weather',
      description: 'Get the current weather for a location',
      parameters: [
        ToolParam.string(
          'location',
          description: 'The city and state, e.g. San Francisco, CA',
          required: true,
        ),
        ToolParam.enumType(
          'unit',
          values: ['celsius', 'fahrenheit'],
          description: 'Temperature unit',
        ),
      ],
      handler: (params) async => '',
    );

    // 3. Convert to JSON
    final tools = [weatherTool.toJson()];

    // 4. Render template
    String result = '';
    try {
      result = template.render({
        'tools': tools,
        'messages': [
          {'role': 'user', 'content': 'What is the weather in SF?'},
        ],
        'bos_token': '<bos>',
      });
      print('Rendered Output:\n$result');
    } catch (e, s) {
      print('Error rendering template: $e');
      print(s);
      rethrow;
    }

    // 5. Verify output contains enum values
    expect(
      result,
      contains('enum:[<escape>celsius<escape>,<escape>fahrenheit<escape>]'),
    );
  });
}
