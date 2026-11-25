import 'dart:convert';
import 'dart:math' as math;

/// One token and its log-probability.
class LlamaTokenLogprob {
  /// Creates a token log-probability.
  LlamaTokenLogprob({
    required this.token,
    required List<int> bytes,
    required this.logprob,
  }) : bytes = List.unmodifiable(bytes);

  /// Token id in the model's vocabulary.
  final int token;

  /// UTF-8 bytes of the token's text, special tokens included. A token can
  /// hold part of a multi-byte character.
  final List<int> bytes;

  /// Natural-log probability of the token.
  final double logprob;

  /// The token's text, with malformed UTF-8 replaced by U+FFFD.
  String get text => utf8.decode(bytes, allowMalformed: true);

  /// The probability, `exp(logprob)`.
  double get probability => math.exp(logprob);
}

/// Log-probabilities of the token that would follow a prompt, from
/// `LlamaEngine.scoreNextToken`.
///
/// They come from a softmax over the model's raw logits at the last prompt
/// position. Sampling settings such as temperature, top-k, penalties and
/// grammar do not apply.
class LlamaNextTokenScores {
  /// Creates next-token scores.
  LlamaNextTokenScores({
    required List<LlamaTokenLogprob> candidates,
    required List<LlamaTokenLogprob> top,
    required this.promptTokens,
  }) : candidates = List.unmodifiable(candidates),
       top = List.unmodifiable(top);

  /// The requested candidate tokens, in request order.
  final List<LlamaTokenLogprob> candidates;

  /// The most probable tokens, most probable first.
  final List<LlamaTokenLogprob> top;

  /// Number of tokens the prompt tokenized to.
  final int promptTokens;
}
