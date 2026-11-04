import 'dart:convert';

/// Lightweight Dart port of llama.cpp's PEG parser builder/serializer.
///
/// This emits parser JSON payloads compatible with `common_peg_arena::save()`.
class PegParserBuilder {
  final List<Map<String, dynamic>> _parsers = <Map<String, dynamic>>[];
  final Map<String, int> _rules = <String, int>{};
  int _root = -1;

  /// Creates an epsilon parser node.
  PegParser eps() => _add(<String, dynamic>{'type': 'epsilon'});

  /// Creates a parser that matches only at input start.
  PegParser start() => _add(<String, dynamic>{'type': 'start'});

  /// Creates a parser that matches only at input end.
  PegParser end() => _add(<String, dynamic>{'type': 'end'});

  /// Creates a literal string parser.
  PegParser literal(String literal) =>
      _add(<String, dynamic>{'type': 'literal', 'literal': literal});

  /// Creates a sequence parser and flattens nested sequences.
  PegParser sequence(List<PegParser> parsers) {
    final flattened = <int>[];
    for (final parser in parsers) {
      final node = _parsers[parser.id];
      if (node['type'] == 'sequence') {
        flattened.addAll(_intList(node['children']));
      } else {
        flattened.add(parser.id);
      }
    }
    return _add(<String, dynamic>{'type': 'sequence', 'children': flattened});
  }

  /// Creates a choice parser and flattens nested choices.
  PegParser choice(List<PegParser> parsers) {
    final flattened = <int>[];
    for (final parser in parsers) {
      final node = _parsers[parser.id];
      if (node['type'] == 'choice') {
        flattened.addAll(_intList(node['children']));
      } else {
        flattened.add(parser.id);
      }
    }
    return _add(<String, dynamic>{'type': 'choice', 'children': flattened});
  }

  /// Creates a repetition parser with [minCount] and [maxCount].
  PegParser repeat(PegParser parser, int minCount, int maxCount) {
    return _add(<String, dynamic>{
      'type': 'repetition',
      'child': parser.id,
      'min_count': minCount,
      'max_count': maxCount,
    });
  }

  /// Creates a one-or-more repetition parser.
  PegParser oneOrMore(PegParser parser) => repeat(parser, 1, -1);

  /// Creates a zero-or-more repetition parser.
  PegParser zeroOrMore(PegParser parser) => repeat(parser, 0, -1);

  /// Creates an optional parser.
  PegParser optional(PegParser parser) => repeat(parser, 0, 1);

  /// Creates a positive lookahead parser.
  PegParser peek(PegParser parser) =>
      _add(<String, dynamic>{'type': 'and', 'child': parser.id});

  /// Creates a negative lookahead parser.
  PegParser negate(PegParser parser) =>
      _add(<String, dynamic>{'type': 'not', 'child': parser.id});

  /// Creates a parser that matches any single UTF-8 codepoint.
  PegParser any() => _add(<String, dynamic>{'type': 'any'});

  /// Creates a parser for whitespace.
  PegParser space() => _add(<String, dynamic>{'type': 'space'});

  /// Creates a character-class parser using llama.cpp-compatible ranges.
  PegParser chars(String pattern, {int minCount = 1, int maxCount = -1}) {
    final parsed = _parseCharClasses(pattern);
    return _add(<String, dynamic>{
      'type': 'chars',
      'pattern': pattern,
      'ranges': parsed.ranges
          .map(
            (range) => <String, dynamic>{
              'start': range.start,
              'end': range.end,
            },
          )
          .toList(growable: false),
      'negated': parsed.negated,
      'min_count': minCount,
      'max_count': maxCount,
    });
  }

  /// Creates a rule reference parser.
  PegParser ref(String name) =>
      _add(<String, dynamic>{'type': 'ref', 'name': name});

  /// Creates an `until` parser for a single delimiter.
  PegParser until(String delimiter) => untilOneOf(<String>[delimiter]);

  /// Creates an `until` parser for any of [delimiters].
  PegParser untilOneOf(List<String> delimiters) {
    return _add(<String, dynamic>{'type': 'until', 'delimiters': delimiters});
  }

