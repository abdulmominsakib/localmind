import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/chat_api_error.dart';
import 'package:localmind/features/chat/data/chat_error_formatter.dart';

void main() {
  group('ChatErrorFormatter', () {
    test('decodes Ollama envelope with type tag and humanises context error', () {
      final formatted = ChatErrorFormatter.formatBody(
        '{"error":{"code":400,"message":"request (4286 tokens) exceeds the available context size (4096 tokens), try increasing it","type":"exceed_context_size_error"}}',
        statusCode: 400,
      );
      final parsed = ChatApiError.tryParse(formatted)!;
      expect(parsed.type, 'exceed_context_size_error');
      expect(parsed.code, '400');
      expect(parsed.message, contains('context window'));
    });

    test(
      'decodes Ollama string error and humanises "does not support images"',
      () {
        final formatted = ChatErrorFormatter.formatBody(
          '{"error":"this model does not support images"}',
        );
        final parsed = ChatApiError.tryParse(formatted)!;
        expect(parsed.message, contains('vision model'));
      },
    );

    test('decodes OpenAI-style nested error and attaches status code', () {
      final formatted = ChatErrorFormatter.formatBody(
        '{"error":{"message":"Incorrect API key provided","type":"invalid_request_error","code":"invalid_api_key"}}',
        statusCode: 401,
      );
      final parsed = ChatApiError.tryParse(formatted)!;
      expect(parsed.message, contains('API key'));
      expect(parsed.type, 'invalid_request_error');
      // Either the body's code or the status code should appear.
      expect(parsed.code, anyOf('invalid_api_key', '401'));
    });

    test('falls back to status-only message when body is empty', () {
      final formatted = ChatErrorFormatter.formatBody('', statusCode: 429);
      final parsed = ChatApiError.tryParse(formatted)!;
      expect(parsed.type, 'rate_limited');
      expect(parsed.message, contains('Rate limit'));
    });

    test('humanises ECONNREFUSED-style messages', () {
      final formatted = ChatErrorFormatter.formatBody(
        '{"error":"dial tcp 127.0.0.1:11434: connect: connection refused"}',
      );
      final parsed = ChatApiError.tryParse(formatted)!;
      expect(parsed.message.toLowerCase(), contains('ollama'));
    });
  });
}
