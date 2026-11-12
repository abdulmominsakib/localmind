import 'dart:convert';
import 'dart:math';

/// A GBNF grammar rule with its content and dependencies.
class _BuiltinRule {
  final String content;
  final List<String> deps;
  const _BuiltinRule(this.content, [this.deps = const []]);
}

/// Whitespace rule matching llama.cpp's SPACE_RULE.
const _spaceRule = '| " " | "\\n"{1,2} [ \\t]{0,20}';

/// Primitive GBNF rules matching llama.cpp's PRIMITIVE_RULES.
const _primitiveRules = <String, _BuiltinRule>{
  'boolean': _BuiltinRule('("true" | "false") space', []),
  'decimal-part': _BuiltinRule('[0-9]{1,16}', []),
  'integral-part': _BuiltinRule('[0] | [1-9] [0-9]{0,15}', []),
  'number': _BuiltinRule(
    '("-"? integral-part) ("." decimal-part)? ([eE] [-+]? integral-part)? space',
    ['integral-part', 'decimal-part'],
  ),
  'integer': _BuiltinRule('("-"? integral-part) space', ['integral-part']),
  'value': _BuiltinRule('object | array | string | number | boolean | null', [
    'object',
    'array',
    'string',
    'number',
    'boolean',
    'null',
  ]),
  'object': _BuiltinRule(
    '"{" space ( string ":" space value ("," space string ":" space value)* )? "}" space',
    ['string', 'value'],
  ),
  'array': _BuiltinRule('"[" space ( value ("," space value)* )? "]" space', [
    'value',
  ]),
  'char': _BuiltinRule(
    r'[^"\\\x7F\x00-\x1F] | [\\] (["\\bfnrt] | "u" [0-9a-fA-F]{4})',
    [],
  ),
  'string': _BuiltinRule(r'"\"" char* "\"" space', ['char']),
  // A raw quote is text when the next non-space character cannot follow a
  // closing quote, or when `"` or `}"` follows it. Closers before other text
  // still end the string, so a model that miscounts closers is corrected
  // rather than left inside the string.
  'inner-quote-string': _BuiltinRule(
    r'"\"" ( char | inner-quote | inner-quote-run+ inner-quote )* inner-quote-run* "\"" space',
    ['char', 'inner-quote', 'inner-quote-run'],
  ),
  'inner-quote': _BuiltinRule(
    r'"\"" " "* ( [^"\\\x7F\x00-\x1F ,}\]] | [\\] (["\\bfnrt] | "u" [0-9a-fA-F]{4}) )',
    [],
  ),
  'inner-quote-run': _BuiltinRule(r'"\"" "}"?', []),
  'null': _BuiltinRule('"null" space', []),
};

// llama.cpp v0.7.0 STRING_FORMAT_RULES. Calendar validity is deliberately
// limited to the same lexical ranges as the upstream grammar.
const _formatRules = <String, _BuiltinRule>{
  'uuid': _BuiltinRule(
    r'"\"" [0-9a-fA-F]{8} "-" [0-9a-fA-F]{4} "-" [0-9a-fA-F]{4} "-" [0-9a-fA-F]{4} "-" [0-9a-fA-F]{12} "\"" space',
  ),
  'date': _BuiltinRule(
    '[0-9]{4} "-" ( "0" [1-9] | "1" [0-2] ) "-" ( "0" [1-9] | [1-2] [0-9] | "3" [0-1] )',
  ),
  'time': _BuiltinRule(
    '([01] [0-9] | "2" [0-3]) ":" [0-5] [0-9] ":" [0-5] [0-9] ( "." [0-9]{3} )? ( "Z" | ( "+" | "-" ) ( [01] [0-9] | "2" [0-3] ) ":" [0-5] [0-9] )',
  ),
  'date-time': _BuiltinRule('date "T" time', ['date', 'time']),
  'date-string': _BuiltinRule(r'"\"" date "\"" space', ['date']),
  'time-string': _BuiltinRule(r'"\"" time "\"" space', ['time']),
  'date-time-string': _BuiltinRule(r'"\"" date-time "\"" space', ['date-time']),
};
const _datePattern = r'[0-9]{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[1-2][0-9]|3[0-1])';
const _timePattern =
    r'(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]{3})?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])';

/// Reserved rule names that need a suffix to avoid collision.
final _reservedNames = <String>{
  'root',
  ..._primitiveRules.keys,
  ..._formatRules.keys,
};

/// Largest alternative count or repetition bound kept in an inline group.
///
/// llama.cpp rejects a repeated group once the symbols created inside it,
/// including first references to named rules, multiplied by the repetition
/// count reach `MAX_REPETITION_THRESHOLD` (2000). Larger generated groups move
/// into named rules, each of which counts as one symbol.
const _maxInlineGroupSize = 256;

/// Longest optional-property list that keeps llama.cpp's own `-rest` rule chain.
const _maxOptionalRestChain = 128;

/// Optional properties in one `-tail` rule of a longer list.
const _optionalBlockSize = 32;

/// Most characters the declared-key exclusion rules may add to one grammar.
///
/// Open objects beyond this budget use the plain `string` key rule, so the
/// grammar still loads and final validation checks declared properties.
const _maxKeyTrieGrammarLength = 64 * 1024;

/// Escapes for GBNF literal strings.
const _literalEscapes = <String, String>{
  '\r': '\\r',
  '\n': '\\n',
  '"': '\\"',
  '\\': '\\\\',
};

/// Converts JSON Schema to GBNF grammar strings.
///
/// Port of llama.cpp's `SchemaConverter` (json-schema-to-grammar.mjs).
class JsonSchemaConverter {
  /// Creates a converter; see [convert] for [innerQuoteStrings].
  JsonSchemaConverter({this.innerQuoteStrings = false});

  /// Whether unconstrained `string` schemas accept raw inner quotes.
  final bool innerQuoteStrings;

  final Map<String, String> _rules = {'space': _spaceRule};
  final Map<String, dynamic> _refs = {};
  final Set<String> _refsBeingResolved = {};
  int _keyTrieGrammarLength = 0;

  /// Rule name of each declared-key escape rule, by rule text.
  final Map<String, String> _escapeRuleNames = {};

