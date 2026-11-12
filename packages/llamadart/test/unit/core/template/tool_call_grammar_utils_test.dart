import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/command_r7b_handler.dart';
import 'package:llamadart/src/core/template/handlers/hermes_handler.dart';
import 'package:llamadart/src/core/template/handlers/hunyuan_v3_handler.dart';
import 'package:llamadart/src/core/template/tool_call_grammar_utils.dart';
import 'package:test/test.dart';

void main() {
  test('ruleName preserves safe names and distinguishes escaped runes', () {
    expect(ToolCallGrammarUtils.ruleName('code'), 'code');
    expect(
      ToolCallGrammarUtils.ruleName('a b'),
      isNot(ToolCallGrammarUtils.ruleName('a-b')),
    );
    expect(
      ToolCallGrammarUtils.ruleName('Weather'),
      isNot(ToolCallGrammarUtils.ruleName('weather')),
    );
    expect(
      ToolCallGrammarUtils.ruleName(''),
      isNot(ToolCallGrammarUtils.ruleName('rule-empty')),
    );
  });

  test('collision-sensitive handlers reject lossy schema identities', () {
    final duplicateTools = [_tool('inspect'), _tool('inspect')];
    final duplicateParameters = ToolDefinition(
      name: 'ambiguous',
      description: 'Duplicate parameter coverage',
      parameters: [ToolParam.string('mode'), ToolParam.boolean('mode')],
      handler: _noop,
    );
    final builders = <String? Function(List<ToolDefinition>?)>[
      CommandR7BHandler().buildGrammar,
      HermesHandler().buildGrammar,
      HunyuanV3Handler().buildGrammar,
    ];

    for (final buildGrammar in builders) {
      expect(
        () => buildGrammar(duplicateTools),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('unique tool names'),
          ),
        ),
      );
      expect(
        () => buildGrammar([duplicateParameters]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('declared more than once'),
          ),
        ),
      );
    }
  });

  group('afterForcedOpenThought', () {
    for (final endTag in [
      '</think>',
      '</seed:think>',
      '</thinking>',
      '<|end|><|begin|>assistant<|content|>',
      '<|close|>think<|sep|>',
      'aab',
      'abab',
      'aaa',
    ]) {
      test('requires $endTag once before the calls', () {
        final grammar = ToolCallGrammarUtils.afterForcedOpenThought(
          'root ::= call\ncall ::= "x"\n',
          endTag,
        );
        final lines = grammar.split('\n');
        expect(
          lines.first,
          'root ::= think-body ${ToolCallGrammarUtils.literal(endTag)} '
          'think-space (call)',
        );
        expect(lines, contains('call ::= "x"'));

        final body = _ExcludingRules(lines, 'think-body');
        final head = endTag.substring(0, endTag.length - 1);
        final samples = [
          '',
          'plan',
          endTag,
          'plan $endTag',
          '<$endTag',
          '${endTag.substring(0, 3)}$endTag tail',
          head,
          '<$head',
          'x${endTag.substring(0, 1)}',
          '${endTag.substring(0, 3)}${endTag.substring(0, 2)}',
          '${endTag.substring(0, 2)}${endTag.substring(0, 2)}',
          '$head$head',
          '${endTag.substring(0, endTag.length ~/ 2)}$endTag',
          // A partial match that must fall back to a shorter one, not to the
          // start, as in `<|end|><|end|>...`.
          '${endTag.substring(0, 2)}$endTag',
          '${endTag.substring(0, 1)}$endTag',
        ];
        for (final text in samples) {
          // The thought is the text before the first end tag.
          expect(
            body.matches(text),
            '$text$endTag'.indexOf(endTag) == text.length,
            reason: text,
          );
        }
      });
    }

    test('ends a thought at the first end tag after a partial match', () {
      for (final (endTag, thought) in [
        (
          '<|end|><|begin|>assistant<|content|>',
          '<|end|><|end|><|begin|>assistant<|content|>',
        ),
        ('<|close|>think<|sep|>', '<|close|>think<|close|>think<|sep|>'),
      ]) {
        final body = _ExcludingRules(
          ToolCallGrammarUtils.afterForcedOpenThought(
            'root ::= "x"\n',
            endTag,
          ).split('\n'),
          'think-body',
        );
        expect(body.matches(thought), isFalse, reason: thought);
        expect(
          body.matches(thought.substring(0, thought.length - 1)),
          isTrue,
          reason: thought,
        );
      }
    });

    test('ends a thought only where its end tag cannot start earlier', () {
      final lines = ToolCallGrammarUtils.afterForcedOpenThought(
        'root ::= "x"\n',
        'abab',
      ).split('\n');
      final body = _ExcludingRules(lines, 'think-body');

      expect(body.matches('xab'), isFalse);
      expect(body.matches('xaba'), isTrue);
      expect(body.matches('xa'), isTrue);
      expect(
        lines,
        contains('think-body-2 ::= [a] think-body-3 | [^a] think-body'),
      );
    });
  });

  test('excludingRules match text without any delimiter that may end where '
      'none can start inside it', () {
    for (final delimiters in [
      ['<t>', '<f=g>'],
      ['ab', 'xaby'],
      ['abab', 'ba'],
      ['aa', 'ab', 'b'],
      ['^a', 'a^]', '-\\['],
      ['<s>\n', '\t\r'],
    ]) {
      final rules = ToolCallGrammarUtils.excludingRules('t', delimiters);
      // llama.cpp's GBNF parser rejects `\^`.
      expect(rules.join('\n'), isNot(contains(r'\^')), reason: '$delimiters');
      expect(rules, everyElement(isNot(contains('\n'))), reason: '$delimiters');
      final body = _ExcludingRules(rules, 't');
      final alphabet = {...delimiters.join().split(''), 'z'}.toList();
      var texts = [''];
      for (var length = 0; length <= 5; length++) {
        for (final text in texts) {
          bool startsBefore(String delimiter) {
            final joined = text + delimiter.substring(0, delimiter.length - 1);
            return [
              for (var at = 0; at < text.length; at++)
                for (final d in delimiters) joined.startsWith(d, at),
            ].any((match) => match);
          }

          expect(
            body.matches(text),
            !delimiters.any(text.contains) && !delimiters.any(startsBefore),
            reason: '$delimiters "$text"',
          );
        }
        texts = [
          for (final text in texts)
            for (final char in alphabet) '$text$char',
        ];
      }
    }
  });

  test('afterForcedOpenThought leaves a grammar that takes the thought', () {
    final once = ToolCallGrammarUtils.afterForcedOpenThought(
      'root ::= call\ncall ::= "x"\n',
      '</think>',
    );

    expect(ToolCallGrammarUtils.afterForcedOpenThought(once, '</think>'), once);
  });

  test('wrapRootGrammar wraps root rule with literals', () {
    const grammar = 'root ::= obj\nobj ::= "{}"\n';

    final wrapped = ToolCallGrammarUtils.wrapRootGrammar(
      grammar,
      prefix: '<tool>',
      suffix: '</tool>',
    );

    expect(wrapped, contains('root ::= "<tool>" (obj) "</tool>"'));
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

  test('buildWrappedArrayGrammar applies wrappers and requires the id key', () {
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
      allowParallelToolCalls: false,
    );
    final parallel = ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '[TOOL_CALLS]',
      suffix: '',
      idKey: 'id',
      allowParallelToolCalls: true,
    );

    expect(
      noParallel,
      contains('root ::= "[TOOL_CALLS]" ("[" space root-item  "]" space)'),
    );
    expect(
      parallel,
      contains(
        'root ::= "[TOOL_CALLS]" ("[" space root-item ("," space root-item)* '
        '"]" space)',
      ),
    );
    for (final grammar in [noParallel, parallel]) {
      expect(
        grammar,
        contains(
          'root-item ::= "{" space root-item-name-kv "," space '
          'root-item-arguments-kv "," space root-item-id-kv "}" space',
        ),
      );
      expect(grammar, contains('root-item-name ::= "\\"weather\\"" space'));
      expect(
        grammar,
        contains('root-item-id-kv ::= "\\"id\\"" space ":" space string'),
      );
    }
  });

  test('buildWrappedArrayGrammar constrains the id key with idPattern', () {
    final tools = [
      ToolDefinition(
        name: 'weather',
        description: 'Weather lookup',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final grammar = ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '[TOOL_CALLS]',
      suffix: '',
      idKey: 'id',
      idPattern: r'^[a-zA-Z0-9]{9}$',
    );

    expect(
      grammar,
      contains('root-item-id ::= "\\"" (root-item-id-1{9,9}) "\\"" space'),
    );
    expect(grammar, contains('root-item-id-1 ::= [a-zA-Z0-9]'));
    expect(
      grammar,
      contains('root-item-id-kv ::= "\\"id\\"" space ":" space root-item-id'),
    );
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

ToolDefinition _tool(String name) => ToolDefinition(
  name: name,
  description: 'Identity coverage',
  parameters: const [],
  handler: _noop,
);

/// Runs the `name ::= | [chars] next | ...` rules of an excluding grammar; a
/// rule without the leading empty alternative cannot end the text.
class _ExcludingRules {
  _ExcludingRules(List<String> lines, this.start) {
    final alternative = RegExp(r'\[(\^?)((?:\\.|[^\]\\])*)\] ([\w-]+)');
    for (final line in lines) {
      final rule = RegExp(r'^([\w-]+) ::= (\| )?(.*)$').firstMatch(line);
      if (rule == null || !rule[1]!.startsWith(start)) continue;
      if (rule[2] != null) _accepting.add(rule[1]!);
      _rules[rule[1]!] = [
        for (final m in alternative.allMatches(rule[3]!))
          (
            negated: m[1] == '^',
            chars: m[2]!.replaceAllMapped(
              RegExp(r'\\x([0-9A-Fa-f]{2})|\\(.)'),
              (e) => e[2] ?? String.fromCharCode(int.parse(e[1]!, radix: 16)),
            ),
            next: m[3]!,
          ),
      ];
    }
  }

  final String start;
  final _rules = <String, List<({bool negated, String chars, String next})>>{};
  final _accepting = <String>{};

  /// Whether the rules match all of [text].
  bool matches(String text) {
    var state = start;
    for (final char in text.split('')) {
      final next = _rules[state]!
          .where((a) => a.chars.contains(char) != a.negated)
          .map((a) => a.next)
          .firstOrNull;
      if (next == null) return false;
      state = next;
    }
    return _accepting.contains(state);
  }
}
