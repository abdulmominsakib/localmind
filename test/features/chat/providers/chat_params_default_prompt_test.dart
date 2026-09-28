import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/chat/providers/chat_params_providers.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> container({Conversation? conversation}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsProvider.overrideWith(_SettingsNotifier.new),
        conv.activeConversationProvider.overrideWith(
          () => _ActiveConversation(conversation),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('uses the default system prompt when the chat has none (#81)', () async {
    final c = await container();
    final params = c.read(chatParamsProvider);

    expect(params.systemPrompt, 'Default prompt');
    expect(params.sendTemperature, isFalse);
    expect(params.sendTopP, isTrue);
  });

  test('a chat-specific prompt wins over the default', () async {
    final c = await container(
      conversation: Conversation(
        id: 'c1',
        title: 'Chat',
        createdAt: DateTime.utc(2026, 9, 28),
        updatedAt: DateTime.utc(2026, 9, 28),
        systemPrompt: 'Chat prompt',
      ),
    );

    expect(c.read(chatParamsProvider).systemPrompt, 'Chat prompt');
  });
}

class _SettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings(
    defaultSystemPrompt: 'Default prompt',
    sendTemperature: false,
  );
}

class _ActiveConversation extends conv.ActiveConversationNotifier {
  _ActiveConversation(this._conversation);
  final Conversation? _conversation;

  @override
  Conversation? build() => _conversation;
}
