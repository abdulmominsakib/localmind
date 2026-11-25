import 'dart:convert';

import '../../exceptions.dart';
import '../../models/tools/tool_definition.dart';
import '../tool_call_grammar_utils.dart';

const String _toolCallEnd = '<|tool_call_end|>';

/// Builds the schema-directed Python-call language used by LFM2 auto tools.
/// Required/force-JSON callers retain their separate JSON-list grammar.
String? buildLfm2AutoGrammar(
  List<ToolDefinition>? tools, {
  required bool parallelToolCalls,
}) {
  if (tools == null || tools.isEmpty) return null;
  final builder = _PythonGrammar();
  final list = _callList(builder, tools, parallelToolCalls);
  // A trailing comma lets compound tokens close the last argument and call
  // without forcing the sampler back into an unfinished string. Bound closing
  // whitespace so a completed call cannot consume the remaining token budget.
  builder.rules['root'] =
      '${ToolCallGrammarUtils.literal('<|tool_call_start|>')} ws "[" ws $list '
      'close-ws "]" close-ws ${ToolCallGrammarUtils.literal(_toolCallEnd)}';
  final diagnostic = _PythonGrammar(diagnostic: true);
  final diagnosticList = _callList(diagnostic, tools, parallelToolCalls);
  diagnostic.rules['envelope'] =
      '"[" ws $diagnosticList close-ws ("]" close-ws)? '
      'foreign-close diagnostic-tail';
  diagnostic.rules['foreign-close'] = r'"</" [A-Za-z_] [A-Za-z0-9_.:-]* ">"';
  // Neither the call payload nor its diagnostic tail may contain a special
  // marker: the lenient parser could otherwise execute an earlier prefix.
  diagnostic.rules['diagnostic-tail'] = r'([^<] | "<"+ [^<|])* "<"*';
  builder.rules['root'] =
      '${builder.rules['root']} | '
      '${ToolCallGrammarUtils.literal('<|tool_call_start|>')} '
      'diagnostic-ws diagnostic-envelope';

  return builder.rules.entries
      .map((entry) => '${entry.key} ::= ${entry.value}')
      .followedBy(diagnostic.render(prefix: 'diagnostic-'))
      .join('\n');
}

String _callList(
  _PythonGrammar builder,
  List<ToolDefinition> tools,
  bool parallelToolCalls,
) {
  final calls = <String>[];
  final copiedCalls = <String>[];
  for (var index = 0; index < tools.length; index++) {
    final tool = tools[index];
    final schema = tool.toJsonSchema();
    final copiedPath = builder.acceptsCopiedStringTail(tool.name, schema);
    calls.add(
      builder.tool(
        tool.name,
        schema,
        'tool-$index',
        prefixSafeString: copiedPath,
      ),
    );
    if (copiedPath) {
      copiedCalls.add(
        builder.copiedTool(tool.name, schema, 'copied-tool-$index'),
      );
      copiedCalls.add(
        builder.copiedTool(
          tool.name,
          schema,
          'unclosed-tool-$index',
          stringRule: 'unclosed-path-string',
        ),
      );
      calls.add(
        builder.canonicalTool(tool.name, schema, 'canonical-tool-$index'),
      );
    }
  }
  builder.rules['call'] = calls.join(' | ');
  if (copiedCalls.isNotEmpty) {
    builder.rules['copied-call'] = copiedCalls.join(' | ');
  }
  // A diagnostic cannot consume a comma promising another call.
  final normalList =
      'call ${parallelToolCalls ? '(close-ws "," close-ws call)* ' : ''}'
      '${builder.diagnostic ? '' : '(close-ws ",")?'}';
  // The loose fallback reinterprets quotes and JSON objects. Admit copied tails
  // only in one required plain path argument, without either ambiguity.
  return copiedCalls.isEmpty ? normalList : '($normalList | copied-call)';
}

final class _PythonGrammar {
  _PythonGrammar({this.diagnostic = false}) {
    if (diagnostic) {
      rules['double-string'] = r'''"\"" ([^"\\<] | "\\" [^<])* "\""''';
      rules['single-string'] = r'''"'" ([^'\\<] | "\\" [^<])* "'"''';
      rules['canonical-json-char'] =
          r'[^"\\<\x7F\x00-\x1F] | [\\] (["\\bfnrt] | "u" [0-9a-fA-F]{4})';
      rules['never'] = r'[^\x00-\U0010FFFF]';
    }
  }

  final bool diagnostic;

  String _literal(String text) => diagnostic && text.contains('<')
      ? 'never'
      : ToolCallGrammarUtils.literal(text);