  /// Whether a pattern can be enforced by the compiled regex subset.
  static bool supportsPattern(String pattern) =>
      _PatternGrammarBuilder((name, rule) => name, 'pattern').build(pattern) !=
      null;

  /// Integer endpoints with v0.7.0 rounding and inclusive-key precedence.
  static (int?, int?) integerBounds(Map<String, dynamic> schema) {
    final minimum = schema['minimum'] as num?;
    final maximum = schema['maximum'] as num?;
    final exclusiveMinimum = schema['exclusiveMinimum'] as num?;
    final exclusiveMaximum = schema['exclusiveMaximum'] as num?;
    return (
      minimum?.ceil() ??
          (exclusiveMinimum == null ? null : exclusiveMinimum.floor() + 1),
      maximum?.floor() ??
          (exclusiveMaximum == null ? null : exclusiveMaximum.ceil() - 1),
    );
  }

  /// Whether v0.7.0's one-sided suffix builder enforces these endpoints.
  static bool supportsIntegerBounds(Map<String, dynamic> schema) {
    final (min, max) = integerBounds(schema);
    final lower = max == null && min != null && min > 0
        ? min
        : min == null && max != null && max < 0
        ? -max
        : null;
    if (lower == null) return true;
    final digits = lower.toString();
    // Recursive integer suffixes lose leading zeros. At the 16-digit limit,
    // larger prefix digits also emit inverted repetition bounds.
    if (digits.substring(0, digits.length - 1).contains('0')) return false;
    return digits.length < 16 || RegExp(r'^1{15}[0-9]$').hasMatch(digits);
  }

  /// Canonical literal identity used by upstream allOf enum intersection.
  static String literalKey(Object? value) => jsonEncode(value);

  /// Checks the same lexical format subset as the generated grammar.
  static bool matchesFormat(String format, String value) {
    final pattern = switch (format) {
      'uuid' || 'uuid1' || 'uuid2' || 'uuid3' || 'uuid4' || 'uuid5' =>
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
      'date' => _datePattern,
      'time' => _timePattern,
      'date-time' => '${_datePattern}T$_timePattern',
      _ => throw StateError('Unsupported format $format'),
    };
    return RegExp(pattern).matchAsPrefix(value)?.end == value.length;
  }

  /// Resolves a local JSON pointer through object keys and array indexes.
  static Object? resolvePointer(Map<String, dynamic> root, String ref) {
    if (!ref.startsWith('#/')) return null;
    Object? target = root;
    for (final raw in ref.substring(2).split('/')) {
      final segment = raw.replaceAll('~1', '/').replaceAll('~0', '~');
      final index = int.tryParse(segment);
      if (target is Map) {
        target = target[segment];
      } else if (target is List &&
          index != null &&
          index >= 0 &&
          index < target.length) {
        target = target[index];
      } else {
        return null;
      }
    }
    return target;
  }

  /// Access accumulated rules (for multi-tool grammar assembly).
  Map<String, String> get rules => _rules;

  /// Convert a JSON Schema to a GBNF grammar string.
  ///
  /// This is the main entry point. Pass the full JSON Schema as a map.
  ///
  /// With [innerQuoteStrings], values of unconstrained `string` schemas also
  /// accept a raw `"` that no valid JSON continuation could follow, for models
  /// that copy quotes into JSON strings unescaped. Object keys and constrained
  /// strings keep the strict rule.
  static String convert(
    Map<String, dynamic> schema, {
    bool innerQuoteStrings = false,
  }) {
    final converter = JsonSchemaConverter(innerQuoteStrings: innerQuoteStrings);
    converter.resolveRefs(schema, schema);
    converter.visit(schema, 'root');
    return converter.formatGrammar();
  }

