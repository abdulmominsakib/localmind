import 'manifest.dart';

/// Rechecks a complete fixed corpus against the locked profile, including
/// token IDs and counts, rather than trusting producer pass flags.
bool validTokenizationCaseEvidence(
  String id,
  Map<String, dynamic> record,
  ValidationProfile profile,
) {
  if (id != 'T01.roundtrip' && id != 'T02.count') return false;
  final fixture = profile.fixtures['tokenization'] as Map;
  final inputs = fixture['inputs'] as List;
  final trials = record['trials'];
  if (trials is! List || trials.length != inputs.length) return false;
  for (var index = 0; index < inputs.length; index++) {
    final trial = trials[index];
    if (trial is! Map ||
        trial['input'] != inputs[index] ||
        trial['add_special'] != false) {
      return false;
    }
    final tokens = trial['tokens'];
    if (tokens is! List ||
        tokens.any((id) => id is! int || id < 0) ||
        (inputs[index] != '' && tokens.isEmpty)) {
      return false;
    }
    if (id == 'T02.count') {
      if (trial['count'] is! int || trial['count'] != tokens.length) {
        return false;
      }
    } else {
      final repeated = trial['repeated_tokens'];
      final input = inputs[index] as String;
      final expected = input.isEmpty
          ? ''
          : '${fixture['expected_prefix']}$input';
      if (repeated is! List ||
          repeated.length != tokens.length ||
          trial['special'] != false ||
          trial['decoded'] != expected) {
        return false;
      }
      for (var index = 0; index < tokens.length; index++) {
        if (repeated[index] is! int || repeated[index] != tokens[index]) {
          return false;
        }
      }
    }
  }
  return true;
}
