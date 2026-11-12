import 'decision_catalog.dart';

/// Current reproducible catalog contract; older journals retain their version.
const int validationCatalogVersion = 15;

/// Versioned core feature selectors. Optional model/media packs are separate.
const validationFeatures = {
  'text': 1,
  'unicode': 1,
  'thinking': 1,
  'history': 1,
  'tools': 1,
  'streaming': 1,
  'batching': 1,
  'lifecycle': 1,
  'guards': 1,
  'performance': 1,
  'structured_output': 1,
  'tokenization': 1,
  'state_persistence': 1,
  'tool_result_media': 1,
  'next_token_scoring': 1,
  'sampler_controls': 1,
};

/// Feature selectors that catalogs before 8 do not declare.
const catalogEightFeatures = {'structured_output'};

/// Shared synthetic fixtures, compiled into desktop, mobile and Web runners.
/// Model-specific overrides stay in the hashed profile manifest.
const validationFixtures = <String, Map<String, Object>>{
  'unicode': {'input': 'Montréal 👋\n한글 café', 'expected_prefix': ''},
  'unicode_generation': {
    'prompt': 'Reply with exactly: Montréal 👋',
    'expected': 'Montréal 👋',
    'qualification':
        'strict public output assertion; a failure does not identify its root cause',
  },
  'raw': {'prompt': 'Once upon a time'},
  'hello': {
    'prompt': 'Reply with one short sentence saying hello.',
    'regex': r'\bhello\b',
  },
  'arithmetic': {
    'prompt': 'What is 2 + 2? Reply with only the number.',
    'regex': r'^4[.!]?$',
  },
  'history': {
    'system': 'Remember the secret code exactly.',
    'user': 'The secret code is cedar17.',
    'assistant': 'I will remember the code.',
    'prompt': 'What is the secret code? Reply with only the code.',
    'expected': 'cedar17',
  },
  'tools': {
    'prompt': 'Call get_weather for Montréal.',
    'tool': {
      'type': 'function',
      'function': {
        'name': 'get_weather',
        'description': 'Return the weather for a city.',
        'parameters': {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
          'required': ['city'],
        },
      },
    },
    'expected_arguments': {'city': 'Montréal'},
    'response': {'city': 'Montréal', 'temperature_celsius': 17},
    'modes': ['auto', 'required', 'none'],
  },
  'cancel': {
    'chat_prompt':
        'Write a long story about a fox. Continue for at least 500 words.',
    'max_tokens': 256,
    'deadline_ms': 5000,
  },
  'inflight': {'control_fraction': 0.25},
  'batching': {'token_threshold': 1, 'byte_threshold': 1},
  'stop': {
    'prompt': 'Reply with exactly: alpha cedar17 omega',
    'marker': 'cedar17',
  },
  'limit': {'max_tokens': 1, 'expected_native_decode_tokens': 1},
  'invalid_grammar': {
    'grammar': 'root ::= "unterminated',
    'native_message':
        'llama.cpp failed to initialize the requested grammar sampler.',
    'web_details_marker': '(invalid grammar)',
  },
  'benchmark': {
    'chat_prompt': 'List the numbers from one to twenty in English.',
    'warmups': 1,
    'samples': 3,
  },
  'structured_output': structuredOutputFixture,
  'native_json_schema_capability': nativeJsonSchemaCapabilityFixture,
  'tokenization': tokenizationFixture,
  'state_persistence': statePersistenceFixture,
  'tool_result_media': toolResultMediaFixture,
  'next_token_scoring': nextTokenScoringFixture,
  'sampler_controls': samplerControlsFixture,
};

/// Case identity and fixture dependencies. False implementation flags always
/// produce NOT_RUN, never an unsupported-platform exemption.
class ValidationCaseDefinition {
  /// Declares a case without hiding unimplemented obligations.
  const ValidationCaseDefinition(
    this.id,
    this.features,
    this.fixtures, {
    this.implemented = true,
    this.version = 1,
  });

