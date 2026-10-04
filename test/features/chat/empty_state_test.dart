import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/chat/utils/new_chat_presence.dart';
import 'package:localmind/features/chat/views/components/message_list/ascii_logo_view.dart';
import 'package:localmind/features/chat/views/components/message_list/empty_state.dart';
import 'package:localmind/features/chat/views/components/message_list/quick_prompt_chips.dart';
import 'package:localmind/l10n/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ServerType? type,
  String serverName = '',
  NewChatReadiness readiness = NewChatReadiness.ready,
  bool reduceMotion = false,
  void Function(String)? onQuickPrompt,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: EmptyState(
            presence: NewChatPresence.forServerType(type),
            serverName: serverName,
            readiness: readiness,
            onQuickPrompt: onQuickPrompt ?? (_) {},
            quickPrompts: const [
              QuickPrompt(
                icon: HugeIcons.strokeRoundedSourceCode,
                text: 'Help me write a function',
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
}

String _allText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((t) => t.text.toPlainText())
    .join('\n');

void main() {
  testWidgets('on-device promises the chat stays on the phone', (tester) async {
    await _pump(tester, type: ServerType.onDevice);
    final text = _allText(tester);
    expect(text, contains('It stays on this phone.'));
    expect(text, contains('Works offline'));
  });

  testWidgets('a self-hosted server is named and makes no on-device claim', (
    tester,
  ) async {
    await _pump(tester, type: ServerType.ollama, serverName: 'Mac Studio');
    final text = _allText(tester);
    expect(text, contains('Answered by Mac Studio.'));
    expect(text, contains('not to a third party'));
    expect(text, isNot(contains('this phone')));
  });

  testWidgets('cloud providers say messages leave the device', (tester) async {
    await _pump(tester, type: ServerType.openRouter, serverName: 'Mine');
    expect(
      _allText(tester),
      contains('Messages are sent to OpenRouter and the model provider'),
    );

    await _pump(tester, type: ServerType.ollamaCloud);
    expect(
      _allText(tester),
      contains("Messages are sent to Ollama's cloud service."),
    );
  });

  testWidgets('an OpenAI-compatible endpoint makes no privacy claim', (
    tester,
  ) async {
    await _pump(
      tester,
      type: ServerType.openAICompatible,
      serverName: 'My API',
    );
    final text = _allText(tester);
    expect(text, contains('an OpenAI-compatible endpoint'));
    expect(text, isNot(contains('third party')));
  });

  testWidgets('the status pill follows readiness', (tester) async {
    await _pump(
      tester,
      type: ServerType.lmStudio,
      readiness: NewChatReadiness.noModel,
    );
    expect(_allText(tester), contains('No model selected'));

    await _pump(
      tester,
      type: ServerType.lmStudio,
      readiness: NewChatReadiness.disconnected,
    );
    expect(_allText(tester), contains('Not connected'));
    expect(_allText(tester), isNot(contains('Ready')));
  });

  testWidgets('reduced motion shows the still logo', (tester) async {
    await _pump(tester, type: ServerType.requesty, reduceMotion: true);
    final first = _allText(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_allText(tester), first);
    expect(find.byType(AsciiLogoView), findsOneWidget);
  });

  testWidgets('tapping a chip sends its prompt', (tester) async {
    String? sent;
    await _pump(
      tester,
      type: ServerType.onDevice,
      onQuickPrompt: (p) => sent = p,
    );
    await tester.tap(find.byKey(const ValueKey('quick_prompt_0')));
    expect(sent, 'Help me write a function');
  });
}
