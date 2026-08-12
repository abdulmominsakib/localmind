import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/sidebar/components/active_server_indicator.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('Manage Servers closes the sheet and drawer before navigating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final server = Server(
      id: 'on-device',
      name: 'Test Server',
      type: ServerType.onDevice,
      host: '',
      port: 0,
      createdAt: DateTime.utc(2026, 8, 12),
      lastConnectedAt: DateTime.utc(2026, 8, 12),
      status: ConnectionStatus.connected,
    );
    final scaffoldKey = GlobalKey<ScaffoldState>();
    final router = GoRouter(
      routes: [
        ShellRoute(
          builder: (context, state, child) => Scaffold(
            key: scaffoldKey,
            drawer: const Drawer(child: ActiveServerIndicator()),
            body: child,
          ),
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const Text('Home page'),
            ),
            GoRoute(
              path: AppRoutes.servers,
              builder: (context, state) => const Text('Servers page'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeServerProvider.overrideWith(
            () => _StubActiveServerNotifier(server),
          ),
          serversProvider.overrideWith(() => _StubServersNotifier(server)),
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

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(scaffoldKey.currentState!.isDrawerOpen, isTrue);

    await tester.tap(find.text('Test Server'));
    await tester.pumpAndSettle();
    expect(find.text('Switch Server'), findsOneWidget);

    await tester.tap(find.text('Manage Servers'));
    await tester.pumpAndSettle();

    expect(find.text('Servers page'), findsOneWidget);
    expect(find.text('Switch Server'), findsNothing);
    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _StubActiveServerNotifier extends ActiveServerNotifier {
  _StubActiveServerNotifier(this.server);

  final Server server;

  @override
  Server? build() => server;
}

class _StubServersNotifier extends ServersNotifier {
  _StubServersNotifier(this.server);

  final Server server;

  @override
  Future<List<Server>> build() async => [server];
}