  /// Stable identifier in journals and reports.
  final String id;

  /// Feature selectors that include this case.
  final List<String> features;

  /// Fixture keys included in the case's evidence hash.
  final List<String> fixtures;

  /// Whether the shared runner can execute this case.
  final bool implemented;

  /// Semantic version of the current case contract.
  final int version;

  /// Serializable metadata, independent of model-specific fixture overrides.
  Map<String, Object> toJson() => {
    'id': id,
    'version': version,
    'features': features,
    'fixture_ids': fixtures,
    'implemented': implemented,
  };
}

/// Baseline case definitions; model applicability is resolved by the profile.
const coreValidationCases = [
  ValidationCaseDefinition('C01.load', ['lifecycle'], []),
  ValidationCaseDefinition('C02.unicode', ['unicode'], ['unicode']),
  ValidationCaseDefinition('C03.raw', ['text'], ['raw']),
  ValidationCaseDefinition('C04.hello', ['text'], ['hello']),
  ValidationCaseDefinition('C04.arithmetic', ['text'], ['arithmetic']),
  ValidationCaseDefinition('C06.history', ['history'], ['history']),
  ValidationCaseDefinition(
    'C06.history.public_system_wire',
    ['history'],
    ['history'],
  ),
  ValidationCaseDefinition('C06.history.no_system', ['history'], ['history']),
  ValidationCaseDefinition('C06.history.combined', ['history'], ['history']),
  ValidationCaseDefinition(
    'C08.cancel',
    ['streaming', 'lifecycle'],
    ['cancel', 'raw', 'hello', 'inflight'],
    version: 2,
  ),
  ValidationCaseDefinition(
    'C08.cancel.early',
    ['streaming', 'lifecycle'],
    ['cancel', 'raw', 'hello'],
  ),
  ValidationCaseDefinition(
    'C08.cancel.restart',
    ['streaming', 'lifecycle'],
    ['cancel', 'raw', 'hello'],
  ),
  ValidationCaseDefinition(
    'C08.overlap',
    ['streaming', 'lifecycle'],
    ['cancel', 'raw', 'hello', 'inflight'],
    version: 2,
  ),
  ValidationCaseDefinition('C09.reload', ['lifecycle'], ['raw', 'hello']),
  ValidationCaseDefinition(
    'C10.limit',
    ['streaming'],
    ['limit', 'raw', 'hello'],
  ),
  ValidationCaseDefinition(
    'C12.grammar',
    ['guards'],
    ['invalid_grammar', 'raw', 'hello'],
  ),
  ValidationCaseDefinition(
    'C12.recovery',
    ['guards', 'lifecycle'],
    ['raw', 'hello'],
  ),
  ValidationCaseDefinition('B01.warmup', ['performance'], ['benchmark', 'raw']),
  ValidationCaseDefinition('B01.1', ['performance'], ['benchmark', 'raw']),
  ValidationCaseDefinition('B01.2', ['performance'], ['benchmark', 'raw']),
  ValidationCaseDefinition('B01.3', ['performance'], ['benchmark', 'raw']),
];

/// Extra obligations added by release or matching focused feature selections.
const extendedValidationCases = [
  ValidationCaseDefinition(
    'C05.thinking',
    ['thinking'],
    ['arithmetic'],
    version: 2,
  ),
  ValidationCaseDefinition(
    'C07.tools',
    ['tools'],
    ['tools', 'hello'],
    version: 3,
  ),
  ValidationCaseDefinition(
    'C07.tools.auto_text',
    ['tools'],
    ['tools', 'hello'],
  ),
  ValidationCaseDefinition(
    'C10.stop',
    ['streaming'],
    ['stop', 'hello', 'raw'],
    version: 2,
  ),
  ValidationCaseDefinition(
    'C11.batching',
    ['streaming', 'batching'],
    ['raw', 'hello', 'batching'],
    version: 2,
  ),
  ValidationCaseDefinition(
    'C12.guards',
    ['guards'],
    ['hello', 'raw'],
    version: 2,
  ),
  ValidationCaseDefinition(
    'C02.generate',
    ['unicode'],
    ['unicode_generation'],
    version: 2,
  ),
  ValidationCaseDefinition(
    'C09.reload.second',
    ['lifecycle'],
    ['raw', 'hello'],
  ),
  ...structuredOutputValidationCases,
  ...tokenizationValidationCases,
  ...stateValidationCases,
  ...toolResultMediaValidationCases,
  ...nextTokenScoringValidationCases,
  ...samplerControlValidationCases,
];

