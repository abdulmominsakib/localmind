import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/chat/providers/chat_mcp_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatMcpConfigNotifier Tests', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('importIntegrationsFromJson parses mcpServers JSON correctly', () {
      const jsonStr = '''
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp"]
    },
    "danielsig/duckduckgo": {
      "command": "npx",
      "args": ["-y", "@danielsig/duckduckgo"]
    },
    "duckduckgo": {
      "url": "http://localhost:8000/sse"
    }
  }
}
''';

      final notifier = container.read(chatMcpConfigProvider.notifier);
      final count = notifier.importIntegrationsFromJson(jsonStr);

      expect(count, equals(3));
      final state = container.read(chatMcpConfigProvider);
      expect(state.integrations.length, equals(3));

      final playwright = state.integrations.firstWhere((i) => i.serverLabel == 'playwright');
      expect(playwright.type, equals(McpIntegrationType.plugin));
      expect(playwright.pluginId, equals('mcp/playwright'));

      final ddgPlugin = state.integrations.firstWhere((i) => i.serverLabel == 'danielsig/duckduckgo');
      expect(ddgPlugin.type, equals(McpIntegrationType.plugin));
      expect(ddgPlugin.pluginId, equals('danielsig/duckduckgo'));

      final ddg = state.integrations.firstWhere((i) => i.serverLabel == 'duckduckgo');
      expect(ddg.type, equals(McpIntegrationType.ephemeralMcp));
      expect(ddg.serverUrl, equals('http://localhost:8000/sse'));
    });

    test('toggleIntegration toggles integration enabled state', () {
      final notifier = container.read(chatMcpConfigProvider.notifier);
      notifier.addIntegration(
        const McpIntegration(
          type: McpIntegrationType.plugin,
          pluginId: 'mcp/playwright',
          enabled: true,
        ),
      );

      expect(container.read(chatMcpConfigProvider).integrations[0].enabled, isTrue);

      notifier.toggleIntegration(0, false);
      expect(container.read(chatMcpConfigProvider).integrations[0].enabled, isFalse);

      notifier.toggleIntegration(0, true);
      expect(container.read(chatMcpConfigProvider).integrations[0].enabled, isTrue);
    });
  });
}
