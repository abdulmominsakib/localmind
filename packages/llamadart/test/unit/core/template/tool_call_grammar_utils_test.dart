import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/tool_call_grammar_utils.dart';
import 'package:test/test.dart';

void main() {
  test('wrapRootGrammar wraps root rule with literals', () {
    const grammar = 'root ::= obj\nobj ::= "{}"\n';

    final wrapped = ToolCallGrammarUtils.wrapRootGrammar(
      grammar,
      prefix: '<tool>',
      suffix: '</tool>',
    );

    expect(wrapped, contains('root ::= "<tool>" obj "</tool>"'));
    expect(wrapped, endsWith('\n'));
  });

  test('wrapRootGrammar returns original grammar when root is missing', () {
    const grammar = 'obj ::= "{}"\n';

    final wrapped = ToolCallGrammarUtils.wrapRootGrammar(
      grammar,
      prefix: '<x>',
      suffix: '</x>',
    );

    expect(wrapped, equals(grammar));
  });

  test('buildWrappedArrayGrammar returns null without tools', () {
    expect(
      ToolCallGrammarUtils.buildWrappedArrayGrammar(
        tools: null,
        prefix: '<calls>',
        suffix: '</calls>',
      ),
      isNull,
    );
    expect(
      ToolCallGrammarUtils.buildWrappedArrayGrammar(
        tools: const [],
        prefix: '<calls>',
        suffix: '</calls>',
      ),
      isNull,
    );
  });

  test('buildWrappedArrayGrammar applies wrappers and id constraints', () {
    final tools = [
      ToolDefinition(
        name: 'weather',
        description: 'Weather lookup',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final noParallel = ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '[TOOL_CALLS]',
      suffix: '',
      idKey: 'id',
      idPattern: r'^[a-z]{3}$',
      allowParallelToolCalls: false,
    );
    final parallel = ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '[TOOL_CALLS]',
      suffix: '',
      idKey: 'id',
      idPattern: r'^[a-z]{3}$',
      allowParallelToolCalls: true,
    );

    expect(noParallel, isNotNull);
    expect(noParallel, contains('root ::= "[TOOL_CALLS]"'));
    expect(noParallel, contains('weather'));
    expect(noParallel, contains('id'));
    expect(parallel, isNotNull);
    expect(noParallel, isNot(equals(parallel)));
  });

  test('buildWrappedObjectGrammar supports multiple tools and key aliases', () {
    final tools = [
      ToolDefinition(
        name: 'weather',
        description: 'Weather lookup',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
      ToolDefinition(
        name: 'search',
        description: 'Search docs',
        parameters: [ToolParam.string('query', required: true)],
        handler: _noop,
      ),
    ];

    final grammar = ToolCallGrammarUtils.buildWrappedObjectGrammar(
      tools: tools,
      prefix: '<tool>',
      suffix: '</tool>',
      nameKey: 'function',
      argumentsKey: 'params',
    );

    expect(grammar, isNotNull);
    expect(grammar, contains('root ::= "<tool>"'));
    expect(grammar, contains('"</tool>"'));
    expect(grammar, contains('weather'));
    expect(grammar, contains('search'));
    expect(grammar, contains('function'));
    expect(grammar, contains('params'));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
