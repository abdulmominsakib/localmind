import '../grammar/json_schema_converter.dart';
import '../models/tools/tool_definition.dart';

/// Utilities for building tool-call grammars from [ToolDefinition] schemas.
class ToolCallGrammarUtils {
  const ToolCallGrammarUtils._();

  /// Escapes [value] as a grammar string literal.
  static String literal(String value) => _literal(value);

  /// Encodes [value] as a collision-free GBNF rule-name component.
  static String ruleName(String value) {
    if (value.isEmpty) {
      return 'rule-empty';
    }
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final isAsciiAlphaNumeric =
          (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A);
      if (isAsciiAlphaNumeric) {
        buffer.writeCharCode(rune);
      } else {
        buffer.write('-u${rune.toRadixString(16)}-');
      }
    }
    return buffer.toString();
  }

  /// Builds a grammar for an array of tool calls and wraps it with literals.
  static String? buildWrappedArrayGrammar({
    required List<ToolDefinition>? tools,
    required String prefix,
    required String suffix,
    String nameKey = 'name',
    String argumentsKey = 'arguments',
    String? idKey,
    String? idPattern,
    bool allowParallelToolCalls = true,
    bool innerQuoteStrings = false,
    bool allowUnclosedLastString = false,
  }) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final schema = _buildToolArraySchema(
      tools,
      nameKey: nameKey,
      argumentsKey: argumentsKey,
      idKey: idKey,
      idPattern: idPattern,
      allowParallelToolCalls: allowParallelToolCalls,
    );

    var grammar = JsonSchemaConverter.convert(
      schema,
      innerQuoteStrings: innerQuoteStrings,
    );
    if (allowUnclosedLastString && innerQuoteStrings && idKey == null) {
      grammar = _withUnclosedLastString(
        grammar,
        toolCount: tools.length,
        argumentsKey: argumentsKey,
        allowParallelToolCalls: allowParallelToolCalls,
      );
    }
    return wrapRootGrammar(grammar, prefix: prefix, suffix: suffix);
  }

  /// Builds a grammar for a single tool call object and wraps it.
  static String? buildWrappedObjectGrammar({
    required List<ToolDefinition>? tools,
    required String prefix,
    required String suffix,
    String nameKey = 'name',
    String argumentsKey = 'arguments',
    String? idKey,
    String? idPattern,
  }) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final itemSchemas = tools
        .map(
          (tool) => _buildToolObjectSchema(
            tool,
            nameKey: nameKey,
            argumentsKey: argumentsKey,
            idKey: idKey,
            idPattern: idPattern,
          ),
        )
        .toList(growable: false);

    final schema = itemSchemas.length == 1
        ? itemSchemas.first
        : <String, dynamic>{'anyOf': itemSchemas};
    final grammar = JsonSchemaConverter.convert(schema);
    return wrapRootGrammar(grammar, prefix: prefix, suffix: suffix);
  }

  /// Adds a root alternative for a call list that ends inside the last string
  /// argument of a tool whose last required property is a plain string.
  ///
  /// The string stays open until `}}]`, so text that closes the call is
  /// the only way to end it. The closers take no whitespace: every token
  /// before them is one the closed string already admits, including the
  /// reservation of the literal LFM2 end marker.
  static String _withUnclosedLastString(
    String grammar, {
    required int toolCount,
    required String argumentsKey,
    required bool allowParallelToolCalls,
  }) {
    final lines = grammar.trimRight().split('\n');
    final rules = <String, String>{
      for (final line in lines)
        if (line.indexOf(' ::= ') case final at when at > 0)
          line.substring(0, at): line.substring(at + ' ::= '.length),
    };
    final rootIndex = lines.indexWhere((line) => line.startsWith('root ::= '));
    if (rootIndex == -1) {
      return grammar;
    }

    final openItems = <String>[
      for (var i = 0; i < toolCount; i++)
        ?_openItem(
          rules,
          toolCount == 1 ? 'root-item' : 'root-item-$i',
          argumentsKey,
        ),
    ];
    if (openItems.isEmpty) {
      return grammar;
    }

    final openRule = openItems.length == 1
        ? openItems.single
        : openItems.join(' | ');
    final repeated = allowParallelToolCalls ? '(root-item "," space)* ' : '';
    lines[rootIndex] =
        '${lines[rootIndex]} | "[" space $repeated'
        'root-item-open';
    return [
      ...lines,
      'root-item-open ::= $openRule',
      ...JsonSchemaConverter.unclosedInnerQuoteRules(),
      '',
    ].join('\n');
  }

  /// The item that opens [itemRule]'s last required string, or null when that
  /// property is not a plain inner-quote string.
  static String? _openItem(
    Map<String, String> rules,
    String itemRule,
    String argumentsKey,
  ) {
    final item = RegExp(
      r'^"\{" space ([\w-]+) "," space ([\w-]+) "\}" space$',
    ).firstMatch(rules[itemRule] ?? '');
    final argumentsKv = item == null ? null : _splitKv(rules[item[2]!]);
    if (item == null ||
        argumentsKv == null ||
        argumentsKv.head !=
            '${_literal(_literal(argumentsKey))} space ":" space') {
      return null;
    }
    final properties = RegExp(
      r'^"\{" space ([\w-]+(?: "," space [\w-]+)*)(?: \(.*\)\?)? "\}" space$',
    ).firstMatch(rules[argumentsKv.value] ?? '');
    if (properties == null) return null;
    final required = properties[1]!.split(' "," space ');
    final last = _splitKv(rules[required.last]);
    if (last == null || rules[last.value] != 'inner-quote-string') {
      return null;
    }
    return '"{" space ${item[1]} "," space ${argumentsKv.head} "{" space '
        '${[...required.take(required.length - 1), ''].join(' "," space ')}'
        '${last.head} "\\"" open-0';
  }

  /// Splits a `"key" space ":" space value` rule body into its head and value.
  static ({String head, String value})? _splitKv(String? body) {
    final at = body?.lastIndexOf(' ') ?? -1;
    return at < 0
        ? null
        : (head: body!.substring(0, at), value: body.substring(at + 1));
  }

  /// Rewrites the grammar `root` rule with wrapper literals.
  static String wrapRootGrammar(
    String grammar, {
    String prefix = '',
    String suffix = '',
  }) {
    final lines = grammar.trimRight().split('\n');
    final rootIndex = lines.indexWhere((line) => line.startsWith('root ::= '));
    if (rootIndex == -1) {
      return grammar;
    }

    final rootExpr = lines[rootIndex].substring('root ::= '.length).trim();
    final prefixExpr = prefix.isEmpty ? '' : '${literal(prefix)} ';
    final suffixExpr = suffix.isEmpty ? '' : ' ${literal(suffix)}';
    lines[rootIndex] = 'root ::= $prefixExpr($rootExpr)$suffixExpr';

    return '${lines.join('\n')}\n';
  }

  /// Lets [grammar] start inside a forced-open thought.
  ///
  /// The grammar applies from the first token, which is reasoning when the
  /// prompt ends with a thinking start tag. As in llama.cpp's reasoning
  /// parser, any text without [endTag] may precede its output; the end tag is
  /// required because forced-open parsing treats unclosed output as
  /// reasoning. A grammar that already takes the thought is returned as is.
  static String afterForcedOpenThought(String grammar, String endTag) =>
      takesForcedOpenThought(grammar)
      ? grammar
      : [
          for (final line in grammar.trimRight().split('\n'))
            line.startsWith('root ::= ')
                ? 'root ::= think-body ${_literal(endTag)} think-space '
                      '(${line.substring('root ::= '.length)})'
                : line,
          ...excludingRules('think-body', [endTag]),
          r'think-space ::= | " " | "\n"{1,2} [ \t]{0,20}',
        ].join('\n');

  /// Whether [grammar] takes a forced-open thought itself, as
  /// [afterForcedOpenThought] returns it. A thinking budget must leave such a
  /// grammar applied while the model reasons: paused, it would resume in the
  /// thought and take the answer as reasoning.
  static bool takesForcedOpenThought(String grammar) =>
      grammar.contains(RegExp(r'^root ::= think-body ', multiLine: true));

  /// Whether a thinking budget must leave [grammar] applied while the model
  /// reasons: it takes a forced-open thought ([takesForcedOpenThought]) or
  /// models the thought it opens itself, as Seed-OSS's `seed-thought` does.
  /// Paused, such a grammar would resume inside the thought and no longer
  /// constrain the reply after the budget closes it.
  static bool keepsAppliedThroughThought(String grammar) =>
      takesForcedOpenThought(grammar) ||
      grammar.contains(
        RegExp(r'^root ::= seed-thought\??[ \n]', multiLine: true),
      );

  /// Rules for [name] matching text without any of [delimiters], as
  /// llama.cpp's `gbnf_excluding_grammar` emits them. Each state is the
  /// longest suffix of the text that starts a delimiter; a character that
  /// would complete one has no transition.
  ///
  /// Unlike llama.cpp, where every state may end the text, a state may end it
  /// only if no delimiter that follows can start inside it: when a
  /// delimiter's prefix is also its suffix, as in `abab`, text ending `ab`
  /// would let the delimiter start inside it.
  static List<String> excludingRules(String name, List<String> delimiters) {
    String state(int i) => i == 0 ? name : '$name-$i';
    // llama.cpp's GBNF parser has no `\^` escape, and a leading `^` would
    // negate the class. A raw line break would split the rule's line.
    String chars(String value) =>
        value.replaceAllMapped(RegExp(r'[\\\]\[^\x00-\x1F-]'), (m) {
          final code = m[0]!.codeUnitAt(0);
          return m[0] == '^' || code < 0x20
              ? '\\x${code.toRadixString(16).padLeft(2, '0').toUpperCase()}'
              : '\\${m[0]}';
        });
    final children = <Map<String, int>>[{}];
    final ends = <int>[0];
    for (final delimiter in delimiters) {
      var node = 0;
      for (final char in delimiter.split('')) {
        node = children[node][char] ??= () {
          children.add({});
          ends.add(0);
          return children.length - 1;
        }();
      }
      ends[node] = delimiter.length;
    }
    // Aho-Corasick failure links, in breadth-first order so that a node's
    // link is done before its children's.
    final failure = List<int>.filled(children.length, 0);
    final queue = [...children[0].values];
    for (var i = 0; i < queue.length; i++) {
      final node = queue[i];
      for (final MapEntry(key: char, value: child) in children[node].entries) {
        var link = failure[node];
        while (link > 0 && !children[link].containsKey(char)) {
          link = failure[link];
        }
        failure[child] = children[link][char] ?? 0;
        queue.add(child);
      }
      // The longest delimiter that ends here.
      if (ends[node] == 0) ends[node] = ends[failure[node]];
    }
    int next(int node, String char) {
      while (node > 0 && !children[node].containsKey(char)) {
        node = failure[node];
      }
      return children[node][char] ?? 0;
    }

    bool mayEnd(int node) {
      for (final delimiter in delimiters) {
        var at = node;
        for (var i = 0; i < delimiter.length - 1; i++) {
          at = next(at, delimiter[i]);
          if (ends[at] > i + 1) return false;
        }
      }
      return true;
    }

    final alphabet = {
      for (final delimiter in delimiters) ...delimiter.split(''),
    };
    String rule(int node) {
      final moves = [
        for (final char in alphabet)
          if (next(node, char) case final to when to > 0) (char: char, to: to),
      ]..sort((a, b) => b.to.compareTo(a.to));
      final alternatives = [
        for (final move in moves)
          if (ends[move.to] == 0) '[${chars(move.char)}] ${state(move.to)}',
        '[^${moves.map((move) => chars(move.char)).join()}] $name',
      ];
      return '${state(node)} ::= ${mayEnd(node) ? '| ' : ''}'
          '${alternatives.join(' | ')}';
    }

    return [
      for (var node = 0; node < children.length; node++)
        if (ends[node] == 0) rule(node),
    ];
  }

  static Map<String, dynamic> _buildToolArraySchema(
    List<ToolDefinition> tools, {
    required String nameKey,
    required String argumentsKey,
    String? idKey,
    String? idPattern,
    required bool allowParallelToolCalls,
  }) {
    final itemSchemas = tools
        .map(
          (tool) => _buildToolObjectSchema(
            tool,
            nameKey: nameKey,
            argumentsKey: argumentsKey,
            idKey: idKey,
            idPattern: idPattern,
          ),
        )
        .toList(growable: false);

    final schema = <String, dynamic>{
      'type': 'array',
      'items': itemSchemas.length == 1
          ? itemSchemas.first
          : <String, dynamic>{'anyOf': itemSchemas},
      'minItems': 1,
    };

    if (!allowParallelToolCalls) {
      schema['maxItems'] = 1;
    }

    return schema;
  }

  static Map<String, dynamic> _buildToolObjectSchema(
    ToolDefinition tool, {
    required String nameKey,
    required String argumentsKey,
    String? idKey,
    String? idPattern,
  }) {
    final properties = <String, dynamic>{
      nameKey: <String, dynamic>{'type': 'string', 'const': tool.name},
      argumentsKey: tool.toJsonSchema(),
    };
    final required = <String>[nameKey, argumentsKey];

    if (idKey != null) {
      properties[idKey] = <String, dynamic>{
        'type': 'string',
        if (idPattern != null && idPattern.isNotEmpty) 'pattern': idPattern,
      };
      required.add(idKey);
    }

    return <String, dynamic>{
      'type': 'object',
      'properties': properties,
      'required': required,
    };
  }

  static String _literal(String value) {
    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return '"$escaped"';
  }
}