  /// Creates an `until` parser that consumes remaining input.
  PegParser rest() => untilOneOf(const <String>[]);

  /// Wraps [parser] in a schema node compatible with llama.cpp serialization.
  PegParser schema(
    PegParser parser,
    String name,
    Map<String, dynamic> schema, {
    bool raw = false,
  }) {
    return _add(<String, dynamic>{
      'type': 'schema',
      'child': parser.id,
      'name': name,
      'schema': schema,
      'raw': raw,
    });
  }

  /// Registers a named rule and returns a reference to it.
  PegParser rule(String name, PegParser parser, {bool trigger = false}) {
    final cleanName = _ruleName(name);
    final ruleId = _parsers.length;
    _parsers.add(<String, dynamic>{
      'type': 'rule',
      'name': cleanName,
      'child': parser.id,
      'trigger': trigger,
    });
    _rules[cleanName] = ruleId;
    return ref(cleanName);
  }

  /// Registers a lazily built named rule and returns a reference to it.
  PegParser ruleLazy(
    String name,
    PegParser Function() builder, {
    bool trigger = false,
  }) {
    final cleanName = _ruleName(name);
    if (_rules.containsKey(cleanName)) {
      return ref(cleanName);
    }

    final placeholder = any();
    final placeholderRuleId = _parsers.length;
    _parsers.add(<String, dynamic>{
      'type': 'rule',
      'name': cleanName,
      'child': placeholder.id,
      'trigger': trigger,
    });
    _rules[cleanName] = placeholderRuleId;

    final parser = builder();
    final ruleId = _parsers.length;
    _parsers.add(<String, dynamic>{
      'type': 'rule',
      'name': cleanName,
      'child': parser.id,
      'trigger': trigger,
    });
    _rules[cleanName] = ruleId;
    return ref(cleanName);
  }

  /// Registers a trigger rule used for lazy grammar activation.
  PegParser triggerRule(String name, PegParser parser) {
    return rule(name, parser, trigger: true);
  }

  /// Wraps a parser as atomic.
  PegParser atomic(PegParser parser) =>
      _add(<String, dynamic>{'type': 'atomic', 'child': parser.id});

  /// Wraps a parser with an AST tag.
  PegParser tag(String tag, PegParser parser) =>
      _add(<String, dynamic>{'type': 'tag', 'child': parser.id, 'tag': tag});

  /// Sets the root parser for serialization.
  void setRoot(PegParser parser) {
    _root = parser.id;
  }

  /// Returns a JSON number parser.
  PegParser jsonNumber() {
    return ruleLazy('json-number', () {
      final digit1To9 = chars('[1-9]', minCount: 1, maxCount: 1);
      final digits = chars('[0-9]');
      final intPart = choice(<PegParser>[
        literal('0'),
        sequence(<PegParser>[
          digit1To9,
          chars('[0-9]', minCount: 0, maxCount: -1),
        ]),
      ]);
      final frac = sequence(<PegParser>[literal('.'), digits]);
      final exp = sequence(<PegParser>[
        choice(<PegParser>[literal('e'), literal('E')]),
        optional(chars('[+-]', minCount: 1, maxCount: 1)),
        digits,
      ]);
      return sequence(<PegParser>[
        optional(literal('-')),
        intPart,
        optional(frac),
        optional(exp),
        space(),
      ]);
    });
  }

  /// Returns a JSON string parser.
  PegParser jsonString() {
    return ruleLazy('json-string', () {
      return sequence(<PegParser>[
        literal('"'),
        jsonStringContent(),
        literal('"'),
        space(),
      ]);
    });
  }

  /// Returns a JSON boolean parser.
  PegParser jsonBool() {
    return ruleLazy('json-bool', () {
      return sequence(<PegParser>[
        choice(<PegParser>[literal('true'), literal('false')]),
        space(),
      ]);
    });
  }

  /// Returns a JSON null parser.
  PegParser jsonNull() {
    return ruleLazy('json-null', () {
      return sequence(<PegParser>[literal('null'), space()]);
    });
  }

