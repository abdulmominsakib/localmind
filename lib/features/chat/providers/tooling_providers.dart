import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../data/tools/tool_registry.dart';
import '../data/tools/builtin_tool_provider.dart';
import '../data/tools/calendar_service.dart';
import '../data/tools/location_service.dart';
import '../data/tools/mcp_tool_provider.dart';
import '../data/tools/tool_definition.dart';
import '../data/mcp_server_manager.dart';
import '../data/tools/web/web_search_client.dart';
import '../data/tools/web/web_search_service.dart';
import '../data/tools/web/web_tool_provider.dart';

final mcpServerManagerProvider = Provider<McpServerManager>((ref) {
  // Built once: rebuilding would drop every live server connection, so the
  // app version is applied when package info loads instead of watched.
  final manager = McpServerManager(
    appVersion: ref.read(packageInfoProvider).value?.version ?? '1.0.0',
  );
  ref.listen(packageInfoProvider, (_, next) {
    final version = next.value?.version;
    if (version != null) manager.appVersion = version;
  });
  return manager;
});

final calendarServiceProvider = Provider<CalendarService>(
  (ref) => CalendarService.instance,
);

final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService.instance,
);

final builtInToolProviderProvider = Provider<BuiltInToolProvider>((ref) {
  final settings = ref.watch(settingsProvider);
  return BuiltInToolProvider(
    calendarToolsEnabled: settings.calendarToolsEnabled,
    locationToolsEnabled: settings.locationToolsEnabled,
  );
});

final webSearchKeyStoreProvider = Provider<WebSearchKeyStore>(
  (ref) => WebSearchKeyStore(),
);

final webSearchServiceProvider = Provider<WebSearchService>((ref) {
  final kind = ref.watch(
    settingsProvider.select(
      (s) => WebSearchProviderKind.parse(s.webSearchProvider),
    ),
  );
  final url = ref.watch(settingsProvider.select((s) => s.webSearchSearxngUrl));
  return WebSearchService(
    kind: kind,
    searxngUrl: url,
    keyStore: ref.watch(webSearchKeyStoreProvider),
  );
});

/// Whether web search is switched on and has what it needs to run.
final webSearchReadyProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(settingsProvider.select((s) => s.webSearchEnabled))) {
    return false;
  }
  return ref.watch(webSearchServiceProvider).isConfigured();
});

final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  final mcpServerManager = ref.watch(mcpServerManagerProvider);
  return ToolRegistry(
    providers: [
      ref.watch(builtInToolProviderProvider),
      WebToolProvider(
        service: ref.watch(webSearchServiceProvider),
        enabled: ref.watch(settingsProvider.select((s) => s.webSearchEnabled)),
      ),
      McpToolProvider(serverManager: mcpServerManager),
    ],
  );
});

final availableToolsProvider = FutureProvider<List<ToolDefinition>>((
  ref,
) async {
  final registry = ref.watch(toolRegistryProvider);
  return registry.listTools();
});
