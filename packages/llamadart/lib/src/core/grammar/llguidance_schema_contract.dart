import '../exceptions.dart';
import 'json_schema_converter.dart';
import 'response_schema_validation.dart';

const _draft202012 = 'https://json-schema.org/draft/2020-12/schema';
const _refusedKeywords = {
  'oneOf': 'is not enforced as oneOf; use anyOf',
  'uniqueItems': 'is not implemented',
  r'$dynamicAnchor': 'is not implemented',
  r'$recursiveAnchor': 'is not implemented',
  'x-guidance': 'would override the constraint compiler options',
};
const _formats = {'uuid', 'date'};
const _maxSafeInteger = 9007199254740992;
const _maxPatternRepetition = 100000;
const _maxAllOfEnumProduct = 20000;
const _maxOptionalProperties = 400;

/// Checks [schema] against the JSON Schema subset that both the llama.cpp
/// GBNF converter and LiteRT-LM's llguidance 1.9.1 provider enforce alike.
///
/// llguidance rejects some schemas only when a message is sent, and compiles
/// others into a different language than the GBNF converter; both are refused
/// here, before generation, naming the feature.
void validateLlguidanceResponseSchema(Map<String, dynamic> schema) {
  validateResponseSchema(schema);
  final declared = schema[r'$schema'];
  if (declared != null &&
      (declared is! String ||
          (declared != _draft202012 && declared != '$_draft202012#'))) {
    _refuse(r'$.$schema', 'must be absent or JSON Schema draft 2020-12');
  }
  final walked = <String>{};
  final acyclicRefs = <String>{};
  void walk(Map<String, dynamic> node, String path, {bool root = false}) {
    for (final entry in _refusedKeywords.entries) {
      if (node.containsKey(entry.key)) {
        _refuse('$path.${entry.key}', entry.value);
      }
    }
    if (!root) {
      for (final key in const [r'$schema', r'$id']) {
        if (node.containsKey(key)) {
          _refuse('$path.$key', 'is supported only at the schema root');
        }
      }
    }
    if (node['format'] case final Object format
        when !_formats.contains(format)) {
      _refuse(
        '$path.format',
        'is "$format"; only uuid and date are enforced alike',
      );
    }
    final tuple =
        node['prefixItems'] ?? (node['items'] is List ? node['items'] : null);
    if (tuple is List &&
        (node['minItems'] != tuple.length ||
            node['maxItems'] != tuple.length)) {
      _refuse(
        '$path.prefixItems',
        'needs minItems and maxItems equal to the tuple length',
      );
    }
    if (node['pattern'] case final String pattern) {
      _checkPattern(pattern, '$path.pattern');
    }
    for (final key in const ['const', 'enum']) {
      if (node.containsKey(key) && _hasUnsafeInteger(node[key])) {
        _refuse('$path.$key', 'has an integer beyond 2^53');
      }
    }
    _checkAllOfEnumProduct(node, schema, path);
    if (_optionalProperties(node, schema, <String>{}) >
        _maxOptionalProperties) {
      _refuse(
        path,
        'allows more than $_maxOptionalProperties optional properties at one '
        'value',
      );
    }
    _checkInPlaceRefCycle(node, schema, path, const [], acyclicRefs);

    final ref = node[r'$ref'];
    if (ref is String) {
      if (ref.contains('~')) {
        _refuse('$path.\$ref', 'must not use ~0 or ~1 pointer escapes');
      }
      if (walked.add(ref)) {
        walk(_resolve(schema, ref, path), '$path.\$ref');
      }
    }
    if (node['properties'] case final Map properties) {
      for (final entry in properties.entries) {
        walk(
          responseSchemaMap(entry.value, '$path.properties.${entry.key}'),
          '$path.properties.${entry.key}',
        );
      }
    }
    for (final key in const ['items', 'additionalProperties']) {
      if (node[key] case final Map child) {
        walk(responseSchemaMap(child, '$path.$key'), '$path.$key');
      }
    }
    for (final key in const ['items', 'prefixItems', 'anyOf', 'allOf']) {
      if (node[key] case final List children) {
        for (var i = 0; i < children.length; i++) {
          walk(
            responseSchemaMap(children[i], '$path.$key[$i]'),
            '$path.$key[$i]',
          );
        }
      }
    }
  }

  walk(schema, r'$', root: true);
}

Never _refuse(String path, String reason) => throw LlamaUnsupportedException(
  'Unsupported structured JSON schema for native LiteRT-LM output: '
  '$path $reason.',
);

Map<String, dynamic> _resolve(
  Map<String, dynamic> root,
  String ref,
  String path,
) => responseSchemaMap(
  JsonSchemaConverter.resolvePointer(root, ref),
  '$path.\$ref',
);

bool _hasUnsafeInteger(Object? value) => switch (value) {
  final int v => v.abs() > _maxSafeInteger,
  final double v => v == v.truncateToDouble() && v.abs() > _maxSafeInteger,
  final List values => values.any(_hasUnsafeInteger),
  final Map values => values.values.any(_hasUnsafeInteger),
  _ => false,
};