/// Stable order for the complete selected/omitted inventory.
const validationCaseCatalog = [
  ...coreValidationCases,
  ...extendedValidationCases,
];

/// Cases that catalogs 1 to 4 do not declare.
const catalogFiveCaseIds = {
  'C08.cancel.early',
  'C08.cancel.restart',
  'C08.overlap',
  'C12.grammar',
  'C07.tools.auto_text',
};

/// Whether [catalogVersion] declares case [id]. Decision cases exist only in
/// catalogs 5 and newer, and only decision profiles select them.
bool catalogDeclaresCase(String id, int catalogVersion) =>
    samplerControlValidationCases.any((definition) => definition.id == id)
    ? catalogVersion >= 15
    : id == 'P05.identity'
    ? catalogVersion >= 14
    : nextTokenScoringValidationCases.any((definition) => definition.id == id)
    ? catalogVersion >= 13
    : toolResultMediaValidationCases.any((definition) => definition.id == id)
    ? catalogVersion >= 12
    : stateValidationCases.any((definition) => definition.id == id)
    ? catalogVersion >= 11
    : tokenizationValidationCases.any((definition) => definition.id == id)
    ? catalogVersion >= 9
    : structuredOutputValidationCases.any((definition) => definition.id == id)
    ? catalogVersion >= 8
    : [
        ...decisionValidationCases,
        ...embeddingValidationCases,
      ].any((definition) => definition.id == id)
    ? catalogVersion >= 5
    : catalogVersion >= 5 || !catalogFiveCaseIds.contains(id);

/// Finds a declared case; an unknown ID is a programming error.
ValidationCaseDefinition validationCase(
  String id, {
  int catalogVersion = validationCatalogVersion,
}) {
  if (catalogVersion < 1 || catalogVersion > validationCatalogVersion) {
    throw const FormatException('Unsupported catalog version');
  }
  if (!catalogDeclaresCase(id, catalogVersion)) {
    throw FormatException('Catalog $catalogVersion does not declare $id');
  }
  if (catalogVersion < 10 && id == 'S01.capabilities') {
    return const ValidationCaseDefinition(
      'S01.capabilities',
      ['structured_output'],
      ['structured_output'],
    );
  }
  if (catalogVersion < 6 && (id == 'C08.cancel' || id == 'C08.overlap')) {
    return ValidationCaseDefinition(
      id,
      ['streaming', 'lifecycle'],
      ['cancel', 'raw', 'hello'],
    );
  }
  final current = catalogVersion < 5 && id == 'C07.tools'
      ? const ValidationCaseDefinition(
          'C07.tools',
          ['tools'],
          ['tools'],
          version: 2,
        )
      : [
          ...validationCaseCatalog,
          ...decisionValidationCases,
          ...embeddingValidationCases,
        ].singleWhere((definition) => definition.id == id);
  if (catalogVersion < 4 &&
      ['C05.thinking', 'C07.tools', 'C02.generate'].contains(id)) {
    return ValidationCaseDefinition(
      id,
      current.features,
      current.fixtures,
      implemented: false,
    );
  }
  if (catalogVersion < 3 && (id == 'C10.stop' || id == 'C12.guards')) {
    return ValidationCaseDefinition(
      id,
      [id == 'C10.stop' ? 'streaming' : 'guards'],
      [],
      implemented: false,
    );
  }
  if (catalogVersion == 1 && id == 'C11.batching') {
    return const ValidationCaseDefinition(
      'C11.batching',
      ['streaming'],
      ['raw', 'hello'],
      implemented: false,
    );
  }
  return current;
}

