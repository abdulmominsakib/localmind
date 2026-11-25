import '../exceptions.dart';
import 'decision_question.dart';
import 'decision_result.dart';

/// A question with its id, typed by what reading its answer gives: [R].
///
/// Build a request's questions with [questionsOf] and read each answer with
/// [DecisionResultKeys.answerOf]:
///
/// ```dart
/// enum Department { billing, technical, other }
///
/// final department = ChoiceKey.enumOf(
///   'department',
///   'Which department should handle this request?',
///   criteria: {
///     Department.billing: 'invoices, payments, refunds',
///     Department.technical: 'bugs, outages, system errors',
///     Department.other: null,
///   },
/// );
/// final urgency = ScoreKey.of(
///   'urgency',
///   'How urgent is this request?',
///   levels: ['not urgent', 'soon', 'critical'],
/// );
///
/// final result = await decisions.systemOne(
///   state: 'We were billed twice for March.',
///   questions: DecisionKey.questionsOf([department, urgency]),
/// );
/// final Department route = result.answerOf(department).value;
/// final double level = result.answerOf(urgency).score;
/// ```
///
/// Read a result with the key object whose [question] built its request.
/// When the result records its [DecisionResult.questions], as every result of
/// the decision engine does, a read checks that the question under [id] is
/// this key's [question] object, not an equal one. A key built again (for
/// example by a getter), a question parsed back from JSON, and a result sent
/// to another isolate without its keys do not match; send the keys and the
/// result in one message, or read the result before sending it. Keys that wrap
/// one shared question object match each other's results, so give each key
/// its own question when their values differ.
sealed class DecisionKey<R extends Object?> {
  DecisionKey._(this.id);

  /// Question id; the key of the question and of its answer.
  final String id;

  /// The question asked under [id].
  DecisionQuestion get question;

  R _readFrom(DecisionResult result) {
    final asked = result.questions;
    if (asked != null && !identical(asked[id], question)) {
      throw LlamaDecisionException(
        asked.containsKey(id)
            ? 'Result question "$id" is not this key\'s question object. Read '
                  'each result with the key whose question built its request; '
                  'a rebuilt, JSON-parsed or copied question does not match.'
            : 'This result has no question "$id".',
      );
    }
    final answer = result.answers[id];
    if (answer == null) {
      throw LlamaDecisionException('This result has no answer "$id".');
    }
    return _read(answer);
  }

  R _read(DecisionAnswer answer);

  /// The questions of [keys] by id, in order, in an unmodifiable map.
  ///
  /// Throws [LlamaDecisionException] when an id is used more than once.
  static Map<String, DecisionQuestion> questionsOf(
    Iterable<DecisionKey<Object?>> keys,
  ) {
    final questions = <String, DecisionQuestion>{};
    for (final key in keys) {
      if (questions.containsKey(key.id)) {
        throw LlamaDecisionException(
          'The decision key id "${key.id}" is used more than once.',
        );
      }
      questions[key.id] = key.question;
    }
    return Map.unmodifiable(questions);
  }
}

/// Typed reads of a [DecisionResult] through [DecisionKey]s.
extension DecisionResultKeys on DecisionResult {
  /// The answer to [key]'s question, typed by the key.
  ///
  /// Throws [LlamaDecisionException] when [DecisionResult.questions] is known
  /// and has no question under the key's id, or one that is not the key's
  /// question object; when there is no answer under that id; when the answer
  /// is of another kind than the key's question; or when its option labels
  /// or level keys differ from the question's.
  R answerOf<R extends Object?>(DecisionKey<R> key) => key._readFrom(this);
}

/// Key of a pick-one question ([ChoiceQuestion]) whose options stand for
/// values of type [T].
///
/// Reading it gives a [ChoiceOf] with the chosen option's value.
final class ChoiceKey<T extends Object?> extends DecisionKey<ChoiceOf<T>> {
  /// Creates a key for [question], with [value] giving the value of each
  /// option label.
  ///
  /// [value] runs once per label, in option order, while the key is built,
  /// and an error it throws propagates. For a question parsed from JSON,
  /// `value: Department.values.byName` gives enum values and throws
  /// [ArgumentError] for a label that names none.
  ChoiceKey(super.id, this.question, {required T Function(String label) value})
    : values = Map.unmodifiable({
        for (final label in question.criteria.keys) label: value(label),
      }),
      super._();

  /// Creates a key for a choice over [options], in list order.
  ///
  /// [label] gives the text the model sees for each option from its value and
  /// position, and [describe] its description; without [describe], options
  /// have none. Equal values stay separate options. Throws
  /// [LlamaDecisionException] when [options] is empty, two options share a
  /// label, or [instructions] or a description is not JSON-like.
  factory ChoiceKey.of(
    String id,
    Object instructions, {
    required List<T> options,
    required String Function(T value, int index) label,
    Object? Function(T value)? describe,
  }) {
    if (options.isEmpty) {
      throw LlamaDecisionException('A choice key needs at least one option.');
    }
    final criteria = <String, Object?>{};
    final values = <String, T>{};
    for (final (i, option) in options.indexed) {
      final text = label(option, i);
      if (values.containsKey(text)) {
        throw LlamaDecisionException(
          'Two choice options share the label "$text"; labels must be unique.',
        );
      }
      criteria[text] = describe?.call(option);
      values[text] = option;
    }
    return ChoiceKey(
      id,
      ChoiceQuestion(instructions, criteria: criteria),
      value: (text) => values[text] as T,
    );
  }