  Iterable<String> render({required String prefix}) sync* {
    // Match terminals before rule names so literal data is never renamed.
    final tokens = RegExp(
      r'"(?:[^"\\]|\\.)*"|\[(?:[^\]\\]|\\.)*\]|[A-Za-z][A-Za-z0-9-]*',
    );
    for (final entry in rules.entries) {
      final expression = entry.value.replaceAllMapped(tokens, (match) {
        final text = match[0]!;
        return rules.containsKey(text) ? '$prefix$text' : text;
      });
      yield '$prefix${entry.key} ::= $expression';
    }
  }

  // Uniqueness needs a finite state per remaining argument set. Bound schema
  // expansion before constructing an exponential number of grammar rules.
  static const int _maxArgumentStates = 4096;
  static const int _maxWhitespace = 8;
  static const String _whitespace =
      r'[ \t\n\r]{0,'
      '$_maxWhitespace}';
  static const String _pathAscii =
      r'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ ./:\-';
  static const String _pathUnicode = r'[\u0080-\U0010FFFF]';
  int _argumentStates = 0;
  int _nextValue = 0;
  final Map<String, String> rules = {
    // This rule is structural only; string and literal payloads do not use it.
    'ws': _whitespace,
    'close-ws': _whitespace,
    'py-string': 'double-string | single-string',
    'double-string': r'''"\"" ([^"\\] | "\\" .)* "\""''',
    'single-string': r'''"'" ([^'\\] | "\\" .)* "'"''',
    'copied-path-string':
        r'''"\"" copied-path-char* "\\" "\"" | "'" copied-path-char* "\\" "'"''',
    'unclosed-path-string':
        r'''"\"" copied-path-char+ | "'" copied-path-char+''',
    'copied-path-char': '${_characterClass(_pathAscii)} | $_pathUnicode',
    'canonical-json-char':
        r'[^"\\\x7F\x00-\x1F] | [\\] (["\\bfnrt] | "u" [0-9a-fA-F]{4})',
    'canonical-json-string': r'''"\"" canonical-json-char* "\""''',
    'integer': r'"-"? ("0" | [1-9] [0-9]*)',
    'number': r'integer ("." [0-9]+)? ([eE] [+-]? [0-9]+)?',
    'boolean': r'"True" | "False" | "true" | "false"',
    'null': r'"None" | "null"',
  };

