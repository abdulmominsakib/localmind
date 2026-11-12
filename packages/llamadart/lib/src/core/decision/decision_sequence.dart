import 'dart:math' as math;

import '../exceptions.dart';
import 'decision_question.dart';
import 'python_json.dart';

/// Token ids and limits for building decision sequences.
class DecisionSequenceSpec {
  /// Creates a spec.
  const DecisionSequenceSpec({
    required this.clsToken,
    required this.sepToken,
    required this.maskToken,
    required this.maskText,
    this.maxTokens = 512,
    this.headMaxTokens = 192,
  });

  /// Sequence start token id.
  final int clsToken;

  /// Separator token id.
  final int sepToken;

  /// Option marker token id.
  final int maskToken;

  /// Mask token text, replaced by a space in instruction, option and state
  /// text.
  final String maskText;

  /// Maximum sequence length, Laya's `max_len`.
  final int maxTokens;

  /// Token budget for the question text and options, Laya's `head_max_len`.
  final int headMaxTokens;
}

/// Token ids of one question's sequence and the positions of its option
/// markers.
class DecisionSequence {
  /// Creates a sequence.
  const DecisionSequence({required this.tokens, required this.markers});

  /// Token ids.
  final List<int> tokens;

  /// Index in [tokens] of each option's marker, in option order.
  final List<int> markers;
}

/// Option texts of [question] in option order, as Laya's `render_options`.
List<String> renderDecisionOptions(DecisionQuestion question) {
  switch (question) {
    case ChoiceQuestion(:final criteria):
      return [
        for (final MapEntry(:key, :value) in criteria.entries)
          value == null || value == '' ? key : '$key: ${_criterion(value)}',
      ];
    case ScoreQuestion(:final levels):
      return [
        for (var i = 0; i < levels.length; i++)
          'level $i: ${_criterion(levels[i])}',
      ];
    case NoulQuestion(:final whenTrue, :final whenFalse):
      return [
        'false: ${_criterionOr(whenFalse, 'no, the statement does not hold')}',
        'true: ${_criterionOr(whenTrue, 'yes, the statement holds')}',
      ];
  }
}

/// Tokenizer input for the head of [question]:
/// `<type> question: <instructions>`.
String decisionHeadText(DecisionQuestion question, DecisionSequenceSpec spec) =>
    '${question.type.name} question: '
    '${_unmasked(question.instructions, spec)}';

/// Tokenizer inputs for the options of [question] in option order, each with
/// a leading space.
List<String> decisionOptionTexts(
  DecisionQuestion question,
  DecisionSequenceSpec spec,
) => [
  for (final option in renderDecisionOptions(question))
    ' ${_unmasked(option, spec)}',
];

/// Tokenizer input for [state]: text as is, anything else as
/// `json.dumps(state, ensure_ascii=False)`.
String decisionStateText(Object? state, DecisionSequenceSpec spec) =>
    _unmasked(state is String ? state : pythonJsonDumps(state), spec);

/// Assembles one question's sequence from tokenized pieces, as Laya's
/// `build_sequence`.
///
/// The layout is `[CLS] head [SEP] ([MASK] option)... [SEP] state [SEP]`.
/// Each option keeps its marker and first 48 tokens. When the options leave
/// fewer than 16 of [DecisionSequenceSpec.headMaxTokens] tokens, each option,
/// marker included, is cut to `max(4, (headMaxTokens - 16) ~/ K)`. The head
/// keeps `max(8, remaining budget)` tokens and the state fills the rest. The
/// result is cut to [DecisionSequenceSpec.maxTokens], dropping markers past
/// it.
DecisionSequence assembleDecisionSequence({
  required List<int> headTokens,
  required List<List<int>> optionTokens,
  required List<int> stateTokens,
  required DecisionSequenceSpec spec,
}) {
  var options = [
    for (final tokens in optionTokens) [spec.maskToken, ...tokens.take(48)],
  ];
  var budget = spec.headMaxTokens - _totalLength(options);
  if (budget < 16) {
    final perOption = math.max(
      4,
      (spec.headMaxTokens - 16) ~/ math.max(1, options.length),
    );
    options = [for (final option in options) option.take(perOption).toList()];
    budget = spec.headMaxTokens - _totalLength(options);
  }

  final tokens = [
    spec.clsToken,
    ...headTokens.take(math.max(8, budget)),
    spec.sepToken,
  ];
  final markers = <int>[];
  for (final option in options) {
    markers.add(tokens.length);
    tokens.addAll(option);
  }
  tokens.add(spec.sepToken);
  final room = math.max(0, spec.maxTokens - tokens.length - 1);
  tokens
    ..addAll(stateTokens.take(room))
    ..add(spec.sepToken);

  return DecisionSequence(
    tokens: tokens.take(spec.maxTokens).toList(),
    markers: [
      for (final marker in markers)
        if (marker < spec.maxTokens) marker,
    ],
  );
}

/// Builds one sequence per question of [request], in question order.
///
/// Throws [LlamaDecisionException] when a question's option markers do not
/// all fit in [DecisionSequenceSpec.maxTokens].
Future<List<DecisionSequence>> buildDecisionSequences(
  DecisionRequest request,
  DecisionSequenceSpec spec,
  Future<List<int>> Function(String text) tokenize,
) async {
  final stateTokens = await tokenize(decisionStateText(request.state, spec));
  final sequences = <DecisionSequence>[];
  for (final MapEntry(key: id, value: question) in request.questions.entries) {
    final sequence = assembleDecisionSequence(
      headTokens: await tokenize(decisionHeadText(question, spec)),
      optionTokens: [
        for (final text in decisionOptionTexts(question, spec))
          await tokenize(text),
      ],
      stateTokens: stateTokens,
      spec: spec,
    );
    if (sequence.markers.length < question.optionCount) {
      throw LlamaDecisionException(
        'Decision question "$id" options exceed '
        'head_max_len=${spec.headMaxTokens}: only ${sequence.markers.length} '
        'of ${question.optionCount} option markers fit in '
        '${spec.maxTokens} tokens. Use fewer options.',
      );
    }
    sequences.add(sequence);
  }
  return sequences;
}

String _unmasked(String text, DecisionSequenceSpec spec) =>
    text.replaceAll(spec.maskText, ' ');

String _criterion(Object? value) =>
    value is String ? value : pythonJsonDumps(value);

String _criterionOr(Object? value, String fallback) =>
    value == null || value == '' ? fallback : _criterion(value);

int _totalLength(List<List<int>> lists) =>
    lists.fold(0, (total, list) => total + list.length);
