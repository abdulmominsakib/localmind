import 'dart:math' as math;

import 'manifest.dart';

const _scoringModel =
    '61b50d457809a5194818fd22e6724b456cd7bb9a6264c52c8110684c53f3704a';

/// Independent backend oracle: LiteRT-LM denies scoring regardless of weights;
/// only the sealed native CPU model is expected to support it. Provider
/// capability is never an input.
bool? expectedScoringCapability(
  ValidationProfile profile, {
  required bool web,
  required Map diagnostics,
}) {
  if (profile.runtime == 'litert') {
    final name = diagnostics['backend_name'];
    return name is String && name.startsWith('LiteRT-LM ') ? false : null;
  }
  if (web) return null;
  if (profile.runtime != 'gguf' ||
      profile.backend != 'cpu' ||
      profile.model['sha256'] != _scoringModel ||
      profile.model['bytes'] != 98357920 ||
      profile.contextSize != 256 ||
      profile.threads != 4 ||
      !profile.focusFeatures.contains('next_token_scoring') ||
      diagnostics['backend_name'] != 'CPU' ||
      diagnostics['context_size'] != 256 ||
      diagnostics['reported_gpu_layers'] != 0) {
    return null;
  }
  return true;
}

bool _same(Object? left, Object? right) =>
    canonicalJson(left) == canonicalJson(right);

List<Map>? _rows(Object? value) {
  if (value is! List) return null;
  final rows = <Map>[];
  for (final row in value) {
    if (row is! Map ||
        row['token'] is! int ||
        (row['token'] as int) < 0 ||
        row['logprob'] is! num ||
        !(row['logprob'] as num).isFinite ||
        (row['logprob'] as num) > 0) {
      return null;
    }
    rows.add(row);
  }
  return rows;
}

double _logprob(Map row) => (row['logprob'] as num).toDouble();

/// A well-formed result: bounded, sorted, distinct top tokens and a prompt
/// token count that matches the independently tokenized prompt.
List<Map>? _top(
  Object? score,
  int expectedCount,
  int promptTokens,
  num maxMass,
) {
  if (score is! Map || score['prompt_tokens'] != promptTokens) return null;
  final top = _rows(score['top']);
  if (top == null || top.length != expectedCount) return null;
  var mass = 0.0;
  for (var i = 0; i < top.length; i++) {
    if (i > 0 && _logprob(top[i]) > _logprob(top[i - 1])) return null;
    mass += math.exp(_logprob(top[i]));
  }
  if (mass > maxMass ||
      top.map((row) => row['token']).toSet().length != top.length) {
    return null;
  }
  return top;
}

List<Map>? _candidates(Object? score, List<int> ids) {
  if (score is! Map) return null;
  final rows = _rows(score['candidates']);
  if (rows == null || !_same([for (final row in rows) row['token']], ids)) {
    return null;
  }
  return rows;
}

double _delta(List<Map> left, List<Map> right) {
  var result = 0.0;
  for (var i = 0; i < left.length; i++) {
    result = math.max(result, (_logprob(left[i]) - _logprob(right[i])).abs());
  }
  return result;
}

List<int> _ids(List<Map> rows) => [for (final row in rows) row['token'] as int];

/// Smallest non-negative token ID that is absent from [top].
int scoringOutsider(List<int> top) {
  var id = 0;
  while (top.contains(id)) {
    id++;
  }
  return id;
}

