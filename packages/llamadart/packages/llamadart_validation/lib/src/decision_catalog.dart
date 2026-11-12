import 'case_catalog.dart';

/// Laya 0.3.5 parity reference and the tolerances of the decision E2E tests
/// (`DecisionParity` in `test/support/decision_fixture.dart`). Bound into every
/// decision case record; decision profiles have no overrides.
const decisionValidationFixture = <String, Object>{
  'reference': 'assets/decision/laya_0_3_5_reference.json',
  'reference_sha256':
      '5db4092aa428d1568dc4705bc0776c0218e261a045baf7292f996ac788a6169d',
  'rows': 24,
  'logit_tolerance': 0.25,
  'probability_tolerance': 0.05,
  'score_tolerance': 0.1,
  'model': 'laya-rl-agent',
};

/// Decision cases, selected only by decision profiles after `C01.load`.
const decisionValidationCases = [
  ValidationCaseDefinition('D01.head', ['decision'], ['decision']),
  ValidationCaseDefinition('D02.tokenizer', ['decision'], ['decision']),
  ValidationCaseDefinition('D03.logits', ['decision'], ['decision']),
  ValidationCaseDefinition('D04.answers', ['decision'], ['decision']),
  ValidationCaseDefinition('D05.batch', ['decision'], ['decision']),
  ValidationCaseDefinition(
    'D06.reload',
    ['decision', 'lifecycle'],
    ['decision'],
  ),
  ValidationCaseDefinition('D07.guards', ['decision', 'guards'], ['decision']),
];

/// Successful head loads per case. Each creates an encoder context with its
/// own compute buffer, which the GGUF placement check counts.
const decisionHeadContexts = {'D01.head': 1, 'D03.logits': 1, 'D06.reload': 2};