  /// Format all accumulated rules into a GBNF grammar string.
  String formatGrammar() {
    final buf = StringBuffer();
    final sortedEntries = _rules.entries.toList()
      ..sort((a, b) {
        // Always put 'root' first.
        if (a.key == 'root') return -1;
        if (b.key == 'root') return 1;
        return a.key.compareTo(b.key);
      });
    for (final entry in sortedEntries) {
      buf.writeln('${entry.key} ::= ${entry.value}');
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Rule management
  // ---------------------------------------------------------------------------

  String _addRule(String name, String rule) {
    final escName = name.replaceAll(RegExp(r'[^\dA-Za-z-]+'), '-');
    var key = escName;

    if (_rules.containsKey(escName)) {
      if (_rules[escName] == rule) return key;
      var i = 0;
      while (_rules.containsKey('$escName$i') && _rules['$escName$i'] != rule) {
        i++;
      }
      key = '$escName$i';
    }

    _rules[key] = rule;
    return key;
  }

  String _addPrimitive(String name, _BuiltinRule rule) {
    final n = _addRule(name, rule.content);
    for (final dep in rule.deps) {
      final depRule = _primitiveRules[dep] ?? _formatRules[dep];
      if (depRule == null) throw StateError('Rule $dep not known');
      if (!_rules.containsKey(dep)) {
        _addPrimitive(dep, depRule);
      }
    }
    return n;
  }

  // ---------------------------------------------------------------------------
  // Literal formatting
  // ---------------------------------------------------------------------------

  String _formatLiteral(String literal) {
    final escaped = literal.replaceAllMapped(
      RegExp(r'[\n\r"\\]'),
      (m) => _literalEscapes[m[0]!] ?? m[0]!,
    );
    return '"$escaped"';
  }

  // ---------------------------------------------------------------------------
  // Ref resolution
  // ---------------------------------------------------------------------------

  /// Resolves `$ref` references within the [node] against the [rootSchema].
  void resolveRefs(dynamic node, dynamic rootSchema) {
    if (node is List) {
      for (final item in node) {
        resolveRefs(item, rootSchema);
      }
    } else if (node is Map<String, dynamic>) {
      final ref = node[r'$ref'] as String?;
      if (ref != null && !_refs.containsKey(ref) && ref.startsWith('#/')) {
        // Local ref
        final target = resolvePointer(rootSchema as Map<String, dynamic>, ref);
        if (target == null) {
          throw StateError('Error resolving ref $ref: target not found');
        }
        _refs[ref] = target;
        // Resolve refs nested inside the target as well.
        resolveRefs(target, rootSchema);
      }
      // Only schema-bearing positions contain references. Property names and
      // annotation payloads such as examples are ordinary JSON data.
      for (final key in [
        'properties',
        'patternProperties',
        'dependentSchemas',
      ]) {
        final schemas = node[key];
        if (schemas is Map) {
          for (final schema in schemas.values) {
            resolveRefs(schema, rootSchema);
          }
        }
      }
      for (final key in [
        'items',
        'prefixItems',
        'additionalProperties',
        'additionalItems',
        'contains',
        'not',
        'if',
        'then',
        'else',
        'anyOf',
        'oneOf',
        'allOf',
        'unevaluatedProperties',
        'unevaluatedItems',
        'propertyNames',
      ]) {
        resolveRefs(node[key], rootSchema);
      }
    }
  }

  String _resolveRef(String ref) {
    var refFragment = ref.split('#').last;
    var refName =
        'ref${refFragment.replaceAll(RegExp(r'[^a-zA-Z0-9-]+'), '-')}';
    // Fail loudly for unresolvable refs based on the ref itself, not the
    // generated rule name. `resolveRefs` registers every local "#/..." ref in
    // _refs up front, so a ref that is absent there (and not mid-resolution for
    // cycles) is external/unresolvable. Checking the ref rather than the
    // rule-name cache keeps this order-independent even when an external ref
    // would collide with an already-emitted local rule name.
    if (!_refs.containsKey(ref) && !_refsBeingResolved.contains(ref)) {
      throw StateError(
        'Cannot resolve \$ref "$ref": only local "#/..." references within '
        'the same schema are supported.',
      );
    }
    if (!_rules.containsKey(refName) && !_refsBeingResolved.contains(ref)) {
      _refsBeingResolved.add(ref);
      final resolved = _refs[ref];
      if (resolved != null) {
        refName = visit(resolved as Map<String, dynamic>, refName);
      }
      _refsBeingResolved.remove(ref);
    }
    return refName;
  }

  // ---------------------------------------------------------------------------
  // Schema visitor (main dispatch)
  // ---------------------------------------------------------------------------

  /// Visit a JSON Schema node and generate GBNF rules for it.
  String visit(Map<String, dynamic> schema, String name) {
    var schemaType = schema['type'];
    final ruleName = _reservedNames.contains(name) && name != 'root'
        ? '$name-'
        : (name.isEmpty ? 'root' : name);

    // $ref
    final ref = schema[r'$ref'] as String?;
    if (ref != null) {
      return _addRule(ruleName, _resolveRef(ref));
    }

    // oneOf / anyOf
    if (schema.containsKey('oneOf') || schema.containsKey('anyOf')) {
      final alts = (schema['oneOf'] ?? schema['anyOf']) as List;
      return _addRule(ruleName, _generateUnionRule(name, alts));
    }

    // Array of types
    if (schemaType is List) {
      final typeSchemas = schemaType
          .map((t) => <String, dynamic>{...schema, 'type': t})
          .toList();
      return _addRule(ruleName, _generateUnionRule(name, typeSchemas));
    }

    // const
    if (schema.containsKey('const')) {
      return _addRule(
        ruleName,
        '${_formatLiteral(jsonEncode(schema['const']))} space',
      );
    }

    // enum
    if (schema.containsKey('enum')) {
      final values = (schema['enum'] as List)
          .map((v) => _formatLiteral(jsonEncode(v)))
          .join(' | ');
      return _addRule(ruleName, '($values) space');
    }

    // object with properties
    if ((schemaType == null || schemaType == 'object') &&
        (schema.containsKey('properties') ||
            (schema.containsKey('additionalProperties') &&
                schema['additionalProperties'] != true))) {
      final required = Set<String>.from(
        (schema['required'] as List?)?.cast<String>() ?? [],
      );
      final properties =
          (schema['properties'] as Map<String, dynamic>?)?.entries.toList() ??
          [];
      return _addRule(
        ruleName,
        _buildObjectRule(
          properties,
          required,
          name,
          schema['additionalProperties'],
        ),
      );
    }

    // allOf
    if ((schemaType == null ||
            schemaType == 'object' ||
            schemaType == 'string') &&
        schema.containsKey('allOf')) {
      final required = <String>{};
      final properties = <MapEntry<String, dynamic>>[];
      final enumCounts = <String, int>{};
      final components = schema['allOf'] as List;
      void addComponent(Map<String, dynamic> component, bool isRequired) {
        final seen = <String>{};
        while (component[r'$ref'] is String) {
          final ref = component[r'$ref'] as String;
          if (!seen.add(ref)) throw StateError('Cyclic allOf component $ref');
          component = _refs[ref] as Map<String, dynamic>;
        }
        if (component['properties'] is Map<String, dynamic>) {
          final props = component['properties'] as Map<String, dynamic>;
          properties.addAll(props.entries);
          if (isRequired) required.addAll(props.keys);
        } else if (component['enum'] is List) {
          for (final literal
              in (component['enum'] as List)
                  .map((value) => _formatLiteral(literalKey(value)))
                  .toSet()) {
            enumCounts.update(literal, (count) => count + 1, ifAbsent: () => 1);
          }
        }
      }

      for (final component in components.cast<Map<String, dynamic>>()) {
        addComponent(component, true);
      }
      final intersection =
          enumCounts.keys
              .where((key) => enumCounts[key] == components.length)
              .toList()
            ..sort();
      if (intersection.isNotEmpty) {
        return _addRule(ruleName, '(${intersection.join(' | ')}) space');
      }
      return _addRule(
        ruleName,
        _buildObjectRule(properties, required, name, null),
      );
    }

    // array with items
    if ((schemaType == null || schemaType == 'array') &&
        (schema.containsKey('items') ||
            schema.containsKey('prefixItems') ||
            schema.containsKey('minItems') ||
            schema.containsKey('maxItems'))) {
      final items = schema['items'] ?? schema['prefixItems'];
      if (items is List) {
        // Tuple
        final tupleRules = items
            .asMap()
            .entries
            .map(
              (e) => visit(
                e.value as Map<String, dynamic>,
                '${name.isNotEmpty ? '$name-' : ''}tuple-${e.key}',
              ),
            )
            .join(' "," space ');
        return _addRule(ruleName, '"[" space $tupleRules "]" space');
      } else {
        final itemName = '${name.isNotEmpty ? '$name-' : ''}item';
        final itemRuleName = items == null
            ? _addPrimitive(itemName, _primitiveRules['value']!)
            : visit(items as Map<String, dynamic>, itemName);
        final minItems = (schema['minItems'] as int?) ?? 0;
        final maxItems = schema['maxItems'] as int?;
        return _addRule(
          ruleName,
          '"[" space ${_itemsRepetition(itemRuleName, minItems, maxItems, name)} "]" space',
        );
      }
    }

    if ((schemaType == null || schemaType == 'string') &&
        schema['pattern'] is String) {
      final patternRule = _visitPattern(schema['pattern'] as String, ruleName);
      if (patternRule != null) return patternRule;
      schemaType = 'string';
    }

    final format = schema['format'];
    if ((schemaType == null || schemaType == 'string') &&
        format is String &&
        {
          'uuid',
          'uuid1',
          'uuid2',
          'uuid3',
          'uuid4',
          'uuid5',
          'date',
          'time',
          'date-time',
        }.contains(format)) {
      final primitive = format.startsWith('uuid') ? 'uuid' : '$format-string';
      return _addRule(
        ruleName,
        _addPrimitive(primitive, _formatRules[primitive]!),
      );
    }
    if (schemaType == 'integer' &&
        [
          'minimum',
          'maximum',
          'exclusiveMinimum',
          'exclusiveMaximum',
        ].any(schema.containsKey)) {
      final (min, max) = integerBounds(schema);
      return _addRule(ruleName, '(${_buildMinMaxInt(min, max)}) space');
    }

    // string with minLength/maxLength
    if (schemaType == 'string' &&
        (schema.containsKey('minLength') || schema.containsKey('maxLength'))) {
      final charRuleName = _addPrimitive('char', _primitiveRules['char']!);
      final minLen = (schema['minLength'] as int?) ?? 0;
      final maxLen = schema['maxLength'] as int?;
      return _addRule(
        ruleName,
        r'"\"" ' +
            _buildRepetition(charRuleName, minLen, maxLen) +
            r' "\"" space',
      );
    }

    // plain object or empty schema
    if (schemaType == 'object' || schema.isEmpty) {
      return _addRule(
        ruleName,
        _addPrimitive('object', _primitiveRules['object']!),
      );
    }

    if (schemaType == 'string' && innerQuoteStrings) {
      return _addRule(
        ruleName,
        _addPrimitive(
          'inner-quote-string',
          _primitiveRules['inner-quote-string']!,
        ),
      );
    }

    // Primitive types
    if (schemaType is String && _primitiveRules.containsKey(schemaType)) {
      return _addPrimitive(
        ruleName == 'root' ? 'root' : schemaType,
        _primitiveRules[schemaType]!,
      );
    }

    // Untyped annotation-only schemas impose no restriction on the value.
    if (schemaType == null) {
      return _addRule(
        ruleName,
        _addPrimitive('value', _primitiveRules['value']!),
      );
    }

    throw StateError('Unrecognized schema: ${jsonEncode(schema)}');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _itemsRepetition(
    String itemRule,
    int minItems,
    int? maxItems,
    String name,
  ) {
    final bound = maxItems ?? minItems;
    if (bound <= _maxInlineGroupSize || bound < minItems) {
      return _buildRepetition(
        itemRule,
        minItems,
        maxItems,
        separatorRule: '"," space',
      );
    }
    final prefix = '${name.isNotEmpty ? '$name-' : ''}item';
    final tail = _addRule('$prefix-tail', '"," space $itemRule');
    final items =
        '$itemRule ${_buildRepetition(tail, minItems > 0 ? minItems - 1 : 0, maxItems == null ? null : maxItems - 1)}';
    return minItems > 0 ? items : '${_addRule('$prefix-list', items)}?';
  }

  String? _visitPattern(String pattern, String ruleName) {
    final snapshot = Map<String, String>.from(_rules);
    final expr = _PatternGrammarBuilder(_addRule, ruleName).build(pattern);
    if (expr == null) {
      _rules
        ..clear()
        ..addAll(snapshot);
      return null;
    }
    return _addRule(ruleName, '"\\"" ($expr) "\\"" space');
  }

  String _generateUnionRule(String name, List alts) {
    return alts
        .asMap()
        .entries
        .map(
          (e) => visit(
            e.value as Map<String, dynamic>,
            '${name.isNotEmpty ? '$name-' : 'alternative-'}${e.key}',
          ),
        )
        .join(' | ');
  }

  /// Returns the name of a JSON string rule (with trailing space) that
  /// matches none of [strings] in their canonical `jsonEncode` wire form, or
  /// `null` when its rules would exceed this grammar's remaining
  /// [_maxKeyTrieGrammarLength].
  ///
  /// Follows llama.cpp's `_not_strings` trie, with two corrections: a proper
  /// prefix of a declared key stays available, and the divergent character
  /// excludes `"`, `\` and control characters so the key remains valid JSON.
  /// Where a declared key continues with an escape sequence, other escapes
  /// are not offered at that position. Elsewhere, a `\u` escape of a
  /// character that a declared key continues with is not offered, so an
  /// escaped spelling (such as `\u0063ity` for `city`) cannot bypass the
  /// exclusion. Every key not declared still matches in canonical spelling.
  ///
  /// A subtree whose inline groups would create more than
  /// [_maxInlineGroupSize] llama.cpp symbols becomes a named rule, so no
  /// repeated group reaches `MAX_REPETITION_THRESHOLD`.
  String? _notStrings(List<String> strings, String name) {
    final trie = _KeyTrieNode();
    for (final string in strings) {
      final wire = jsonEncode(string);
      var node = trie;
      for (final token in _wireTokens(wire.substring(1, wire.length - 1))) {
        node = node.children.putIfAbsent(token, _KeyTrieNode.new);
      }
      node.isEnd = true;
    }

    String build(
      String Function(String name, String rule) emit,
      String char,
      Map<String, String> escapeRules,
    ) {
      var index = 0;
      var newEscapeRules = 0;

      // Every key trie in the grammar shares one short-named rule per set.
      String escapeExcluding(List<int> runes) {
        final units = {
          for (final rune in runes)
            rune > 0xFFFF ? 0xD800 + ((rune - 0x10000) >> 10) : rune,
        }.toList()..sort();
        final rule =
            '[\\\\] (["\\\\bfnrt] | "u" (${_hexExcluding(units, 0)!}))';
        return escapeRules[rule] ??= emit(
          _escapeRuleNames[rule] ??
              'esc-${_escapeRuleNames.length + newEscapeRules++}',
          rule,
        );
      }

      // Each record holds GBNF text and an upper bound on the symbols
      // llama.cpp creates while parsing it inside a group: one per group, per
      // repetition operator and per first reference to a named rule.
      (String, int) group((String, int) body) {
        final (text, symbols) = body;
        if (symbols <= _maxInlineGroupSize) return ('($text)', symbols + 1);
        return (emit('$name-${index++}', text), 1);
      }

      (String, int) visitNode(_KeyTrieNode node) {
        final alternatives = <String>[];
        final plain = <int>[];
        var symbols = 0;
        var escapedChild = false;
        final tokens = node.children.keys.toList()..sort();
        for (final token in tokens) {
          final child = node.children[token]!;
          final String head;
          if (token.startsWith(r'\')) {
            escapedChild = true;
            head = _formatLiteral(token);
          } else {
            plain.add(token.runes.single);
            head = '[${_classChar(token.runes.single)}]';
          }
          if (child.children.isEmpty) {
            alternatives.add('$head $char+');
            symbols += 2;
          } else {
            final (text, childSymbols) = group(visitNode(child));
            alternatives.add('$head $text${child.isEnd ? '' : '?'}');
            symbols += childSymbols + 1;
          }
        }
        final other = StringBuffer(r'[^"\\\x7F\x00-\x1F');
        for (final rune in plain) {
          other.write(_classChar(rune));
        }
        other.write(']');
        final divergent = escapedChild
            ? other.toString()
            : '($other | ${escapeExcluding(plain)})';
        alternatives.add('$divergent $char*');
        symbols += escapedChild ? 1 : 3;
        return (alternatives.join(' | '), symbols);
      }

      final (root, _) = group(visitNode(trie));
      return emit(name, '"\\"" $root${trie.isEnd ? '' : '?'} "\\"" space');
    }

    var length = 0;
    build(
      (name, rule) {
        // Escape rules shared with an earlier key trie are already in the
        // grammar, so `_addRule` will not add them again.
        if (_rules[name] != rule) length += name.length + rule.length;
        return name;
      },
      'char',
      {},
    );
    if (_keyTrieGrammarLength + length > _maxKeyTrieGrammarLength) return null;
    _keyTrieGrammarLength += length;
    final escapeRules = <String, String>{};
    final keyRule = build(
      _addRule,
      _addPrimitive('char', _primitiveRules['char']!),
      escapeRules,
    );
    _escapeRuleNames.addAll(escapeRules);
    return keyRule;
  }

  /// Matches four hex digits, in either case, spelling none of the sorted
  /// code [units], which share their first [depth] digits.
  static String? _hexExcluding(List<int> units, int depth) {
    final shift = 4 * (3 - depth);
    final byDigit = <int, List<int>>{};
    for (final unit in units) {
      (byDigit[(unit >> shift) & 0xF] ??= []).add(unit);
    }
    final alternatives = <String>[
      if (depth < 3)
        for (final MapEntry(key: digit, value: rest) in byDigit.entries)
          if (_hexExcluding(rest, depth + 1) case final tail?)
            '${_hexClass([digit])} ($tail)',
    ];
    final other = [
      for (var digit = 0; digit < 16; digit++)
        if (!byDigit.containsKey(digit)) digit,
    ];
    if (other.isNotEmpty) {
      final rest = switch (3 - depth) {
        0 => '',
        1 => ' [0-9a-fA-F]',
        final count => ' [0-9a-fA-F]{$count}',
      };
      alternatives.add('${_hexClass(other)}$rest');
    }
    return alternatives.isEmpty ? null : alternatives.join(' | ');
  }

  String _buildObjectRule(
    List<MapEntry<String, dynamic>> properties,
    Set<String> required,
    String name,
    dynamic additionalProperties,
  ) {
    final propKvRuleNames = <String, String>{};
    final sortedPropNames = properties.map((e) => e.key).toList();

    for (final prop in properties) {
      final propName = prop.key;
      final propSchema = prop.value as Map<String, dynamic>;
      final propRuleName = visit(
        propSchema,
        '${name.isNotEmpty ? '$name-' : ''}$propName',
      );
      propKvRuleNames[propName] = _addRule(
        '${name.isNotEmpty ? '$name-' : ''}$propName-kv',
        '${_formatLiteral(jsonEncode(propName))} space ":" space $propRuleName',
      );
    }

    final subName = '${name.isNotEmpty ? '$name-' : ''}additional';
    String? additionalValueRule;
    String additionalValue() =>
        additionalValueRule ??= additionalProperties is Map<String, dynamic>
        ? visit(additionalProperties, '$subName-value')
        : _addPrimitive('value', _primitiveRules['value']!);

    // llama.cpp drops required names that `properties` does not declare, so
    // its grammar could omit a key that tool validation requires.
    final undeclaredRequired = required
        .where((k) => !propKvRuleNames.containsKey(k))
        .toList();
    for (final propName in undeclaredRequired) {
      propKvRuleNames[propName] = _addRule(
        '${name.isNotEmpty ? '$name-' : ''}$propName-kv',
        '${_formatLiteral(jsonEncode(propName))} space ":" space ${additionalValue()}',
      );
    }
    final keyNames = [...sortedPropNames, ...undeclaredRequired];

    final requiredProps = keyNames.where((k) => required.contains(k)).toList();
    final optionalProps = sortedPropNames
        .where((k) => !required.contains(k))
        .toList();

    // Keep the extra-property slot separate from every required or declared
    // wire key.
    String? additionalKey;
    // Handle additionalProperties
    if (additionalProperties != null && additionalProperties != false) {
      final valueRule = additionalValue();
      final keyRule = keyNames.isEmpty
          ? null
          : _notStrings(keyNames, '$subName-k');

      var extraKey = '*';
      while (propKvRuleNames.containsKey(extraKey)) {
        extraKey = '$extraKey*';
      }
      additionalKey = extraKey;
      propKvRuleNames[extraKey] = _addRule(
        '$subName-kv',
        '${keyRule ?? _addPrimitive('string', _primitiveRules['string']!)} ":" space $valueRule',
      );
      optionalProps.add(extraKey);
    }

    var rule = '"{" space ';
    rule += requiredProps.map((k) => propKvRuleNames[k]).join(' "," space ');

    if (optionalProps.isNotEmpty) {
      rule += ' (';
      if (requiredProps.isNotEmpty) {
        rule += ' "," space ( ';
      }

      final rulePrefix = name.isNotEmpty ? '$name-' : '';
      String optionalRef(String k) =>
          '( "," space ${propKvRuleNames[k]} )${k == additionalKey ? '*' : '?'}';

      // The `-rest` rules of a long list would each lead into the next, and
      // llama.cpp from v0.8.0 refuses rules chained over 256 levels deep. A
      // `-tail` rule covers one block of properties, which bounds the depth
      // by a block plus the number of blocks.
      String tailRule(int from) {
        final end = min(from + _optionalBlockSize, optionalProps.length);
        final refs = [
          for (final k in optionalProps.sublist(from, end)) optionalRef(k),
          if (end < optionalProps.length) tailRule(end),
        ];
        return _addRule(
          '$rulePrefix${optionalProps[from]}-tail',
          refs.join(' '),
        );
      }

      String getRecursiveRefs(List<String> ks, bool firstIsOptional) {
        final k = ks.first;
        final rest = ks.sublist(1);
        final kvRuleName = propKvRuleNames[k]!;
        String res;
        if (firstIsOptional) {
          res = optionalRef(k);
        } else {
          res =
              '$kvRuleName${k == additionalKey ? ' ( "," space $kvRuleName )*' : ''}';
        }
        if (rest.isNotEmpty) {
          final restStart = optionalProps.length - rest.length;
          res +=
              optionalProps.length > _maxOptionalRestChain &&
                  restStart % _optionalBlockSize == 0
              ? ' ${tailRule(restStart)}'
              : ' ${_addRule('$rulePrefix$k-rest', getRecursiveRefs(rest, true))}';
        }
        return res;
      }

      final optAlternatives = <String>[];
      for (var i = 0; i < optionalProps.length; i++) {
        optAlternatives.add(getRecursiveRefs(optionalProps.sublist(i), false));
      }
      final alternatives = optAlternatives.join(' | ');
      rule += optAlternatives.length > _maxInlineGroupSize
          ? _addRule('${name.isNotEmpty ? '$name-' : ''}optional', alternatives)
          : alternatives;

      if (requiredProps.isNotEmpty) {
        rule += ' )';
      }
      rule += ' )?';
    }

    rule += ' "}" space';
    return rule;
  }
}

class _KeyTrieNode {
  final Map<String, _KeyTrieNode> children = {};
  bool isEnd = false;
}

/// Splits JSON string contents into characters and whole escape sequences.
List<String> _wireTokens(String wire) {
  final tokens = <String>[];
  final runes = wire.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    if (runes[i] == 0x5C) {
      final length = runes[i + 1] == 0x75 ? 6 : 2;
      tokens.add(String.fromCharCodes(runes.sublist(i, i + length)));
      i += length - 1;
    } else {
      tokens.add(String.fromCharCode(runes[i]));
    }
  }
  return tokens;
}

/// Returns a GBNF class matching the ascending hex [digits] in either case.
String _hexClass(List<int> digits) {
  String runs(List<int> values, String Function(int) spell) {
    final out = StringBuffer();
    for (var start = 0; start < values.length;) {
      var end = start;
      while (end + 1 < values.length && values[end + 1] == values[end] + 1) {
        end++;
      }
      if (end - start >= 2) {
        out.write('${spell(values[start])}-${spell(values[end])}');
      } else {
        for (var i = start; i <= end; i++) {
          out.write(spell(values[i]));
        }
      }
      start = end + 1;
    }
    return out.toString();
  }

  final decimal = [
    for (final digit in digits)
      if (digit < 10) digit,
  ];
  final letters = [
    for (final digit in digits)
      if (digit >= 10) digit,
  ];
  String letter(int digit) => digit.toRadixString(16);
  return '[${runs(decimal, (digit) => '$digit')}${runs(letters, letter)}'
      '${runs(letters, (digit) => letter(digit).toUpperCase())}]';
}

/// Encodes [rune] for a GBNF character class.
String _classChar(int rune) {
  final isAsciiAlphaNumeric =
      (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A);
  if (isAsciiAlphaNumeric) return String.fromCharCode(rune);
  final hex = rune.toRadixString(16).toUpperCase();
  if (rune <= 0xFF) return '\\x${hex.padLeft(2, '0')}';
  if (rune <= 0xFFFF) return '\\u${hex.padLeft(4, '0')}';
  return '\\U${hex.padLeft(8, '0')}';
}

/// Compiles the supported subset of JSON Schema `pattern` regexes into a GBNF
/// expression.
///
/// The subset is anchored `^...$` patterns whose body is a single sequence of
/// literal characters, positive character classes of plain characters and
/// ranges, `(...)` and `(?:...)` groups, and `*`, `+`, `?` or `{n}` / `{m,}` /
/// `{m,n}` repetition with counts up to [_maxRepetitionCount]. Alternation is
/// supported inside a group; a top-level `|` is not, because ECMA-262 gives it
/// lower precedence than the anchors.
///
/// [build] returns `null` for anything else, and in particular for every
/// construct that could admit `"`, `\`, or a control character inside the JSON
/// string, so the caller can fall back to a length-bounded or unconstrained
/// string.
class _PatternGrammarBuilder {
  _PatternGrammarBuilder(this._addRule, this._name);

  static const _maxRepetitionCount = 1024;

  /// Maximum nesting depth of `(...)` groups the parser descends into.
  ///
  /// The parser recurses once per nested group, so an unbounded pattern would
  /// exhaust the Dart stack. Patterns nested deeper than this are unsupported,
  /// so [build] returns `null` for them as it does for any other unsupported
  /// construct.
  static const _maxGroupDepth = 32;

  static const _metaCharacters = <String>{
    '.',
    '^',
    r'$',
    '*',
    '+',
    '?',
    '(',
    ')',
    '[',
    ']',
    '{',
    '}',
    '|',
  };
  static const _classSpecials = <String>{'"', '\\', '[', ']', '^', '-'};

  final String Function(String name, String rule) _addRule;
  final String _name;
  final Map<String, String> _subRuleIds = {};

  String _source = '';
  int _pos = 0;
  int _groupDepth = 0;

  /// Returns the GBNF expression for [pattern], or `null` if it is outside the
  /// supported subset.
  String? build(String pattern) {
    if (!pattern.startsWith('^') || !pattern.endsWith(r'$')) {
      return null;
    }
    _source = pattern.substring(1, pattern.length - 1);
    _pos = 0;
    final branches = _alternationBranches();
    if (branches == null || branches.length != 1 || _pos != _source.length) {
      return null;
    }
    return branches.single;
  }

  String? _alternation() {
    final branches = _alternationBranches();
    if (branches == null) return null;
    return branches.join(' | ');
  }

  List<String>? _alternationBranches() {
    final branches = <String>[];
    while (true) {
      final branch = _sequence();
      if (branch == null) return null;
      branches.add(branch);
      if (_pos < _source.length && _source[_pos] == '|') {
        _pos++;
        continue;
      }
      return branches;
    }
  }

  String? _sequence() {
    final parts = <String>[];
    while (_pos < _source.length) {
      final char = _source[_pos];
      if (char == '|' || char == ')') break;
      String? atom;
      if (char == '(') {
        atom = _group();
      } else if (char == '[') {
        atom = _characterClass();
      } else if (_isQuantifierStart(char) ||
          char == '.' ||
          char == '^' ||
          char == r'$') {
        return null;
      } else {
        atom = _literalRun();
      }
      if (atom == null) return null;
      final quantified = _quantified(atom);
      if (quantified == null) return null;
      parts.add(quantified);
    }
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  String? _group() {
    if (_groupDepth >= _maxGroupDepth) return null;
    var next = _pos + 1;
    if (next < _source.length && _source[next] == '?') {
      if (next + 1 < _source.length && _source[next + 1] == ':') {
        next += 2;
      } else {
        return null;
      }
    }
    _pos = next;
    _groupDepth++;
    final inner = _alternation();
    _groupDepth--;
    if (inner == null) return null;
    if (_pos >= _source.length || _source[_pos] != ')') return null;
    _pos++;
    return '($inner)';
  }

  String? _characterClass() {
    var next = _pos + 1;
    final buffer = StringBuffer('[');
    var items = 0;
    while (true) {
      if (next >= _source.length) return null;
      final char = _source[next];
      if (char == ']') {
        next++;
        break;
      }
      if (char == '-' &&
          next + 1 < _source.length &&
          _source[next + 1] == ']') {
        buffer.write('-');
        next++;
        items++;
        continue;
      }
      if (!_isClassChar(char)) return null;
      if (next + 2 < _source.length &&
          _source[next + 1] == '-' &&
          _source[next + 2] != ']') {
        final end = _source[next + 2];
        if (!_isClassChar(end) ||
            !_isSafeRange(char.codeUnitAt(0), end.codeUnitAt(0))) {
          return null;
        }
        buffer.write('$char-$end');
        next += 3;
      } else {
        buffer.write(char);
        next++;
      }
      items++;
    }
    if (items == 0) return null;
    buffer.write(']');
    _pos = next;
    return buffer.toString();
  }

  String? _literalRun() {
    final chars = <String>[];
    final starts = <int>[];
    while (_pos < _source.length) {
      final start = _pos;
      final char = _literalChar();
      if (char == null) break;
      chars.add(char);
      starts.add(start);
    }
    if (chars.isEmpty) return null;
    if (chars.length > 1 &&
        _pos < _source.length &&
        _isQuantifierStart(_source[_pos])) {
      _pos = starts.last;
      chars.removeLast();
    }
    return '"${chars.join()}"';
  }

  String? _literalChar() {
    final char = _source[_pos];
    if (char == '\\') {
      if (_pos + 1 >= _source.length) return null;
      final escaped = _source[_pos + 1];
      if (!_metaCharacters.contains(escaped) && escaped != '/') return null;
      _pos += 2;
      return escaped;
    }
    if (!_isLiteralChar(char)) return null;
    _pos++;
    return char;
  }

  String? _quantified(String atom) {
    if (_pos >= _source.length) return atom;
    final char = _source[_pos];
    if (char == '*' || char == '+' || char == '?') {
      _pos++;
      if (_pos < _source.length && _isQuantifierStart(_source[_pos])) {
        return null;
      }
      return '$atom$char';
    }
    if (char != '{') return atom;
    final closing = _source.indexOf('}', _pos);
    if (closing == -1) return null;
    final bounds = _source.substring(_pos + 1, closing).split(',');
    if (bounds.length > 2) return null;
    final min = _parseCount(bounds.first);
    if (min == null) return null;
    int? max;
    if (bounds.length == 1) {
      max = min;
    } else if (bounds[1].isNotEmpty) {
      max = _parseCount(bounds[1]);
      if (max == null) return null;
    }
    if (max != null && (max == 0 || max < min)) return null;
    _pos = closing + 1;
    if (_pos < _source.length && _isQuantifierStart(_source[_pos])) return null;
    return _buildRepetition(_subRule(atom), min, max);
  }

  String _subRule(String atom) => _subRuleIds.putIfAbsent(
    atom,
    () => _addRule('$_name-${_subRuleIds.length + 1}', atom),
  );

  static bool _isQuantifierStart(String char) =>
      char == '*' || char == '+' || char == '?' || char == '{';

  static bool _isLiteralChar(String char) {
    final code = char.codeUnitAt(0);
    if (code < 0x20 || code > 0x7E) return false;
    return char != '"' && char != '\\' && !_metaCharacters.contains(char);
  }

  static bool _isClassChar(String char) {
    final code = char.codeUnitAt(0);
    if (code < 0x20 || code > 0x7E) return false;
    return !_classSpecials.contains(char);
  }

  /// Whether [end] is not below [start] and the inclusive range between them
  /// excludes the two code units a GBNF character class must never admit
  /// inside a JSON string: `"` (0x22) and `\` (0x5C).
  static bool _isSafeRange(int start, int end) {
    if (end < start) return false;
    if (start <= 0x22 && 0x22 <= end) return false;
    if (start <= 0x5C && 0x5C <= end) return false;
    return true;
  }

  static int? _parseCount(String value) {
    if (value.isEmpty || value.length > 4) return null;
    for (final unit in value.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return null;
    }
    final count = int.parse(value);
    return count > _maxRepetitionCount ? null : count;
  }
}

/// Build a GBNF repetition expression.
///
/// Matches llama.cpp's `_buildRepetition`.
String _buildRepetition(
  String itemRule,
  int minItems,
  int? maxItems, {
  String separatorRule = '',
}) {
  // Validate bounds before formatting: a malformed schema with min > max (or a
  // negative count) would otherwise emit invalid GBNF like `rule{2,1}`.
  final normalizedMin = minItems < 0 ? 0 : minItems;
  if (maxItems != null && maxItems < normalizedMin) {
    // Generic wording: this helper backs both array minItems/maxItems and
    // string minLength/maxLength repetition.
    throw StateError(
      'Invalid repetition bounds: maximum ($maxItems) must be >= minimum '
      '($normalizedMin) and non-negative.',
    );
  }
  minItems = normalizedMin;
  if (maxItems != null && maxItems == 0) return '';
  if (minItems == 0 && maxItems != null && maxItems == 1) return '$itemRule?';

  if (separatorRule.isEmpty) {
    if (minItems == 1 && maxItems == null) return '$itemRule+';
    if (minItems == 0 && maxItems == null) return '$itemRule*';
    return '$itemRule{$minItems,${maxItems ?? ''}}';
  }

  final result =
      '$itemRule ${_buildRepetition('($separatorRule $itemRule)', minItems > 0 ? minItems - 1 : 0, maxItems != null ? maxItems - 1 : null)}';
  return minItems == 0 ? '($result)?' : result;
}

/// Port of v0.7.0 build_min_max_int; null endpoints are unbounded.
String _buildMinMaxInt(
  int? min,
  int? max, [
  int decimals = 16,
  bool top = true,
]) {
  String digits(int low, int high) => low == high && low == 1
      ? '[0-9]'
      : '[0-9]{${low == high ? low : '$low,$high'}}';
  String range(String from, String to) =>
      from == to ? '[$from]' : '[$from-$to]';
  String uniform(String from, String to) {
    var i = 0;
    while (i < from.length && i < to.length && from[i] == to[i]) {
      i++;
    }
    final prefix = i > 0 ? '"${from.substring(0, i)}"' : '';
    if (i >= from.length || i >= to.length) return prefix;
    final len = from.length - i - 1;
    String body;
    if (len == 0) {
      body = '[${from[i]}-${to[i]}]';
    } else {
      final fromSub = from.substring(i + 1);
      final toSub = to.substring(i + 1);
      final zeros = '0' * len;
      final nines = '9' * len;
      final fromDigit = int.parse(from[i]);
      final toDigit = int.parse(to[i]);
      final parts = <String>[];
      var reached = false;
      if (fromSub == zeros) {
        parts.add('${range(from[i], '${toDigit - 1}')} ${digits(len, len)}');
      } else {
        parts.add('[${from[i]}] (${uniform(fromSub, nines)})');
        if (fromDigit < toDigit - 1) {
          reached = toSub == nines;
          parts.add(
            '${range('${fromDigit + 1}', reached ? to[i] : '${toDigit - 1}')} ${digits(len, len)}',
          );
        }
      }
      if (!reached) parts.add('[${to[i]}] ${uniform(zeros, toSub)}');
      body = '(${parts.join(' | ')})';
    }
    return '$prefix${prefix.isEmpty ? '' : ' '}$body';
  }

  final less = decimals > 1 ? decimals - 1 : 1;
  if (min != null && max != null) {
    if (min < 0 && max < 0) {
      return '"-" (${_buildMinMaxInt(-max, -min, decimals)})';
    }
    var prefix = '';
    if (min < 0) {
      prefix = '"-" (${_buildMinMaxInt(0, -min, decimals)}) | ';
      min = 0;
    }
    var from = '$min';
    final to = '$max';
    final parts = <String>[];
    for (var count = from.length; count < to.length; count++) {
      parts.add(uniform(from, '9' * count));
      from = '1${'0' * count}';
    }
    parts.add(uniform(from, to));
    return '$prefix${parts.join(' | ')}';
  }
  if (min != null) {
    if (min < 0) {
      return '"-" (${_buildMinMaxInt(null, -min, decimals, false)}) | [0] | [1-9] ${digits(0, decimals - 1)}';
    }
    if (min == 0) {
      return top ? '[0] | [1-9] ${digits(0, less)}' : digits(1, decimals);
    }
    if (min <= 9) {
      final start = top ? 1 : 0;
      final prefix = min > start
          ? '${range('$start', '${min - 1}')} ${digits(1, less)} | '
          : '';
      return '$prefix${range('$min', '9')} ${digits(0, less)}';
    }
    final text = '$min';
    final len = text.length;
    final first = int.parse(text[0]);
    final prefix = first > 1
        ? '${range(top ? '1' : '0', '${first - 1}')} ${digits(len, less)} | '
        : '';
    final suffix = first < 9
        ? ' | ${range('${first + 1}', '9')} ${digits(len - 1, less)}'
        : '';
    return '$prefix[$first] (${_buildMinMaxInt(int.parse(text.substring(1)), null, less, false)})$suffix';
  }
  if (max != null) {
    if (max >= 0) {
      return '${top ? '"-" [1-9] ${digits(0, less)} | ' : ''}${_buildMinMaxInt(0, max, decimals)}';
    }
    // Diverge from v0.7.0 only here: the first digit after a minus sign is
    // still a leading digit. Upstream's suffix mode admits invalid -00/-01.
    return '"-" (${_buildMinMaxInt(-max, null, decimals)})';
  }
  throw StateError('At least one integer endpoint is required');
}
