import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'manifest.dart';

const _stateModel =
    '61b50d457809a5194818fd22e6724b456cd7bb9a6264c52c8110684c53f3704a';

/// Independent backend oracle: excluded runtimes are distinct from unqualified
/// model/configuration/host combinations. Provider capability is never input.
bool? expectedStateCapability(
  ValidationProfile profile, {
  required bool web,
  required Map diagnostics,
}) {
  // Both LiteRT adapters explicitly deny state independently of model weights.
  if (profile.runtime == 'litert') {
    final name = diagnostics['backend_name'];
    return name is String && name.startsWith('LiteRT-LM ') ? false : null;
  }
  // Bridge v0.1.15+ can persist state; no Web build identity oracle is shipped here.
  if (web) return null;
  if (profile.runtime != 'gguf' ||
      profile.backend != 'cpu' ||
      profile.model['sha256'] != _stateModel ||
      profile.model['bytes'] != 98357920 ||
      profile.contextSize != 256 ||
      profile.threads != 4 ||
      !profile.focusFeatures.contains('state_persistence') ||
      diagnostics['backend_name'] != 'CPU' ||
      diagnostics['context_size'] != 256 ||
      diagnostics['reported_gpu_layers'] != 0) {
    return null;
  }
  return true;
}

/// Identity support is independent of persistence: Web can persist state while
/// lacking the native build identity required by this public API.
bool? expectedStateIdentityCapability(
  ValidationProfile profile, {
  required bool web,
  required Map diagnostics,
}) {
  if (web) return false;
  if (profile.runtime == 'litert') {
    final name = diagnostics['backend_name'];
    return name is String && name.startsWith('LiteRT-LM ') ? false : null;
  }
  return expectedStateCapability(profile, web: false, diagnostics: diagnostics);
}

bool _same(Object? left, Object? right) =>
    canonicalJson(left) == canonicalJson(right);
bool _tokens(Object? value) =>
    value is List &&
    value.isNotEmpty &&
    value.every((id) => id is int && id >= 0);
