import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/providers/chat_notifier.dart';

void main() {
  group('shouldIncludeMessageInChatContext', () {
    test('drops empty errored assistant placeholders', () {
      final message = _message(
        role: MessageRole.assistant,
        status: MessageStatus.error,
        content: '',
      );

      expect(shouldIncludeMessageInChatContext(message), isFalse);
    });

    test('keeps assistant errors that already have content', () {
      final message = _message(
        role: MessageRole.assistant,
        status: MessageStatus.error,
        content: 'Partial response',
      );

      expect(shouldIncludeMessageInChatContext(message), isTrue);
    });

    test('keeps non-assistant messages and completed assistant messages', () {
      expect(
        shouldIncludeMessageInChatContext(
          _message(role: MessageRole.user, content: 'hello'),
        ),
        isTrue,
      );
      expect(
        shouldIncludeMessageInChatContext(
          _message(role: MessageRole.assistant, content: 'hi'),
        ),
        isTrue,
      );
    });
  });
}

Message _message({
  required MessageRole role,
  MessageStatus status = MessageStatus.complete,
  String content = '',
}) {
  return Message(
    id: 'message-${role.name}-${status.name}-$content',
    conversationId: 'conversation-1',
    role: role,
    content: content,
    createdAt: DateTime.utc(2026, 9, 21),
    status: status,
  );
}
