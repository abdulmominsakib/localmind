/// Token counts and timings of one generation request.
class LlamaGenerationUsage {
  /// Prompt tokens in the context when generation started, including
  /// [cachedPromptTokens].
  ///
  /// A cancel during prompt evaluation leaves only the tokens evaluated
  /// before it.
  ///
  /// Native llama.cpp counts the image and audio tokens of a multimodal
  /// prompt, as llama-server does. WebGPU counts the context positions it
  /// filled, which models with M-RoPE vision, such as Qwen2-VL, give an image
  /// fewer of than image tokens.
  final int promptTokens;

  /// Leading prompt tokens reused from the KV cache, left by the context's
  /// previous request or by a loaded state, instead of being evaluated again.
  /// Null when the backend cannot tell.
  final int? cachedPromptTokens;

  /// Generated tokens, including tokens that formed a stop sequence and
  /// excluding the end-of-generation token.
  ///
  /// On WebGPU it can also count tokens the bridge generated after a stop
  /// sequence, before the stop reached it.
  final int completionTokens;

  /// Time from the backend starting the request to its first streamed text,
  /// or null when it streamed none.
  ///
  /// Measured where the backend generates. It excludes time spent queued
  /// behind another request and the batching of streamed tokens.
  final Duration? timeToFirstToken;

  /// Time from the backend starting the request to the end of generation, or
  /// null when unknown, such as after parsing JSON without `duration_ms`.
  final Duration? duration;

  /// Creates a new [LlamaGenerationUsage].
  const LlamaGenerationUsage({
    required this.promptTokens,
    this.cachedPromptTokens,
    required this.completionTokens,
    this.timeToFirstToken,
    this.duration,
  });

  /// [promptTokens] plus [completionTokens].
  int get totalTokens => promptTokens + completionTokens;

  /// Creates a [LlamaGenerationUsage] from a map produced by [toJson] or an
  /// OpenAI-style `usage` map.
  factory LlamaGenerationUsage.fromJson(Map<String, dynamic> json) {
    final details = json['prompt_tokens_details'] as Map<String, dynamic>?;
    final timeToFirstTokenMs = json['time_to_first_token_ms'] as num?;
    final durationMs = json['duration_ms'] as num?;
    return LlamaGenerationUsage(
      promptTokens: json['prompt_tokens'] as int,
      cachedPromptTokens: details?['cached_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int,
      timeToFirstToken: timeToFirstTokenMs == null
          ? null
          : _durationFromMs(timeToFirstTokenMs),
      duration: durationMs == null ? null : _durationFromMs(durationMs),
    );
  }

  /// Converts this object to an OpenAI-style `usage` map, with
  /// `time_to_first_token_ms` and `duration_ms` added.
  Map<String, dynamic> toJson() {
    final timeToFirstToken = this.timeToFirstToken;
    final duration = this.duration;
    return {
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': totalTokens,
      if (cachedPromptTokens != null)
        'prompt_tokens_details': {'cached_tokens': cachedPromptTokens},
      if (timeToFirstToken != null)
        'time_to_first_token_ms': timeToFirstToken.inMicroseconds / 1000,
      if (duration != null) 'duration_ms': duration.inMicroseconds / 1000,
    };
  }

  static Duration _durationFromMs(num ms) =>
      Duration(microseconds: (ms * 1000).round());

  @override
  String toString() =>
      'LlamaGenerationUsage(promptTokens: $promptTokens, '
      'cachedPromptTokens: $cachedPromptTokens, '
      'completionTokens: $completionTokens, '
      'timeToFirstToken: $timeToFirstToken, duration: $duration)';
}