  /// Returns a JSON object parser.
  PegParser jsonObject() {
    return ruleLazy('json-object', () {
      final ws = space();
      final member = sequence(<PegParser>[
        jsonString(),
        ws,
        literal(':'),
        ws,
        json(),
      ]);
      final members = sequence(<PegParser>[
        member,
        zeroOrMore(sequence(<PegParser>[ws, literal(','), ws, member])),
      ]);
      return sequence(<PegParser>[
        literal('{'),
        ws,
        choice(<PegParser>[
          literal('}'),
          sequence(<PegParser>[members, ws, literal('}')]),
        ]),
        ws,
      ]);
    });
  }

  /// Returns a JSON array parser.
  PegParser jsonArray() {
    return ruleLazy('json-array', () {
      final ws = space();
      final elements = sequence(<PegParser>[
        json(),
        zeroOrMore(sequence(<PegParser>[literal(','), ws, json()])),
      ]);
      return sequence(<PegParser>[
        literal('['),
        ws,
        choice(<PegParser>[
          literal(']'),
          sequence(<PegParser>[elements, ws, literal(']')]),
        ]),
        ws,
      ]);
    });
  }

  /// Returns a JSON value parser.
  PegParser json() {
    return ruleLazy('json-value', () {
      return choice(<PegParser>[
        jsonObject(),
        jsonArray(),
        jsonString(),
        jsonNumber(),
        jsonBool(),
        jsonNull(),
      ]);
    });
  }

  /// Returns a JSON string-content parser.
  PegParser jsonStringContent() =>
      _add(<String, dynamic>{'type': 'json_string'});

  /// Returns a parser for a JSON object member with [key].
  PegParser jsonMember(String key, PegParser parser) {
    final ws = space();
    return sequence(<PegParser>[
      literal('"$key"'),
      ws,
      literal(':'),
      ws,
      parser,
    ]);
  }

  /// Serializes the parser arena to llama.cpp-compatible JSON.
  String save() {
    _resolveRefs();
    return jsonEncode(<String, dynamic>{
      'parsers': _parsers,
      'rules': _rules,
      'root': _root,
    });
  }

  PegParser _add(Map<String, dynamic> node) {
    final id = _parsers.length;
    _parsers.add(node);
    return PegParser._(id, this);
  }

  PegParser _coerce(Object other) {
    if (other is PegParser) {
      return other;
    }
    if (other is String) {
      return literal(other);
    }
    throw ArgumentError.value(other, 'other', 'Expected PegParser or String');
  }

  int _resolveRefId(int id) {
    final node = _parsers[id];
    if (node['type'] == 'ref') {
      final name = node['name'] as String?;
      if (name == null || !_rules.containsKey(name)) {
        throw StateError('Unknown rule reference: $name');
      }
      return _rules[name]!;
    }
    return id;
  }

  void _resolveRefs() {
    for (final node in _parsers) {
      final type = node['type'];
      if (type == 'sequence' || type == 'choice') {
        final children = _intList(node['children']);
        node['children'] = children.map(_resolveRefId).toList(growable: false);
      } else if (type == 'repetition' ||
          type == 'and' ||
          type == 'not' ||
          type == 'schema' ||
          type == 'rule' ||
          type == 'atomic' ||
          type == 'tag') {
        final child = node['child'];
        if (child is int) {
          node['child'] = _resolveRefId(child);
        } else if (child is num) {
          node['child'] = _resolveRefId(child.toInt());
        }
      }
    }
    if (_root >= 0) {
      _root = _resolveRefId(_root);
    }
  }

  static List<int> _intList(Object? value) {
    final raw = value as List<dynamic>? ?? const <dynamic>[];
    return raw.map((item) => (item as num).toInt()).toList(growable: false);
  }

  static String _ruleName(String name) {
    final invalid = RegExp(r'[^a-zA-Z0-9-]+');
    return name.replaceAll(invalid, '-');
  }