/// Reconstructs the scoring proof from raw observations. This detects
/// inconsistent journals; it is not attestation of a producer or native binary.
bool validScoringCaseEvidence(
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
        'N01.capability',
        'N02.top_k',
        'N03.candidates',
        'N04.reuse',
        'N05.guards',
      ].contains(id) ||
      record['web'] is! bool ||
      record['diagnostics'] is! Map) {
    return false;
  }
  final expected = expectedScoringCapability(
    profile,
    web: record['web'] as bool,
    diagnostics: record['diagnostics'] as Map,
  );
  if (expected == null || record['supported'] != expected) return false;
  if (id == 'N01.capability') {
    if (expected) return true;
    final recovery = record['recovery'];
    return record['rejection'] == 'LlamaUnsupportedException' &&
        recovery is Map &&
        recovery['stream_completed'] == true &&
        recovery['content'] is String &&
        (recovery['content'] as String).isNotEmpty;
  }
  if (!expected ||
      record['model_sha256'] != profile.model['sha256'] ||
      record['config_hash'] != jsonHash(profile.effectiveConfig)) {
    return false;
  }
  final fixture = profile.fixtures['next_token_scoring'] as Map;
  final topK = fixture['top_k'] as int;
  final prompts = (fixture['prompts'] as List).cast<String>();
  final tolerance = fixture['max_abs_logprob_delta'] as num;
  final ranks = (fixture['candidate_ranks'] as List).cast<int>();
  final maxMass = fixture['max_probability_mass'] as num;
  bool tokens(Object? value, int limit) =>
      value is List &&
      value.length >= 8 &&
      value.length < limit &&
      value.every((token) => token is int && token >= 0);
  switch (id) {
    case 'N02.top_k':
      final trials = record['trials'];
      if (trials is! List || trials.length != prompts.length) return false;
      for (var i = 0; i < prompts.length; i++) {
        final trial = trials[i];
        if (trial is! Map ||
            trial['prompt'] != prompts[i] ||
            !tokens(trial['tokens'], profile.contextSize)) {
          return false;
        }
        final count = (trial['tokens'] as List).length;
        final first = _top(trial['first'], topK, count, maxMass);
        final repeat = _top(trial['repeat'], topK, count, maxMass);
        if (first == null ||
            repeat == null ||
            !_same(_ids(first), _ids(repeat)) ||
            _delta(first, repeat) > tolerance ||
            !_same((trial['first'] as Map)['candidates'], const []) ||
            !_same((trial['repeat'] as Map)['candidates'], const [])) {
          return false;
        }
      }
      return true;
    case 'N03.candidates':
      if (!tokens(record['tokens'], profile.contextSize) ||
          record['prompt'] != prompts.first) {
        return false;
      }
      final count = (record['tokens'] as List).length;
      final base = _top(record['baseline'], topK, count, maxMass);
      if (base == null) return false;
      final topIds = _ids(base);
      final ids = [
        for (final rank in ranks) topIds[rank],
        scoringOutsider(topIds),
      ];
      if (!_same(record['candidate_ids'], ids)) return false;
      final only = record['candidates_only'];
      final combined = record['combined'];
      final onlyRows = _candidates(only, ids);
      final combinedRows = _candidates(combined, ids);
      final combinedTop = _top(combined, topK, count, maxMass);
      if (onlyRows == null ||
          combinedRows == null ||
          only is! Map ||
          only['prompt_tokens'] != count ||
          !_same(only['top'], const []) ||
          combinedTop == null ||
          !_same(_ids(combinedTop), topIds) ||
          _delta(combinedTop, base) > tolerance) {
        return false;
      }
      for (final rows in [onlyRows, combinedRows]) {
        for (var i = 0; i < ranks.length; i++) {
          if ((_logprob(rows[i]) - _logprob(base[ranks[i]])).abs() >
              tolerance) {
            return false;
          }
        }
        if (_logprob(rows.last) > _logprob(base.last)) return false;
      }
      return _delta(onlyRows, combinedRows) <= tolerance;
    case 'N04.reuse':
      final prefix = record['prefix_tokens'];
      final full = record['full_tokens'];
      if (record['prefix'] != fixture['prefix'] ||
          record['full'] != '${fixture['prefix']}${fixture['suffix']}' ||
          !tokens(prefix, profile.contextSize) ||
          !tokens(full, profile.contextSize)) {
        return false;
      }
      var common = 0;
      while (common < (prefix as List).length &&
          common < (full as List).length &&
          prefix[common] == full[common]) {
        common++;
      }
      if (common < 8 || full.length - common < 2) return false;
      final fresh = _top(record['fresh'], topK, full.length, maxMass);
      if (fresh == null ||
          _top(record['prime'], topK, prefix.length, maxMass) == null) {
        return false;
      }
      final reused = _candidates(record['reused'], _ids(fresh));
      return reused != null &&
          (record['reused'] as Map)['prompt_tokens'] == full.length &&
          _delta(reused, fresh) <= tolerance;
    default:
      final count = record['tokens'];
      if (!tokens(count, profile.contextSize) ||
          record['prompt'] != prompts.first) {
        return false;
      }
      final length = (count as List).length;
      final base = _top(record['baseline'], topK, length, maxMass);
      final recovery = _top(record['recovery'], topK, length, maxMass);
      final rejections = record['rejections'];
      return base != null &&
          recovery != null &&
          _same(_ids(base), _ids(recovery)) &&
          _delta(base, recovery) <= tolerance &&
          rejections is Map &&
          _same(rejections, {
            for (final name in const [
              'empty_prompt',
              'negative_candidate',
              'negative_top_k',
              'no_selection',
            ])
              name: 'ArgumentError',
          });
  }
}

/// Whether every passing case that scored the first fixture prompt fresh
/// (N02 trial 0, the N03 and N05 baselines) saw the same tokens and scores.
/// Each case is self-consistent alone, so this catches consistently permuted
/// token IDs that no single case can.
bool scoringFreshPromptsAgree(
  Iterable<Map<String, dynamic>> passedRecords,
  ValidationProfile profile,
) {
  try {
    final fixture = profile.fixtures['next_token_scoring'] as Map;
    final tolerance = fixture['max_abs_logprob_delta'] as num;
    final views = <({List tokens, List<Map> top})>[];
    for (final record in passedRecords) {
      switch (record['case_id']) {
        case 'N02.top_k':
          final source = (record['trials'] as List).first as Map;
          views.add((
            tokens: source['tokens'] as List,
            top: _rows((source['first'] as Map)['top'])!,
          ));
        case 'N03.candidates' || 'N05.guards':
          views.add((
            tokens: record['tokens'] as List,
            top: _rows((record['baseline'] as Map)['top'])!,
          ));
      }
    }
    for (final view in views.skip(1)) {
      final first = views.first;
      if (!_same(view.tokens, first.tokens) ||
          !_same(_ids(view.top), _ids(first.top)) ||
          _delta(view.top, first.top) > tolerance) {
        return false;
      }
    }
    return true;
  } on Object {
    return false;
  }
}
