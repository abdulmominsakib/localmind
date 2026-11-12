import 'package:genkit/genkit.dart';
import 'package:llamadart/llamadart.dart' as llama;

/// Raw-prompt input for a model's typed next-token scoring action.
///
/// Apply the model's chat template yourself when using an instruction model.
/// Scoring evaluates one next-token distribution; it does not generate text or
/// apply sampling settings, tools, grammar or media. Candidate IDs belong to
/// this model's vocabulary. Use the plugin's tokenizer to obtain them.
class LlamaDartScoringRequest {
  /// Creates a request, copying [candidates] to prevent mutation while queued.
  ///
  /// An action rejects an empty [prompt], negative or oversized integer values,
  /// and requests with neither candidates nor a positive [topK]. Vocabulary
  /// limits are checked by the loaded backend before prompt evaluation.
  LlamaDartScoringRequest({
    required this.prompt,
    List<int> candidates = const [],
    this.topK = 0,
    this.reusePromptPrefix = true,
  }) : candidates = List<int>.unmodifiable(candidates);

  /// Parses the action's JSON input without coercing numbers or ignoring keys.
  ///
  /// Throws [GenkitException] with `invalidArgument` for invalid input. Defaults
  /// match the constructor; explicit nulls are not treated as missing values.
  factory LlamaDartScoringRequest.fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json.keys.any(
          (key) => !const {
            'prompt',
            'candidates',
            'topK',
            'reusePromptPrefix',
          }.contains(key),
        ) ||
        json['prompt'] is! String ||
        (json.containsKey('candidates') &&
            (json['candidates'] is! List ||
                (json['candidates'] as List).any((v) => v is! int))) ||
        (json.containsKey('topK') && json['topK'] is! int) ||
        (json.containsKey('reusePromptPrefix') &&
            json['reusePromptPrefix'] is! bool)) {
      throw _invalidScoringRequest();
    }
    final request = LlamaDartScoringRequest(
      prompt: json['prompt'] as String,
      candidates: (json['candidates'] as List?)?.cast<int>() ?? const [],
      topK: json['topK'] as int? ?? 0,
      reusePromptPrefix: json['reusePromptPrefix'] as bool? ?? true,
    );
    validateScoringRequest(request);
    return request;
  }

  /// Raw prompt, including any caller-supplied chat-template special tokens.
  final String prompt;

  /// Vocabulary IDs to score, preserving order and duplicates in the result.
  final List<int> candidates;

  /// Number of highest-probability tokens to return, or zero for candidates only.
  final int topK;

  /// Whether the backend may reuse a matching prompt prefix on this context.
  ///
  /// Reuse is a backend optimization, not session or user state isolation.
  final bool reusePromptPrefix;

  /// Serializes this request for Genkit custom actions and reflection.
  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    'candidates': candidates,
    'topK': topK,
    'reusePromptPrefix': reusePromptPrefix,
  };
}

/// JSON-serializable next-token scores using llamadart's score/result types.
///
/// Log probabilities are natural logs of softmax over raw next-token logits.
/// Sampling temperature, penalties and grammar do not apply. Token bytes may
/// contain incomplete UTF-8; [llama.LlamaTokenLogprob.text] replaces malformed
/// sequences when decoded. This is not whole-answer token-level telemetry.
class LlamaDartTokenScores extends llama.LlamaNextTokenScores {
  /// Copies [scores] without changing candidate order, bytes or probabilities.
  LlamaDartTokenScores.fromScores(llama.LlamaNextTokenScores scores)
    : super(
        candidates: scores.candidates,
        top: scores.top,
        promptTokens: scores.promptTokens,
      );

  /// Serializes vocabulary IDs, raw token bytes and natural-log probabilities.
  ///
  /// Derived text/probability getters remain available on each typed entry.
  Map<String, dynamic> toJson() {
    Map<String, dynamic> token(llama.LlamaTokenLogprob value) => {
      'token': value.token,
      'bytes': value.bytes,
      'logprob': value.logprob,
    };
    return {
      'candidates': candidates.map(token).toList(),
      'top': top.map(token).toList(),
      'promptTokens': promptTokens,
    };
  }
}

void validateScoringRequest(LlamaDartScoringRequest request) {
  bool validInt(int value) => value >= 0 && value <= 2147483647;
  if (request.prompt.isEmpty ||
      !validInt(request.topK) ||
      request.candidates.any((value) => !validInt(value)) ||
      (request.candidates.isEmpty && request.topK == 0)) {
    throw _invalidScoringRequest();
  }
}

GenkitException _invalidScoringRequest() => GenkitException(
  'Next-token scoring requires a nonempty raw prompt and candidate token IDs '
  'or a positive topK. Token IDs and topK must be integers from 0 to '
  '2147483647; only prompt, candidates, topK and reusePromptPrefix are accepted.',
  status: StatusCode.invalidArgument,
);
