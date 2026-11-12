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

  void expectGbnfRules(String grammar) {
    final rules = grammar
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    expect(rules, isNotEmpty);
    for (final rule in rules) {
      expect(rule, matches(RegExp(r'^[a-z0-9-]+ ::= .+$')), reason: rule);
    }
    expect(rules.where((rule) => rule.startsWith('root ::= ')), hasLength(1));
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

      final grammar = result!.grammar;
      expectGbnfRules(grammar);
      expect(
        grammar,
        contains('root ::= "{" space root-tool-call-kv "}" space'),
      );
      expect(
        grammar,
        contains(
          'root-tool-call ::= "{" space root-tool-call-name-kv "," space '
          'root-tool-call-arguments-kv "}" space',
        ),
      );
      expect(
        grammar,
        contains('root-tool-call-name ::= "\\"get_weather\\"" space'),
      );
      expect(
        grammar,
        contains(
          'root-tool-call-arguments ::= "{" space '
          'root-tool-call-arguments-location-kv "}" space',
        ),
      );
      expect(
        grammar,
        contains(
          'root-tool-call-arguments-location-kv ::= "\\"location\\"" space '
          '":" space string',
        ),
      );
      expect(result.grammarLazy, isFalse);
      expect(grammar, isNot(contains(r'\"response\"')));
    });

    test('generates response-or-tool grammar for ToolChoice.auto', () {
      final tool = makeTool('search', 'Search the web', [
        ToolParam.string('query', description: 'Search query', required: true),
      ]);

      final result = ToolGrammarGenerator.generate([
        tool,
      ], toolChoice: ToolChoice.auto);

      final grammar = result!.grammar;
      expectGbnfRules(grammar);
      expect(result.grammarLazy, isFalse);
      expect(result.grammarTriggers, isEmpty);
      expect(grammar, contains('root ::= root-0 | root-1'));
      expect(
        grammar,
        contains('root-0 ::= "{" space root-0-tool-call-kv "}" space'),
      );
      expect(
        grammar,
        contains('root-0-tool-call-name ::= "\\"search\\"" space'),
      );
      expect(
        grammar,
        contains(
          'root-1 ::= "{" space root-1-response-kv "}" space\n'
          'root-1-response-kv ::= "\\"response\\"" space ":" space string',
        ),
      );
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

      final grammar = result!.grammar;
      expectGbnfRules(grammar);
      expect(
        grammar,
        contains('root ::= "{" space root-tool-call-kv "}" space'),
      );
      expect(
        grammar,
        contains('root-tool-call ::= root-tool-call-0 | root-tool-call-1'),
      );
      expect(
        grammar,
        contains('root-tool-call-0-name ::= "\\"search\\"" space'),
      );
      expect(
        grammar,
        contains(
          'root-tool-call-0-arguments-query-kv ::= "\\"query\\"" space '
          '":" space string',
        ),
      );
      expect(
        grammar,
        contains('root-tool-call-1-name ::= "\\"calculate\\"" space'),
      );
      expect(
        grammar,
        contains(
          'root-tool-call-1-arguments-expression-kv ::= "\\"expression\\"" '
          'space ":" space string',
        ),
      );
      expect(grammar, isNot(contains(r'\"response\"')));
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

      final grammar = result!.grammar;
      expectGbnfRules(grammar);
      expect(
        grammar,
        contains(
          'root-tool-call-arguments ::= "{" space  '
          '(root-tool-call-arguments-target-kv )? "}" space',
        ),
      );
      expect(
        grammar,
        contains(
          'root-tool-call-arguments-target-kv ::= "\\"target\\"" space '
          '":" space string',
        ),
      );
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

      final grammar = result!.grammar;
      expectGbnfRules(grammar);
      expect(
        grammar,
        contains(
          'root-tool-call-arguments ::= "{" space '
          'root-tool-call-arguments-name-kv "," space '
          'root-tool-call-arguments-count-kv ( "," space '
          '( root-tool-call-arguments-active-kv ) )? "}" space',
        ),
      );
      expect(
        grammar,
        contains(
          'root-tool-call-arguments-name-kv ::= "\\"name\\"" space ":" space '
          'string',
        ),
      );
      expect(
        grammar,
        contains(
          'root-tool-call-arguments-count-kv ::= "\\"count\\"" space ":" '
          'space integer',
        ),
      );
      expect(
        grammar,
        contains(
          'root-tool-call-arguments-active-kv ::= "\\"active\\"" space ":" '
          'space boolean',
        ),
      );
      expect(grammar, contains('boolean ::= ("true" | "false") space'));
      expect(grammar, contains('integer ::= ("-"? integral-part) space'));
    });
  });
}
