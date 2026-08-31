import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/providers/chat_notifier.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';

// Regression test for issue #73:
//   "Crash: Cannot use the Ref of NotifierProvider<ChatNotifier, ChatState>...
//    after it has been disposed."
//
// The bug: `_saveMessage` evaluated `_isInMemoryChat` (which reads `state`)
// BEFORE checking `ref.mounted`. On a disposed notifier, reading `state`
// throws. The fix is to check `ref.mounted` first, then fall back to the
// `_isInMemoryChat` short-circuit.
void main() {
  test(
    '_saveMessage does not throw when the provider is disposed before call',
    () async {
      final container = ProviderContainer(
        overrides: [
          activeServerProvider.overrideWith(_ConnectedServerNotifier.new),
          onDeviceEngineProvider.overrideWith(_EmptyEngineNotifier.new),
          chatProvider.overrideWith(_DisposedChatNotifier.new),
        ],
      );

      // Read the notifier once to instantiate it, then dispose the container
      // so any subsequent call to `state` would normally throw
      // "Cannot use the Ref ... after it has been disposed".
      final notifier = container.read(chatProvider.notifier);
      container.dispose();

      // This used to throw before the fix because `_saveMessage` touched
      // `_isInMemoryChat` (=> `state`) before `ref.mounted`.
      expect(
        () => notifier.debugSaveMessageForTest(_dummyMessage()),
        returnsNormally,
      );
    },
  );
}

Message _dummyMessage() => Message(
  id: 'msg-1',
  conversationId: 'conv-1',
  role: MessageRole.user,
  content: 'hello',
  createdAt: DateTime.utc(2026, 8, 29),
);

class _EmptyEngineNotifier extends OnDeviceEngineNotifier {
  @override
  OnDeviceEngineState build() => const OnDeviceEngineState();
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

class _DisposedChatNotifier extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
}