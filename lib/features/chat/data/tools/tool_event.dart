import 'tool_definition.dart';

enum ToolEventStatus {
  requested,
  approved,
  rejected,
  running,
  completed,
  failed,
}

class ToolEvent {
  final String eventId;
  final DateTime timestamp;
  final ToolEventStatus status;
  final String toolName;
  final ToolProviderType providerType;
  final String? providerRef;
  final Map<String, dynamic>? arguments;
  final String? result;
  final String? error;
  final int? durationMs;

  const ToolEvent({
    required this.eventId,
    required this.timestamp,
    required this.status,
    required this.toolName,
    required this.providerType,
    this.providerRef,
    this.arguments,
    this.result,
    this.error,
    this.durationMs,
  });

  factory ToolEvent.requested({
    required String eventId,
    required String toolName,
    required ToolProviderType providerType,
    String? providerRef,
    Map<String, dynamic>? arguments,
  }) => ToolEvent(
    eventId: eventId,
    timestamp: DateTime.now(),
    status: ToolEventStatus.requested,
    toolName: toolName,
    providerType: providerType,
    providerRef: providerRef,
    arguments: arguments,
  );

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'toolName': toolName,
      'providerType': providerType.name,
      'providerRef': providerRef,
      'arguments': arguments,
      'result': result,
      'error': error,
      'durationMs': durationMs,
    };
  }

  factory ToolEvent.fromMap(Map<String, dynamic> map) {
    return ToolEvent(
      eventId: map['eventId'],
      timestamp: DateTime.parse(map['timestamp']),
      status: ToolEventStatus.values.byName(map['status']),
      toolName: map['toolName'],
      providerType: ToolProviderType.values.byName(map['providerType']),
      providerRef: map['providerRef'],
      arguments: map['arguments'] != null
          ? Map<String, dynamic>.from(map['arguments'])
          : null,
      result: map['result'],
      error: map['error'],
      durationMs: map['durationMs'],
    );
  }
}
