import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/features/models/components/model_list.dart';
import 'package:localmind/features/models/components/model_tile.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _server = Server(
  id: 'test-server',
  name: 'Provider',
  type: ServerType.openAICompatible,
  host: 'https://example.com',
  port: 443,
  createdAt: DateTime.utc(2026),
  lastConnectedAt: DateTime.utc(2026),
  status: ConnectionStatus.connected,
);

final _text = ModelInfo(
  id: 'dual',
  name: 'Dual model',
  serverType: _server.type,
  serverId: _server.id,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('manual IDs survive catalog failure and refresh after edits', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        serversProvider.overrideWith(_Servers.new),
        activeServerProvider.overrideWith(_ActiveServer.new),
        connectionStatusProvider.overrideWith(_Offline.new),
        availableModelsProvider(
          _server.id,
        ).overrideWith((_) async => throw StateError('No catalog')),
      ],
    );
    addTearDown(container.dispose);
    final manualIds = manualImageModelIdsProvider(_server.id);
    await container
        .read(manualIds.notifier)
        .setIds('custom/image, custom/image\n second ');
    expect(container.read(manualIds), ['custom/image', 'second']);

    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();
    expect(find.text('Image generation'), findsOneWidget);
    expect(find.text('custom/image'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);

    await tester.runAsync(
      () => container.read(manualIds.notifier).setIds('new-image'),
    );
    await tester.pumpAndSettle();
    expect(find.text('new-image'), findsOneWidget);
    expect(find.text('custom/image'), findsNothing);
  });

  testWidgets('selects only the image row when a model ID has both modes', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        serversProvider.overrideWith(_Servers.new),
        activeServerProvider.overrideWith(_ActiveServer.new),
        connectionStatusProvider.overrideWith(_Connected.new),
        availableModelsProvider(_server.id).overrideWith(
          (_) async => [_text, _text.copyWith(isImageGeneration: true)],
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();
    final rows = tester.widgetList<ModelTile>(find.byType(ModelTile)).toList();
    expect(rows, hasLength(2));
    expect(
      rows.where((row) => row.isSelected).single.model.isImageGeneration,
      isTrue,
    );
    await tester.tap(find.widgetWithText(ModelTile, 'Dual model').last);
    expect(container.read(selectedModelProvider)?.isImageGeneration, isTrue);
  });

  testWidgets('a failed image catalog leaves text choices visible', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        serversProvider.overrideWith(_Servers.new),
        activeServerProvider.overrideWith(_ActiveServer.new),
        connectionStatusProvider.overrideWith(_Connected.new),
        additionalImageModelsProvider(_server.id).overrideWith(
          (_) async => throw StateError('Image catalog unavailable'),
        ),
        availableModelsProvider(_server.id).overrideWith((_) async => [_text]),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();
    expect(find.text('Dual model'), findsOneWidget);
    expect(find.text('Image generation'), findsOneWidget);
    expect(find.byTooltip('Retry'), findsOneWidget);
  });
}

Widget _harness(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ModelList(
        serverId: _server.id,
        selectedModelId: _text.id,
        selectedImageModel: true,
        includeImageModels: true,
        closeOnSelect: false,
        isDark: false,
      ),
    ),
  ),
);

class _Servers extends ServersNotifier {
  @override
  Future<List<Server>> build() async => [_server];
}

class _ActiveServer extends ActiveServerNotifier {
  @override
  Server? build() => _server;
}

class _Connected extends ConnectionStatusNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _Offline extends ConnectionStatusNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.error;
}
