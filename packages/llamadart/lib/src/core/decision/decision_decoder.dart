import 'dart:convert';
import 'dart:math' as math;

import '../exceptions.dart';
import 'decision_question.dart';
import 'decision_result.dart';

/// Model name reported in decision responses, as Laya reports it.
const String decisionResponseModel = 'laya-rl-agent';

/// Sequence limits, layer count and calibration temperatures of a decision
/// head.
class DecisionHeadConfig {
  /// Creates a config.
  const DecisionHeadConfig({
    this.maxTokens = 512,
    this.headMaxTokens = 192,
    this.headLayers = 2,
    this.temperature = const [1.0, 1.0, 1.0],
    this.temperatureByOptions = const {},
  });

  /// Reads Laya's `rl_agent_config.json` fields.
  ///
  /// `max_len`, `head_max_len` and `head_layers` must be positive integers,
  /// `temperature` a list of at least 3 values and `temperature_by_options` a
  /// map; missing or `null` fields take the defaults. Temperatures are stored
  /// clamped by [clampDecisionTemperature]. Throws [LlamaDecisionException]
  /// for other shapes.
  factory DecisionHeadConfig.fromJson(Map<String, Object?> json) {
    final temperature = json['temperature'] ?? const [1.0, 1.0, 1.0];
    if (temperature is! List || temperature.length < 3) {
      throw LlamaDecisionException(
        'Decision head "temperature" must be a list of at least 3 values, '
        'got $temperature.',
      );
    }
    final byOptions = json['temperature_by_options'] ?? const {};
    if (byOptions is! Map) {
      throw LlamaDecisionException(
        'Decision head "temperature_by_options" must be a map, got '
        '$byOptions.',
      );
    }
    return DecisionHeadConfig(
      maxTokens: _positiveInt(json, 'max_len', 512),
      headMaxTokens: _positiveInt(json, 'head_max_len', 192),
      headLayers: _positiveInt(json, 'head_layers', 2),
      temperature: List.unmodifiable(temperature.map(clampDecisionTemperature)),
      temperatureByOptions: Map.unmodifiable({
        for (final MapEntry(:key, :value) in byOptions.entries)
          '$key': clampDecisionTemperature(value),
      }),
    );
  }

  /// Maximum sequence length, Laya's `max_len`.
  final int maxTokens;

  /// Token budget for the question text and options, Laya's `head_max_len`.
  final int headMaxTokens;

  /// Transformer layers of the head, Laya's `head_layers`.
  final int headLayers;

  /// Temperature per [DecisionQuestionType.index].
  final List<double> temperature;

  /// Temperatures by [decisionTemperatureBucket], preferred over
  /// [temperature].
  final Map<String, double> temperatureByOptions;

  /// Temperature for a [type] question with [optionCount] options, as
  /// stored; [DecisionHeadConfig.fromJson] stores it clamped.
  double temperatureFor(DecisionQuestionType type, int optionCount) =>
      temperatureByOptions[decisionTemperatureBucket(type, optionCount)] ??
      temperature[type.index];
}

/// Decodes decision head config [text], Laya's `rl_agent_config.json`.
///
/// Throws [LlamaDecisionException] when [text] is not a JSON object or
/// [DecisionHeadConfig.fromJson] rejects it.
DecisionHeadConfig decodeDecisionHeadConfig(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw LlamaDecisionException(
      'Decision head config is not valid JSON: ${error.message}',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw LlamaDecisionException('Decision head config is not a JSON object.');
  }
  return DecisionHeadConfig.fromJson(decoded);
}

/// A usable temperature, as Laya's `clamp_temperature`.
///
/// Numbers, numeric strings and booleans (as 1 or 0) are clamped to
/// `[0.5, 5.0]`. Anything else, `NaN` and infinities give 1.0. Strings are
/// parsed by [double.tryParse], so spellings only Python's `float()` accepts,
/// such as `1_0` or non-ASCII digits, give 1.0.
double clampDecisionTemperature(Object? value) {
  final t = switch (value) {
    bool() => value ? 1.0 : 0.0,
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };
  if (t == null || !t.isFinite) return 1.0;
  return t.clamp(0.5, 5.0);
}

