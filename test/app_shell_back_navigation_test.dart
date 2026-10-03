import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/app.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/core/routes/shell_back_scope.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  late GoRouter router;
  late List<MethodCall> platformCalls;
  late Widget Function(Widget) wrapShell;

  setUp(() {
    wrapShell = (child) => child;
    router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        ShellRoute(
          builder: (context, state, child) => wrapShell(AppShell(child: child)),
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) =>
                  const ShellBackScope(child: Text('Home')),
            ),
            GoRoute(
              path: AppRoutes.ttsModels,
              builder: (context, state) =>
                  const ShellBackScope(child: Text('TTS models')),
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

    platformCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    // The framework only reports back handling to the engine once the app
    // has a lifecycle state.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

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
    await tester.pumpAndSettle();
  }

  /// Whether the framework last told Android it handles back itself. When
  /// false, Android 16+ (predictive back) closes the app without asking.
  bool? frameworkHandlesBack() {
    final calls = platformCalls.where(
      (call) => call.method == 'SystemNavigator.setFrameworkHandlesBack',
    );
    return calls.isEmpty ? null : calls.last.arguments as bool;
  }

  bool exitedApp() =>
      platformCalls.any((call) => call.method == 'SystemNavigator.pop');

  ScaffoldState shellScaffold(WidgetTester tester) =>
      tester.state<ScaffoldState>(find.byType(Scaffold));

  testWidgets('back on empty home with the drawer closed leaves the app', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(frameworkHandlesBack(), isFalse);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(exitedApp(), isTrue);
    expect(shellScaffold(tester).isDrawerOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back from TTS is claimed by the app and returns home', (
    tester,
  ) async {
    await pumpShell(tester, location: AppRoutes.ttsModels);
    expect(find.text('TTS models'), findsOneWidget);
    // Regression: with the PopScope on the shell's root route, this was
    // false and Android 16+ closed the app instead of going home.
    expect(frameworkHandlesBack(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(exitedApp(), isFalse);
    expect(frameworkHandlesBack(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back closes an open drawer before anything else', (
    tester,
  ) async {
    await pumpShell(tester, location: AppRoutes.ttsModels);

    shellScaffold(tester).openDrawer();
    await tester.pumpAndSettle();
    expect(shellScaffold(tester).isDrawerOpen, isTrue);
    expect(frameworkHandlesBack(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(shellScaffold(tester).isDrawerOpen, isFalse);
    expect(find.text('TTS models'), findsOneWidget);
    expect(exitedApp(), isFalse);
  });

  testWidgets('back on empty home closes the drawer instead of exiting', (
    tester,
  ) async {
    await pumpShell(tester);

    shellScaffold(tester).openDrawer();
    await tester.pumpAndSettle();
    expect(frameworkHandlesBack(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(shellScaffold(tester).isDrawerOpen, isFalse);
    expect(exitedApp(), isFalse);
    expect(frameworkHandlesBack(), isFalse);
  });

  testWidgets('an overlay above the shell can claim back', (tester) async {
    var overrideCalls = 0;
    wrapShell = (child) =>
        ShellBackOverride(onBack: () => overrideCalls++, child: child);
    await pumpShell(tester);
    expect(frameworkHandlesBack(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(overrideCalls, 1);
    expect(exitedApp(), isFalse);
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
