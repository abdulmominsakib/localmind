import 'package:genkit_llamadart/src/core/streaming/completion_accumulator.dart';
import 'package:test/test.dart';

import '../../runtime/test_support/fake_runtime.dart';

void main() {
  test(
    'CompletionAccumulator accumulates streamed tool call argument deltas',
    () {
      final accumulator = CompletionAccumulator();

      accumulator.addChunk(
        toolCallDeltaChunk(id: 'call-1', name: 'get_weather', arguments: '{'),
      );
      accumulator.addChunk(toolCallDeltaChunk(arguments: '"city":"Seo'));
      accumulator.addChunk(
        toolCallDeltaChunk(arguments: 'ul"}', finishReason: 'tool_calls'),
      );

      final result = accumulator.toResult();

      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.id, 'call-1');
      expect(result.toolCalls.single.function?.name, 'get_weather');
      expect(result.toolCalls.single.function?.arguments, '{"city":"Seoul"}');
      expect(result.finishReason, 'tool_calls');
    },
  );
}
