import 'package:test/test.dart';
import 'package:llamadart/src/core/grammar/tool_grammar_generator.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';

void main() {
  // Helper to create simple tool definitions for testing
  ToolDefinition makeTool(
    String name,
    String description,
    List<ToolParam> params,
  ) {
    return ToolDefinition(
      name: name,
      description: description,
      parameters: params,
      handler: (_) async => null,
    );
  }

  group('ToolGrammarGenerator', () {
    test('returns null for empty tools', () {
      final result = ToolGrammarGenerator.generate([]);
      expect(result, isNull);
    });

    test('returns null for ToolChoice.none', () {
      final tool = makeTool('test', 'A test tool', []);
      final result = ToolGrammarGenerator.generate([
        tool,
      ], toolChoice: ToolChoice.none);
      expect(result, isNull);
    });

    test('generates grammar for single tool with ToolChoice.required', () {
      final tool = makeTool('get_weather', 'Get weather info', [
        ToolParam.string('location', description: 'City name', required: true),
      ]);

      final result = ToolGrammarGenerator.generate([
        tool,
      ], toolChoice: ToolChoice.required);

      expect(result, isNotNull);
      expect(result!.grammar, contains('root ::='));
      expect(result.grammar, contains(r'\"tool_call\"'));
      expect(result.grammar, contains(r'\"name\"'));
      expect(result.grammar, contains(r'\"arguments\"'));
      expect(result.grammar, contains(r'\"get_weather\"'));
      expect(result.grammar, contains(r'\"location\"'));
      expect(result.grammarLazy, isFalse);
      expect(result.grammar, isNot(contains(r'\"response\"')));
    });

    test('generates response-or-tool grammar for ToolChoice.auto', () {
      final tool = makeTool('search', 'Search the web', [
        ToolParam.string('query', description: 'Search query', required: true),
      ]);

      final result = ToolGrammarGenerator.generate([
        tool,
      ], toolChoice: ToolChoice.auto);

      expect(result, isNotNull);
      expect(result!.grammarLazy, isFalse);
      expect(result.grammarTriggers, isEmpty);
      expect(result.grammar, contains(r'\"tool_call\"'));
      expect(result.grammar, contains(r'\"response\"'));
    });

    test('generates grammar for multiple tools', () {
      final tools = [
        makeTool('search', 'Search', [
          ToolParam.string('query', description: 'Query', required: true),
        ]),
        makeTool('calculate', 'Calculate', [
          ToolParam.string(
            'expression',
            description: 'Math expression',
            required: true,
          ),
        ]),
      ];

      final result = ToolGrammarGenerator.generate(
        tools,
        toolChoice: ToolChoice.required,
      );

      expect(result, isNotNull);
      expect(result!.grammar, contains('root ::='));
      expect(result.grammar, contains(r'\"tool_call\"'));
      expect(result.grammar, contains(r'\"search\"'));
      expect(result.grammar, contains(r'\"calculate\"'));
      expect(result.grammar, contains(r'\"query\"'));
      expect(result.grammar, contains(r'\"expression\"'));
    });

    test('generateForSchema produces valid GBNF', () {
      final grammar = ToolGrammarGenerator.generateForSchema({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'value': {'type': 'number'},
        },
        'required': ['name'],
      });

      expect(grammar, contains('root ::='));
      expect(grammar, contains(r'\"name\"'));

      for (final line in grammar.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        expect(trimmed, contains(' ::= '), reason: 'Rule syntax: $trimmed');
      }
    });

    test('handles tool with no required params', () {
      final tool = makeTool('ping', 'Ping', [
        ToolParam.string('target', description: 'Target host'),
      ]);

      final result = ToolGrammarGenerator.generate([
        tool,
      ], toolChoice: ToolChoice.required);

      expect(result, isNotNull);
      expect(result!.grammar, contains('root ::='));
    });

    test('handles tool with multiple param types', () {
      final tool = makeTool('create_item', 'Create an item', [
        ToolParam.string('name', description: 'Item name', required: true),
        ToolParam.integer('count', description: 'Count', required: true),
        ToolParam.boolean('active', description: 'Active flag'),
      ]);

      final result = ToolGrammarGenerator.generate([
        tool,
      ], toolChoice: ToolChoice.required);

      expect(result, isNotNull);
      expect(result!.grammar, contains(r'\"name\"'));
      expect(result.grammar, contains(r'\"count\"'));
      expect(result.grammar, contains(r'\"active\"'));
    });
  });
}
