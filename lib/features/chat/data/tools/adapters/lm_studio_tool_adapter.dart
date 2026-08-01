class ServerExecutedToolCall {
  final String name;
  final Map<String, dynamic> arguments;
  final String output;
  final Map<String, dynamic>? providerInfo;
  const ServerExecutedToolCall({
    required this.name,
    required this.arguments,
    required this.output,
    this.providerInfo,
  });
}

class LmStudioToolAdapter {
  final List<ServerExecutedToolCall> _completedCalls = [];
  String? _currentTool;
  Map<String, dynamic> _currentArgs = {};
  Map<String, dynamic>? _currentProviderInfo;

  void consumeEvent(String eventType, Map<String, dynamic> data) {
    switch (eventType) {
      case 'tool_call.start':
        _currentTool = data['tool'] as String?;
        _currentArgs = {};
        _currentProviderInfo =
            (data['provider_info'] as Map?)?.cast<String, dynamic>();
        break;
      case 'tool_call.arguments':
        final args = data['arguments'] as Map<String, dynamic>?;
        if (args != null) {
          _currentArgs = args;
        }
        final pi = (data['provider_info'] as Map?)?.cast<String, dynamic>();
        if (pi != null) {
          _currentProviderInfo = pi;
        }
        break;
      case 'tool_call.success':
        final tool = data['tool'] as String? ?? _currentTool;
        final args = data['arguments'] as Map<String, dynamic>? ?? _currentArgs;
        final output = data['output'] as String? ?? '';
        final pi = (data['provider_info'] as Map?)?.cast<String, dynamic>() ??
            _currentProviderInfo;
        if (tool != null) {
          _completedCalls.add(ServerExecutedToolCall(
            name: tool,
            arguments: args,
            output: output,
            providerInfo: pi,
          ));
        }
        _currentTool = null;
        _currentArgs = {};
        _currentProviderInfo = null;
        break;
      case 'tool_call.failure':
        final tool = data['tool'] as String? ?? _currentTool;
        final args = data['arguments'] as Map<String, dynamic>? ?? _currentArgs;
        final reason = data['reason'] as String? ?? 'Tool execution failed';
        final pi = (data['provider_info'] as Map?)?.cast<String, dynamic>() ??
            _currentProviderInfo;
        if (tool != null) {
          _completedCalls.add(ServerExecutedToolCall(
            name: tool,
            arguments: args,
            output: reason,
            providerInfo: pi,
          ));
        }
        _currentTool = null;
        _currentArgs = {};
        _currentProviderInfo = null;
        break;
    }
  }

  List<ServerExecutedToolCall> takeServerExecutedCalls() {
    final calls = List<ServerExecutedToolCall>.from(_completedCalls);
    _completedCalls.clear();
    return calls;
  }
}
