import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/chat/views/components/token_usage_indicator.dart';
import 'package:localmind/l10n/app_localizations.dart';

class _TestChatNotifier extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
}

void main() {
  testWidgets('uses the configured per-chat context length', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatParamsProvider.overrideWithValue(
            const ChatParameters(
              temperature: 0.7,
              topP: 0.9,
              maxTokens: 2048,
              contextLength: 16384,
            ),
          ),
          chatProvider.overrideWith(_TestChatNotifier.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: TokenUsageIndicator(totalTokenCount: 8192),
          ),
        ),
      ),
    );

    expect(find.text('50%'), findsOneWidget);
    await tester.tap(find.byType(TokenUsageIndicator));
    await tester.pumpAndSettle();

    expect(find.text('16384'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget);
  });
}