  /// Creates a key whose values are the option labels of [criteria].
  ///
  /// Throws like [ChoiceQuestion.new].
  static ChoiceKey<String> labels(
    String id,
    Object instructions, {
    required Map<String, Object?> criteria,
  }) => ChoiceKey(
    id,
    ChoiceQuestion(instructions, criteria: criteria),
    value: (label) => label,
  );

  /// Creates a key over the enum values of [criteria], in map order, each
  /// described by its map value.
  ///
  /// The model sees [label] of each value, or else its [Enum.name]. [E] is
  /// inferred from the keys of [criteria], and values of more than one enum
  /// type make it a shared supertype such as [Enum], with no diagnostic.
  /// Write the type argument, as in `ChoiceKey.enumOf<Department>(...)`, to
  /// make a value of another type a compile error. Throws like
  /// [ChoiceKey.of].
  static ChoiceKey<E> enumOf<E extends Enum>(
    String id,
    Object instructions, {
    required Map<E, Object?> criteria,
    String Function(E value)? label,
  }) => ChoiceKey.of(
    id,
    instructions,
    options: criteria.keys.toList(),
    label: (value, _) => label?.call(value) ?? value.name,
    describe: (value) => criteria[value],
  );

  @override
  final ChoiceQuestion question;

  /// The value of each option label, in option order.
  final Map<String, T> values;

  @override
  ChoiceOf<T> _read(DecisionAnswer answer) {
    if (answer is! ChoiceAnswer) {
      throw LlamaDecisionException(
        'Answer "$id" is a ${answer.type.name} answer, not a choice answer.',
      );
    }
    if (answer.probabilities.length != values.length) {
      throw LlamaDecisionException(
        'Answer "$id" has ${answer.probabilities.length} options; this key\'s '
        'question has ${values.length}.',
      );
    }
    for (final label in [answer.choice, ...answer.probabilities.keys]) {
      if (!values.containsKey(label)) {
        throw LlamaDecisionException(
          'Answer "$id" has the option "$label", which this key\'s question '
          'does not offer.',
        );
      }
    }
    return ChoiceOf._(answer, values);
  }
}

/// A [ChoiceAnswer] read through a [ChoiceKey], with option values of type
/// [T].
final class ChoiceOf<T extends Object?> {
  ChoiceOf._(this.answer, this.values)
    : value = values[answer.choice] as T,
      index = values.keys.toList().indexOf(answer.choice);

  /// The answer as returned, with option labels.
  final ChoiceAnswer answer;

  /// The value of each option label, in option order.
  final Map<String, T> values;

  /// Value of the most probable option.
  final T value;

  /// Position of the most probable option in [values]; for a key made by
  /// [ChoiceKey.of], its index in `options`.
  final int index;

  /// Label of the most probable option.
  String get label => answer.choice;

  /// Probability of each option label: the answer's
  /// [ChoiceAnswer.probabilities].
  Map<String, double> get probabilities => answer.probabilities;

  /// Probability of each option by its position in [values], in an
  /// unmodifiable list.
  List<double> get optionProbabilities => List.unmodifiable([
    for (final label in values.keys) answer.probabilities[label]!,
  ]);

  /// How sure the model is of the answer, from 0 to 1; see
  /// [DecisionAnswer.confidence].
  double get confidence => answer.confidence;

  /// Laya's action signal; see [DecisionAnswer.actProbability].
  double get actProbability => answer.actProbability;
}

/// Key of a rating question ([ScoreQuestion]); reading it gives the
/// [ScoreAnswer].
final class ScoreKey extends DecisionKey<ScoreAnswer> {
  /// Creates a key for [question].
  ScoreKey(super.id, this.question) : super._();

  /// Creates a key for a score question with [levels] from lowest to
  /// highest.
  ///
  /// Throws like [ScoreQuestion.new].
  ScoreKey.of(String id, Object instructions, {required List<Object?> levels})
    : this(id, ScoreQuestion(instructions, levels: levels));

  @override
  final ScoreQuestion question;

  @override
  ScoreAnswer _read(DecisionAnswer answer) {
    if (answer is! ScoreAnswer) {
      throw LlamaDecisionException(
        'Answer "$id" is a ${answer.type.name} answer, not a score answer.',
      );
    }
    final levels = [for (var i = 0; i < question.levels.length; i++) '$i'];
    if (answer.probabilities.length != levels.length ||
        !levels.every(answer.probabilities.containsKey)) {
      throw LlamaDecisionException(
        'Answer "$id" has the levels ${answer.probabilities.keys.toList()}; '
        'this key\'s question has $levels.',
      );
    }
    return answer;
  }
}

/// Key of a yes/no question ([NoulQuestion]); reading it gives the
/// [NoulAnswer].
final class NoulKey extends DecisionKey<NoulAnswer> {
  /// Creates a key for [question].
  NoulKey(super.id, this.question) : super._();

  /// Creates a key for a yes-or-no question with optional descriptions of
  /// each answer.
  ///
  /// Throws like [NoulQuestion.new].
  NoulKey.of(
    String id,
    Object instructions, {
    Object? whenTrue,
    Object? whenFalse,
  }) : this(
         id,
         NoulQuestion(instructions, whenTrue: whenTrue, whenFalse: whenFalse),
       );

  @override
  final NoulQuestion question;

  @override
  NoulAnswer _read(DecisionAnswer answer) => answer is NoulAnswer
      ? answer
      : throw LlamaDecisionException(
          'Answer "$id" is a ${answer.type.name} answer, not a noul answer.',
        );
}