/// Laya's temperature bucket for a [type] question with [k] options, such as
/// `choice:3-5`.
String decisionTemperatureBucket(DecisionQuestionType type, int k) {
  final size = k <= 2
      ? '2'
      : k <= 5
      ? '3-5'
      : k <= 10
      ? '6-10'
      : '11+';
  return '${type.name}:$size';
}

/// Softmax of [logits], computed in double precision after subtracting the
/// maximum.
List<double> decisionSoftmax(List<double> logits) {
  final top = logits.reduce(math.max);
  final exps = [for (final logit in logits) math.exp(logit - top)];
  final sum = exps.fold(0.0, (total, value) => total + value);
  return [for (final value in exps) value / sum];
}

/// Entropy confidence `1 - H(p) / ln K` clamped to `[0, 1]`, with `p` clipped
/// to `[1e-12, 1]` inside the log; 1.0 when `K < 2`.
double decisionConfidence(List<double> probabilities) {
  final k = probabilities.length;
  if (k < 2) return 1.0;
  var entropy = 0.0;
  for (final p in probabilities) {
    entropy -= p * math.log(p.clamp(1e-12, 1.0));
  }
  return (1 - entropy / math.log(k)).clamp(0.0, 1.0);
}

/// Act-head features from untempered marker logits: `top1`, `top1 - top2`
/// (`top2` is 0 for one option), entropy over `ln(max(K, 2))` with `p`
/// clipped to at least 1e-9 inside the log, and `max(K, 2) / 255`.
List<double> decisionActFeatures(List<double> rawLogits) {
  final p = decisionSoftmax(rawLogits);
  final k = math.max(p.length, 2);
  final sorted = [...p]..sort((a, b) => b.compareTo(a));
  final top1 = sorted[0];
  final top2 = sorted.length > 1 ? sorted[1] : 0.0;
  var entropy = 0.0;
  for (final value in p) {
    entropy -= value * math.log(math.max(value, 1e-9));
  }
  return [top1, top1 - top2, entropy / math.log(k), k / 255];
}

/// Probability of the first action in [actLogits].
double decisionActProbability(List<double> actLogits) =>
    decisionSoftmax(actLogits)[0];

/// Decodes raw marker [logits] and act-head [actLogits] into an answer to
/// [question], as Laya's `system_one`.
///
/// Throws [LlamaDecisionException] when [logits] does not have one value per
/// option or [actLogits] is empty.
DecisionAnswer decodeDecisionAnswer(
  DecisionQuestion question,
  List<double> logits,
  List<double> actLogits,
  DecisionHeadConfig config,
) {
  final k = question.optionCount;
  if (logits.length != k) {
    throw LlamaDecisionException(
      'Decision head returned ${logits.length} logits for a question with '
      '$k options.',
    );
  }
  if (actLogits.isEmpty) {
    throw LlamaDecisionException('Decision head returned no act logits.');
  }
  final t = config.temperatureFor(question.type, k);
  final p = decisionSoftmax([for (final logit in logits) logit / t]);
  final actProbability = decisionActProbability(actLogits);
  switch (question) {
    case ChoiceQuestion(:final criteria):
      final labels = criteria.keys.toList();
      var best = 0;
      for (var i = 1; i < k; i++) {
        if (p[i] > p[best]) best = i;
      }
      return ChoiceAnswer(
        choice: labels[best],
        probabilities: {for (var i = 0; i < k; i++) labels[i]: p[i]},
        confidence: decisionConfidence(p),
        actProbability: actProbability,
      );
    case ScoreQuestion(:final levels):
      var score = 0.0;
      for (var i = 0; i < k; i++) {
        score += i * p[i];
      }
      return ScoreAnswer(
        score: score,
        legend: {for (var i = 0; i < k; i++) '$i': levels[i]},
        probabilities: {for (var i = 0; i < k; i++) '$i': p[i]},
        confidence: decisionConfidence(p),
        actProbability: actProbability,
      );
    case NoulQuestion():
      return NoulAnswer(
        noul: p[1],
        confidence: math.max(p[1], 1 - p[1]),
        actProbability: actProbability,
      );
  }
}

int _positiveInt(Map<String, Object?> json, String key, int fallback) {
  final value = json[key] ?? fallback;
  if (value is int && value > 0) return value;
  throw LlamaDecisionException(
    'Decision head "$key" must be a positive integer, got $value.',
  );
}
