import 'mcp_client.dart';

class McpServerManager {
  final Map<String, McpClient> _clients = {};
  final Map<String, McpCapabilities> _capabilities = {};
  final Map<String, List<McpTool>> _tools = {};
  final Map<String, String> _serverUrls = {};

  Future<void> addServer(
    String label,
    String url, {
    Map<String, String>? headers,
  }) async {
    if (_clients.containsKey(label)) {
      removeServer(label);
    }

    final client = McpClient(serverUrl: url, headers: headers);

    final capabilities = await client.initialize();
    final tools = await client.listTools();

    _clients[label] = client;
    _capabilities[label] = capabilities;
    _tools[label] = tools;
    _serverUrls[label] = url;
  }

  void removeServer(String label) {
    _clients[label]?.close();
    _clients.remove(label);
    _capabilities.remove(label);
    _tools.remove(label);
    _serverUrls.remove(label);
  }

  bool hasServer(String label) => _clients.containsKey(label);

  List<McpTool> getTools(String label) => _tools[label] ?? [];

  Map<String, List<McpTool>> get allTools => Map.unmodifiable(_tools);

  McpCapabilities? getCapabilities(String label) => _capabilities[label];

  String? getServerUrl(String label) => _serverUrls[label];

  Future<String> callTool(
    String serverLabel,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final client = _clients[serverLabel];
    if (client == null) {
      throw McpException('MCP server not connected: $serverLabel');
    }

    if (!client.isInitialized) {
      await client.initialize();
    }

    return client.callTool(toolName, args);
  }

  Future<String> readResource(String serverLabel, String uri) async {
    final client = _clients[serverLabel];
    if (client == null) {
      throw McpException('MCP server not connected: $serverLabel');
    }

    if (!client.isInitialized) {
      await client.initialize();
    }

    return client.readResource(uri);
  }

  void clear() {
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
    _capabilities.clear();
    _tools.clear();
    _serverUrls.clear();
  }

  int get serverCount => _clients.length;

  List<String> get serverLabels => _clients.keys.toList();
}
