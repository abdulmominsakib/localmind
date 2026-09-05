import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/models/message.dart' as m
    show Message, ToolCallData;
import 'package:localmind/features/chat/data/tools/tool_event.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';

// Regression test for issue #77:
//   "MCP: tool result is never sent back to the model — conversation ends
//    after tool execution".
//
// After the server streams an assistant message that contains a tool call
// and the client successfully executes the tool, the app MUST issue a
// follow-up chat completion that includes:
//   1. The tool-role message(s) carrying the result, each with a
//      `toolCallId` that matches the assistant's `tool_calls[].id`.
//   2. Matching `tool_calls` entries on the assistant message so the
//      OpenAI-compatible protocol can pair the two.
//
// The test below mirrors the message-construction logic in
// `_sendFollowupWithToolResults` in `chat_notifier.dart` and asserts the
// invariants the model depends on. If this test ever fails, the
// follow-up request will be malformed and the model will not produce a
// final answer — the original symptom in #77.

m.Message _previousAssistant({
  required String id,
  required String toolName,
}) {
  return m.Message(
    id: id,
    conversationId: 'conv-1',
    role: MessageRole.assistant,
    content: 'I will check your calendar now.',
    createdAt: DateTime.utc(2026, 9, 5),
    status: MessageStatus.complete,
    modelId: 'qwen-test',
    toolSessionId: 'session-1',
    variantGroupId: 'group-1',
    variantIndex: 0,
    threadOrder: 1,
  );
}

ToolEvent _completedEvent({
  required String sessionId,
  required String toolName,
  required String result,
}) {
  return ToolEvent(
    eventId: '${sessionId}_1_$toolName',
    timestamp: DateTime.utc(2026, 9, 5, 12, 0, 0),
    status: ToolEventStatus.completed,
    toolName: toolName,
    providerType: ToolProviderType.builtIn,
    arguments: const {},
    result: result,
  );
}

/// Mirrors the helper used inside `_sendFollowupWithToolResults` to ensure
/// the assistant message's `tool_calls[].id` and the tool-role message's
/// `tool_call_id` are the same value. The OpenAI-compatible protocol
/// requires this exact pairing or the model will reject the request.
String _toolCallIdFor(ToolEvent event) {
  final uniqueSuffix = event.eventId.isNotEmpty
      ? event.eventId
      : '${event.toolName}_${event.timestamp.microsecondsSinceEpoch}';
  return 'call_${uniqueSuffix}_completed';
}

({m.Message assistant, List<m.Message> toolMessages}) _buildFollowup({
  required m.Message previousAssistant,
  required List<ToolEvent> toolEvents,
}) {
  final completed = toolEvents
      .where((e) => e.status == ToolEventStatus.completed)
      .toList();

  final toolCallEntries = completed
      .map(
        (e) => m.ToolCallData(
          id: _toolCallIdFor(e),
          toolName: e.toolName,
          arguments: e.arguments ?? const {},
          result: e.result,
        ),
      )
      .toList();

  final assistant = previousAssistant.copyWith(
    toolCalls: toolCallEntries,
    stopReason: 'tool_use',
  );

  final toolMessages = completed.map((e) {
    final callId = _toolCallIdFor(e);
    return m.Message(
      id: 'tool_${callId}_${e.timestamp.microsecondsSinceEpoch}',
      conversationId: previousAssistant.conversationId,
      role: MessageRole.tool,
      content: e.result ?? e.error ?? '',
      createdAt: e.timestamp,
      status: MessageStatus.complete,
      toolCallId: callId,
      toolSessionId: previousAssistant.toolSessionId,
      parentMessageId: previousAssistant.id,
      variantGroupId: previousAssistant.variantGroupId,
      variantIndex: previousAssistant.variantIndex,
    );
  }).toList();

  return (assistant: assistant, toolMessages: toolMessages);
}

void main() {
  group('Issue #77 follow-up message construction', () {
    test('tool_call_id on tool messages matches assistant.toolCalls[*].id', () {
      final assistant = _previousAssistant(
        id: 'asst-1',
        toolName: 'calendar.list_events',
      );
      final events = [
        _completedEvent(
          sessionId: 'session-1',
          toolName: 'calendar.list_events',
          result: '[{"date":"2026-09-07","title":"Standup"}]',
        ),
      ];

      final built = _buildFollowup(
        previousAssistant: assistant,
        toolEvents: events,
      );

      expect(
        built.assistant.toolCalls,
        isNotNull,
        reason:
            'Assistant message must carry tool_calls so the OpenAI protocol '
            'knows which tool_call_id each tool message corresponds to.',
      );
      expect(built.assistant.toolCalls!.length, 1);
      expect(built.toolMessages.length, 1);
      expect(
        built.assistant.toolCalls!.first.id,
        built.toolMessages.first.toolCallId,
        reason:
            'The OpenAI-compatible protocol requires tool_call_id in the '
            'tool-role message to match tool_calls[].id on the assistant '
            'message exactly — without this pairing the model cannot '
            'associate the result with the call and will not produce a '
            'final answer (issue #77).',
      );
    });

    test('multiple completed tools each get a unique matching id', () {
      final assistant = _previousAssistant(id: 'asst-1', toolName: 'multi');
      final events = [
        _completedEvent(
          sessionId: 'session-1',
          toolName: 'calendar.list_events',
          result: '[]',
        ),
        _completedEvent(
          sessionId: 'session-1',
          toolName: 'weather.get',
          result: '{"temp":72}',
        ),
      ];

      final built = _buildFollowup(
        previousAssistant: assistant,
        toolEvents: events,
      );

      expect(built.assistant.toolCalls!.length, 2);
      expect(built.toolMessages.length, 2);

      final ids = built.assistant.toolCalls!.map((tc) => tc.id).toSet();
      expect(ids.length, 2, reason: 'Tool-call IDs must be unique');

      for (final tm in built.toolMessages) {
        expect(
          ids.contains(tm.toolCallId),
          isTrue,
          reason:
              'Every tool message tool_call_id (${tm.toolCallId}) must be '
              'paired with one assistant tool_calls entry.',
        );
      }
    });

    test('failed tool events are excluded from the follow-up request', () {
      final assistant = _previousAssistant(id: 'asst-1', toolName: 'multi');
      final events = [
        _completedEvent(
          sessionId: 'session-1',
          toolName: 'ok.tool',
          result: '{"ok":true}',
        ),
        ToolEvent(
          eventId: 'session-1_1_bad.tool',
          timestamp: DateTime.utc(2026, 9, 5, 12, 0, 1),
          status: ToolEventStatus.failed,
          toolName: 'bad.tool',
          providerType: ToolProviderType.builtIn,
          arguments: const {},
          error: 'Permission denied',
        ),
      ];

      final built = _buildFollowup(
        previousAssistant: assistant,
        toolEvents: events,
      );

      expect(built.assistant.toolCalls!.length, 1);
      expect(built.toolMessages.length, 1);
      expect(built.assistant.toolCalls!.first.toolName, 'ok.tool');
    });

    test('assistant stopReason is set to tool_use', () {
      final assistant = _previousAssistant(id: 'asst-1', toolName: 't');
      final events = [
        _completedEvent(
          sessionId: 's',
          toolName: 't',
          result: 'ok',
        ),
      ];

      final built = _buildFollowup(
        previousAssistant: assistant,
        toolEvents: events,
      );

      expect(
        built.assistant.stopReason,
        'tool_use',
        reason:
            'Marking the assistant message with stopReason="tool_use" makes '
            'the turn boundary explicit and lets the conversation history '
            'render the tool card as a self-contained step.',
      );
    });
  });
}
