import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/app.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  late GoRouter router;

  setUp(() {
    router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const Text('Home'),
            ),
            GoRoute(
              path: AppRoutes.ttsModels,
              builder: (context, state) => const Text('TTS models'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    String location = AppRoutes.home,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    router.go(location);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatProvider.overrideWith(_StubChatNotifier.new),
          activeServerProvider.overrideWith(_StubActiveServerNotifier.new),
          serversProvider.overrideWith(_StubServersNotifier.new),
          ttsProvider.overrideWith(_StubTtsNotifier.new),
        ],
        child: ShadTheme(
          data: AppTheme.lightShadTheme,
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('back on empty mobile home opens the drawer without crashing', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
    expect(scaffold.isDrawerOpen, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back from TTS returns home, then opens the drawer safely', (
    tester,
  ) async {
    await pumpShell(tester, location: AppRoutes.ttsModels);
    expect(find.text('TTS models'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pump();

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
    expect(scaffold.isDrawerOpen, isTrue);
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
