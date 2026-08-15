import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/chat/views/components/chat_input_bar.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ChatInputBar handles explorer_not_found error safely',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
      (MethodCall methodCall) async {
        throw PlatformException(
          code: 'explorer_not_found',
          message:
              "Can't find a valid activity to handle the request. Make sure you have a file explorer installed.",
        );
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          chatProvider.overrideWith(_StubChatNotifier.new),
          activeServerProvider.overrideWith(_StubActiveServerNotifier.new),
          serversProvider.overrideWith(_StubServersNotifier.new),
          ttsProvider.overrideWith(_StubTtsNotifier.new),
        ],
        child: ShadTheme(
          data: AppTheme.lightShadTheme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChatInputBar(
                onSend: (text, {attachments}) {},
                onStop: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(ChatInputBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _StubChatNotifier extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
}

class _StubActiveServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => null;
}

class _StubServersNotifier extends ServersNotifier {
  @override
  Future<List<Server>> build() async => const [];
}

class _StubTtsNotifier extends TtsNotifier {
  @override
  TtsState build() => const TtsState();
}
