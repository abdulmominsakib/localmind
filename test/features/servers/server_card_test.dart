import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/views/components/server_card.dart';
import 'package:localmind/l10n/app_localizations.dart';

Widget _wrapWithApp(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

Server _buildServer({
  String name = 'llama home',
  ServerType type = ServerType.ollama,
  String host = '192.168.0.210',
  int port = 11434,
  bool isDefault = false,
  ConnectionStatus status = ConnectionStatus.disconnected,
}) {
  return Server(
    id: 'test-id',
    name: name,
    type: type,
    host: host,
    port: port,
    isDefault: isDefault,
    createdAt: DateTime(2026, 1, 1),
    lastConnectedAt: DateTime(2026, 1, 1),
    status: status,
  );
}

void main() {
  group('ServerCard', () {
    testWidgets('renders server name, type chip and address',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ServerCard(server: _buildServer()),
        ),
      );
      await tester.pump();

      expect(find.text('llama home'), findsOneWidget);
      // Type chip should render the localized ollama display name.
      expect(find.text('Ollama'), findsOneWidget);
      // Address row should render the IP:port.
      expect(find.text('192.168.0.210:11434'), findsOneWidget);
    });

    testWidgets('shows the Offline status pill when disconnected',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ServerCard(server: _buildServer()),
        ),
      );
      await tester.pump();

      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('shows the Connected status pill when connected',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ServerCard(
            server: _buildServer(status: ConnectionStatus.connected),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('shows the Checking status pill while checking',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ServerCard(
            server: _buildServer(status: ConnectionStatus.checking),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Checking'), findsOneWidget);
    });

    testWidgets('shows the default star indicator when server is default',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ServerCard(server: _buildServer(isDefault: true)),
        ),
      );
      await tester.pump();

      // The star icon (Tooltip wraps the icon) should be present.
      expect(find.byTooltip('Default'), findsOneWidget);
    });

    testWidgets('invokes onTap when the card is tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrapWithApp(
          ServerCard(
            server: _buildServer(),
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(ServerCard));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('renders different content for on-device servers',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          ServerCard(
            server: _buildServer(
              name: 'On-Device',
              type: ServerType.onDevice,
              host: '',
              port: 0,
            ),
          ),
        ),
      );
      await tester.pump();

      // The name and the on-device type chip both render "On-Device".
      expect(find.text('On-Device'), findsWidgets);
      // On-device uses a localized placeholder for the address.
      expect(find.text('Local inference'), findsOneWidget);
    });
  });
}