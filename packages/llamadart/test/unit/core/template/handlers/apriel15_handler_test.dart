import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/apriel15_handler.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:test/test.dart';

void main() {
  test('Apriel15Handler exposes chat format', () {
    final handler = Apriel15Handler();
    expect(handler.format, isA<ChatFormat>());
  });

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
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
