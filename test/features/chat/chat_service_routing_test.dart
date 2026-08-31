import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/on_device_chat_service.dart';
import 'package:localmind/features/on_device/data/on_device_gemma_service.dart';
import 'package:localmind/features/on_device/data/on_device_llama_service.dart';
import 'package:localmind/features/on_device/data/on_device_mlx_service.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('createChatServiceForServer', () {
    test('routes imported GGUF models to llama.cpp service', () {
      final service = createChatServiceForServer(
        server: _onDeviceServer(),
        dio: Dio(),
        onDeviceGemmaService: OnDeviceGemmaService(),
        onDeviceLlamaService: OnDeviceLlamaService(),
        loadedOnDeviceRuntime: OnDeviceModelRuntime.llamaCpp,
      );

      expect(service, isA<OnDeviceLlamaChatService>());
    });

    test('routes curated on-device models to Gemma service', () {
      final service = createChatServiceForServer(
        server: _onDeviceServer(),
        dio: Dio(),
        onDeviceGemmaService: OnDeviceGemmaService(),
        onDeviceLlamaService: OnDeviceLlamaService(),
        loadedOnDeviceRuntime: OnDeviceModelRuntime.gemma,
      );

      expect(service, isA<OnDeviceChatService>());
    });

    test('routes an MLX runtime to the MLX chat adapter', () {
      final service = createChatServiceForServer(
        server: _onDeviceServer(),
        dio: Dio(),
        onDeviceGemmaService: OnDeviceGemmaService(),
        onDeviceLlamaService: OnDeviceLlamaService(),
        onDeviceMlxService: OnDeviceMlxService(Dio()),
        loadedOnDeviceRuntime: OnDeviceModelRuntime.mlx,
      );

      expect(service, isA<OnDeviceMlxChatService>());
    });
  });

  test('exposes MLX downloads on Apple platforms (iOS, iPadOS, macOS)', () {
    expect(
      availableCuratedMlxModels(isIOS: true),
      OnDeviceModel.curatedMlxModels,
    );
    expect(
      availableCuratedMlxModels(isMacOS: true),
      OnDeviceModel.curatedMlxModels,
    );
    expect(
      availableCuratedMlxModels(
        isApplePlatform: false,
        isIOS: false,
        isMacOS: false,
      ),
      isEmpty,
    );
  });

  group('chatServiceProvider', () {
    test(
      'only recreates when loadedRuntime changes, not on every status change',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            activeServerProvider.overrideWith(_StubActiveServerNotifier.new),
            onDeviceGemmaServiceProvider.overrideWithValue(
              _FakeOnDeviceGemmaService(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final initialService = container.read(chatServiceProvider);
        expect(initialService, isA<OnDeviceChatService>());

        // Toggle status without changing runtime — the service instance must be
        // preserved so we don't drop an in-flight chat.
        container.read(onDeviceEngineProvider.notifier).state =
            const OnDeviceEngineState(status: OnDeviceEngineStatus.loading);
        final stillSameService = container.read(chatServiceProvider);
        expect(identical(initialService, stillSameService), isTrue);

        // Switching the runtime rebuilds the service so it can pick up the
        // llama.cpp adapter.
        container
            .read(onDeviceEngineProvider.notifier)
            .state = const OnDeviceEngineState(
          status: OnDeviceEngineStatus.loaded,
          loadedRuntime: OnDeviceModelRuntime.llamaCpp,
        );
        final llamaService = container.read(chatServiceProvider);
        expect(llamaService, isA<OnDeviceLlamaChatService>());
      },
    );
  });
}

class _StubActiveServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => _onDeviceServer();
}

class _FakeOnDeviceGemmaService extends OnDeviceGemmaService {
  @override
  Future<List<String>> getInstalledModelIds() async => const [];
}

Server _onDeviceServer() {
  return Server(
    id: 'on-device',
    name: 'On-Device',
    type: ServerType.onDevice,
    host: '',
    port: 0,
    createdAt: DateTime.utc(2026, 6, 21),
    lastConnectedAt: DateTime.utc(2026, 6, 21),
    status: ConnectionStatus.connected,
  );
}
