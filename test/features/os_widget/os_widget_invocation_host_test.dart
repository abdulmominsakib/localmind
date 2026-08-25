import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/os_widget/data/models/os_widget_models.dart';
import 'package:localmind/features/os_widget/data/os_widget_service.dart';
import 'package:localmind/features/os_widget/providers/os_widget_providers.dart';
import 'package:localmind/features/os_widget/views/os_widget_invocation_host.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _TestSettingsNotifier extends SettingsNotifier {
  _TestSettingsNotifier({this.customSettings});
  final AppSettings? customSettings;

  @override
  AppSettings build() =>
      customSettings ?? AppSettings(unloadModelsBeforeLoad: false);
}

class _StubServersNotifier extends ServersNotifier {
  _StubServersNotifier([this.servers = const []]);
  final List<Server> servers;

  @override
  Future<List<Server>> build() async => servers;
}

void main() {
  group('WidgetPendingPromptNotifier', () {
    test('sets and consumes prompt', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(widgetPendingPromptProvider), isNull);

      container
          .read(widgetPendingPromptProvider.notifier)
          .setPrompt('Draft prompt from widget');
      expect(
        container.read(widgetPendingPromptProvider),
        'Draft prompt from widget',
      );

      final consumed = container
          .read(widgetPendingPromptProvider.notifier)
          .consumePrompt();
      expect(consumed, 'Draft prompt from widget');
      expect(container.read(widgetPendingPromptProvider), isNull);
    });
  });

  group('OsWidgetInvocationHost', () {
    testWidgets(
      'voice invocation with a prompt surfaces the prompt as pending',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = OsWidgetService(isSupportedOverride: true);

        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              osWidgetServiceProvider.overrideWithValue(service),
              settingsProvider.overrideWith(_TestSettingsNotifier.new),
              serversProvider.overrideWith(_StubServersNotifier.new),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const ShadApp(
                  home: Scaffold(
                    body: OsWidgetInvocationHost(child: Text('Root Body')),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        service.dispatchInvocation(
          const OsWidgetInvocation(
            action: OsWidgetAction.voice,
            prompt: 'Voice-mode preset prompt',
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final pending = container.read(widgetPendingPromptProvider);
        expect(pending, 'Voice-mode preset prompt');
      },
    );

    testWidgets(
      'renders child and handles widget prompt when default model is unset',
      (tester) async {
        final service = OsWidgetService(isSupportedOverride: true);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              osWidgetServiceProvider.overrideWithValue(service),
              settingsProvider.overrideWith(_TestSettingsNotifier.new),
              serversProvider.overrideWith(_StubServersNotifier.new),
            ],
            child: const ShadApp(
              home: Scaffold(
                body: OsWidgetInvocationHost(child: Text('App Shell Content')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('App Shell Content'), findsOneWidget);

        // Dispatch invocation with prompt
        service.dispatchInvocation(
          const OsWidgetInvocation(
            action: OsWidgetAction.chat,
            prompt: 'Quick question about Flutter',
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('App Shell Content'), findsOneWidget);
      },
    );

    testWidgets(
      'loads default model and sets pending prompt when default model is configured',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final service = OsWidgetService(isSupportedOverride: true);
        final server = Server(
          id: 'ollama-1',
          name: 'Local Ollama',
          host: 'http://localhost',
          port: 11434,
          type: ServerType.ollama,
          createdAt: DateTime.now(),
          lastConnectedAt: DateTime.now(),
        );
        final model = ModelInfo(
          id: 'llama3:8b',
          name: 'Llama 3 8B',
          serverId: server.id,
          serverType: ServerType.ollama,
        );

        final testSettings = AppSettings(
          defaultModelId: model.id,
          defaultModelServerId: server.id,
          unloadModelsBeforeLoad: false,
        );

        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              osWidgetServiceProvider.overrideWithValue(service),
              settingsProvider.overrideWith(
                () => _TestSettingsNotifier(customSettings: testSettings),
              ),
              serversProvider.overrideWith(
                () => _StubServersNotifier([server]),
              ),
              availableModelsProvider(
                server.id,
              ).overrideWith((ref) => Future.value([model])),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const ShadApp(
                  home: Scaffold(
                    body: OsWidgetInvocationHost(
                      child: Text('Chat Screen Body'),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Chat Screen Body'), findsOneWidget);

        // Dispatch chat invocation with prompt
        service.dispatchInvocation(
          const OsWidgetInvocation(
            action: OsWidgetAction.newChat,
            prompt: 'Summarize today meetings',
          ),
        );

        await tester.pump();
        await tester.pumpAndSettle();

        // Model is selected
        final selected = container.read(selectedModelProvider);
        expect(selected?.id, 'llama3:8b');

        // Active server is set
        final activeServer = container.read(activeServerProvider);
        expect(activeServer?.id, 'ollama-1');

        // Pending prompt is populated
        final pendingPrompt = container.read(widgetPendingPromptProvider);
        expect(pendingPrompt, 'Summarize today meetings');

        // Active conversation was cleared for new chat
        final activeConvId = container.read(conv.activeConversationIdProvider);
        expect(activeConvId, isNull);
      },
    );
  });
}
