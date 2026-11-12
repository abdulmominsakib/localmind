import 'dart:convert';

const v1SchemaModelSha256 =
    'c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108';
const v1SchemaModelBytes = 613722264;
const v1SchemaPrompt =
    'Reply with exactly the word BANANA. Do not use JSON, quotes, punctuation, or explanation.';
const v1SchemaDefinition = <String, Object>{
  'type': 'object',
  'properties': {
    'café': {'type': 'string', 'const': '日本 😊'},
    'count': {'type': 'integer', 'const': 3},
    'active': {'type': 'boolean', 'const': true},
    'empty': {'type': 'null', 'const': null},
  },
  'required': ['café', 'count', 'active', 'empty'],
  'additionalProperties': false,
};

void requireV1SchemaPlainControl(String text) {
  if (text.trim() != 'BANANA') {
    throw StateError('Unconstrained control must return exactly BANANA.');
  }
}

Map<String, dynamic> requireV1SchemaTypedResponse(String text) {
  if (text.contains('<think>') || text.contains('</think>')) {
    throw StateError('Schema response exposed thinking delimiters.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw StateError('Schema response must be complete raw JSON.');
  }
  if (decoded is! Map<String, dynamic> ||
      decoded.length != 4 ||
      decoded['café'] != '日本 😊' ||
      decoded['count'] is! num ||
      decoded['count'] != 3 ||
      decoded['active'] != true ||
      !decoded.containsKey('empty') ||
      decoded['empty'] != null) {
    throw StateError(
      'Schema response violated the fixed Unicode/typed contract.',
    );
  }
  return decoded;
}
