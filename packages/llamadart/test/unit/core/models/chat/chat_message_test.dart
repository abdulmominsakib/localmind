import 'package:test/test.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';

void main() {
  group('LlamaChatMessage serialization', () {
    test('standard text message', () {
      final msg = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Hello',
      );
      expect(msg.toJson(), {'role': 'user', 'content': 'Hello'});
      expect(msg.continuesPreviousTurn, isFalse);
    });

    test(
      'continuation marker survives copies without entering prompt JSON',
      () {
        final message = LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'tool result',
          continuesPreviousTurn: true,
        );

        final copied = message.copyWith(content: 'updated tool result');

        expect(message.continuesPreviousTurn, isTrue);
        expect(copied.continuesPreviousTurn, isTrue);
        expect(copied.toJson(), {
          'role': 'user',
          'content': 'updated tool result',
        });
      },
    );

    test('multimodal message with multiple text parts', () {
      final msg = LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [LlamaTextContent('Part 1'), LlamaTextContent('Part 2')],
      );
      expect(msg.toJson(), {'role': 'user', 'content': 'Part 1Part 2'});
    });

    test('multimodal message with multiple text parts (multimodal format)', () {
      final msg = LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [LlamaTextContent('Part 1'), LlamaTextContent('Part 2')],
      );
      expect(msg.toJsonMultimodal(), {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Part 1Part 2'},
        ],
      });
    });

    test('thinking message (reasoning_content)', () {
      final msg = LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          LlamaThinkingContent('Let me think...'),
          LlamaTextContent('The answer is 42.'),
        ],
      );
      expect(msg.toJson(), {
        'role': 'assistant',
        'reasoning_content': 'Let me think...',
        'content': 'The answer is 42.',
      });
    });

    test('assistant message with thinking but no final content', () {
      final msg = LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [LlamaThinkingContent('I am thinking...')],
      );
      expect(msg.toJson(), {
        'role': 'assistant',
        'reasoning_content': 'I am thinking...',
        'content': null,
      });
    });

    test('tool call message', () {
      final msg = LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          LlamaToolCallContent(
            id: 'call_1',
            name: 'get_weather',
            arguments: {'city': 'London'},
            rawJson: '{"city": "London"}',
          ),
        ],
      );
      expect(msg.toJson(), {
        'role': 'assistant',
        'tool_calls': [
          {
            'type': 'function',
            'function': {
              'name': 'get_weather',
              'arguments': '{"city": "London"}',
            },
            'id': 'call_1',
          },
        ],
        'content': null,
      });
    });

    test('combined thinking and tool call', () {
      final msg = LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          LlamaThinkingContent('I should check the weather.'),
          LlamaToolCallContent(
            id: 'call_1',
            name: 'get_weather',
            arguments: {'city': 'London'},
            rawJson: '{"city": "London"}',
          ),
        ],
      );
      expect(msg.toJson(), {
        'role': 'assistant',
        'reasoning_content': 'I should check the weather.',
        'tool_calls': [
          {
            'type': 'function',
            'function': {
              'name': 'get_weather',
              'arguments': '{"city": "London"}',
            },
            'id': 'call_1',
          },
        ],
        'content': null,
      });
    });

    test('tool result message', () {
      final msg = LlamaChatMessage.withContent(
        role: LlamaChatRole
            .tool, // role is ignored in constructor but used in toJson
        content: [
          LlamaToolResultContent(
            id: 'call_1',
            name: 'get_weather',
            result: 'Sunny, 20°C',
          ),
        ],
      );
      expect(msg.toJson(), {
        'role': 'tool',
        'tool_call_id': 'call_1',
        'name': 'get_weather',
        'content': 'Sunny, 20°C',
      });
    });
  });
}
