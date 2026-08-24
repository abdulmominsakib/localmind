import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/chat/data/mcp_server_manager.dart';
import 'package:localmind/features/chat/providers/chat_mcp_providers.dart';
import 'package:localmind/features/chat/providers/tooling_providers.dart';

class RecordingMcpServerManager extends McpServerManager {
  final List<({String label, String url, Map<String, String>? headers})>
  addedServers = [];

  @override
  Future<void> addServer(
    String label,
    String url, {
    Map<String, String>? headers,
  }) async {
    addedServers.add((label: label, url: url, headers: headers));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatMcpConfigNotifier Tests', () {
    late ProviderContainer container;
    late RecordingMcpServerManager mcpServerManager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      mcpServerManager = RecordingMcpServerManager();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mcpServerManagerProvider.overrideWithValue(mcpServerManager),
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

      final playwright = state.integrations.firstWhere(
        (i) => i.serverLabel == 'playwright',
      );
      expect(playwright.type, equals(McpIntegrationType.plugin));
      expect(playwright.pluginId, equals('mcp/playwright'));

      final ddgPlugin = state.integrations.firstWhere(
        (i) => i.serverLabel == 'danielsig/duckduckgo',
      );
      expect(ddgPlugin.type, equals(McpIntegrationType.plugin));
      expect(ddgPlugin.pluginId, equals('danielsig/duckduckgo'));

      final ddg = state.integrations.firstWhere(
        (i) => i.serverLabel == 'duckduckgo',
      );
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

      expect(
        container.read(chatMcpConfigProvider).integrations[0].enabled,
        isTrue,
      );

      notifier.toggleIntegration(0, false);
      expect(
        container.read(chatMcpConfigProvider).integrations[0].enabled,
        isFalse,
      );

      notifier.toggleIntegration(0, true);
      expect(
        container.read(chatMcpConfigProvider).integrations[0].enabled,
        isTrue,
      );
    });

    test('addIntegrationFromInput connects an HTTPS MCP server', () {
      final notifier = container.read(chatMcpConfigProvider.notifier);

      final added = notifier.addIntegrationFromInput(
        label: 'Remote tools',
        url: 'https://example.com/mcp/sse',
      );

      expect(added, isTrue);
      final integration = container
          .read(chatMcpConfigProvider)
          .integrations
          .single;
      expect(integration.type, McpIntegrationType.ephemeralMcp);
      expect(integration.serverLabel, 'Remote tools');
      expect(integration.serverUrl, 'https://example.com/mcp/sse');
      expect(integration.pluginId, isNull);
      expect(mcpServerManager.addedServers, hasLength(1));
      expect(mcpServerManager.addedServers.single.label, 'Remote tools');
      expect(
        mcpServerManager.addedServers.single.url,
        'https://example.com/mcp/sse',
      );
    });

    test('addIntegrationFromInput still accepts a plugin id', () {
      final notifier = container.read(chatMcpConfigProvider.notifier);

      final added = notifier.addIntegrationFromInput(
        label: 'mcp/playwright',
        url: '',
      );

      expect(added, isTrue);
      final integration = container
          .read(chatMcpConfigProvider)
          .integrations
          .single;
      expect(integration.type, McpIntegrationType.plugin);
      expect(integration.pluginId, 'mcp/playwright');
      expect(integration.serverUrl, isNull);
      expect(mcpServerManager.addedServers, isEmpty);
    });

    test('addIntegrationFromInput rejects an unlabeled MCP URL', () {
      final notifier = container.read(chatMcpConfigProvider.notifier);

      final added = notifier.addIntegrationFromInput(
        label: '',
        url: 'https://example.com/mcp/sse',
      );

      expect(added, isFalse);
      expect(container.read(chatMcpConfigProvider).integrations, isEmpty);
      expect(mcpServerManager.addedServers, isEmpty);
    });
  });
}
