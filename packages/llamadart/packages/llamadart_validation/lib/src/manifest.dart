import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

import 'case_catalog.dart';
import 'decision_catalog.dart';

/// Canonical encoding for stable experiment identity.
String canonicalJson(Object? value) {
  Object? ordered(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: ordered(value[key])};
    }
    if (value is List) return value.map(ordered).toList();
    return value;
  }

  return jsonEncode(ordered(value));
}

/// SHA256 identity of a JSON-compatible value.
Object? freezeJson(Object? value) => value is Map
    ? Map<String, dynamic>.unmodifiable(
        value.map((key, item) => MapEntry(key as String, freezeJson(item))),
      )
    : value is List
    ? List<dynamic>.unmodifiable(value.map(freezeJson))
    : value;

/// SHA256 identity of a JSON-compatible value.
String jsonHash(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

/// Locked model and inference selection shared by every host adapter.
class ValidationProfile {
  /// Validates an immutable model/profile manifest before use.
  ValidationProfile.fromJson(Map<String, dynamic> input)
    : data = freezeJson(jsonDecode(jsonEncode(input))) as Map<String, dynamic> {
    if (data['schema_version'] != 1) {
      throw const FormatException('Unsupported validation schema_version');
    }
    if (!RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(id)) {
      throw const FormatException('Invalid profile id');
    }
    if (!const ['gguf', 'litert'].contains(runtime)) {
      throw const FormatException('runtime must be gguf or litert');
    }
    final validBackends = runtime == 'litert'
        ? ['cpu', 'gpu', 'npu', 'auto']
        : [...GpuBackend.values.map((value) => value.name), 'webgpu'];
    if (!validBackends.contains(backend)) {
      throw FormatException('Invalid $runtime backend: $backend');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(modelHash) ||
        !RegExp(
          r'^[0-9a-f]{40}$',
        ).hasMatch(model['revision'] as String? ?? '')) {
      throw const FormatException(
        'Model requires SHA256 and immutable revision',
      );
    }
    final uri = Uri.parse(model['url'] as String);
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        !uri.path.contains('/${model['revision']}/')) {
      throw const FormatException('Use a public, immutable HTTPS model URL');
    }
    if (!filename.endsWith(runtime == 'gguf' ? '.gguf' : '.litertlm') ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(filename) ||
        (model['bytes'] as int) <= 0) {
      throw const FormatException('Invalid model filename, format or size');
    }
    if (!const [
      'raw',
      'chat',
      'decision',
      'embedding',
    ].contains(model['kind'])) {
      throw const FormatException(
        'Model kind must be raw, chat, decision or embedding',
      );
    }
    if (isDecision != data.containsKey('decision') ||
        (isDecision &&
            (runtime != 'gguf' ||
                selection != 'quick' ||
                data.containsKey('fixtures') ||
                data['history_controls'] == true ||
                data['execution_path'] == 'native_c_api'))) {
      throw const FormatException(
        'A decision model needs a decision head lock and a quick public GGUF '
        'profile without fixture overrides',
      );
    }
    if (isDecision) {
      final decision = data['decision'];
      if (decision is! Map ||
          decision.keys.any((key) => key != 'head' && key != 'config') ||
          !_isArtifact(decision['head'], '.safetensors') ||
          (decision.containsKey('config') &&
              !_isArtifact(decision['config'], '.json'))) {
        throw const FormatException(
          'Decision head and config need immutable HTTPS locks',
        );
      }
    }
    if (isEmbedding != data.containsKey('embedding') ||
        (isEmbedding &&
            (runtime != 'gguf' ||
                !['cpu', 'metal'].contains(backend) ||
                selection != 'quick' ||
                data.containsKey('fixtures') ||
                data['history_controls'] == true ||
                nativeReference ||
                contextSize != 2048 ||
                threads != 4))) {
      throw const FormatException(
        'Embedding pack requires a quick native CPU/Metal GGUF profile, context 2048, four threads and no overrides',
      );
    }
    if (isEmbedding) {
      final embedding = data['embedding'];
      if (embedding is! Map ||
          embedding.length != 2 ||
          embedding['case_timeout_ms'] is! int ||
          embedding['case_timeout_ms'] != 300000 ||
          !_isArtifact(embedding['projector'], '.gguf') ||
          embedding['projector']['revision'] != model['revision']) {
        throw const FormatException(
          'Embedding pack requires a matching immutable GGUF projector lock and case_timeout_ms 300000',
        );
      }
    }
    if (contextSize < 128 ||
        contextSize > 8192 ||
        maxTokens < 1 ||
        maxTokens > 512 ||
        threads < 1 ||
        threads > 32) {
      throw const FormatException('Profile exceeds bounded core limits');
    }
    final reloadTimeout = data['engine_create_case_timeout_ms'];
    if (data.containsKey('engine_create_case_timeout_ms') &&
        (reloadTimeout is! int ||
            reloadTimeout < 60000 ||
            reloadTimeout > 180000 ||
            runtime != 'litert' ||
            (backend != 'gpu' && backend != 'cpu'))) {
      throw const FormatException(
        'engine_create_case_timeout_ms requires a LiteRT CPU or GPU profile and an '
        'integer from 60000 to 180000',
      );
    }
    if (!const ['quick', 'focused', 'release'].contains(selection)) {
      throw const FormatException(
        'selection must be quick, focused or release',
      );
    }
    final focus = data['focus_features'] ?? const [];
    if (focus is! List ||
        focus.any((feature) => !validationFeatures.containsKey(feature)) ||
        focus.toSet().length != focus.length ||
        (selection != 'focused' && data.containsKey('focus_features')) ||
        (selection == 'focused') != focus.isNotEmpty) {
      throw const FormatException(
        'Only focused selection requires a nonempty unique focus_features list '
        'of catalog feature IDs',
      );
    }
    if (data.containsKey('projector') !=
            focusFeatures.contains('tool_result_media') ||
        (data.containsKey('projector') &&
            (runtime != 'gguf' ||
                !['cpu', 'metal'].contains(backend) ||
                !isChat ||
                nativeReference ||
                !_isArtifact(data['projector'], '.gguf') ||
                data['projector']['revision'] != model['revision']))) {
      throw const FormatException(
        'Tool-result media requires a native CPU/Metal GGUF chat profile with '
        'a matching immutable GGUF projector lock, and a projector lock '
        'requires the tool_result_media focus',
      );
    }
    final overrides = data['fixtures'];
    if (overrides != null &&
        (overrides is! Map ||
            overrides.entries.any(
              (entry) =>
                  !validationFixtures.containsKey(entry.key) ||
                  entry.value is! Map ||
                  (const {
                        'native_json_schema_capability',
                        'state_persistence',
                        'tool_result_media',
                        'next_token_scoring',
                        'sampler_controls',
                      }.contains(entry.key) &&
                      (entry.value as Map).isNotEmpty) ||
                  (entry.value as Map).entries.any(
                    (field) =>
                        !validationFixtures[entry.key]!.containsKey(
                          field.key,
                        ) ||
                        // Core overrides are synthetic text/predicate fixtures;
                        // tool/media schemas need their own qualified pack.
                        field.value is! String ||
                        validationFixtures[entry.key]![field.key] is! String,
                  ),
            ))) {
      throw const FormatException('Invalid core fixture override');
    }
    for (final key in ['enable_thinking', 'history_controls']) {
      if (data.containsKey(key) && data[key] is! bool) {
        throw FormatException('$key must be a boolean');
      }
    }
    if (data['history_controls'] == true &&
        (runtime != 'litert' || backend != 'cpu' || !isChat)) {
      throw const FormatException(
        'Optional history controls require a LiteRT CPU chat profile',
      );
    }
    if (!const [
          'public_api',
          'native_c_api',
        ].contains(data['execution_path'] ?? 'public_api') ||
        (nativeReference && backend != 'npu')) {
      throw const FormatException(
        'Native C API controls require an explicit NPU profile',
      );
    }
    if (nativeReference && !enableThinking) {
      throw const FormatException(
        'Native C API controls currently require thinking enabled',
      );
    }
  }

  /// JSON definition; callers receive a defensive copy through [toJson].
  final Map<String, dynamic> data;

  /// Stable profile identifier.
  String get id => data['id'] as String;

  /// Model format/runtime identity.
  String get runtime => data['runtime'] as String;

  /// Explicit runtime selector.
  String get backend => data['backend'] as String;

  /// Immutable model definition.
  Map<String, dynamic> get model => data['model'] as Map<String, dynamic>;

  /// Expected bytes SHA256.
  String get modelHash => model['sha256'] as String;

  /// Safe local model basename.
  String get filename => model['filename'] as String;

  /// Whether semantic chat cases apply.
  bool get isChat => model['kind'] == 'chat';

  /// Whether the model is a decision encoder that runs only decision cases.
  bool get isDecision => model['kind'] == 'decision';

  /// Whether this is a multimodal embedding-only pack.
  bool get isEmbedding => model['kind'] == 'embedding';

  /// Immutable matching projector definition.
  Map<String, dynamic> get embeddingProjector =>
      (data['embedding'] as Map)['projector'] as Map<String, dynamic>;

  /// Locked vision projector of a tool-result media profile, if any.
  Map<String, dynamic>? get toolResultProjector =>
      data['projector'] as Map<String, dynamic>?;

  /// Locked decision head and optional config, keyed `head` and `config`.
  Map<String, dynamic> get decisionArtifacts =>
      data['decision'] as Map<String, dynamic>? ?? const {};

  static bool _isArtifact(Object? value, String extension) {
    if (value is! Map ||
        value.keys.any(
          (key) =>
              !['filename', 'revision', 'sha256', 'bytes', 'url'].contains(key),
        )) {
      return false;
    }
    final filename = value['filename'];
    final revision = value['revision'];
    final url = value['url'];
    final bytes = value['bytes'];
    if (filename is! String ||
        revision is! String ||
        url is! String ||
        bytes is! int) {
      return false;
    }
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.path.endsWith('/$revision/$filename') &&
        RegExp(r'^[0-9a-f]{40}$').hasMatch(revision) &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch('${value['sha256']}') &&
        RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(filename) &&
        filename.endsWith(extension) &&
        bytes > 0;
  }

  /// Context token budget.
  int get contextSize => data['context_size'] as int? ?? 1024;

  /// Maximum generation length.
  int get maxTokens => data['max_tokens'] as int? ?? 32;

  /// Native inference threads.
  int get threads => data['threads'] as int? ?? 4;

  /// Deadline for cases that include an engine create, when overridden.
  Duration? get engineCreateCaseTimeout {
    final value = data['engine_create_case_timeout_ms'] as int?;
    return value == null ? null : Duration(milliseconds: value);
  }

  /// Locked phone-sized deadline for the embedding pack, including load.
  Duration? get embeddingCaseTimeout => isEmbedding
      ? Duration(
          milliseconds: (data['embedding'] as Map)['case_timeout_ms'] as int,
        )
      : null;

  /// Catalog selection; release includes explicit uncovered obligations.
  String get selection => data['selection'] as String? ?? 'quick';

  /// Canonical feature set used only by focused runs.
  List<String> get focusFeatures =>
      List<String>.from(data['focus_features'] as List? ?? const [])..sort();

  /// Separate direct-C-API controls from public-package qualification.
  bool get nativeReference => data['execution_path'] == 'native_c_api';

  /// Explicit model setting; preserves existing NPU and Qwen pilot defaults.
  bool get enableThinking =>
      data['enable_thinking'] as bool? ?? backend == 'npu';

  /// Adds the same seeded, literal-system, no-system and combined diagnostics.
  bool get historyControls =>
      nativeReference || data['history_controls'] == true;

  List<String> _quickCaseIds(int catalogVersion) => isEmbedding
      ? [
          'C01.load',
          for (final definition in embeddingValidationCases) definition.id,
        ]
      : isDecision
      ? [
          'C01.load',
          for (final definition in decisionValidationCases) definition.id,
        ]
      : [
          'C01.load',
          if (!nativeReference) ...['C02.unicode', 'C03.raw'],
          if (isChat) ...['C04.hello', 'C04.arithmetic'],
          if (isChat) 'C06.history',
          if (historyControls && isChat) ...[
            'C06.history.public_system_wire',
            'C06.history.no_system',
            'C06.history.combined',
          ],
          if (!nativeReference) 'C08.cancel',
          if (!nativeReference && catalogVersion >= 5) ...[
            'C08.cancel.early',
            if (runtime == 'gguf' || catalogVersion >= 7) ...[
              'C08.cancel.restart',
              'C08.overlap',
            ],
          ],
          'C09.reload',
          if (!nativeReference) ...[
            'C10.limit',
            if (catalogVersion >= 5 && runtime == 'gguf') 'C12.grammar',
            'C12.recovery',
          ],
          'B01.warmup',
          'B01.1',
          'B01.2',
          'B01.3',
        ];

  /// Original journal-v1 obligations, retained for existing report imports.
  List<String> get legacyCaseIds => [
    ..._quickCaseIds(1),
    if (selection == 'release') ...[
      'C05.thinking',
      'C07.tools',
      'C10.stop',
      'C11.batching',
      'C12.guards',
    ],
  ];

  /// Expanded obligations; a focused run adds relevant cases to the quick core.
  List<String> get caseIds => caseIdsForCatalog(validationCatalogVersion);

  /// Obligations that catalog [version] derived from this profile.
  List<String> caseIdsForCatalog(int version) => [
    ..._quickCaseIds(version),
    for (final definition in extendedValidationCases)
      if (catalogDeclaresCase(definition.id, version) &&
          _structuredOmission(definition.id) == null &&
          !(definition.id.startsWith('T') && nativeReference) &&
          _stateOmission(definition.id) == null &&
          _mediaOmission(definition.id) == null &&
          _scoringOmission(definition.id) == null &&
          _samplerOmission(definition.id) == null &&
          (selection == 'release' ||
              (selection == 'focused' &&
                  definition.features.any(focusFeatures.contains))))
        definition.id,
  ];

  /// Resolved synthetic fixtures, including explicit model-specific overrides.
  Map<String, dynamic> get fixtures {
    final overrides = data['fixtures'] as Map? ?? const {};
    return {
      for (final entry in validationFixtures.entries)
        entry.key: {...entry.value, ...?overrides[entry.key] as Map?},
      if (isDecision) 'decision': {...decisionValidationFixture},
      if (isEmbedding) 'embeddings': {...embeddingValidationFixture},
    };
  }

  Map<String, dynamic> _fixturesForVersion(int version) {
    final resolved = fixtures;
    if (version < 15) resolved.remove('sampler_controls');
    if (version < 13) resolved.remove('next_token_scoring');
    if (version < 12) resolved.remove('tool_result_media');
    if (version < 11) resolved.remove('state_persistence');
    if (version < 10) resolved.remove('native_json_schema_capability');
    if (version < 9) resolved.remove('tokenization');
    if (version < 8) resolved.remove('structured_output');
    if (version < 6) resolved.remove('inflight');
    if (version < 5) resolved.remove('invalid_grammar');
    if (version < 4) {
      final tools = resolved['tools'] as Map;
      final tool = tools['tool'] as Map;
      final function = tool['function'] as Map;
      resolved['tools'] = {
        ...tools,
        'tool': {
          ...tool,
          'function': {
            ...function,
            'parameters': {
              ...function['parameters'] as Map,
              'additionalProperties': false,
            },
          },
        },
      };
      resolved['unicode_generation'] = {
        ...resolved['unicode_generation'] as Map,
        'qualification':
            (data['fixtures']
                as Map?)?['unicode_generation']?['qualification'] ??
            'requires an exact-model reference before execution',
      };
    }
    return resolved;
  }

  /// Text read by the runner and included in the replay catalog.
  String fixtureText(String fixture, String field) =>
      (fixtures[fixture] as Map)[field] as String;

  /// The resolved fixtures whose identity is bound to one case record.
  Map<String, dynamic> caseFixtures(
    String id, {
    int catalogVersion = validationCatalogVersion,
  }) => {
    for (final key in validationCase(
      id,
      catalogVersion: catalogVersion,
    ).fixtures)
      key: _fixturesForVersion(catalogVersion)[key],
  };

  /// Current selected/omitted inventory with reproducible fixture contents.
  Map<String, dynamic> get catalog =>
      catalogForVersion(validationCatalogVersion);

  /// Reconstructs a supported historical catalog without inventing new evidence.
  Map<String, dynamic> catalogForVersion(int version) {
    validationCase('C11.batching', catalogVersion: version);
    if ((isDecision || isEmbedding) && version < 5) {
      throw const FormatException(
        'Decision and embedding cases require catalog version 5 or newer',
      );
    }
    if (version == 1 &&
        (focusFeatures.contains('batching') ||
            (data['fixtures'] as Map?)?.containsKey('batching') == true)) {
      throw const FormatException(
        'Batching selection requires catalog version 2',
      );
    }
    if (version < 15 &&
        (focusFeatures.contains('sampler_controls') ||
            (data['fixtures'] as Map?)?.containsKey('sampler_controls') ==
                true)) {
      throw const FormatException(
        'Sampler-control selection or fixture requires catalog version 15',
      );
    }
    if (version < 13 &&
        (focusFeatures.contains('next_token_scoring') ||
            (data['fixtures'] as Map?)?.containsKey('next_token_scoring') ==
                true)) {
      throw const FormatException(
        'Next-token scoring selection or fixture requires catalog version 13',
      );
    }
    if (version < 12 &&
        (focusFeatures.contains('tool_result_media') ||
            (data['fixtures'] as Map?)?.containsKey('tool_result_media') ==
                true)) {
      throw const FormatException(
        'Tool-result media selection or fixture requires catalog version 12',
      );
    }
    if (version < 11 &&
        (focusFeatures.contains('state_persistence') ||
            (data['fixtures'] as Map?)?.containsKey('state_persistence') ==
                true)) {
      throw const FormatException(
        'State selection or fixture requires catalog version 11',
      );
    }
    if (version < 9 &&
        (focusFeatures.contains('tokenization') ||
            (data['fixtures'] as Map?)?.containsKey('tokenization') == true)) {
      throw const FormatException(
        'Tokenization selection or fixture requires catalog version 9',
      );
    }
    if (version < 8 && focusFeatures.any(catalogEightFeatures.contains)) {
      throw const FormatException(
        'Structured-output selection requires catalog version 8',
      );
    }
    if (version < 6 &&
        (data['fixtures'] as Map?)?.containsKey('inflight') == true) {
      throw const FormatException(
        'In-flight fixture requires catalog version 6',
      );
    }
    if (version < 5 &&
        (data['fixtures'] as Map?)?.containsKey('invalid_grammar') == true) {
      throw const FormatException(
        'Invalid grammar fixture requires catalog version 5',
      );
    }
    final selected = caseIdsForCatalog(version);
    return {
      'version': version,
      'features': {
        for (final entry in validationFeatures.entries)
          if ((version != 1 || entry.key != 'batching') &&
              (version >= 8 || !catalogEightFeatures.contains(entry.key)) &&
              (version >= 9 || entry.key != 'tokenization') &&
              (version >= 11 || entry.key != 'state_persistence') &&
              (version >= 12 || entry.key != 'tool_result_media') &&
              (version >= 13 || entry.key != 'next_token_scoring') &&
              (version >= 15 || entry.key != 'sampler_controls'))
            entry.key: entry.value,
        if (isDecision) 'decision': 1,
        if (isEmbedding) 'embeddings': 1,
      },
      'selection': selection,
      'focus_features': focusFeatures,
      'fixtures': {
        for (final entry in _fixturesForVersion(version).entries)
          if ((version != 1 || entry.key != 'batching') &&
              (version >= 3 || entry.key != 'stop'))
            entry.key: entry.value,
      },
      'cases': [
        for (final definition in [
          ...validationCaseCatalog,
          if (isDecision) ...decisionValidationCases,
          if (isEmbedding) ...embeddingValidationCases,
        ])
          if (catalogDeclaresCase(definition.id, version))
            {
              ...validationCase(
                definition.id,
                catalogVersion: version,
              ).toJson(),
              'selected': selected.contains(definition.id),
              if (!selected.contains(definition.id))
                'omission_reason': _omissionReason(definition.id),
            },
      ],
    };
  }

  /// Why this profile cannot run structured-output case [id], or null.
  /// Runtimes without a constraint keep only the capability contract case.
  String? _structuredOmission(String id) {
    if (!id.startsWith('S')) return null;
    if (nativeReference) return 'outside_native_reference_scope';
    if (id == 'S01.capabilities') return null;
    if (runtime == 'litert') return 'litert_grammar_unsupported';
    if (backend == 'webgpu' && id == 'S05.grammar.lazy') {
      return 'webgpu_lazy_grammar_unsupported';
    }
    return null;
  }

  String? _stateOmission(String id) {
    if (!id.startsWith('P')) return null;
    if (nativeReference) return 'outside_native_reference_scope';
    if (id == 'P01.capability' || id == 'P05.identity') return null;
    if (runtime != 'gguf' || backend != 'cpu') {
      return 'outside_initial_native_cpu_state_scope';
    }
    return null;
  }

  String? _scoringOmission(String id) {
    if (!id.startsWith('N')) return null;
    if (nativeReference) return 'outside_native_reference_scope';
    if (id == 'N01.capability') return null;
    if (runtime != 'gguf' || backend != 'cpu') {
      return 'outside_initial_native_cpu_scoring_scope';
    }
    return null;
  }

  String? _samplerOmission(String id) {
    if (!id.startsWith('G')) return null;
    if (nativeReference) return 'outside_native_reference_scope';
    if (id == 'G01.capability') return null;
    if (runtime != 'gguf' || backend != 'cpu') {
      return 'outside_initial_native_cpu_sampler_scope';
    }
    return null;
  }

  /// Why this profile cannot run tool-result media case [id], or null.
  String? _mediaOmission(String id) {
    if (!id.startsWith('M')) return null;
    if (nativeReference) return 'outside_native_reference_scope';
    if (!data.containsKey('projector')) return 'no_vision_projector_locked';
    return null;
  }

  String _omissionReason(String id) {
    if (isDecision) return 'decision_model_has_no_text_generation';
    if (isEmbedding) return 'embedding_model_has_no_text_generation';
    final media = _mediaOmission(id);
    if (media != null) return media;
    final scoring = _scoringOmission(id);
    if (scoring != null) return scoring;
    final sampler = _samplerOmission(id);
    if (sampler != null) return sampler;
    final state = _stateOmission(id);
    if (state != null) return state;
    if (id.startsWith('T') && nativeReference) {
      return 'outside_native_reference_scope';
    }
    final structured = _structuredOmission(id);
    if (structured != null) return structured;
    if (id.startsWith('C06.history.') && !historyControls) {
      return 'history_controls_disabled';
    }
    if (!isChat && (id.startsWith('C04.') || id.startsWith('C06.'))) {
      return 'raw_model_has_no_chat_oracle';
    }
    if (nativeReference &&
        const [
          'C02.unicode',
          'C03.raw',
          'C08.cancel',
          'C08.cancel.early',
          'C08.cancel.restart',
          'C08.overlap',
          'C10.limit',
          'C12.grammar',
          'C12.recovery',
        ].contains(id)) {
      return 'outside_native_reference_scope';
    }
    if (runtime == 'litert' &&
        const ['C08.cancel.restart', 'C08.overlap'].contains(id)) {
      return 'litert_restart_contract_undefined';
    }
    if (runtime == 'litert' && id == 'C12.grammar') {
      return 'litert_grammar_unsupported';
    }
    return 'outside_selected_features';
  }

  /// Accelerator evidence is mandatory for an explicit accelerator selection.
  bool get requiresAcceleratorProof =>
      !['cpu', 'auto', 'blas'].contains(backend);

  /// NPU candidates require the installed Android host to verify the kit first.
  /// `webgpu` profiles run only on the [web] host, which runs decision
  /// profiles only on WebGPU.
  void requireRunnable({
    bool verifiedAndroidNpuHost = false,
    bool web = false,
  }) {
    if (backend == 'npu' && !verifiedAndroidNpuHost) {
      throw LlamaUnsupportedException(
        'NPU validation needs installed-app vendor packaging, SoC checks and '
        'per-generation execution proof. Use validation.dart npu-preflight '
        'to inspect the locked inputs without downloading or loading a model.',
      );
    }
    if (toolResultProjector != null && web) {
      throw LlamaUnsupportedException(
        'Tool-result media pack runs only on native desktop: the Web host '
        'does not prepare the locked vision projector.',
      );
    }
    if (isEmbedding && web) {
      throw LlamaUnsupportedException(
        'Embedding pack Web artifact/reference adapter is unqualified; keep Web NOT_RUN.',
      );
    }
    if (backend == 'webgpu' && !web) {
      throw LlamaUnsupportedException(
        'The webgpu backend runs only in the Web validation host.',
      );
    }
    if (web && isDecision && backend != 'webgpu') {
      throw LlamaUnsupportedException(
        'Web decision validation runs only on WebGPU: decision cases on the '
        'WASM CPU exceed the case deadline '
        '(doc/cross_platform_validation.md#decision-profiles). Use '
        'decision-gguf-webgpu.',
      );
    }
  }

  /// Configuration actually passed to the public model loader.
  ModelParams get loadParams {
    final device = runtime == 'litert'
        ? ComputeDevice.values.byName(backend)
        : ComputeDevice.auto;
    final gpuLayers = backend == 'cpu' ? 0 : ModelParams.maxGpuLayers;
    if (runtime == 'litert') {
      return LiteRtLmModelParams(
        contextSize: contextSize,
        device: device,
        gpuLayers: gpuLayers,
        preferredBackend: device == ComputeDevice.cpu
            ? GpuBackend.cpu
            : GpuBackend.auto,
        // LiteRT-LM rejects a thread count for any backend but CPU.
        numberOfThreads: device == ComputeDevice.cpu ? threads : 0,
      );
    }
    return LlamaCppModelParams(
      contextSize: contextSize,
      gpuLayers: gpuLayers,
      preferredBackend: backend == 'webgpu'
          ? GpuBackend.auto
          : GpuBackend.values.byName(backend),
      batchSize: isEmbedding
          ? 2048
          : focusFeatures.contains('state_persistence')
          ? 8
          : 0,
      microBatchSize: isEmbedding
          ? 2048
          : focusFeatures.contains('state_persistence')
          ? 8
          : 0,
      numberOfThreads: threads,
      numberOfThreadsBatch: threads,
    );
  }

  /// Requested sampler; NPU retains compiled runtime defaults instead.
  GenerationParams get generationParams => GenerationParams(
    maxTokens: maxTokens,
    temp: 0,
    seed: 1,
    topK: 40,
    topP: 0.9,
    minP: 0,
    penalty: 1.1,
    presencePenalty: 0,
    reusePromptPrefix: false,
  );

  /// Expanded options and explicit defaults for replay and cohort matching.
  Map<String, Object?> get effectiveConfig => {
    if (isEmbedding)
      'embedding_case_timeout_ms': embeddingCaseTimeout!.inMilliseconds,
    if (focusFeatures.contains('state_persistence')) ...{
      'state_batch_size': 8,
      'state_micro_batch_size': 8,
    },
    'context_size': contextSize,
    'threads': threads,
    'batch_threads': runtime == 'litert' ? 0 : threads,
    'backend': backend,
    'gpu_layers_hint': loadParams.gpuLayers,
    'max_tokens': maxTokens,
    'sampling_application': backend == 'npu'
        ? 'runtime_defaults_requested_sampler_not_applied'
        : 'requested_sampler',
    'effective_npu_sampler': null,
    'temperature': 0,
    'seed': 1,
    'top_k': 40,
    'top_p': 0.9,
    'min_p': 0,
    'repeat_penalty': 1.1,
    'presence_penalty': 0,
    'stop_sequences': <String>[],
    'enable_thinking': enableThinking,
    'execution_path': nativeReference ? 'native_c_api' : 'public_api',
    'reuse_prompt_prefix': false,
    'stream_batch_tokens': generationParams.streamBatchTokenThreshold,
    'stream_batch_bytes': generationParams.streamBatchByteThreshold,
    'speculative_decoding': false,
    'grammar': null,
    'thinking_budget': null,
    'activation_type': null,
    'prefill_chunk_size': null,
    'dispatch_dir': backend == 'npu' ? 'android.nativeLibraryDir' : null,
    'batch_size': isEmbedding ? 2048 : 0,
    'micro_batch_size': isEmbedding ? 2048 : 0,
    'flash_attention': 'auto',
    'cache_type_k': 'f16',
    'cache_type_v': 'f16',
    'kv_unified': null,
    'use_mmap': true,
    'use_mlock': false,
    'load_mtp': false,
    'split_mode': 'layer',
    'main_gpu': 0,
    'loras': <String>[],
    'max_parallel_sequences': 1,
    'speculative_rollback_token_max': 0,
    'rope_frequency_base': null,
    'rope_frequency_scale': null,
    'prefer_memory64': null,
    'parallel_file_section_loading': null,
    'runtime_defaults': 'resolved by the recorded runtime artifact',
    'native_log_level': 'info',
    'cache_behavior': 'fresh request; runtime cache unknown',
  };

  /// Detached serialized definition.
  Map<String, dynamic> toJson() =>
      jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
}
