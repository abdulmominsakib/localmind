import 'dart:async';
import 'tool_definition.dart';
import 'tool_event.dart';
import 'tool_registry.dart';
import 'adapters/tool_transport_adapter.dart';

class ToolLoopResult {
  final String finalAssistantContent;
  final List<ToolEvent> events;
  final bool completedWithinLimit;
  final int toolCallCount;

  const ToolLoopResult({
    required this.finalAssistantContent,
    required this.events,
    this.completedWithinLimit = true,
    this.toolCallCount = 0,
  });
}

typedef ToolApprovalCallback = Future<bool> Function(ParsedToolCall call);

class ToolExecutionLoop {
  final ToolTransportAdapter adapter;
  final ToolRegistry registry;
  final int maxIterations;
  final Duration toolTimeout;
  final Duration approvalTimeout;
  final ToolApprovalCallback? onRequestApproval;

  String _sessionId = '';
  final List<ToolEvent> _events = [];

  ToolExecutionLoop({
    required this.adapter,
    required this.registry,
    this.maxIterations = 6,
    this.toolTimeout = const Duration(seconds: 30),
    this.approvalTimeout = const Duration(seconds: 60),
    this.onRequestApproval,
  });

  String get sessionId => _sessionId;

  Future<ToolLoopResult> run({
    required String initialUserMessage,
    List<Map<String, dynamic>> conversationHistory = const [],
    String? assistantContent,
    List<ParsedToolCall>? preParsedCalls,
  }) async {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _events.clear();

    int iteration = 0;
    int toolCallCount = 0;
    final toolDefinitions = {
      for (final tool in await registry.listTools()) tool.name: tool,
    };

    final callsToProcess = preParsedCalls ?? adapter.takeCompletedCalls();

    if (callsToProcess.isEmpty) {
      return ToolLoopResult(
        finalAssistantContent: assistantContent ?? '',
        events: const [],
        completedWithinLimit: true,
        toolCallCount: 0,
      );
    }

    iteration++;
    for (final call in callsToProcess) {
      toolCallCount++;
      final baseId = '${_sessionId}_${iteration}_${call.id}';
      final toolDefinition = toolDefinitions[call.name];
      final providerType =
          toolDefinition?.providerType ?? ToolProviderType.builtIn;
      final providerRef = toolDefinition?.providerRef;

      if (onRequestApproval != null) {
        _events.add(
          ToolEvent(
            eventId: '$baseId.requested',
            timestamp: DateTime.now(),
            status: ToolEventStatus.requested,
            toolName: call.name,
            providerType: providerType,
            providerRef: providerRef,
            arguments: call.arguments,
          ),
        );

        try {
          final approved = await onRequestApproval!(
            call,
          ).timeout(approvalTimeout);
          if (!approved) {
            _events.add(
              ToolEvent(
                eventId: '$baseId.rejected',
                timestamp: DateTime.now(),
                status: ToolEventStatus.rejected,
                toolName: call.name,
                providerType: providerType,
                providerRef: providerRef,
                arguments: call.arguments,
                error: 'Rejected by user',
              ),
            );
            continue;
          }
        } on TimeoutException {
          _events.add(
            ToolEvent(
              eventId: '$baseId.rejected',
              timestamp: DateTime.now(),
              status: ToolEventStatus.rejected,
              toolName: call.name,
              providerType: providerType,
              providerRef: providerRef,
              arguments: call.arguments,
              error: 'Approval timed out',
            ),
          );
          continue;
        } catch (_) {
          _events.add(
            ToolEvent(
              eventId: '$baseId.failed',
              timestamp: DateTime.now(),
              status: ToolEventStatus.failed,
              toolName: call.name,
              providerType: providerType,
              providerRef: providerRef,
              arguments: call.arguments,
              error: 'Approval callback error',
            ),
          );
          continue;
        }

        _events.add(
          ToolEvent(
            eventId: '$baseId.approved',
            timestamp: DateTime.now(),
            status: ToolEventStatus.approved,
            toolName: call.name,
            providerType: providerType,
            providerRef: providerRef,
            arguments: call.arguments,
          ),
        );
      }

      _events.add(
        ToolEvent(
          eventId: '$baseId.running',
          timestamp: DateTime.now(),
          status: ToolEventStatus.running,
          toolName: call.name,
          providerType: providerType,
          providerRef: providerRef,
          arguments: call.arguments,
        ),
      );

      final stopwatch = Stopwatch()..start();
      try {
        final result = await registry
            .execute(call.name, call.arguments)
            .timeout(toolTimeout);

        stopwatch.stop();

        _events.add(
          ToolEvent(
            eventId: '$baseId.${result.success ? "completed" : "failed"}',
            timestamp: DateTime.now(),
            status: result.success
                ? ToolEventStatus.completed
                : ToolEventStatus.failed,
            toolName: call.name,
            providerType: providerType,
            providerRef: providerRef,
            arguments: call.arguments,
            result: result.success ? result.output : null,
            error: result.success ? null : result.error,
            durationMs: stopwatch.elapsedMilliseconds,
          ),
        );
      } catch (e) {
        stopwatch.stop();

        _events.add(
          ToolEvent(
            eventId: '$baseId.failed',
            timestamp: DateTime.now(),
            status: ToolEventStatus.failed,
            toolName: call.name,
            providerType: providerType,
            providerRef: providerRef,
            arguments: call.arguments,
            error: 'Timeout or error: $e',
            durationMs: stopwatch.elapsedMilliseconds,
          ),
        );
      }
    }

    return ToolLoopResult(
      finalAssistantContent: assistantContent ?? '',
      events: List<ToolEvent>.from(_events),
      completedWithinLimit: iteration < maxIterations,
      toolCallCount: toolCallCount,
    );
  }
}
