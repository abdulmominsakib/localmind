import '../exceptions.dart';
import 'python_json.dart';

/// Kind of a [DecisionQuestion]: pick one, rate on a scale, or yes/no.
///
/// [name] is the wire `type`, and [index] is Laya's numeric question type.
enum DecisionQuestionType {
  /// Pick one label from a set of options.
  choice,

  /// Rate on ordered levels; the answer is the expected level.
  score,

  /// Yes or no ("noul", from Jev); the answer is the probability of true.
  noul,
}

/// A question with a typed answer (pick one, rate, or yes/no), asked about
/// a state, in Laya's `system_one` format.
///
/// Instructions are text, or a JSON-like value that becomes Laya's
/// `json.dumps(value)` text with `ensure_ascii=True`. Values in criteria,
/// levels and noul descriptions must be JSON-like too: `null`, [bool], [num],
/// [String], or a [List] or [Map] with [String] keys of JSON-like values. They
/// are deep-copied into unmodifiable collections.
sealed class DecisionQuestion {
  DecisionQuestion._(Object instructions)
    : instructions = _instructionText(instructions);

  /// Creates a pick-one question ([ChoiceQuestion]) over the labels of
  /// `criteria`.
  factory DecisionQuestion.choice(
    Object instructions, {
    required Map<String, Object?> criteria,
  }) = ChoiceQuestion;

  /// Creates a rating question ([ScoreQuestion]) on `levels`, lowest
  /// first.
  factory DecisionQuestion.score(
    Object instructions, {
    required List<Object?> levels,
  }) = ScoreQuestion;

  /// Creates a yes/no question ([NoulQuestion]): its answer is the
  /// probability that `instructions` is true.
  factory DecisionQuestion.noul(
    Object instructions, {
    Object? whenTrue,
    Object? whenFalse,
  }) = NoulQuestion;

  /// Parses the wire format `{"type", "instructions", "criteria"}`.
  ///
  /// Follows Laya: a list of choice labels becomes labels without
  /// descriptions, keeping the first of any duplicates, and non-string
  /// `instructions` become `json.dumps(value)` text with `ensure_ascii=True`.
  /// Stricter than Laya: score `criteria` must be a list and noul `criteria`
  /// `null` or a map, where Laya also takes other shapes, such as a map of
  /// score levels or an empty list for noul.
  ///
  /// Throws [LlamaDecisionException] for a malformed question.
  factory DecisionQuestion.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type != 'choice' && type != 'score' && type != 'noul') {
      throw LlamaDecisionException(
        'Decision question "type" must be "choice", "score" or "noul", '
        'got $type.',
      );
    }
    if (!json.containsKey('instructions')) {
      throw LlamaDecisionException(
        'Decision question is missing "instructions".',
      );
    }
    final instructions = _instructionText(json['instructions']);
    final criteria = json['criteria'];
    return switch (type) {
      'choice' => ChoiceQuestion(
        instructions,
        criteria: _choiceCriteriaFromJson(criteria),
      ),
      'score' => ScoreQuestion(
        instructions,
        levels: criteria is List
            ? criteria
            : throw LlamaDecisionException(
                'A score question needs "criteria" as a list of levels.',
              ),
      ),
      _ => _noulFromJson(instructions, criteria),
    };
  }

  /// The question text the model reads, Laya's `instructions`.
  final String instructions;

  /// Kind of this question.
  DecisionQuestionType get type;

  /// Number of options the model scores: labels, levels, or 2 for yes/no.
  int get optionCount;

  /// Converts this question to the wire format.
  Map<String, Object?> toJson();
}

/// A pick-one question: the answer is the most probable label of
/// [criteria].
final class ChoiceQuestion extends DecisionQuestion {
  /// Creates a choice question over the labels of [criteria].
  ///
  /// A `null` or empty-string value means the label has no description.
  /// Throws [LlamaDecisionException] when [criteria] is empty, or when
  /// [instructions] or a value is not JSON-like.
  ChoiceQuestion(super.instructions, {required Map<String, Object?> criteria})
    : criteria = _frozenCriteria(criteria),
      super._();

  /// The options ("criteria"): each label mapped to its description, in
  /// option order.
  final Map<String, Object?> criteria;

  @override
  DecisionQuestionType get type => DecisionQuestionType.choice;

  @override
  int get optionCount => criteria.length;

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'instructions': instructions,
    'criteria': criteria,
  };
}

/// A rating question: the answer places the state on ordered [levels].
final class ScoreQuestion extends DecisionQuestion {
  /// Creates a score question with [levels] from lowest to highest.
  ///
  /// Throws [LlamaDecisionException] when [levels] is empty, or when
  /// [instructions] or a level is not JSON-like.
  ScoreQuestion(super.instructions, {required List<Object?> levels})
    : levels = _frozenLevels(levels),
      super._();

  /// Level descriptions from level 0 upward, sent as `criteria`.
  final List<Object?> levels;

  @override
  DecisionQuestionType get type => DecisionQuestionType.score;

  @override
  int get optionCount => levels.length;

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'instructions': instructions,
    'criteria': levels,
  };
}

