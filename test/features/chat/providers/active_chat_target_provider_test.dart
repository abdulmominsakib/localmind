import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';

void main() {
  test('uses a loaded on-device model without an explicit selection', () {
    final container = ProviderContainer(
      overrides: [
        activeServerProvider.overrideWith(_OnDeviceServerNotifier.new),
        onDeviceEngineProvider.overrideWith(_LoadedEngineNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final target = container.read(activeChatTargetProvider);

    expect(target.isReady, isTrue);
    expect(target.effectiveModelId, 'smollm2-135m-instruct');
    expect(target.modelLabel, 'SmolLM 135M Instruct');
  });

  test('does not treat a native restored spec as a loaded model', () {
    final container = ProviderContainer(
      overrides: [
        activeServerProvider.overrideWith(_OnDeviceServerNotifier.new),
        onDeviceEngineProvider.overrideWith(_EmptyEngineNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final target = container.read(activeChatTargetProvider);

    expect(target.isReady, isFalse);
    expect(target.effectiveModelId, isNull);
    expect(target.modelLabel, 'No model');
  });

  test('keeps default routing for a selected remote server', () {
    final container = ProviderContainer(
      overrides: [activeServerProvider.overrideWith(_RemoteServerNotifier.new)],
    );
    addTearDown(container.dispose);

    final target = container.read(activeChatTargetProvider);

    expect(target.isReady, isTrue);
    expect(target.effectiveModelId, 'default');
    expect(target.modelLabel, 'Default model');
  });
}

class _OnDeviceServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => _server(ServerType.onDevice, 'On-Device');
}

class _RemoteServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => _server(ServerType.ollama, 'Ollama');
}

class _LoadedEngineNotifier extends OnDeviceEngineNotifier {
  @override
  OnDeviceEngineState build() => const OnDeviceEngineState(
    status: OnDeviceEngineStatus.loaded,
    loadedModelId: 'smollm2-135m-instruct',
  );
}

class _EmptyEngineNotifier extends OnDeviceEngineNotifier {
  @override
  OnDeviceEngineState build() => const OnDeviceEngineState();
}

Server _server(ServerType type, String name) => Server(
  id: type == ServerType.onDevice ? 'on-device' : 'remote',
  name: name,
  type: type,
  host: 'localhost',
  port: 11434,
  createdAt: DateTime.utc(2026, 8, 13),
  lastConnectedAt: DateTime.utc(2026, 8, 13),
  status: ConnectionStatus.connected,
);
