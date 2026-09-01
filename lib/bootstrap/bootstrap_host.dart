import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import '../core/providers/app_providers.dart';
import '../core/providers/highlighter_provider.dart';
import '../core/providers/storage_providers.dart';
import '../core/storage/objectbox_store.dart';
import '../features/on_device/data/on_device_gemma_service.dart';
import '../features/on_device/providers/on_device_providers.dart';
import '../core/models/enums.dart';
import '../features/personas/providers/personas_providers.dart';
import '../features/servers/data/models/server.dart';
import '../features/servers/providers/server_providers.dart';
import '../features/cloud_sync/views/cloud_sync_lifecycle_host.dart';
import '../core/logger/app_logger.dart';
import '../core/utils/locale_utils.dart';
import 'bootstrap_screen.dart';
import 'bootstrap_state.dart';

class BootstrapHost extends StatefulWidget {
  const BootstrapHost({super.key});

  @override
  State<BootstrapHost> createState() => _BootstrapHostState();
}

class _BootstrapHostState extends State<BootstrapHost> {
  BootstrapState _state = const BootstrapState();
  ProviderContainer? _container;
  Locale? _savedLocale;

  @override
  void initState() {
    super.initState();
    _runBootstrap();
  }

  Future<void> _runBootstrap() async {
    _updateStage(BootstrapStage.initializing, 'Initializing...');

    try {
      final results = await Future.wait([
        initializeHighlighter(),
        SharedPreferences.getInstance(),
        ObjectBoxStore.create(),
      ]);

      final prefs = results[1] as SharedPreferences;
      final database = results[2] as ObjectBoxStore;

      // Seed built-in personas once before any provider reads the database.
      PersonasNotifier.seedIfNeeded(database);

      _updateStage(BootstrapStage.preparingApp, 'Preparing app...');

      try {
        final settingsJson = prefs.getString('appSettings');
        if (settingsJson != null) {
          final settings = json.decode(settingsJson) as Map<String, dynamic>;
          final code = settings['localeCode'] as String?;
          _savedLocale = parseLocaleCode(code);
        }
      } catch (_) {}

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(database),
        ],
      );

      _updateStage(
        BootstrapStage.initializingServices,
        'Initializing services...',
      );

      final hfToken = container.read(
        settingsProvider.select((s) => s.huggingFaceToken),
      );
      await OnDeviceGemmaService.initialize(huggingFaceToken: hfToken);

      // Migrate models from old custom download location in background to prevent cold start ANR
      OnDeviceGemmaService.migrateOldModels().catchError((e) {
        Log.error('Error migrating old models: $e');
        return 0;
      });

      _updateStage(BootstrapStage.configuringServer, 'Configuring server...');
      final servers = await container.read(serversProvider.future);
      final hasOnDevice = servers.any((s) => s.type == ServerType.onDevice);
      if (!hasOnDevice) {
        final server = Server(
          id: 'on-device',
          name: 'On-Device',
          type: ServerType.onDevice,
          host: '',
          port: 0,
          isDefault: false,
          createdAt: DateTime.now(),
          lastConnectedAt: DateTime.now(),
          status: ConnectionStatus.connected,
          iconName: 'strokeRoundedSmartPhone01',
        );
        await container.read(serversProvider.notifier).addServer(server);
      }

      // Eagerly resolve foundational state providers so their initial state
      // is stable before UncontrolledProviderScope mounts the widget tree.
      container.read(settingsProvider);
      container.read(activeServerIdProvider);
      container.read(activeServerProvider);
      container.read(connectionStatusProvider);
      container.read(onDeviceEngineProvider);

      _container = container;
      _updateStage(BootstrapStage.done, 'Ready');
    } catch (e) {
      _state = BootstrapState(
        stage: BootstrapStage.error,
        statusMessage: 'Startup failed',
        error: e,
      );
      if (mounted) setState(() {});
    }
  }

  void _updateStage(BootstrapStage stage, String message) {
    if (!mounted) return;
    setState(() {
      _state = BootstrapState(stage: stage, statusMessage: message);
    });
  }

  @override
  void dispose() {
    _container?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_container != null) {
      return UncontrolledProviderScope(
        container: _container!,
        child: const CloudSyncLifecycleHost(child: App()),
      );
    }

    return BootstrapScreen(
      state: _state,
      locale: _savedLocale,
      onRetry: _state.stage == BootstrapStage.error ? _runBootstrap : null,
    );
  }
}
