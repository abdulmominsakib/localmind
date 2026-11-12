import 'manifest.dart';

const _samplerModel =
    '61b50d457809a5194818fd22e6724b456cd7bb9a6264c52c8110684c53f3704a';

/// The reported flags in the order G01 records them.
const samplerCapabilityFlags = [
  'penalty',
  'presence_penalty',
  'min_p',
  'thinking_budget',
];

/// Independent backend oracle; provider capability is never an input. The
/// sealed native CPU profile applies every control. LiteRT-LM rejects Min-P on
/// every bundle, while its penalty and budget support depend on the runtime
/// and bundle, so those flags are recorded but not asserted (null).
Map<String, bool?>? expectedSamplerCapabilities(
  ValidationProfile profile, {
  required bool web,
  required Map diagnostics,
}) {
  if (profile.runtime == 'litert') {
    final name = diagnostics['backend_name'];
    return !web && name is String && name.startsWith('LiteRT-LM ')
        ? const {
            'penalty': null,
            'presence_penalty': null,
            'min_p': false,
            'thinking_budget': null,
          }
        : null;
  }
  if (web ||
      profile.runtime != 'gguf' ||
      profile.backend != 'cpu' ||
      profile.model['sha256'] != _samplerModel ||
      profile.model['bytes'] != 98357920 ||
      profile.contextSize != 256 ||
      profile.threads != 2 ||
      !profile.focusFeatures.contains('sampler_controls') ||
      diagnostics['backend_name'] != 'CPU' ||
      diagnostics['context_size'] != 256 ||
      diagnostics['reported_gpu_layers'] != 0) {
    return null;
  }
  return const {
    'penalty': true,
    'presence_penalty': true,
    'min_p': true,
    'thinking_budget': true,
  };
}

/// Occurrences of whitespace-separated word [n]-grams beyond each one's first.
int repeatedWordNgrams(String text, int n) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final seen = <String>{};
  var repeats = 0;
  for (var i = 0; i + n <= words.length; i++) {
    if (!seen.add(words.sublist(i, i + n).join(' '))) repeats++;
  }
  return repeats;
}

bool _text(Object? value) => value is String && value.isNotEmpty;

/// Reconstructs the sampler-control proof from raw observations. This detects
/// inconsistent journals; it is not attestation of a producer or native binary.
bool validSamplerCaseEvidence(
  String id,
  Map<String, dynamic> record,
  ValidationProfile profile, {
  required bool web,
  required Map diagnostics,
}) {
  if (record['web'] != web ||
      canonicalJson(record['diagnostics']) != canonicalJson(diagnostics)) {
    return false;
  }
  try {
    return _valid(id, record, profile);
  } on Object {
    return false;
  }
}

bool _valid(String id, Map<String, dynamic> record, ValidationProfile profile) {
  final expected = expectedSamplerCapabilities(
    profile,
    web: record['web'] as bool,
    diagnostics: record['diagnostics'] as Map,
  );
  final reported = record['reported'];
  if (expected == null ||
      reported is! Map ||
      reported.length != samplerCapabilityFlags.length ||
      samplerCapabilityFlags.any(
        (flag) =>
            reported[flag] is! bool ||
            (expected[flag] != null && reported[flag] != expected[flag]),
      )) {
    return false;
  }
  if (id == 'G01.capability') {
    final unsupported = [
      for (final flag in samplerCapabilityFlags)
        if (expected[flag] == false) flag,
    ];
    final rejections = record['rejections'];
    if (rejections is! Map ||
        canonicalJson(rejections) !=
            canonicalJson({
              for (final flag in unsupported) flag: 'LlamaUnsupportedException',
            })) {
      return false;
    }
    if (unsupported.isEmpty) return !record.containsKey('recovery');
    final recovery = record['recovery'];
    return recovery is Map &&
        recovery['stream_completed'] == true &&
        _text(recovery['content']);
  }
  if (!const [
        'G02.min_p',
        'G03.repeat_penalty',
        'G04.presence_penalty',
        'G05.thinking_budget',
      ].contains(id) ||
      expected.values.any((flag) => flag != true) ||
      record['model_sha256'] != profile.model['sha256'] ||
      record['config_hash'] != jsonHash(profile.effectiveConfig)) {
    return false;
  }
  final fixture = profile.fixtures['sampler_controls'] as Map;
  switch (id) {
    case 'G02.min_p':
      final greedy = record['greedy'];
      final filtered = record['filtered'];
      final control = record['control'];
      final seeds = fixture['seeds'] as List;
      return _text(greedy) &&
          canonicalJson(record['seeds']) == canonicalJson(seeds) &&
          filtered is List &&
          control is List &&
          filtered.length == seeds.length &&
          control.length == seeds.length &&
          filtered.every((output) => output == greedy) &&
          control.every(_text) &&
          control.any((output) => output != greedy);
    case 'G03.repeat_penalty' || 'G04.presence_penalty':
      final baseline = record['baseline'];
      final penalized = record['penalized'];
      final n = fixture['repeat_ngram_words'] as int;
      return _text(baseline) &&
          _text(penalized) &&
          record['repeat'] == penalized &&
          penalized != baseline &&
          repeatedWordNgrams(penalized as String, n) <
              repeatedWordNgrams(baseline as String, n);
    default:
      final endTag = fixture['end_tag'] as String;
      final forced = '${(fixture['forced_message'] as String).trim()}$endTag';
      final free = record['free'];
      final trials = record['trials'];
      final budgets = fixture['budgets'] as List;
      if (!_text(free) ||
          (free as String).contains(endTag) ||
          trials is! List ||
          trials.length != budgets.length) {
        return false;
      }
      for (var i = 0; i < budgets.length; i++) {
        final trial = trials[i];
        if (trial is! Map || trial['budget'] != budgets[i]) return false;
        final prefix = trial['prefix'];
        final output = trial['output'];
        if (prefix is! String ||
            (budgets[i] == 0) != prefix.isEmpty ||
            !free.startsWith(prefix) ||
            output is! String ||
            !output.startsWith(prefix) ||
            !output.substring(prefix.length).trimLeft().startsWith(forced)) {
          return false;
        }
      }
      final rejection = record['untagged_rejection'];
      return (rejection == 'ArgumentError' ||
              rejection == 'LlamaInferenceException') &&
          record['recovery'] == (trials.last as Map)['output'];
  }
}

/// Whether every passing case that decoded the shared prompt greedily (the
/// G02 greedy run and the G03/G04 baselines) saw the same text. Each case is
/// self-consistent alone, so only this catches one fabricated baseline.
bool samplerBaselinesAgree(Iterable<Map<String, dynamic>> passedRecords) {
  final baselines = {
    for (final record in passedRecords)
      switch (record['case_id']) {
        'G02.min_p' => record['greedy'],
        'G03.repeat_penalty' || 'G04.presence_penalty' => record['baseline'],
        _ => null,
      },
  }..remove(null);
  return baselines.length <= 1;
}
