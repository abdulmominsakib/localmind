part of 'runner.dart';

/// Public token count, separate from adapters that expose only a reference
/// tokenizer. Computing the length in this adapter would bypass the API case.
abstract interface class TokenCountValidationEngine {
  /// Calls the public engine count API without deriving a count locally.
  Future<int> getTokenCount(String text);
}

extension _TokenizationValidation on ValidationRunner {
  Future<Map<String, dynamic>> _tokenizationCase(String id) async {
    final counter = engine;
    if (id == 'T02.count' && counter is! TokenCountValidationEngine) {
      return {
        'status': 'NOT_RUN',
        'reason': 'Adapter does not expose public getTokenCount',
      };
    }
    final fixture = profile.fixtures['tokenization'] as Map;
    final trials = <Map<String, dynamic>>[];
    _partialCaseEvidence = {'trials': trials};
    for (final input in (fixture['inputs'] as List).cast<String>()) {
      final trial = <String, dynamic>{'input': input, 'add_special': false};
      trials.add(trial);
      _operationPhase = 'tokenization.tokenize';
      final tokens = await _checked(() => engine.tokenize(input));
      // Preserve the first result if a backend reuses a mutable output buffer.
      trial['tokens'] = List<int>.of(tokens);
      if (id == 'T01.roundtrip') {
        _operationPhase = 'tokenization.repeat';
        trial['repeated_tokens'] = List<int>.of(
          await _checked(() => engine.tokenize(input)),
        );
        _operationPhase = 'tokenization.detokenize';
        trial['special'] = false;
        trial['decoded'] = await _checked(() => engine.detokenize(tokens));
      } else {
        _operationPhase = 'tokenization.getTokenCount';
        trial['count'] = await _checked(
          () => (counter as TokenCountValidationEngine).getTokenCount(input),
        );
      }
    }
    final evidence = <String, dynamic>{'trials': trials};
    return {
      ...evidence,
      'status': validTokenizationCaseEvidence(id, evidence, profile)
          ? 'PASS'
          : 'FAIL',
    };
  }
}
