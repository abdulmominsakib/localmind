import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/providers/chat_notifier.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';

void main() {
  test('sendMessage refuses to send when no model is selected', () async {
    final container = ProviderContainer(
      overrides: [
        activeServerProvider.overrideWith(_ConnectedServerNotifier.new),
        onDeviceEngineProvider.overrideWith(_EmptyEngineNotifier.new),
        chatProvider.overrideWith(_GuardTestChatNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatProvider.notifier).sendMessage('hello');

    final state = container.read(chatProvider);
    expect(state.errorMessage, modelSelectionRequiredMessage);
    expect(state.messages, isEmpty);
    expect(state.allMessages, isEmpty);
    expect(state.isStreaming, isFalse);
  });
}

class _EmptyEngineNotifier extends OnDeviceEngineNotifier {
  @override
  OnDeviceEngineState build() => const OnDeviceEngineState();
}

class _GuardTestChatNotifier extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
}

class _ConnectedServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => Server(
    id: 'on-device',
    name: 'On-Device',
    type: ServerType.onDevice,
    host: '',
    port: 0,
    createdAt: DateTime.utc(2026, 8, 13),
    lastConnectedAt: DateTime.utc(2026, 8, 13),
    status: ConnectionStatus.connected,
  );
}
