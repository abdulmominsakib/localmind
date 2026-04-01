import 'dart:async';
import 'package:dio/dio.dart';

class McpClient {
  final String serverUrl;
  final Map<String, String>? headers;
  final Dio _dio;
  bool _initialized = false;
  McpCapabilities? _capabilities;

  McpClient({required this.serverUrl, this.headers, Dio? dio})
    : _dio = dio ?? Dio();

  bool get isInitialized => _initialized;
  McpCapabilities? get capabilities => _capabilities;

  Future<McpCapabilities> initialize() async {
    if (_initialized && _capabilities != null) {
      return _capabilities!;
    }

    try {
      final response = await _dio.post(
        serverUrl,
        data: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2024-11-05',
            'capabilities': {},
            'clientInfo': {'name': 'localmind', 'version': '1.0.0'},
          },
        },
        options: Options(
          headers: {'Content-Type': 'application/json', ...?headers},
        ),
      );

      _capabilities = McpCapabilities.fromJson(
        response.data['result']['capabilities'] as Map<String, dynamic>,
      );
      _initialized = true;

      await _sendInitializedNotification();

      return _capabilities!;
    } catch (e) {
      throw McpException('Failed to initialize MCP client: $e');
    }
  }

  Future<void> _sendInitializedNotification() async {
    try {
      await _dio.post(
        serverUrl,
        data: {
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
          'params': {},
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
    } catch (_) {}
  }

  Future<List<McpTool>> listTools() async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final response = await _dio.post(
        serverUrl,
        data: {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list', 'params': {}},
      );

      final tools = response.data['result']['tools'] as List?;
      if (tools == null) return [];

      return tools
          .map((t) => McpTool.fromJson(t as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw McpException('Failed to list tools: $e');
    }
  }

  Future<String> callTool(String name, Map<String, dynamic> arguments) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final response = await _dio.post(
        serverUrl,
        data: {
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {'name': name, 'arguments': arguments},
        },
      );

      final result = response.data['result'];
      if (result == null) {
        throw McpException('Tool call returned no result');
      }

      final content = result['content'] as List?;
      if (content == null || content.isEmpty) {
        return '';
      }

      return content.first['text'] as String? ?? '';
    } catch (e) {
      if (e is McpException) rethrow;
      throw McpException('Failed to call tool $name: $e');
    }
  }

  Future<List<McpResource>> listResources() async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final response = await _dio.post(
        serverUrl,
        data: {
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'resources/list',
          'params': {},
        },
      );

      final resources = response.data['result']['resources'] as List?;
      if (resources == null) return [];

      return resources
          .map((r) => McpResource.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw McpException('Failed to list resources: $e');
    }
  }

  Future<String> readResource(String uri) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final response = await _dio.post(
        serverUrl,
        data: {
          'jsonrpc': '2.0',
          'id': 5,
          'method': 'resources/read',
          'params': {'uri': uri},
        },
      );

      final contents = response.data['result']['contents'] as List?;
      if (contents == null || contents.isEmpty) {
        return '';
      }

      return contents.first['text'] as String? ?? '';
    } catch (e) {
      throw McpException('Failed to read resource $uri: $e');
    }
  }

  Future<void> close() async {
    _initialized = false;
    _capabilities = null;
  }
}

class McpCapabilities {
  final bool tools;
  final bool resources;
  final bool prompts;

  McpCapabilities({
    this.tools = false,
    this.resources = false,
    this.prompts = false,
  });

  factory McpCapabilities.fromJson(Map<String, dynamic> json) {
    return McpCapabilities(
      tools: json['tools'] == true,
      resources: json['resources'] == true,
      prompts: json['prompts'] == true,
    );
  }
}

class McpTool {
  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema;

  McpTool({required this.name, this.description, this.inputSchema = const {}});

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: json['inputSchema'] as Map<String, dynamic>? ?? {},
    );
  }
}

class McpResource {
  final String uri;
  final String? name;
  final String? description;
  final String? mimeType;

  McpResource({required this.uri, this.name, this.description, this.mimeType});

  factory McpResource.fromJson(Map<String, dynamic> json) {
    return McpResource(
      uri: json['uri'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }
}

class McpException implements Exception {
  final String message;
  McpException(this.message);

  @override
  String toString() => 'McpException: $message';
}
