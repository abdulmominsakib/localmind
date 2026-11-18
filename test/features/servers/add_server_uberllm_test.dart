import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/storage/entities.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/data/server_api_service.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/servers/views/add_server_screen.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CapturingServersNotifier extends ServersNotifier {
  Server? added;

  @override
  Future<List<Server>> build() async => [];

  @override
  Future<void> addServer(Server server) async {
    added = server;
  }

  @override
  Future<ConnectionStatus> testConnection(
    String serverId,
    dynamic apiService,
  ) async => ConnectionStatus.connected;
}

void main() {
  testWidgets(
    'switching from Ollama Cloud to UberLLM saves the UberLLM endpoint',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = _CapturingServersNotifier();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          serversProvider.overrideWith(() => notifier),
          serverApiServiceProvider.overrideWithValue(ServerApiService(Dio())),
        ],
      );
      addTearDown(container.dispose);

      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadTheme(
            data: AppTheme.lightShadTheme,
            child: const MaterialApp(
              locale: Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AddServerScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ollama Cloud').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('UberLLM').first);
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'My UberLLM');
      await tester.enterText(fields.last, 'ull_test');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Server'));
      await tester.pumpAndSettle();

      final saved = notifier.added;
      expect(saved, isNotNull);
      expect(saved!.type, ServerType.uberllm);
      expect(saved.host, 'https://api.uberllm.dev/v1');
      expect(saved.apiKey, 'ull_test');
      expect(
        ServerEntity.fromDomain(saved).toDomain().type,
        ServerType.uberllm,
      );
    },
  );
}
