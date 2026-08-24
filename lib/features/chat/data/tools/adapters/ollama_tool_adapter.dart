import 'dart:convert';

import 'package:localmind/features/chat/data/tools/adapters/tool_transport_adapter.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';

class OllamaToolAdapter implements ToolTransportAdapter {
  final List<ParsedToolCall> _completedCalls = [];

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
    final message = chunk['message'] as Map<String, dynamic>?;
    if (message == null) return;
    final toolCalls = message['tool_calls'] as List?;
    if (toolCalls == null) return;
    for (final tc in toolCalls) {
      final func = tc['function'] as Map<String, dynamic>?;
      if (func == null) continue;
      _completedCalls.add(
        ParsedToolCall(
          id: tc['id'] ?? '',
          name: func['name'] as String? ?? '',
          arguments: Map<String, dynamic>.from(
            jsonDecode(func['arguments'] as String? ?? '{}') as Map,
          ),
        ),
      );
    }
  }

  @override
  List<ParsedToolCall> takeCompletedCalls() {
    final calls = List<ParsedToolCall>.from(_completedCalls);
    _completedCalls.clear();
    return calls;
  }

  @override
  Map<String, dynamic> buildToolResultMessage({
    required ParsedToolCall call,
    required String output,
  }) {
    return {'role': 'tool', 'tool_name': call.name, 'content': output};
  }
}