/// Version-one synthetic media, native CPU vectors and numerical contracts.
const embeddingValidationFixture = <String, Object>{
  'version': 1,
  'directory': 'assets/embeddings/v1',
  'files': {
    'checker.png':
        '48907b2f7a4c600cdbc4de829a7badc4801f48b2e53816276bbc81f31367e030',
    'tone.wav':
        '963aa326ea0d5067c3981f029116ce68a33518463b23035d503b4350f4b5f8b3',
    'reference.json':
        '89321caf3f61e6905d018f0b8c0975cc96fd5f0d33518060f9bd3b7544764d08',
  },
  'dimensions': 768,
  'text': 'The Eiffel Tower is in Paris.',
  'mixed_text': ['first ', ' between ', ' last'],
  'rows': ['text', 'image', 'audio', 'mixed', 'mixed_reversed'],
  'batch_order': [2, 0, 4, 2],
  'thresholds': {
    'cpu': {'minimum_cosine': 0.999, 'maximum_absolute_error': 0.01},
    'metal': {'minimum_cosine': 0.999, 'maximum_absolute_error': 0.01},
  },
  'norm_tolerance': 0.000001,
  'cancel_deadline_ms': 5000,
};

/// Selected only by embedding profiles; no text generation or TPS claims.
const embeddingValidationCases = [
  ValidationCaseDefinition('E01.capabilities', ['embeddings'], ['embeddings']),
  ValidationCaseDefinition('E02.text', ['embeddings'], ['embeddings']),
  ValidationCaseDefinition('E03.image', ['embeddings'], ['embeddings']),
  ValidationCaseDefinition('E04.audio', ['embeddings'], ['embeddings']),
  ValidationCaseDefinition('E05.mixed', ['embeddings'], ['embeddings']),
  ValidationCaseDefinition('E06.batch', ['embeddings'], ['embeddings']),
  ValidationCaseDefinition('E07.normalization', ['embeddings'], ['embeddings']),
  ValidationCaseDefinition('E08.guards', ['embeddings'], ['embeddings']),
  ValidationCaseDefinition('E09.cancel.before', ['embeddings'], ['embeddings']),
  ValidationCaseDefinition('E10.cancel.after', ['embeddings'], ['embeddings']),
];

