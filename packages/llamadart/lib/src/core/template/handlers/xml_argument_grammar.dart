import '../../grammar/json_schema_converter.dart';

/// JSON value rules that end where llama.cpp's argument value parsers end,
/// for the XML argument grammars of Qwen3-Coder and Ling 3.
///
/// llama.cpp's argument value ends where its JSON does, so the closing tag
/// follows it directly, as the parser requires. Values nested inside it keep
/// the converter's whitespace.
final class ValueEndRules {
  /// Creates rules over the rules [converter] has visited.
  ValueEndRules(this.converter);

  static const _suffix = '-at-value-end';

  /// The converter that holds the rules of the visited schemas.
  final JsonSchemaConverter converter;

  final Set<String> _visited = {};
  final Map<String, String> _copyNames = {};

  // A nested property can name a converter rule `<rule>-at-value-end`, so the
  // copy takes a name no converter rule or other copy has.
  String _copyName(String rule) {
    final existing = _copyNames[rule];
    if (existing != null) return existing;
    final taken = _copyNames.values.toSet();
    var name = '$rule$_suffix';
    for (
      var n = 2;
      converter.rules.containsKey(name) || taken.contains(name);
      n++
    ) {
      name = '$rule$_suffix-$n';
    }
    return _copyNames[rule] = name;
  }

  /// The rule for a value of [schema], named from [name], that ends where its
  /// JSON does.
  String visit(Map<String, dynamic> schema, String name) {
    final rule = converter.visit(schema, name);
    _visited.add(rule);
    return _copyName(rule);
  }

  /// Writes the converter's rules, then the value-end variants of the visited
  /// ones, to [sink].
  void writeTo(StringSink sink) {
    final jsonRules = converter.rules.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final MapEntry(:key, :value) in jsonRules) {
      sink.writeln('$key ::= $value');
    }
    final written = <String>{};
    void writeAtEnd(String rule) {
      if (!written.add(rule)) return;
      final body = _withoutTrailingSpace(converter.rules[rule]!, (last) {
        if (!converter.rules.containsKey(last) || last == 'space') return null;
        writeAtEnd(last);
        return _copyName(last);
      });
      sink.writeln('${_copyName(rule)} ::= $body');
    }

    _visited.forEach(writeAtEnd);
  }
}

/// [body] with the `space` that ends each of its alternatives removed, and
/// an alternative's last rule reference replaced by what [atEnd] returns for
/// it, unless null.
String _withoutTrailingSpace(String body, String? Function(String rule) atEnd) {
  final alternatives = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < body.length; i++) {
    switch (body[i]) {
      case '"':
        i = _closing(body, i, '"');
      case '[':
        i = _closing(body, i, ']');
      case '(':
        depth++;
      case ')':
        depth--;
      case '|' when depth == 0:
        alternatives.add(body.substring(start, i));
        start = i + 1;
    }
  }
  alternatives.add(body.substring(start));
  return alternatives
      .map((alternative) {
        final trimmed = alternative.trim();
        if (trimmed.endsWith(' space')) {
          return trimmed.substring(0, trimmed.length - ' space'.length);
        }
        final last = RegExp(r'[A-Za-z0-9-]+$').stringMatch(trimmed);
        final replacement = last == null ? null : atEnd(last);
        return replacement == null
            ? trimmed
            : '${trimmed.substring(0, trimmed.length - last!.length)}'
                  '$replacement';
      })
      .join(' | ');
}

/// The index of the unescaped [close] that ends the literal or class
/// opening at [open] in [body].
int _closing(String body, int open, String close) {
  var i = open + 1;
  while (i < body.length && body[i] != close) {
    i += body[i] == r'\' ? 2 : 1;
  }
  return i;
}

/// [arguments] in any order, as llama.cpp's `permute`, which keeps the
/// declaration order beyond six of them.
String permutedArguments(
  List<String> rules,
  String prefix,
  List<String> arguments,
) {
  if (arguments.length == 1 || arguments.length > 6) {
    return arguments.join(' ');
  }
  String remaining(int mask) {
    final name = '$prefix-$mask';
    if (rules.any((rule) => rule.startsWith('$name ::= '))) return name;
    final alternatives = <String>[
      for (var index = 0; index < arguments.length; index++)
        if (mask & (1 << index) != 0)
          mask == 1 << index
              ? arguments[index]
              : '${arguments[index]} ${remaining(mask & ~(1 << index))}',
    ];
    rules.add('$name ::= ${alternatives.join(' | ')}');
    return name;
  }

  return remaining((1 << arguments.length) - 1);
}

/// Whether a value of [schema] may be a string, which llama.cpp's grammar
/// then takes as any text.
bool mayBeString(Map<String, dynamic> schema) {
  final type = schema['type'];
  if (type is String) return type == 'string';
  if (type is List) return type.contains('string');
  if (schema.containsKey('const')) return schema['const'] is String;
  final values = schema['enum'];
  if (values is List) return values.any((value) => value is String);
  for (final key in const ['anyOf', 'oneOf']) {
    final children = schema[key];
    if (children is List) {
      return children.any(
        (child) => child is! Map || mayBeString(child.cast<String, dynamic>()),
      );
    }
  }
  final children = schema['allOf'];
  if (children is List) {
    return children.every(
      (child) => child is! Map || mayBeString(child.cast<String, dynamic>()),
    );
  }
  return true;
}
