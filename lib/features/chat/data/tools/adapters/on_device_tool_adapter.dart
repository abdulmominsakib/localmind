import 'package:localmind/features/chat/data/tools/adapters/tool_transport_adapter.dart';

class OnDeviceToolAdapter {
  final List<ParsedToolCall> _completedCalls = [];

  void consumeFunctionCall(String name, Map<String, dynamic> args) {
    _completedCalls.add(
      ParsedToolCall(
        id: 'ondevice_${_completedCalls.length}',
        name: name,
        arguments: Map<String, dynamic>.from(args),
      ),
    );
  }

  List<ParsedToolCall> takeCompletedCalls() {
    final calls = List<ParsedToolCall>.from(_completedCalls);
    _completedCalls.clear();
    return calls;
  }
}