/// Rechecks successful numerical evidence on import instead of trusting the
/// producer's `passed` flags. Fixture thresholds cannot be journal overrides.
bool validEmbeddingCaseEvidence(
  String id,
  Map<String, dynamic> record, {
  String backend = 'cpu',
}) {
  final thresholds =
      (embeddingValidationFixture['thresholds'] as Map)[backend] as Map;
  bool comparison(Object? value) =>
      value is Map &&
      value['cosine'] is num &&
      (value['cosine'] as num).isFinite &&
      (value['cosine'] as num) >= (thresholds['minimum_cosine'] as num) &&
      (value['cosine'] as num) <= 1.0000000001 &&
      value['max_abs'] is num &&
      (value['max_abs'] as num).isFinite &&
      (value['max_abs'] as num) >= 0 &&
      (value['max_abs'] as num) <=
          (thresholds['maximum_absolute_error'] as num);
  switch (id) {
    case 'E01.capabilities':
      return record['text'] == true &&
          record['image'] == true &&
          record['audio'] == true &&
          record.containsKey('media_unsupported_reason') &&
          record['media_unsupported_reason'] == null;
    case 'E02.text':
    case 'E03.image':
    case 'E04.audio':
    case 'E05.mixed':
    case 'E06.batch':
      final comparisons = record['comparisons'];
      final count = id == 'E06.batch'
          ? (embeddingValidationFixture['batch_order'] as List).length
          : 1;
      return comparisons is List &&
          comparisons.length == count &&
          comparisons.every(comparison) &&
          (id != 'E06.batch' ||
              record['vector_count'] == count &&
                  '${record['order']}' ==
                      '${embeddingValidationFixture['batch_order']}');
    case 'E07.normalization':
      final raw = record['raw_norm'];
      final normalized = record['normalized_norm'];
      return raw is num &&
          raw.isFinite &&
          raw > 0 &&
          (raw - 1).abs() > 0.0001 &&
          normalized is num &&
          normalized.isFinite &&
          (normalized - 1).abs() <=
              (embeddingValidationFixture['norm_tolerance'] as num) &&
          comparison(record['raw_comparison']) &&
          comparison(record['normalized_comparison']);
    case 'E08.guards':
      return [
            'unsupported_input',
            'unsupported_source',
            'reserved_marker',
          ].every(
            (key) =>
                record[key] is Map &&
                (record[key] as Map)['rejected'] == true &&
                (record[key] as Map)['error_type'] ==
                    'LlamaUnsupportedException',
          ) &&
          comparison(record['recovery']);
    case 'E09.cancel.before':
    case 'E10.cancel.after':
      final elapsed = record['cancel_ms'];
      return record['precondition_met'] == true &&
          record['in_flight'] == true &&
          record['dispatch_observed'] == (id == 'E10.cancel.after') &&
          record['cancelled'] == true &&
          record['error_type'] == 'LlamaInferenceException' &&
          elapsed is num &&
          elapsed.isFinite &&
          elapsed >= 0 &&
          elapsed <=
              (embeddingValidationFixture['cancel_deadline_ms'] as num) &&
          comparison(record['recovery']) &&
          comparison(record['media_recovery']);
    default:
      return false;
  }
}

