import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';

import 'lm_studio_mcp_integration_test.dart' show buildLmStudioHarness;

void main() {
  group('context length settings migration', () {
    test('fresh settings use server-default mode', () {
      expect(AppSettings().contextLengthOverridden, isFalse);
    });

    test('saved 4096 without the flag migrates to server default', () {
      final restored = AppSettings.fromMap(const {'contextLength': 4096});
      expect(restored.contextLength, 4096);
      expect(restored.contextLengthOverridden, isFalse);
    });

    test('saved non-default value without the flag stays explicit', () {
      final restored = AppSettings.fromMap(const {'contextLength': 16384});
      expect(restored.contextLength, 16384);
      expect(restored.contextLengthOverridden, isTrue);
    });

    test('a deliberately chosen 4096 survives a round-trip', () {
      final settings = AppSettings(
        contextLength: 4096,
        contextLengthOverridden: true,
      );
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.contextLengthOverridden, isTrue);
    });
  });

  group('LM Studio chat request context_length', () {
    final server = Server(
      id: 'lms',
      name: 'LM Studio',
      type: ServerType.lmStudio,
      host: 'localhost',
      port: 1234,
      createdAt: DateTime(2026),
      lastConnectedAt: DateTime(2026),
    );
    final message = Message(
      id: 'm1',
      conversationId: 'c1',
      role: MessageRole.user,
      content: 'hi',
      createdAt: DateTime(2026),
    );

    Future<Map<String, dynamic>> sentBody(ChatParameters params) async {
      final harness = buildLmStudioHarness();
      await harness.service
          .sendMessage(
            server: server,
            modelId: 'test-model',
            messages: [message],
            params: params,
          )
          .drain<void>();
      return harness.interceptor.capturedRequest!.data as Map<String, dynamic>;
    }

    const base = ChatParameters(
      temperature: 0.7,
      topP: 0.9,
      maxTokens: 512,
      contextLength: 4096,
    );

    test('server-default mode omits context_length', () async {
      final body = await sentBody(base.copyWith(contextLengthExplicit: false));
      expect(body.containsKey('context_length'), isFalse);
    });

    test('an explicit 4096 is still sent', () async {
      final body = await sentBody(base);
      expect(body['context_length'], 4096);
    });

    test('requestedContextLength is null only in server-default mode', () {
      expect(base.requestedContextLength, 4096);
      expect(
        base.copyWith(contextLengthExplicit: false).requestedContextLength,
        isNull,
      );
    });
  });
}