bool _digest(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
bool _scores(Object? value, List ids, int? length) {
  if (value is! Map ||
      value['prompt_tokens'] is! int ||
      (value['prompt_tokens'] as int) <= 0 ||
      (length != null && value['prompt_tokens'] != length)) {
    return false;
  }
  final rows = value['candidates'];
  if (rows is! List || rows.length != ids.length) return false;
  for (var i = 0; i < ids.length; i++) {
    final row = rows[i];
    if (row is! Map ||
        row['token'] != ids[i] ||
        row['logprob'] is! num ||
        !(row['logprob'] as num).isFinite ||
        (row['logprob'] as num) > 0) {
      return false;
    }
  }
  return true;
}

List<double> _values(List rows) => [
  for (final row in rows) ((row as Map)['logprob'] as num).toDouble(),
];
double _delta(List<double> left, List<double> right) {
  var result = 0.0;
  for (var i = 0; i < left.length; i++) {
    result = math.max(result, (left[i] - right[i]).abs());
  }
  return result;
}

/// Reconstructs the fixed state proof from raw observations. This detects
/// inconsistent journals; it is not attestation of a producer or native binary.
bool validStateCaseEvidence(
  String id,
  Map<String, dynamic> record,
  ValidationProfile profile, {
  required bool web,
  required Map diagnostics,
}) {
  if (record['web'] != web || !_same(record['diagnostics'], diagnostics)) {
    return false;
  }
  try {
    return _valid(id, record, profile);
  } on Object {
    return false;
  }
}

bool _valid(String id, Map<String, dynamic> record, ValidationProfile profile) {
  if (!const [
        'P01.capability',
        'P02.roundtrip',
        'P03.restore_reuse',
        'P04.invalid_recovery',
        'P05.identity',
      ].contains(id) ||
      record['web'] is! bool ||
      record['diagnostics'] is! Map) {
    return false;
  }
  if (id == 'P05.identity' &&
      expectedStateIdentityCapability(
            profile,
            web: record['web'] as bool,
            diagnostics: record['diagnostics'] as Map,
          ) ==
          false) {
    final recovery = record['recovery'];
    return record['identity_rejection'] == 'LlamaUnsupportedException' &&
        !record.containsKey('phases') &&
        !record.containsKey('identity') &&
        recovery is Map &&
        recovery['stream_completed'] == true &&
        recovery['content'] is String &&
        (recovery['content'] as String).isNotEmpty;
  }
  final expected = expectedStateCapability(
    profile,
    web: record['web'] as bool,
    diagnostics: record['diagnostics'] as Map,
  );
  if (expected == null || record['supported'] != expected) return false;
  if (id == 'P01.capability') {
    if (expected) return record['scoring'] == true;
    final recovery = record['recovery'];
    return record['save_rejection'] == 'LlamaUnsupportedException' &&
        record['load_rejection'] == 'LlamaUnsupportedException' &&
        recovery is Map &&
        recovery['stream_completed'] == true &&
        recovery['content'] is String &&
        (recovery['content'] as String).isNotEmpty;
  }
  if (!expected ||
      record['scoring'] != true ||
      record['model_sha256'] != profile.model['sha256'] ||
      record['config_hash'] != jsonHash(profile.effectiveConfig) ||
      record['workspace_disposed'] != true) {
    return false;
  }
  final phases = record['phases'];
  final roles = [
    'source',
    if (id == 'P02.roundtrip' || id == 'P05.identity')
      'roundtrip'
    else ...[
      'reference_full',
      'reference_suffix_only',
      'score_exact',
      'score_suffix',
      'generate_exact',
      'generate_suffix',
      'control_fresh',
      'control_reuse_disabled',
    ],
  ];
  const negatives = [
    'missing',
    'garbage',
    'short',
    'incompatible',
    'capacity_zero',
    'capacity_oversized',
    'capacity_small',
  ];
  if (id == 'P04.invalid_recovery') {
    for (final name in negatives) {
      roles.addAll([
        'negative_$name',
        'recovery_score_$name',
        'recovery_$name',
      ]);
    }
  }
  if (phases is! List || phases.length != roles.length) return false;
  for (var i = 0; i < phases.length; i++) {
    final phase = phases[i];
    if (phase is! Map ||
        phase['role'] != roles[i] ||
        phase['lifetime'] != i + 1 ||
        phase['disposed'] != true ||
        phase['model_sha256'] != record['model_sha256'] ||
        phase['config_hash'] != record['config_hash'] ||
        phase['diagnostics'] is! Map ||
        expectedStateCapability(
              profile,
              web: false,
              diagnostics: phase['diagnostics'] as Map,
            ) !=
            true) {
      return false;
    }
  }
  final source = phases.first as Map;
  final fixture = profile.fixtures['state_persistence'] as Map;
  final prefix = fixture['prefix'] as String;
  final suffix = fixture['suffix'] as String;
  final tokens = source['tokens'];
  final ids = record['candidates'];
  if (!_tokens(tokens) ||
      (tokens as List).length < 8 ||
      tokens.length >= profile.contextSize ||
      source['saved'] != true ||
      source['add_special'] != true ||
      source['reuse'] != false ||
      source['prompt'] != prefix ||
      ids is! List ||
      ids.length != fixture['top_k'] ||
      ids.any((v) => v is! int || v < 0) ||
      ids.toSet().length != ids.length) {
    return false;
  }
  final baseline = source['score'];
  if (baseline is! Map ||
      baseline['prompt_tokens'] != tokens.length ||
      !_same(baseline['candidates'], [])) {
    return false;
  }
  final top = baseline['top'];
  if (!_scores(
    {'prompt_tokens': tokens.length, 'candidates': top},
    ids,
    tokens.length,
  )) {
    return false;
  }
  final sourceValues = _values(top as List);
  for (var i = 1; i < sourceValues.length; i++) {
    if (sourceValues[i] > sourceValues[i - 1]) return false;
  }
  final artifact = record['artifact'];
  if (artifact is! Map ||
      artifact['role'] != 'valid' ||
      !_same(artifact['header'], [110, 115, 103, 103, 11, 0, 0, 0]) ||
      artifact['bytes'] is! int ||
      (artifact['bytes'] as int) <= tokens.length * 8 ||
      (artifact['bytes'] as int) > (fixture['max_artifact_bytes'] as int) ||
      !_digest(artifact['sha256'])) {
    return false;
  }
  bool loaded(Map row) =>
      row['capacity'] == profile.contextSize &&
      row['snapshot_sha256'] == artifact['sha256'] &&
      _same(row['loaded_tokens'], tokens);
  if (id == 'P02.roundtrip') return loaded(phases[1] as Map);
  if (id == 'P05.identity') {
    final restoredPhase = phases[1] as Map;
    bool validIdentity(Object? value) =>
        value is Map &&
        value['runtime_build'] is String &&
        (value['runtime_build'] as String).trim().isNotEmpty &&
        value['session_format_version'] == 11 &&
        value['context_size'] == profile.contextSize &&
        _digest(value['context_config_digest']);
    return loaded(restoredPhase) &&
        validIdentity(source['identity']) &&
        validIdentity(restoredPhase['identity_before_load']) &&
        validIdentity(restoredPhase['identity']) &&
        _same(source['identity'], restoredPhase['identity_before_load']) &&
        _same(source['identity'], restoredPhase['identity']);
  }
  final fullReference = phases[1] as Map;
  final fullTokens = fullReference['tokens'];
  if (!_tokens(fullTokens) ||
      (fullTokens as List).length >= profile.contextSize) {
    return false;
  }
  var common = 0;
  while (common < tokens.length &&
      common < fullTokens.length &&
      tokens[common] == fullTokens[common]) {
    common++;
  }
  if (common < 8 || fullTokens.length - common < 2) return false;
  bool score(Map row, String prompt, bool reuse, int? count) =>
      row['prompt'] == prompt &&
      row['reuse'] == reuse &&
      _scores(row['score'], ids, count);
  if (!score(fullReference, prefix + suffix, false, fullTokens.length) ||
      !score(phases[2] as Map, suffix, false, null) ||
      !loaded(phases[3] as Map) ||
      !score(phases[3] as Map, prefix, true, tokens.length) ||
      !loaded(phases[4] as Map) ||
      !score(phases[4] as Map, prefix + suffix, true, fullTokens.length)) {
    return false;
  }
  List<double> values(int i) =>
      _values(((phases[i] as Map)['score'] as Map)['candidates'] as List);
  if (_delta(sourceValues, values(3)) >
          (fixture['max_abs_logprob_delta'] as num) ||
      _delta(values(1), values(4)) >
          (fixture['max_abs_logprob_delta'] as num) ||
      _delta(values(1), values(2)) <
          (fixture['min_context_separation'] as num)) {
    return false;
  }
  bool generation(Map row, String prompt, bool reuse, int count, int cached) {
    final gen = row['generation'];
    if (row['prompt'] != prompt ||
        row['reuse'] != reuse ||
        gen is! Map ||
        gen['output'] is! String ||
        gen['observer_present'] != true ||
        gen['observer_error'] != null ||
        gen['observer_cancelled'] != false ||
        !const ['length', 'stop'].contains(gen['finish_reason']) ||
        gen['prompt_eval_tokens'] != count - cached) {
      return false;
    }
    final usage = gen['usage'];
    return usage is Map &&
        usage['prompt_tokens'] == count &&
        usage['completion_tokens'] is int &&
        (usage['completion_tokens'] as int) >= 0 &&
        (usage['completion_tokens'] as int) <= 1 &&
        usage['total_tokens'] == count + (usage['completion_tokens'] as int) &&
        usage['prompt_tokens_details'] is Map &&
        (usage['prompt_tokens_details'] as Map)['cached_tokens'] == cached;
  }

  if (!loaded(phases[5] as Map) ||
      !generation(
        phases[5] as Map,
        prefix,
        true,
        tokens.length,
        tokens.length - 1,
      ) ||
      !loaded(phases[6] as Map) ||
      !generation(
        phases[6] as Map,
        prefix + suffix,
        true,
        fullTokens.length,
        common,
      ) ||
      (phases[7] as Map).containsKey('loaded_tokens') ||
      !generation(
        phases[7] as Map,
        prefix + suffix,
        true,
        fullTokens.length,
        0,
      ) ||
      !loaded(phases[8] as Map) ||
      !generation(
        phases[8] as Map,
        prefix + suffix,
        false,
        fullTokens.length,
        0,
      )) {
    return false;
  }
  if (id == 'P03.restore_reuse') return true;
  final negativeArtifacts = record['negative_artifacts'];
  if (negativeArtifacts is! Map || negativeArtifacts.length != 3) return false;
  final garbage = negativeArtifacts['garbage'];
  final short = negativeArtifacts['short'];
  final incompatible = negativeArtifacts['incompatible'];
  final garbageBytes = (fixture['garbage'] as List).cast<int>();
  if (garbage is! Map ||
      garbage['bytes'] != garbageBytes.length ||
      garbage['sha256'] != sha256.convert(garbageBytes).toString() ||
      short is! Map ||
      short['bytes'] != fixture['short_header_bytes'] ||
      short['inline_bytes'] is! List ||
      (short['inline_bytes'] as List).length != fixture['short_header_bytes'] ||
      !_same(
        short['inline_bytes'],
        (artifact['header'] as List)
            .take(fixture['short_header_bytes'] as int)
            .toList(),
      ) ||
      short['sha256'] !=
          sha256
              .convert((short['inline_bytes'] as List).cast<int>())
              .toString() ||
      incompatible is! Map ||
      incompatible['bytes'] != artifact['bytes'] ||
      !_digest(incompatible['sha256']) ||
      incompatible['sha256'] == artifact['sha256'] ||
      incompatible['source_sha256'] != artifact['sha256'] ||
      incompatible['recipe'] != 'replace_le_u32_at_4' ||
      !_same(incompatible['header'], [
        110,
        115,
        103,
        103,
        255,
        255,
        255,
        127,
      ])) {
    return false;
  }
  for (var i = 0; i < negatives.length; i++) {
    final name = negatives[i];
    final negative = phases[9 + i * 3] as Map;
    final recovery = phases[11 + i * 3] as Map;
    final recoveredScore = phases[10 + i * 3] as Map;
    if (!loaded(recoveredScore) ||
        !score(recoveredScore, prefix + suffix, true, fullTokens.length) ||
        _delta(
              _values((recoveredScore['score'] as Map)['candidates'] as List),
              values(1),
            ) >
            (fixture['max_abs_logprob_delta'] as num)) {
      return false;
    }
    final capacity = name == 'capacity_zero'
        ? 0
        : name == 'capacity_oversized'
        ? profile.contextSize + 1
        : name == 'capacity_small'
        ? tokens.length - 1
        : profile.contextSize;
    final rejection = name == 'capacity_zero' || name == 'capacity_oversized'
        ? 'LlamaArgumentException'
        : 'LlamaStateException';
    if (negative['artifact_role'] !=
            (name.startsWith('capacity_') ? 'valid' : name) ||
        negative['capacity'] != capacity ||
        negative['rejection'] != rejection ||
        negative.containsKey('returned_tokens') ||
        !loaded(recovery) ||
        !generation(
          recovery,
          prefix + suffix,
          true,
          fullTokens.length,
          common,
        )) {
      return false;
    }
  }
  return true;
}