/// Version-one structured-output prompts, schemas and grammars. Each
/// constrained request asks for output that an unconstrained model would not
/// produce, so conforming output is evidence that the constraint was applied.
const structuredOutputFixture = <String, Object>{
  'max_tokens': 256,
  'capabilities': {
    'native': {
      'grammar': true,
      'lazy_grammar': true,
      'structured_output': true,
    },
    'web': {'grammar': true, 'lazy_grammar': false, 'structured_output': true},
    'litert': {
      'grammar': false,
      'lazy_grammar': false,
      'structured_output': false,
    },
  },
  'json_object': {'prompt': 'Describe a red apple in one short sentence.'},
  'json_schema': {
    'prompt': 'Describe a fictional library member in one short sentence.',
    'schema': {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'minLength': 1, 'maxLength': 20},
        'age': {'type': 'integer', 'minimum': 18, 'maximum': 99},
        'rating': {'type': 'number'},
        'active': {'type': 'boolean'},
        'nickname': {'type': 'null'},
        'tier': {
          'enum': ['bronze', 'silver', 'gold'],
        },
        'address': {
          'type': 'object',
          'properties': {
            'city': {'type': 'string', 'minLength': 1, 'maxLength': 20},
            'zip': {'type': 'string', 'pattern': r'^[0-9]{5}$'},
          },
          'required': ['city', 'zip'],
          'additionalProperties': false,
        },
        'loans': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string', 'minLength': 1, 'maxLength': 20},
              'days': {'type': 'integer', 'minimum': 1, 'maximum': 30},
            },
            'required': ['title', 'days'],
            'additionalProperties': false,
          },
          'minItems': 1,
          'maxItems': 2,
        },
        'fines': {
          'type': 'array',
          'items': {'type': 'number'},
          'maxItems': 0,
        },
        'notes': {'type': 'string', 'maxLength': 0},
        'preferences': {
          'type': 'object',
          'properties': <String, Object>{},
          'additionalProperties': false,
        },
        'email': {'type': 'string', 'maxLength': 24},
      },
      'required': [
        'name',
        'age',
        'rating',
        'active',
        'nickname',
        'tier',
        'address',
        'loans',
        'fines',
        'notes',
        'preferences',
      ],
      'additionalProperties': false,
    },
  },
  'grammar': {
    'prompt': 'Write a short sentence about the sea.',
    'grammar': 'root ::= "cedar-" [0-9] [0-9] [0-9]',
    'regex': r'^cedar-[0-9]{3}$',
  },
  'lazy_grammar': {
    'prompt':
        'Write one sentence about the weather. Then, on a new line, write '
        'ANSWER: followed by your favorite color.',
    'trigger': 'ANSWER:',
    'grammar': 'root ::= "ANSWER: " ("alpha" | "omega")',
    'regex': r'ANSWER: (alpha|omega)$',
  },
  'reject': {
    'malformed_prompt': 'Write one short sentence about the sea.',
    'mismatch_prompt': 'Name a city.',
    'generated_schema': {
      'type': 'object',
      'properties': {
        'city': {'type': 'string', 'minLength': 1, 'maxLength': 20},
      },
      'required': ['city'],
      'additionalProperties': false,
    },
    'parsed_schema': {
      'type': 'object',
      'properties': {
        'zip_code': {'type': 'string'},
      },
      'required': ['zip_code'],
      'additionalProperties': false,
    },
    'unsupported_schema': {
      'type': 'object',
      'properties': {
        'count': {'type': 'integer', 'multipleOf': 3},
      },
      'required': ['count'],
    },
    'unsupported_response_format': {'type': 'yaml'},
    'malformed_message': 'Malformed structured JSON output.',
    'mismatch_message':
        'Structured JSON output did not match the requested schema.',
  },
  'tools': {
    'prompt': 'Call get_forecast for Montréal in fahrenheit for 30 days.',
    'name': 'get_forecast',
    'description': 'Return the forecast for a city.',
    'schema': {
      'type': 'object',
      'properties': {
        'city': {'type': 'string', 'minLength': 1, 'maxLength': 32},
        'unit': {
          'enum': ['celsius', 'kelvin'],
        },
        'days': {
          'type': 'integer',
          'enum': [1, 3, 7],
        },
      },
      'required': ['city', 'unit', 'days'],
      'additionalProperties': false,
    },
  },
};

/// Catalog-10 deterministic native capability predicate, independent of admission.
const nativeJsonSchemaCapabilityFixture = <String, Object>{
  'model_sha256':
      'c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108',
  'model_bytes': 613722264,
  'runtime_tag': 'v0.18.1-4',
  'os': 'macos',
  'abi': 'macos_arm64',
  'requested_backend': 'cpu',
  'actual_backend': 'litert-lm cpu',
  'excluded_family_model_sha256': [
    '1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be',
    '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
  ],
};

/// Selected by `structured_output` focus or release selection, from catalog 8.
const structuredOutputValidationCases = [
  ValidationCaseDefinition(
    'S01.capabilities',
    ['structured_output'],
    ['structured_output', 'native_json_schema_capability'],
    version: 2,
  ),
  ValidationCaseDefinition(
    'S02.json_object',
    ['structured_output'],
    ['structured_output'],
  ),
  ValidationCaseDefinition(
    'S03.json_schema',
    ['structured_output'],
    ['structured_output'],
  ),
  ValidationCaseDefinition(
    'S04.grammar',
    ['structured_output'],
    ['structured_output'],
  ),
  ValidationCaseDefinition(
    'S05.grammar.lazy',
    ['structured_output'],
    ['structured_output'],
  ),
  ValidationCaseDefinition(
    'S06.reject',
    ['structured_output'],
    ['structured_output', 'hello'],
  ),
  ValidationCaseDefinition(
    'S07.stream',
    ['structured_output'],
    ['structured_output'],
  ),
  ValidationCaseDefinition(
    'S08.tools.schema',
    ['structured_output'],
    ['structured_output'],
  ),
];