// llguidance reads patterns as Rust regexes: class set operations and nested
// classes change meaning, and counted repetitions expand into its lexer.
void _checkPattern(String pattern, String path) {
  var i = 0;
  int clamp(int value) =>
      value > _maxPatternRepetition ? _maxPatternRepetition + 1 : value;

  late final int Function() alternatives;

  int quantifier() {
    if (i >= pattern.length) return 1;
    final c = pattern[i];
    if (c == '*' || c == '+' || c == '?') {
      i++;
      return 1;
    }
    if (c != '{') return 1;
    final close = pattern.indexOf('}', i);
    if (close < 0) return 1;
    final bounds = pattern.substring(i + 1, close).split(',');
    i = close + 1;
    final upper = bounds.length == 1 || bounds[1].isEmpty
        ? bounds[0]
        : bounds[1];
    return int.tryParse(upper.trim()) ?? 1;
  }

  int atom() {
    final c = pattern[i];
    if (c == '\\') {
      i += 2;
      return 1;
    }
    if (c == '[') {
      i++;
      if (i < pattern.length && pattern[i] == ']') i++;
      while (i < pattern.length && pattern[i] != ']') {
        if (pattern[i] == '\\') {
          i += 2;
          continue;
        }
        if (pattern[i] == '[' ||
            pattern.startsWith('&&', i) ||
            pattern.startsWith('--', i) ||
            pattern.startsWith('~~', i)) {
          _refuse(
            path,
            'uses a nested class or class set operation, which LiteRT-LM '
            'reads differently',
          );
        }
        i++;
      }
      i++;
      return 1;
    }
    if (c == '(') {
      i++;
      if (pattern.startsWith('?:', i)) i += 2;
      final inner = alternatives();
      i++;
      return inner;
    }
    i++;
    return 1;
  }

  int sequence() {
    var widest = 1;
    while (i < pattern.length && pattern[i] != '|' && pattern[i] != ')') {
      final repeated = clamp(atom() * quantifier());
      if (repeated > widest) widest = repeated;
    }
    return widest;
  }

  alternatives = () {
    var widest = sequence();
    while (i < pattern.length && pattern[i] == '|') {
      i++;
      final next = sequence();
      if (next > widest) widest = next;
    }
    return widest;
  };

  if (alternatives() > _maxPatternRepetition) {
    _refuse(
      path,
      'nests counted repetitions beyond $_maxPatternRepetition, more than '
      'LiteRT-LM compiles',
    );
  }
}

void _checkAllOfEnumProduct(
  Map<String, dynamic> node,
  Map<String, dynamic> root,
  String path,
) {
  final components = node['allOf'];
  if (components is! List) return;
  var product = 1;
  for (var i = 0; i < components.length; i++) {
    var component = responseSchemaMap(components[i], '$path.allOf[$i]');
    final seen = <String>{};
    for (
      var ref = component[r'$ref'];
      ref is String && seen.add(ref);
      ref = component[r'$ref']
    ) {
      component = _resolve(root, ref, '$path.allOf[$i]');
    }
    if (component['enum'] case final List values) {
      product *= values.length;
      if (product > _maxAllOfEnumProduct) {
        _refuse(
          '$path.allOf',
          'intersects enums of more than $_maxAllOfEnumProduct combinations',
        );
      }
    }
  }
}

int _optionalProperties(
  Map<String, dynamic> node,
  Map<String, dynamic> root,
  Set<String> refs,
) {
  var count = 0;
  if (node['properties'] case final Map properties) {
    final required = node['required'] is List
        ? (node['required'] as List).toSet()
        : const <Object?>{};
    count += properties.keys.where((key) => !required.contains(key)).length;
  }
  if (node[r'$ref'] case final String ref when refs.add(ref)) {
    count += _optionalProperties(_resolve(root, ref, r'$'), root, refs);
  }
  for (final key in const ['anyOf', 'allOf']) {
    if (node[key] case final List children) {
      for (final child in children) {
        count += _optionalProperties(responseSchemaMap(child, key), root, refs);
      }
    }
  }
  return count;
}

// A reference cycle with no property or item between its steps compiles to an
// empty language in llguidance and a left-recursive grammar in GBNF.
void _checkInPlaceRefCycle(
  Map<String, dynamic> node,
  Map<String, dynamic> root,
  String path,
  List<String> chain,
  Set<String> acyclic,
) {
  if (node[r'$ref'] case final String ref when !acyclic.contains(ref)) {
    if (chain.contains(ref)) {
      _refuse('$path.\$ref', 'forms a reference cycle with no value between');
    }
    _checkInPlaceRefCycle(_resolve(root, ref, path), root, path, [
      ...chain,
      ref,
    ], acyclic);
    acyclic.add(ref);
  }
  for (final key in const ['anyOf', 'allOf']) {
    if (node[key] case final List children) {
      for (final child in children) {
        _checkInPlaceRefCycle(
          responseSchemaMap(child, '$path.$key'),
          root,
          path,
          chain,
          acyclic,
        );
      }
    }
  }
}
