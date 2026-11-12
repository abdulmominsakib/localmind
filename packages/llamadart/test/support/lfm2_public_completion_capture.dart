import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/models/chat/completion.dart';

/// Keeps the reply actually delivered by one public completion subscription.
/// Raw parser replay is deliberately recorded separately by the driver.
class Lfm2PublicCompletionCapture {
  final LlamaCompletionAccumulator _accumulator = LlamaCompletionAccumulator();
  final List<Map<String, dynamic>> chunks = [];
  bool completed = false;
  Object? error;

  Future<void> consume(Stream<LlamaCompletionChunk> stream) async {
    try {
      await for (final chunk in stream) {
        chunks.add(chunk.toJson());
        _accumulator.add(chunk);
      }
      completed = true;
    } catch (failure) {
      error = failure;
    }
  }

  Map<String, dynamic> toJson() {
    final reply = _accumulator.build();
    final indices = <int>{};
    final diagnostics = <dynamic>[];
    for (final chunk in chunks) {
      final choices = chunk['choices'] as List;
      if (choices.isEmpty) continue;
      final delta = (choices.first as Map)['delta'] as Map;
      for (final call in delta['tool_calls'] as List? ?? const []) {
        indices.add((call as Map)['index'] as int);
      }
      // Reading serialized extensions keeps this helper usable before and
      // after partial diagnostics became part of the public chunk API.
      diagnostics.addAll(delta['partial_tool_calls'] as List? ?? const []);
    }
    final orderedIndices = indices.toList()..sort();
    final result = <String, dynamic>{
      'content': reply.text,
      'thinking': reply.thinking,
      'calls': [
        for (var i = 0; i < reply.toolCalls.length; i++)
          {
            'index': orderedIndices[i],
            'id': reply.toolCalls[i].id,
            'name': reply.toolCalls[i].name,
            'raw_json': reply.toolCalls[i].rawJson,
            'arguments': reply.toolCalls[i].arguments,
          },
      ],
      'finish_reason': reply.finishReason?.wireValue,
      'partial_tool_calls': diagnostics,
      'usage': reply.usage?.toJson(),
    };
    return {
      'public_capture_schema': 1,
      'public_completed': completed,
      'public_chunks': chunks,
      if (completed) 'public_result': result,
      if (!completed) 'public_partial_result': result,
      if (error != null) 'public_error': {'type': error.runtimeType.toString()},
    };
  }
}