/// A yes/no question, Jev's "noul": the answer is the probability that the
/// statement in [instructions] is true.
final class NoulQuestion extends DecisionQuestion {
  /// Creates a yes/no question with optional descriptions of each answer.
  ///
  /// A `null` or empty-string description uses Laya's default text. Throws
  /// [LlamaDecisionException] when [instructions] or a description is not
  /// JSON-like.
  NoulQuestion(super.instructions, {Object? whenTrue, Object? whenFalse})
    : whenTrue = _frozenJson(whenTrue, 'whenTrue'),
      whenFalse = _frozenJson(whenFalse, 'whenFalse'),
      super._();

  /// Description of the true answer, sent as `criteria.true`.
  final Object? whenTrue;

  /// Description of the false answer, sent as `criteria.false`.
  final Object? whenFalse;

  @override
  DecisionQuestionType get type => DecisionQuestionType.noul;

  @override
  int get optionCount => 2;

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'instructions': instructions,
    if (whenTrue != null || whenFalse != null)
      'criteria': {'true': ?whenTrue, 'false': ?whenFalse},
  };
}

/// The input to judge (the "state") and the questions to answer about it.
final class DecisionRequest {
  /// Creates a request.
  ///
  /// [state] is text, or a JSON-like value sent as
  /// `json.dumps(state, ensure_ascii=False)` text. Throws
  /// [LlamaDecisionException] when [questions] is empty, a question id is
  /// empty, or [state] is not JSON-like.
  DecisionRequest({
    required Object? state,
    required Map<String, DecisionQuestion> questions,
  }) : state = _frozenJson(state, 'state'),
       questions = _frozenQuestions(questions);

  /// The text or JSON-like value the questions are about, Laya's `state`.
  final Object? state;

  /// Questions by id, in answer order.
  final Map<String, DecisionQuestion> questions;
}

Map<String, DecisionQuestion> _frozenQuestions(
  Map<String, DecisionQuestion> questions,
) {
  if (questions.isEmpty) {
    throw LlamaDecisionException(
      'A decision request needs at least one question.',
    );
  }
  if (questions.containsKey('')) {
    throw LlamaDecisionException('Decision question ids must be non-empty.');
  }
  return Map.unmodifiable(questions);
}

Map<String, Object?> _frozenCriteria(Map<String, Object?> criteria) {
  if (criteria.isEmpty) {
    throw LlamaDecisionException(
      'A choice question needs at least one option in criteria.',
    );
  }
  return Map.unmodifiable({
    for (final MapEntry(:key, value: description) in criteria.entries)
      key: _frozenJson(description, 'criteria["$key"]'),
  });
}

List<Object?> _frozenLevels(List<Object?> levels) {
  if (levels.isEmpty) {
    throw LlamaDecisionException('A score question needs at least one level.');
  }
  return List.unmodifiable([
    for (var i = 0; i < levels.length; i++)
      _frozenJson(levels[i], 'levels[$i]'),
  ]);
}

Map<String, Object?> _choiceCriteriaFromJson(Object? criteria) {
  final labels = <String, Object?>{};
  if (criteria is List) {
    for (final label in criteria) {
      if (label is! String) {
        throw LlamaDecisionException(
          'Choice labels in a "criteria" list must be strings, got $label.',
        );
      }
      labels[label] = null;
    }
    return labels;
  }
  if (criteria is Map) {
    for (final MapEntry(:key, value: description) in criteria.entries) {
      if (key is! String) {
        throw LlamaDecisionException(
          'Choice "criteria" keys must be strings, got $key.',
        );
      }
      labels[key] = description;
    }
    return labels;
  }
  throw LlamaDecisionException(
    'A choice question needs "criteria" as a map of labels to descriptions '
    'or a list of labels.',
  );
}

NoulQuestion _noulFromJson(String instructions, Object? criteria) {
  if (criteria == null) return NoulQuestion(instructions);
  if (criteria is! Map) {
    throw LlamaDecisionException(
      'A noul question "criteria" must be a map with optional "true" and '
      '"false" descriptions.',
    );
  }
  return NoulQuestion(
    instructions,
    whenTrue: criteria['true'],
    whenFalse: criteria['false'],
  );
}

String _instructionText(Object? instructions) => switch (instructions) {
  final String text => text,
  final other => pythonJsonDumps(
    _frozenJson(other, 'instructions'),
    ensureAscii: true,
  ),
};

Object? _frozenJson(Object? value, String path) =>
    _freeze(value, path, Set<Object>.identity());

Object? _freeze(Object? value, String path, Set<Object> open) {
  switch (value) {
    case null || bool() || num() || String():
      return value;
    case List() || Map() when !open.add(value):
      throw LlamaDecisionException('$path contains itself.');
    case List():
      final copy = List<Object?>.unmodifiable([
        for (var i = 0; i < value.length; i++)
          _freeze(value[i], '$path[$i]', open),
      ]);
      open.remove(value);
      return copy;
    case Map():
      final copy = <String, Object?>{};
      for (final MapEntry(:key, value: item) in value.entries) {
        if (key is! String) {
          throw LlamaDecisionException(
            '$path has the non-string key $key; JSON-like maps need String '
            'keys.',
          );
        }
        copy[key] = _freeze(item, '$path["$key"]', open);
      }
      open.remove(value);
      return Map.unmodifiable(copy);
  }
  throw LlamaDecisionException(
    '$path must be JSON-like (null, bool, num, String, List, or Map with '
    'String keys), got ${value.runtimeType}.',
  );
}
