import 'dart:convert';

import 'package:localmind/features/chat/data/tools/adapters/tool_transport_adapter.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';

class _AccumulatingChunk {
  String? id;
  String? name;
  final StringBuffer argumentsBuffer = StringBuffer();
}

class OpenAiToolAdapter implements ToolTransportAdapter {
  final Map<int, _AccumulatingChunk> _accumulators = {};

  @override
  Map<String, dynamic> buildToolDefinitionPayload(List<ToolDefinition> tools) {
    return {
      'tools': tools
          .map(
            (t) => {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.inputSchema,
              },
            },
          )
          .toList(),
    };
  }

  @override
  void consumeDynamicChunk(Map<String, dynamic> chunk) {
    final choices = chunk['choices'] as List?;
    if (choices == null || choices.isEmpty) return;
    final delta = choices[0]['delta'] as Map<String, dynamic>?;
    if (delta == null) return;
    final toolCalls = delta['tool_calls'] as List?;
    if (toolCalls == null) return;
    for (final tc in toolCalls) {
      final index = tc['index'] as int;
      final acc = _accumulators.putIfAbsent(index, () => _AccumulatingChunk());
      final func = tc['function'] as Map<String, dynamic>?;
      if (tc['id'] != null) acc.id = tc['id'] as String;
      if (func != null) {
        if (func['name'] != null) acc.name = func['name'] as String;
        if (func['arguments'] != null) {
          acc.argumentsBuffer.write(func['arguments'] as String);
        }
      }
    }
  }

  @override
  List<ParsedToolCall> takeCompletedCalls() {
    if (_accumulators.isEmpty) return const [];
    final calls = _accumulators.entries.map((e) {
      final acc = e.value;
      Map<String, dynamic> parsedArgs;
      try {
        parsedArgs = Map<String, dynamic>.from(
          jsonDecode(acc.argumentsBuffer.toString()) as Map,
        );
      } catch (_) {
        parsedArgs = {};
      }
      return ParsedToolCall(
        id: acc.id ?? '',
        name: acc.name ?? '',
        arguments: parsedArgs,
      );
    }).toList();
    _accumulators.clear();
    return calls;
  }

  @override
  Map<String, dynamic> buildToolResultMessage({
    required ParsedToolCall call,
    required String output,
  }) {
    return {'role': 'tool', 'tool_call_id': call.id, 'content': output};
  }
}
