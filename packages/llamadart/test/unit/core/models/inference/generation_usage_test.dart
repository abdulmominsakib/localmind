import 'package:llamadart/src/core/models/inference/generation_usage.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaGenerationUsage', () {
    test('totalTokens adds prompt and completion tokens', () {
      const usage = LlamaGenerationUsage(
        promptTokens: 12,
        completionTokens: 5,
        duration: Duration.zero,
      );

      expect(usage.totalTokens, 17);
    });

    test('toJson writes OpenAI usage keys and millisecond timings', () {
      const usage = LlamaGenerationUsage(
        promptTokens: 12,
        cachedPromptTokens: 8,
        completionTokens: 5,
        timeToFirstToken: Duration(microseconds: 1500),
        duration: Duration(milliseconds: 40),
      );

      expect(usage.toJson(), {
        'prompt_tokens': 12,
        'completion_tokens': 5,
        'total_tokens': 17,
        'prompt_tokens_details': {'cached_tokens': 8},
        'time_to_first_token_ms': 1.5,
        'duration_ms': 40.0,
      });
    });

    test('toJson omits unknown cached tokens and first-token time', () {
      const usage = LlamaGenerationUsage(
        promptTokens: 3,
        completionTokens: 0,
        duration: Duration(milliseconds: 2),
      );

      expect(usage.toJson(), {
        'prompt_tokens': 3,
        'completion_tokens': 0,
        'total_tokens': 3,
        'duration_ms': 2.0,
      });
    });

    test('fromJson reads what toJson writes', () {
      const usage = LlamaGenerationUsage(
        promptTokens: 12,
        cachedPromptTokens: 8,
        completionTokens: 5,
        timeToFirstToken: Duration(microseconds: 1500),
        duration: Duration(microseconds: 40001),
      );

      final decoded = LlamaGenerationUsage.fromJson(usage.toJson());

      expect(decoded.promptTokens, 12);
      expect(decoded.cachedPromptTokens, 8);
      expect(decoded.completionTokens, 5);
      expect(decoded.timeToFirstToken, const Duration(microseconds: 1500));
      expect(decoded.duration, const Duration(microseconds: 40001));
    });

    test('fromJson reads an OpenAI usage map', () {
      final decoded = LlamaGenerationUsage.fromJson({
        'prompt_tokens': 3,
        'completion_tokens': 1,
        'total_tokens': 4,
        'prompt_tokens_details': {'cached_tokens': 2},
      });

      expect(decoded.promptTokens, 3);
      expect(decoded.cachedPromptTokens, 2);
      expect(decoded.completionTokens, 1);
      expect(decoded.timeToFirstToken, isNull);
      expect(decoded.duration, isNull);
    });

    test('toJson omits an unknown duration', () {
      const usage = LlamaGenerationUsage(promptTokens: 3, completionTokens: 1);

      expect(usage.toJson().containsKey('duration_ms'), isFalse);
    });
  });
}
