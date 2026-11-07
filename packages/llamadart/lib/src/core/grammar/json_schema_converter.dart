import 'dart:convert';

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
  'null': _BuiltinRule('"null" space', []),
};

/// Reserved rule names that need a suffix to avoid collision.
final _reservedNames = <String>{'root', ..._primitiveRules.keys};

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
  final Map<String, String> _rules = {'space': _spaceRule};
  final Map<String, dynamic> _refs = {};
  final Set<String> _refsBeingResolved = {};

  /// Access accumulated rules (for multi-tool grammar assembly).
  Map<String, String> get rules => _rules;

  /// Convert a JSON Schema to a GBNF grammar string.
  ///
  /// This is the main entry point. Pass the full JSON Schema as a map.
  static String convert(Map<String, dynamic> schema) {
    final converter = JsonSchemaConverter();
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
      final depRule = _primitiveRules[dep];
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
        dynamic target = rootSchema;
        final selectors = ref.substring(2).split('/');
        for (final sel in selectors) {
          if (target is Map<String, dynamic> && target.containsKey(sel)) {
            target = target[sel];
          } else {
            throw StateError('Error resolving ref $ref: $sel not found');
          }
        }
        _refs[ref] = target;
        // Resolve refs nested inside the target as well.
        resolveRefs(target, rootSchema);
      }
      // Always walk children so refs nested as siblings of a $ref (or inside an
      // already-registered ref-bearing node) are resolved too.
      for (final value in node.values) {
        resolveRefs(value, rootSchema);
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
    final schemaType = schema['type'];
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

      for (final component in schema['allOf'] as List) {
        var compSchema = component as Map<String, dynamic>;
        final compRef = compSchema[r'$ref'] as String?;
        if (compRef != null) {
          compSchema = _refs[compRef] as Map<String, dynamic>? ?? compSchema;
        }

        if (compSchema.containsKey('properties')) {
          final props = compSchema['properties'] as Map<String, dynamic>;
          properties.addAll(props.entries);
          // In allOf, all properties from each component are required
          required.addAll(props.keys);
        }
      }

      return _addRule(
        ruleName,
        _buildObjectRule(properties, required, name, null),
      );
    }

    // array with items
    if ((schemaType == null || schemaType == 'array') &&
        (schema.containsKey('items') || schema.containsKey('prefixItems'))) {
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
        final itemRuleName = visit(
          items as Map<String, dynamic>,
          '${name.isNotEmpty ? '$name-' : ''}item',
        );
        final minItems = (schema['minItems'] as int?) ?? 0;
        final maxItems = schema['maxItems'] as int?;
        return _addRule(
          ruleName,
          '"[" space ${_buildRepetition(itemRuleName, minItems, maxItems, separatorRule: '"," space')} "]" space',
        );
      }
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

    // Primitive types
    if (schemaType is String && _primitiveRules.containsKey(schemaType)) {
      return _addPrimitive(
        ruleName == 'root' ? 'root' : schemaType,
        _primitiveRules[schemaType]!,
      );
    }

    throw StateError('Unrecognized schema: ${jsonEncode(schema)}');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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

    final requiredProps = sortedPropNames
        .where((k) => required.contains(k))
        .toList();
    final optionalProps = sortedPropNames
        .where((k) => !required.contains(k))
        .toList();

    // Handle additionalProperties
    if (additionalProperties != null && additionalProperties != false) {
      final subName = '${name.isNotEmpty ? '$name-' : ''}additional';
      final valueRule = additionalProperties is Map<String, dynamic>
          ? visit(additionalProperties, '$subName-value')
          : _addPrimitive('value', _primitiveRules['value']!);
      final keyRule = sortedPropNames.isEmpty
          ? _addPrimitive('string', _primitiveRules['string']!)
          : _addPrimitive('string', _primitiveRules['string']!);

      propKvRuleNames['*'] = _addRule(
        '$subName-kv',
        '$keyRule ":" space $valueRule',
      );
      optionalProps.add('*');
    }

    var rule = '"{" space ';
    rule += requiredProps.map((k) => propKvRuleNames[k]).join(' "," space ');

    if (optionalProps.isNotEmpty) {
      rule += ' (';
      if (requiredProps.isNotEmpty) {
        rule += ' "," space ( ';
      }

      String getRecursiveRefs(List<String> ks, bool firstIsOptional) {
        final k = ks.first;
        final rest = ks.sublist(1);
        final kvRuleName = propKvRuleNames[k]!;
        String res;
        final commaRef = '( "," space $kvRuleName )';
        if (firstIsOptional) {
          res = '$commaRef${k == '*' ? '*' : '?'}';
        } else {
          res = '$kvRuleName${k == '*' ? ' $commaRef*' : ''}';
        }
        if (rest.isNotEmpty) {
          res +=
              ' ${_addRule('${name.isNotEmpty ? '$name-' : ''}$k-rest', getRecursiveRefs(rest, true))}';
        }
        return res;
      }

      final optAlternatives = <String>[];
      for (var i = 0; i < optionalProps.length; i++) {
        optAlternatives.add(getRecursiveRefs(optionalProps.sublist(i), false));
      }
      rule += optAlternatives.join(' | ');

      if (requiredProps.isNotEmpty) {
        rule += ' )';
      }
      rule += ' )?';
    }

    rule += ' "}" space';
    return rule;
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