  static _ParsedCharClasses _parseCharClasses(String classes) {
    if (classes.isEmpty) {
      return const _ParsedCharClasses(ranges: <_CharRange>[], negated: false);
    }

    var content = classes;
    if (content.startsWith('[')) {
      content = content.substring(1);
    }
    if (content.endsWith(']')) {
      content = content.substring(0, content.length - 1);
    }

    var negated = false;
    if (content.startsWith('^')) {
      negated = true;
      content = content.substring(1);
    }

    final ranges = <_CharRange>[];
    var i = 0;
    while (i < content.length) {
      final start = _parseCharClassChar(content, i);
      i += start.length;

      if (i + 1 < content.length && content.codeUnitAt(i) == 0x2D) {
        final end = _parseCharClassChar(content, i + 1);
        ranges.add(_CharRange(start: start.codePoint, end: end.codePoint));
        i += 1 + end.length;
      } else {
        ranges.add(_CharRange(start: start.codePoint, end: start.codePoint));
      }
    }

    return _ParsedCharClasses(ranges: ranges, negated: negated);
  }

  static _ParsedChar _parseCharClassChar(String content, int pos) {
    if (content.codeUnitAt(pos) == 0x5C && pos + 1 < content.length) {
      final next = content.codeUnitAt(pos + 1);
      switch (next) {
        case 0x78: // x
          final parsed = _parseHexEscape(content, pos + 2, 2);
          if (parsed.length > 0) {
            return _ParsedChar(parsed.value, 2 + parsed.length);
          }
          return _ParsedChar(0x78, 2);
        case 0x75: // u
          final parsed = _parseHexEscape(content, pos + 2, 4);
          if (parsed.length > 0) {
            return _ParsedChar(parsed.value, 2 + parsed.length);
          }
          return _ParsedChar(0x75, 2);
        case 0x55: // U
          final parsed = _parseHexEscape(content, pos + 2, 8);
          if (parsed.length > 0) {
            return _ParsedChar(parsed.value, 2 + parsed.length);
          }
          return _ParsedChar(0x55, 2);
        case 0x6E: // n
          return _ParsedChar(0x0A, 2);
        case 0x74: // t
          return _ParsedChar(0x09, 2);
        case 0x72: // r
          return _ParsedChar(0x0D, 2);
        case 0x5C: // \
          return _ParsedChar(0x5C, 2);
        case 0x5D: // ]
          return _ParsedChar(0x5D, 2);
        case 0x5B: // [
          return _ParsedChar(0x5B, 2);
        default:
          return _ParsedChar(next, 2);
      }
    }

    return _ParsedChar(content.codeUnitAt(pos), 1);
  }

  static _ParsedHex _parseHexEscape(String input, int pos, int count) {
    if (pos + count > input.length) {
      return const _ParsedHex(0, 0);
    }

    var value = 0;
    for (var i = 0; i < count; i++) {
      final code = input.codeUnitAt(pos + i);
      final digit = _hexDigit(code);
      if (digit < 0) {
        return const _ParsedHex(0, 0);
      }
      value = (value << 4) + digit;
    }
    return _ParsedHex(value, count);
  }

  static int _hexDigit(int codeUnit) {
    if (codeUnit >= 0x30 && codeUnit <= 0x39) {
      return codeUnit - 0x30;
    }
    if (codeUnit >= 0x41 && codeUnit <= 0x46) {
      return codeUnit - 0x41 + 10;
    }
    if (codeUnit >= 0x61 && codeUnit <= 0x66) {
      return codeUnit - 0x61 + 10;
    }
    return -1;
  }
}

/// Parser node handle used by [PegParserBuilder] composition operators.
class PegParser {
  PegParser._(this.id, this._builder);

  /// Parser node id within the owning arena.
  final int id;
  final PegParserBuilder _builder;

  /// Sequence composition.
  PegParser operator +(Object other) {
    final rhs = _builder._coerce(other);
    return _builder.sequence(<PegParser>[this, rhs]);
  }

  /// Sequence composition with chaining readability.
  PegParser operator <<(Object other) {
    final rhs = _builder._coerce(other);
    return _builder.sequence(<PegParser>[this, rhs]);
  }

  /// Choice composition.
  PegParser operator |(Object other) {
    final rhs = _builder._coerce(other);
    return _builder.choice(<PegParser>[this, rhs]);
  }
}

/// Base chat parser builder that provides common content/reasoning tags.
class ChatPegBuilder extends PegParserBuilder {
  /// AST tag name for reasoning blocks.
  static const String reasoningBlockTag = 'reasoning-block';

