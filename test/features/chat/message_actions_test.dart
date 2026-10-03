import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/views/components/message_action_bar.dart';
import 'package:localmind/features/chat/views/components/message_actions_sheet.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';

void main() {
  Future<void> pumpBar(WidgetTester tester, MessageActions actions) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ttsProvider.overrideWith(_StubTtsNotifier.new)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MessageActionBar(actions: actions)),
        ),
      ),
    );
  }

  testWidgets('reply row shows only copy, retry, listen and more', (
    tester,
  ) async {
    await pumpBar(
      tester,
      MessageActions(
        content: 'Hello',
        onRetry: () {},
        onDelete: () {},
        onEdit: () {},
        onShare: () {},
        onSave: () {},
      ),
    );

    expect(find.byType(MessageActionButton), findsNWidgets(4));
    expect(find.byKey(const ValueKey('message_action_retry')), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);
  });

  testWidgets('more opens the sheet with the remaining actions and stats', (
    tester,
  ) async {
    var edited = false;
    await pumpBar(
      tester,
      MessageActions(
        content: 'Hello',
        modelId: 'qwen3-4b',
        tokenCount: 64,
        onRetry: () {},
        onEdit: () => edited = true,
        onDelete: () {},
        onModelInfo: () {},
      ),
    );

    await tester.tap(find.byKey(const ValueKey('message_action_more')));
    await tester.pumpAndSettle();

    expect(find.byType(MessageActionsSheet), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('qwen3-4b'), findsOneWidget);
    expect(find.textContaining(' 64', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(edited, isTrue);
    expect(find.byType(MessageActionsSheet), findsNothing);
  });
}

class _StubTtsNotifier extends TtsNotifier {
  @override
  TtsState build() => const TtsState();
}