/// Fixed text corpus for public tokenization without injected special tokens.
/// Only a model's documented decoder prefix may vary in a locked profile.
const tokenizationFixture = <String, Object>{
  'inputs': [
    '',
    'Hello, world!',
    '  leading  and trailing  ',
    'line one\nline two\tend',
    'Montréal 👋\n한글 café',
    'e\u0301 café 中文 العربية',
  ],
  'expected_prefix': '',
};

/// Selected by tokenization focus or release selection from catalog 9.
const tokenizationValidationCases = [
  ValidationCaseDefinition('T01.roundtrip', ['tokenization'], ['tokenization']),
  ValidationCaseDefinition('T02.count', ['tokenization'], ['tokenization']),
];

/// Prompt-only KV fixture. This is not a sampler/RNG checkpoint oracle.
const statePersistenceFixture = <String, Object>{
  'prefix':
      'Once upon a time there was a little girl named Lily. Lily lived in a red house beside a forest. Every morning she visited her friend, a small brown rabbit. One day Lily found a shiny key under an old tree. She took the key home and opened',
  'suffix': ' the wooden box',
  'top_k': 16,
  'max_abs_logprob_delta': 0.01,
  'min_context_separation': 0.10,
  'batch_size': 8,
  'garbage': [110, 111, 116, 45, 115, 116, 97, 116, 101],
  'short_header_bytes': 7,
  'max_artifact_bytes': 16 * 1024 * 1024,
  'incompatible_version': 2147483647,
};

/// Public state obligations from catalog 11, with identity added in catalog 14.
const stateValidationCases = [
  ValidationCaseDefinition(
    'P01.capability',
    ['state_persistence'],
    ['state_persistence'],
  ),
  ValidationCaseDefinition(
    'P02.roundtrip',
    ['state_persistence'],
    ['state_persistence'],
  ),
  ValidationCaseDefinition(
    'P03.restore_reuse',
    ['state_persistence'],
    ['state_persistence'],
  ),
  ValidationCaseDefinition(
    'P04.invalid_recovery',
    ['state_persistence'],
    ['state_persistence'],
  ),
  ValidationCaseDefinition(
    'P05.identity',
    ['state_persistence'],
    ['state_persistence'],
  ),
];

/// Solid-color 128x128 RGB PNGs (red 220,20,20; blue 20,40,220) returned by a
/// tool, with the expected one-word color answers. Embedded as bytes so Web and
/// native runners send identical images without an encoder.
const toolResultMediaFixture = <String, Object>{
  'tool': 'take_photo',
  'tool_description': 'Takes a photo with the camera and returns it.',
  'call_id': 'call_0',
  'question':
      'Take a photo, then tell me the main color of the photo in one word.',
  'call_max_tokens': 128,
  'max_tokens': 48,
  'images': {
    'red': {
      'png_base64':
          'iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAIAAABMXPacAAAAyElEQVR42u3RQREAAAjDsImYf2WIQQY8clcFTabVYbEAAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAAcAEAAAEAIAAABACAAAAQAAACAEAAAAgAAAEAIAAABACAAAAQAAACAEAAAAgAAAEAIAAABACAAAAQAAACAEAAAAgAAAEAIAAABACAAAAQAAAC8KEFbK8D0NOAIb0AAAAASUVORK5CYII=',
      'sha256':
          '67a3791b2963b67d0d449feabd9bd556ab8fa7cbe4f5640246df264f89d8de0d',
    },
    'blue': {
      'png_base64':
          'iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAIAAABMXPacAAAAyUlEQVR42u3RQQ0AAAjEsBOBCPzrQQwy4NFkCtZUjw6LBQAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAAIALAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEAAAAgBAAAAIAAABACAAAAQAgAAAEIAPLZs3BBsTnE8NAAAAAElFTkSuQmCC',
      'sha256':
          '1599912d72d73c6e4d3cc0e70b265bfb045513ac8e2bde155e22553d3f4d3b32',
    },
  },
};