  /// AST tag name for extracted reasoning content.
  static const String reasoningTag = 'reasoning';

  /// AST tag name for extracted assistant content.
  static const String contentTag = 'content';

  /// Tags [parser] as a reasoning block.
  PegParser reasoningBlock(PegParser parser) => tag(reasoningBlockTag, parser);

  /// Tags [parser] as reasoning content.
  PegParser reasoning(PegParser parser) => tag(reasoningTag, parser);

  /// Tags [parser] as assistant content.
  PegParser content(PegParser parser) => tag(contentTag, parser);
}

/// Native-tool-call chat parser builder with tool-specific tags.
class ChatPegNativeBuilder extends ChatPegBuilder {
  /// AST tag name for full tool nodes.
  static const String toolTag = 'tool';

  /// AST tag name for tool open marker.
  static const String toolOpenTag = 'tool-open';

  /// AST tag name for tool close marker.
  static const String toolCloseTag = 'tool-close';

  /// AST tag name for tool id.
  static const String toolIdTag = 'tool-id';

  /// AST tag name for tool function name.
  static const String toolNameTag = 'tool-name';

  /// AST tag name for tool arguments payload.
  static const String toolArgsTag = 'tool-args';

  /// Tags [parser] as a tool wrapper.
  PegParser tool(PegParser parser) => tag(toolTag, parser);

  /// Tags [parser] as atomic tool-open marker.
  PegParser toolOpen(PegParser parser) => atomic(tag(toolOpenTag, parser));

  /// Tags [parser] as atomic tool-close marker.
  PegParser toolClose(PegParser parser) => atomic(tag(toolCloseTag, parser));

  /// Tags [parser] as atomic tool id.
  PegParser toolId(PegParser parser) => atomic(tag(toolIdTag, parser));

  /// Tags [parser] as atomic tool name.
  PegParser toolName(PegParser parser) => atomic(tag(toolNameTag, parser));

  /// Tags [parser] as tool arguments.
  PegParser toolArgs(PegParser parser) => tag(toolArgsTag, parser);
}

/// Constructed-tool-call parser builder with parameter-level argument tags.
///
/// This mirrors llama.cpp's `common_chat_peg_constructed_builder` AST tags.
class ChatPegConstructedBuilder extends ChatPegNativeBuilder {
  /// AST tag name for tool argument open marker.
  static const String toolArgOpenTag = 'tool-arg-open';

  /// AST tag name for tool argument close marker.
  static const String toolArgCloseTag = 'tool-arg-close';

  /// AST tag name for tool argument name.
  static const String toolArgNameTag = 'tool-arg-name';

  /// AST tag name for string tool argument value.
  static const String toolArgStringValueTag = 'tool-arg-string-value';

  /// AST tag name for JSON tool argument value.
  static const String toolArgJsonValueTag = 'tool-arg-json-value';

  /// Tags [parser] as atomic tool argument opening marker.
  PegParser toolArgOpen(PegParser parser) =>
      atomic(tag(toolArgOpenTag, parser));

  /// Tags [parser] as atomic tool argument closing marker.
  PegParser toolArgClose(PegParser parser) =>
      atomic(tag(toolArgCloseTag, parser));

  /// Tags [parser] as atomic tool argument name.
  PegParser toolArgName(PegParser parser) =>
      atomic(tag(toolArgNameTag, parser));

  /// Tags [parser] as tool argument string value.
  PegParser toolArgStringValue(PegParser parser) =>
      tag(toolArgStringValueTag, parser);

  /// Tags [parser] as tool argument JSON value.
  PegParser toolArgJsonValue(PegParser parser) =>
      tag(toolArgJsonValueTag, parser);
}

class _ParsedHex {
  const _ParsedHex(this.value, this.length);

  final int value;
  final int length;
}

class _ParsedChar {
  const _ParsedChar(this.codePoint, this.length);

  final int codePoint;
  final int length;
}

class _CharRange {
  const _CharRange({required this.start, required this.end});

  final int start;
  final int end;
}

class _ParsedCharClasses {
  const _ParsedCharClasses({required this.ranges, required this.negated});

  final List<_CharRange> ranges;
  final bool negated;
}
