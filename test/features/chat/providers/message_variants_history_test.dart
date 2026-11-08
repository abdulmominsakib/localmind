import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/utils/message_variants.dart';

void main() {
  test('reopening a legacy chat keeps its history and newer replies', () {
    final history = [
      _message('old-user', MessageRole.user, 0),
      _message('old-assistant', MessageRole.assistant, 1),
      _message('new-user', MessageRole.user, 2, parent: 'old-assistant'),
      _message('new-assistant', MessageRole.assistant, 3, parent: 'new-user'),
    ];

    expect(
      MessageVariants.resolveActiveTimeline(
        history,
      ).map((message) => message.id),
      ['old-user', 'old-assistant', 'new-user', 'new-assistant'],
    );
  });

  test('keeps later messages attached to a legacy tool result', () {
    final history = [
      _message('user', MessageRole.user, 0),
      _message('call', MessageRole.assistant, 1, parent: 'user'),
      _message('tool-a', MessageRole.tool, 1, parent: 'call'),
      _message('tool-b', MessageRole.tool, 1, parent: 'call'),
      _message('reply', MessageRole.assistant, 2, parent: 'call'),
      _message('next-user', MessageRole.user, 3, parent: 'tool-a'),
    ];

    expect(
      MessageVariants.resolveActiveTimeline(
        history,
      ).map((message) => message.id),
      ['user', 'call', 'tool-a', 'tool-b', 'reply', 'next-user'],
    );
  });
}

Message _message(String id, MessageRole role, int order, {String? parent}) {
  return Message(
    id: id,
    conversationId: 'chat',
    role: role,
    content: id,
    createdAt: DateTime.utc(2026, 11, 8),
    threadOrder: order,
    parentMessageId: parent,
  );
}