/// Selected by `tool_result_media` focus (or `tools` focus or release
/// selection) from catalog 12, only for a profile that locks a vision projector.
const toolResultMediaValidationCases = [
  ValidationCaseDefinition(
    'M01.tool_result_image',
    ['tools', 'tool_result_media'],
    ['tool_result_media'],
  ),
];

/// Prompts, ranks and tolerances for public next-token scoring. Scores are raw
/// softmax log-probabilities, so no sampler setting enters the oracle.
const nextTokenScoringFixture = <String, Object>{
  'prompts': [
    'Once upon a time there was a little girl named Lily. One day Lily found a shiny key under an old tree. She took the key home and opened',
    'The quick brown fox jumps over the lazy',
  ],
  'top_k': 8,
  'candidate_ranks': [0, 2, 5],
  'prefix':
      'Once upon a time there was a little girl named Lily. Lily lived in a red house beside a forest. Every morning she visited her friend, a small brown rabbit. One day Lily found a shiny key under an old tree. She took the key home and opened',
  'suffix': ' the wooden box',
  'max_abs_logprob_delta': 0.01,
  'max_probability_mass': 1.001,
};

/// Public scoring obligations introduced together in catalog 13.
const nextTokenScoringValidationCases = [
  ValidationCaseDefinition(
    'N01.capability',
    ['next_token_scoring'],
    ['next_token_scoring'],
  ),
  ValidationCaseDefinition(
    'N02.top_k',
    ['next_token_scoring'],
    ['next_token_scoring'],
  ),
  ValidationCaseDefinition(
    'N03.candidates',
    ['next_token_scoring'],
    ['next_token_scoring'],
  ),
  ValidationCaseDefinition(
    'N04.reuse',
    ['next_token_scoring'],
    ['next_token_scoring'],
  ),
  ValidationCaseDefinition(
    'N05.guards',
    ['next_token_scoring'],
    ['next_token_scoring'],
  ),
];

/// Greedy and seeded generation settings for the public sampler controls.
/// Every case decodes with top-K and top-P disabled, so only the control under
/// test differs from its greedy baseline.
const samplerControlsFixture = <String, Object>{
  'prompt':
      'Once upon a time, there was a little girl named Lily. She loved to play with her ball.',
  'max_tokens': 48,
  'seeds': [1, 2, 3, 4],
  'sampling_temperature': 1.5,
  'min_p': 1.0,
  'repeat_penalty': 1.5,
  'presence_penalty': 2.0,
  'repeat_ngram_words': 3,
  'budget_prompt': 'One day Lily wrote a secret note. <think>',
  'budget_max_tokens': 24,
  'budgets': [0, 4],
  'start_tag': '<think>',
  'end_tag': '</think>',
  'forced_message': 'Time is up.',
  'unsupported_min_p': 0.05,
};

/// Public sampler-control obligations introduced together in catalog 15.
const samplerControlValidationCases = [
  ValidationCaseDefinition(
    'G01.capability',
    ['sampler_controls'],
    ['sampler_controls'],
  ),
  ValidationCaseDefinition(
    'G02.min_p',
    ['sampler_controls'],
    ['sampler_controls'],
  ),
  ValidationCaseDefinition(
    'G03.repeat_penalty',
    ['sampler_controls'],
    ['sampler_controls'],
  ),
  ValidationCaseDefinition(
    'G04.presence_penalty',
    ['sampler_controls'],
    ['sampler_controls'],
  ),
  ValidationCaseDefinition(
    'G05.thinking_budget',
    ['sampler_controls'],
    ['sampler_controls'],
  ),
];
