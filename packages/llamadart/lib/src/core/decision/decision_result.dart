import '../exceptions.dart';
import 'decision_question.dart';

/// The model's answer to one [DecisionQuestion].
///
/// Values are unrounded; Laya rounds its JSON to 4 decimals.
sealed class DecisionAnswer {
  DecisionAnswer._({required this.confidence, required this.actProbability});

  /// Kind of the question this answers.
  DecisionQuestionType get type;

  /// How sure the model is of this answer, from 0 (unsure) to 1 (certain).
  ///
  /// For choice and score answers it is one minus the entropy of the
  /// probabilities over its maximum; for yes/no answers, `max(noul,
  /// 1 - noul)`. Gate on it before acting on an answer.
  final double confidence;

  /// Laya's action signal (`action.act_probability`): the probability of the
  /// act head's first action.
  ///
  /// Laya documents that it carries no usable signal yet; gate on
  /// [confidence] instead.
  final double actProbability;

  /// Converts this answer to Laya's response format.
  Map<String, Object?> toJson();

  Map<String, Object?> get _action => {'act_probability': actProbability};
}

/// Pick-one answer to a [ChoiceQuestion]: the chosen label and the
/// probability of each.
final class ChoiceAnswer extends DecisionAnswer {
  /// Creates a choice answer.
  ChoiceAnswer({
    required this.choice,
    required Map<String, double> probabilities,
    required super.confidence,
    required super.actProbability,
  }) : probabilities = Map.unmodifiable(probabilities),
       super._();

  /// The most probable label.
  final String choice;

  /// Probability of each label, in option order.
  final Map<String, double> probabilities;

  @override
  DecisionQuestionType get type => DecisionQuestionType.choice;

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'choice': choice,
    'probabilities': probabilities,
    'confidence': confidence,
    'action': _action,
  };
}

/// Rating answer to a [ScoreQuestion]: the expected level and the
/// probability of each.
final class ScoreAnswer extends DecisionAnswer {
  /// Creates a score answer.
  ScoreAnswer({
    required this.score,
    required Map<String, Object?> legend,
    required Map<String, double> probabilities,
    required super.confidence,
    required super.actProbability,
  }) : legend = Map.unmodifiable(legend),
       probabilities = Map.unmodifiable(probabilities),
       super._();

  /// The rating: the expected level, the probability-weighted mean of the
  /// level indices, so it can fall between levels.
  final double score;

  /// The level descriptions ("legend") keyed `'0'`, `'1'`, and so on.
  final Map<String, Object?> legend;

  /// Probability of each level, keyed like [legend].
  final Map<String, double> probabilities;

  /// Probability of each level, indexed by level, in an unmodifiable list.
  ///
  /// Reads [probabilities] under the keys `'0'` to `'K-1'`, where K is its
  /// length, as the decision engine returns them. Throws
  /// [LlamaDecisionException] when [probabilities] has other keys, as a
  /// hand-built answer can.
  List<double> get levelProbabilities => List.unmodifiable([
    for (var i = 0; i < probabilities.length; i++)
      probabilities['$i'] ??
          (throw LlamaDecisionException(
            'Score probabilities are keyed ${probabilities.keys.toList()}, '
            'not by level 0 to ${probabilities.length - 1}.',
          )),
  ]);

  @override
  DecisionQuestionType get type => DecisionQuestionType.score;

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'score': score,
    'legend': legend,
    'probabilities': probabilities,
    'confidence': confidence,
    'action': _action,
  };
}

/// Yes/no answer to a [NoulQuestion]: the probability that its statement is
/// true.
final class NoulAnswer extends DecisionAnswer {
  /// Creates a yes/no answer.
  NoulAnswer({
    required this.noul,
    required super.confidence,
    required super.actProbability,
  }) : super._();

  /// Yes/no probability: how likely the statement is true, from 0 to 1
  /// (Jev's "noul").
  final double noul;

  @override
  DecisionQuestionType get type => DecisionQuestionType.noul;

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'noul': noul,
    'confidence': confidence,
    'action': _action,
  };
}

/// Token usage of a decision call.
class DecisionUsage {
  /// Creates a usage record.
  const DecisionUsage({required this.inputTokens, required this.outputTokens});

  /// Tokens across all encoded sequences.
  final int inputTokens;

  /// Generated tokens; decision models generate none.
  final int outputTokens;

  /// Converts this record to Laya's `usage` format.
  Map<String, Object?> toJson() => {
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
  };
}

/// Answers to the questions of one [DecisionRequest], by question id.
class DecisionResult {
  /// Creates a result.
  ///
  /// [questions] are the questions that [answers] answer. The decision engine
  /// always sets them; a result built without them, such as a test fake or a
  /// copy of [model], [answers] and [usage] alone, has none.
  DecisionResult({
    required this.model,
    required Map<String, DecisionAnswer> answers,
    required this.usage,
    Map<String, DecisionQuestion>? questions,
  }) : answers = Map.unmodifiable(answers),
       questions = questions == null ? null : Map.unmodifiable(questions);

  /// Model name reported in the response.
  final String model;

  /// Answers by question id, in question order.
  final Map<String, DecisionAnswer> answers;

  /// Token usage.
  final DecisionUsage usage;

  /// The questions asked, by id, or `null` when not known.
  ///
  /// A typed key read checks that the question under the key's id is the
  /// key's own question object. Without [questions] it checks only the
  /// answer: its kind, and its option labels or level keys.
  final Map<String, DecisionQuestion>? questions;

  /// The pick-one answers ([ChoiceAnswer]s) in [answers], in question
  /// order.
  Map<String, ChoiceAnswer> get choices => _answersOf<ChoiceAnswer>();

  /// The rating answers ([ScoreAnswer]s) in [answers], in question order.
  Map<String, ScoreAnswer> get scores => _answersOf<ScoreAnswer>();

  /// The yes/no answers ([NoulAnswer]s) in [answers], in question order.
  Map<String, NoulAnswer> get nouls => _answersOf<NoulAnswer>();

  /// Converts this result to Laya's `{model, answers, usage}` response format.
  Map<String, Object?> toJson() => {
    'model': model,
    'answers': {
      for (final MapEntry(:key, :value) in answers.entries) key: value.toJson(),
    },
    'usage': usage.toJson(),
  };

  Map<String, T> _answersOf<T extends DecisionAnswer>() => Map.unmodifiable({
    for (final MapEntry(:key, :value) in answers.entries)
      if (value is T) key: value,
  });
}
