import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/views/components/chat_bubble/assistant_bubble.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness({
    required SharedPreferences prefs,
    required Message message,
    required bool isStreaming,
  }) {
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AssistantBubble(message: message, isStreaming: isStreaming),
        ),
      ),
    );
  }

  testWidgets(
    'AssistantBubble streaming content disables SelectionArea to prevent concurrent modification crash',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final message = Message(
        id: 'msg-stream',
        conversationId: 'conv-1',
        role: MessageRole.assistant,
        content: 'Streaming response token by token...',
        createdAt: DateTime.now(),
        status: MessageStatus.streaming,
      );

      await tester.pumpWidget(
        buildHarness(prefs: prefs, message: message, isStreaming: true),
      );
      await tester.pump();

      // When streaming, SelectionArea must not wrap the live-mutating markdown
      expect(find.byType(SelectionArea), findsNothing);
      expect(find.text('Streaming response token by token...'), findsOneWidget);
    },
  );

  testWidgets(
    'AssistantBubble completed content enables SelectionArea for copy and selection',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final message = Message(
        id: 'msg-done',
        conversationId: 'conv-1',
        role: MessageRole.assistant,
        content: 'Final completed response.',
        createdAt: DateTime.now(),
        status: MessageStatus.complete,
      );

      await tester.pumpWidget(
        buildHarness(prefs: prefs, message: message, isStreaming: false),
      );
      await tester.pump();

      // When completed, SelectionArea should wrap the markdown content
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.text('Final completed response.'), findsOneWidget);
    },
  );
}