  bool acceptsCopiedStringTail(String name, Map<String, dynamic> schema) {
    final fields = _fields(schema);
    if (RegExp(r'[A-Za-z_][A-Za-z0-9_.-]*').matchAsPrefix(name)?.end !=
            name.length ||
        fields.length != 1) {
      return false;
    }
    final field = fields.entries.single;
    final required = schema['required'] as List? ?? const [];
    return RegExp(r'[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(field.key)?.end ==
            field.key.length &&
        required.length == 1 &&
        required.single == field.key &&
        field.value['type'] == 'string' &&
        field.value.keys.every((key) => key == 'type' || key == 'description');
  }

  String copiedTool(
    String name,
    Map<String, dynamic> schema,
    String rule, {
    String stringRule = 'copied-path-string',
  }) {
    final key = _fields(schema).keys.single;
    rules[rule] =
        '${_literal(name)} "(" ws '
        '${_literal(key)} ws "=" ws $stringRule '
        'close-ws ")"';
    return rule;
  }

  // The existing wrapper unwraps a schema-checked object with JSON strings.
  // Its name must remain distinct from the declared argument.
  String canonicalTool(String name, Map<String, dynamic> schema, String rule) {
    final key = _fields(schema).keys.single;
    final alias = key == 'arguments' ? 'parameters' : 'arguments';
    rules[rule] =
        '${_literal(name)} "(" ws '
        '${_literal(alias)} ws "=" ws "{" ws '
        '${_literal(jsonEncode(key))} ws ":" ws '
        'canonical-json-string ws "}" ws ")"';
    return rule;
  }

  String tool(
    String name,
    Map<String, dynamic> schema,
    String rule, {
    bool prefixSafeString = false,
  }) {
    if (prefixSafeString) {
      if (!diagnostic) _addPrefixSafeStringRules();
      _addCopiedValueRules();
    }
    final fields = _fields(schema);
    final required = (schema['required'] as List? ?? const []).cast<String>();
    final members = <({String name, String value, bool required})>[
      for (final entry in fields.entries)
        (
          name: '${_literal(entry.key)} ws "=" ws',
          value: prefixSafeString
              ? '(${diagnostic ? 'py-string' : 'prefix-safe-string'} | copied-value)'
              : value(entry.value),
          required: required.contains(entry.key),
        ),
    ];
    final arguments = objectMembers(members, '$rule-args');
    rules[rule] = '${_literal(name)} "(" ws $arguments ws ")"';
    return rule;
  }

  Map<String, Map<String, dynamic>> _fields(Map<String, dynamic> schema) => {
    for (final entry in (schema['properties'] as Map? ?? const {}).entries)
      entry.key as String: Map<String, dynamic>.from(entry.value as Map),
  };

  void _addCopiedValueRules() {
    if (rules.containsKey('copied-value')) return;
    // The parser retains these spellings as text in a plain string argument.
    // Keeping the emitted spelling avoids forcing a model to re-encode data.
    rules['copied-value'] =
        'copied-container | copied-bare | copied-quoted-container';
    rules['copied-container'] =
        '"{" copied-fragment* "}" | "[" copied-fragment* "]" | '
        '"(" copied-fragment* ")"';
    rules['copied-fragment'] =
        r'''py-string | copied-container | [^"'(){}\[\]<>]''';
    rules['copied-quoted-container'] =
        r'''"\"" copied-opaque-container "\"" | "'" copied-opaque-container "'"''';
    rules['copied-opaque-container'] =
        '"{" copied-opaque-fragment* "}" | "[" copied-opaque-fragment* "]"';
    rules['copied-opaque-fragment'] = r'copied-opaque-container | [^{}\[\]<>]';
    rules['copied-bare-char'] = r'''[^"'(),{}\[\]<> \t\n\r]''';
    rules['copied-bare'] =
        'copied-bare-char+ ([ \\t\\n\\r]{1,$_maxWhitespace} '
        'copied-bare-char+)*';
  }

  void _addPrefixSafeStringRules() {
    if (rules.containsKey('prefix-safe-string')) return;
    rules['prefix-safe-string'] = 'prefix-safe-double | prefix-safe-single';
    for (final (suffix, quote) in [('double', '"'), ('single', "'")]) {
      final name = 'prefix-safe-$suffix';
      final body = '$name-body';
      final prefix = '$name-prefix';
      final escape = '$name-escape';
      final pathWithoutSlash = _pathAscii.replaceAll(r'\', '');
      final quoteContinuation = _characterClass(
        pathWithoutSlash.replaceAll(' ', ''),
      );
      final nonPath = String.fromCharCodes([
        for (var char = 0; char < 128; char++)
          if (!_pathAscii.codeUnits.contains(char) &&
              char != quote.codeUnitAt(0) &&
              char != 0x29)
            char,
      ]);
      final nonPathRule = _characterClass(nonPath);
      final slash = _literal(r'\');
      final endQuote = _literal(quote);
      rules[name] = '$endQuote $prefix';
      rules[body] =
          '(${_characterClass('$quote\\', inverted: true)} | $slash .)* $endQuote';
      rules[prefix] =
          '$endQuote | $endQuote ($quoteContinuation | $_pathUnicode) $prefix | '
          '(${_characterClass(pathWithoutSlash)} | '
          '$_pathUnicode) $prefix | $slash $escape | '
          '")" $name-gap-1-0 | $nonPathRule $body';
      rules[escape] =
          '$endQuote $name-gap-0-0 | copied-path-char $prefix | '
          '")" $name-gap-1-0 | $nonPathRule $body';

      // A completed copied root must not also be a strict string prefix.
      // Track only that closing sequence; any deviation resumes the full body.
      // The canonical arguments wrapper represents the excluded value spelling.
      void state(String rule, Map<String, String?> moves) {
        final blocked = '$quote\\${moves.keys.join()}';
        rules[rule] = [
          endQuote,
          '$slash . $body',
          '${_characterClass(blocked, inverted: true)} $body',
          for (final move in moves.entries)
            if (move.value != null) '${_literal(move.key)} ${move.value}',
        ].join(' | ');
      }

      // The four gaps surround ')', an optional comma, ']', and the marker.
      for (var group = 0; group < 4; group++) {
        for (var count = 0; count <= _maxWhitespace; count++) {
          final moves = <String, String?>{
            if (group == 0) ')': '$name-gap-1-0',
            if (group == 1) ',': '$name-gap-2-0',
            if (group == 1 || group == 2) ']': '$name-gap-3-0',
            if (group == 3) _toolCallEnd[0]: '$name-marker-1',
            if (count < _maxWhitespace)
              for (final char in [' ', '\t', '\n', '\r'])
                char: '$name-gap-$group-${count + 1}',
          };
          state('$name-gap-$group-$count', moves);
        }
      }
      for (var index = 1; index < _toolCallEnd.length; index++) {
        state('$name-marker-$index', {
          _toolCallEnd[index]: index + 1 == _toolCallEnd.length
              ? null
              : '$name-marker-${index + 1}',
        });
      }
    }
  }

  static String _characterClass(String value, {bool inverted = false}) {
    final chars = StringBuffer();
    for (final char in value.runes.toSet()) {
      if (char < 0x20 || char == 0x7f || char == 0x5e || char == 0x2d) {
        chars.write('\\x${char.toRadixString(16).padLeft(2, '0')}');
      } else {
        final literal = String.fromCharCode(char);
        if (r'\]['.contains(literal)) chars.write(r'\');
        chars.write(literal);
      }
    }
    return '[${inverted ? '^' : ''}$chars]';
  }

  String value(Map<String, dynamic> schema) {
    final choices = schema['enum'];
    if (choices is List) {
      if (choices.isEmpty || choices.any((value) => value is! String)) {
        throw LlamaUnsupportedException(
          'LFM2 auto enum arguments require a non-empty string enum.',
        );
      }
      final rule = 'value-${_nextValue++}';
      rules[rule] = choices
          .cast<String>()
          .map((text) {
            final trailingBackslashes = text.codeUnits.reversed
                .takeWhile((codeUnit) => codeUnit == 0x5c)
                .length;
            if (trailingBackslashes.isOdd) {
              throw LlamaUnsupportedException(
                'LFM2 auto enum values ending in an odd number of backslashes '
                'cannot preserve strict argument quote boundaries.',
              );
            }
            final literals = <String>[];
            for (final quote in ['"', "'"]) {
              if (!text.contains(quote)) {
                literals.add(_literal('$quote$text$quote'));
              }
            }
            if (literals.isEmpty) {
              throw LlamaUnsupportedException(
                'LFM2 auto enum values containing both quote styles cannot '
                'preserve the copied-string policy.',
              );
            }
            return literals.join(' | ');
          })
          .join(' | ');
      return rule;
    }
    return switch (schema['type']) {
      'string' => 'py-string',
      'integer' => 'integer',
      'number' => 'number',
      'boolean' => 'boolean',
      'null' => 'null',
      'array' => array(schema),
      'object' => object(schema),
      _ => throw LlamaUnsupportedException(
        'LFM2 auto Python-call grammar requires declared legacy parameter '
        'types; this schema is unsupported.',
      ),
    };
  }

  String array(Map<String, dynamic> schema) {
    final items = schema['items'];
    if (items is! Map) {
      throw LlamaUnsupportedException(
        'LFM2 auto array parameters need a declared item type.',
      );
    }
    final rule = 'value-${_nextValue++}';
    final item = value(Map<String, dynamic>.from(items));
    rules[rule] = '"[" ws ($item (ws "," ws $item)*)? ws "]"';
    return rule;
  }

  String object(Map<String, dynamic> schema) {
    final rule = 'value-${_nextValue++}';
    final fields = _fields(schema);
    final required = (schema['required'] as List? ?? const []).cast<String>();
    final members = <({String name, String value, bool required})>[
      for (final entry in fields.entries)
        (
          name: '${quotedObjectKey(entry.key)} ws ":" ws',
          value: value(entry.value),
          required: required.contains(entry.key),
        ),
    ];
    final body = objectMembers(members, '$rule-members');
    rules[rule] = '"{" ws $body ws "}"';
    return rule;
  }

  String quotedObjectKey(String key) {
    // Nested double-quoted keys use JSON decoding in the existing parser.
    final spellings = [
      jsonEncode(key),
      if (!key.contains("'") &&
          !key.contains(r'\') &&
          key.runes.every((rune) => rune >= 0x20 && rune != 0x7f))
        "'$key'",
    ];
    return '(${spellings.map(_literal).join(' | ')})';
  }

  String objectMembers(
    List<({String name, String value, bool required})> members,
    String prefix,
  ) {
    if (members.length > 20) _tooLarge();
    if (members.isEmpty) {
      rules[prefix] = '""';
      return prefix;
    }
    final visited = <int>{};
    final requiredMask = [
      for (var index = 0; index < members.length; index++)
        if (members[index].required) 1 << index,
    ].fold(0, (left, right) => left | right);
    final full = (1 << members.length) - 1;
    String state(int remaining) {
      final name = '$prefix-$remaining';
      if (!visited.add(remaining)) return name;
      if (++_argumentStates > _maxArgumentStates) _tooLarge();
      final alternatives = <String>[];
      for (var index = 0; index < members.length; index++) {
        final bit = 1 << index;
        if (remaining & bit == 0) continue;
        final member = members[index];
        final next = remaining ^ bit;
        final item = '${member.name} ${member.value}';
        if (next & requiredMask == 0) alternatives.add(item);
        if (next != 0) alternatives.add('$item ws "," ws ${state(next)}');
      }
      rules[name] = alternatives.join(' | ');
      return name;
    }

    final nonempty = state(full);
    if (requiredMask != 0) return nonempty;
    rules[prefix] = '"" | $nonempty';
    return prefix;
  }

  Never _tooLarge() => throw LlamaUnsupportedException(
    'LFM2 auto Python-call grammar exceeds the bounded argument-state '
    'budget; use fewer parameters or nested object fields.',
  );
}
