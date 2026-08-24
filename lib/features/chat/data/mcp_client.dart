// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:localmind/core/logger/app_logger.dart';

class McpClient {
  final String serverUrl;
  final Map<String, String>? headers;
  final String _version;
  final Dio _dio;
  bool _initialized = false;
  McpCapabilities? _capabilities;
  Future<McpCapabilities>? _initializationFuture;

  bool _useSse = false;
  StreamSubscription? _sseSubscription;
  String? _postUrl;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  int _requestIdCounter = 1;

  McpClient({
    required this.serverUrl,
    this.headers,
    String version = '1.0.0',
    Dio? dio,
  }) : _version = version,
       _dio = dio ?? Dio();

  bool get isInitialized => _initialized;
  McpCapabilities? get capabilities => _capabilities;

  Future<void> _connectSse() async {
    try {
      final response = await _dio.get<ResponseBody>(
        serverUrl,
        options: Options(
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            ...?headers,
          },
          responseType: ResponseType.stream,
        ),
      );

      final contentType = response.headers.value('content-type') ?? '';
      if (!contentType.contains('text/event-stream') &&
          !serverUrl.contains('sse')) {
        // Not an SSE stream endpoint, fallback to direct HTTP POST
        return;
      }

      _useSse = true;
      final handshakeCompleter = Completer<void>();

      final stream = response.data!.stream.cast<List<int>>().transform(
        utf8.decoder,
      );
      String buffer = '';
      String currentEvent = 'message';
      String currentData = '';

      _sseSubscription = stream.listen(
        (chunk) {
          buffer += chunk;
          final lines = buffer.split('\n');
          buffer = lines.removeLast();

          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) {
              if (currentData.isNotEmpty) {
                _handleSseMessage(
                  currentEvent,
                  currentData,
                  handshakeCompleter,
                );
                currentEvent = 'message';
                currentData = '';
              }
              continue;
            }

            if (trimmed.startsWith('event:')) {
              currentEvent = trimmed.substring(6).trim();
            } else if (trimmed.startsWith('data:')) {
              final val = trimmed.substring(5).trim();
              if (currentData.isNotEmpty) {
                currentData += '\n$val';
              } else {
                currentData = val;
              }
            }
          }
        },
        onError: (e) {
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.completeError(e);
          }
          _handleSseDisconnect(e);
        },
        onDone: () {
          // Process any remaining data in the buffer before disconnecting.
          if (buffer.isNotEmpty || currentData.isNotEmpty) {
            if (currentData.isNotEmpty) {
              _handleSseMessage(currentEvent, currentData, handshakeCompleter);
            } else if (buffer.trim().isNotEmpty) {
              _handleSseMessage(
                currentEvent,
                buffer.trim(),
                handshakeCompleter,
              );
            }
          }
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.completeError(
              McpException('SSE stream closed before handshake completed'),
            );
          }
          _handleSseDisconnect(null);
        },
      );

      // Wait for the endpoint event or timeout
      await handshakeCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw McpException(
            'Handshake timeout waiting for SSE endpoint event',
          );
        },
      );
    } catch (e) {
      await _closeSse();
      _useSse = false;
      rethrow;
    }
  }

  void _handleSseMessage(
    String event,
    String data,
    Completer<void> initCompleter,
  ) {
    if (event == 'endpoint') {
      try {
        final baseUri = Uri.parse(serverUrl);
        final resolvedUri = baseUri.resolve(data);
        _postUrl = resolvedUri.toString();
        Log.debug('MCP SSE Handshake completed. Message endpoint: $_postUrl');
        if (!initCompleter.isCompleted) {
          initCompleter.complete();
        }
      } catch (e) {
        if (!initCompleter.isCompleted) {
          initCompleter.completeError(e);
        }
      }
    } else {
      try {
        final json = jsonDecode(data);
        if (json is Map<String, dynamic>) {
          final id = json['id'];
          if (id != null) {
            final key = id.toString();
            final completer = _pendingRequests.remove(key);
            if (completer != null && !completer.isCompleted) {
              completer.complete(json);
            }
          }
        }
      } catch (_) {}
    }
  }

  void _handleSseDisconnect(dynamic error) {
    final ex = McpException(
      error != null ? 'SSE disconnected: $error' : 'SSE connection closed',
    );
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(ex);
      }
    }
    _pendingRequests.clear();
    _initialized = false;
  }

  Future<void> _closeSse() async {
    await _sseSubscription?.cancel();
    _sseSubscription = null;
    _postUrl = null;
  }

  Future<Map<String, dynamic>> _sendJsonRpc(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = _requestIdCounter++;
    final payload = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    if (_useSse) {
      if (_postUrl == null) {
        throw McpException(
          'SSE transport initialized but POST endpoint is missing',
        );
      }

      final completer = Completer<Map<String, dynamic>>();
      _pendingRequests[id.toString()] = completer;

      try {
        await _dio.post(
          _postUrl!,
          data: payload,
          options: Options(
            headers: {'Content-Type': 'application/json', ...?headers},
          ),
        );
      } catch (e) {
        _pendingRequests.remove(id.toString());
        throw McpException('Failed to post message over SSE transport: $e');
      }

      final responseJson = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingRequests.remove(id.toString());
          throw McpException(
            'Timeout waiting for JSON-RPC response over SSE transport',
          );
        },
      );

      if (responseJson.containsKey('error')) {
        final error = responseJson['error'];
        final message = error is Map
            ? (error['message'] ?? 'Unknown error')
            : 'Unknown error';
        throw McpException('Server returned error: $message');
      }

      return responseJson;
    } else {
      try {
        final response = await _dio.post(
          serverUrl,
          data: payload,
          options: Options(
            headers: {'Content-Type': 'application/json', ...?headers},
          ),
        );

        final responseData = response.data;
        if (responseData is! Map<String, dynamic>) {
          throw McpException('Invalid JSON-RPC response payload format');
        }

        if (responseData.containsKey('error')) {
          final error = responseData['error'];
          final message = error is Map
              ? (error['message'] ?? 'Unknown error')
              : 'Unknown error';
          throw McpException('Server returned error: $message');
        }

        return responseData;
      } catch (e) {
        throw McpException('Failed to send JSON-RPC request over HTTP: $e');
      }
    }
  }

  Future<McpCapabilities> initialize() async {
    if (_initialized && _capabilities != null) {
      return _capabilities!;
    }

    // If initialization is already in progress, wait for it.
    if (_initializationFuture != null) {
      return _initializationFuture!;
    }

    _initializationFuture = _doInitialize();
    try {
      return await _initializationFuture!;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<McpCapabilities> _doInitialize() async {
    try {
      try {
        await _connectSse();
      } catch (e) {
        Log.debug(
          'Failed to connect via SSE: $e. Falling back to direct HTTP POST.',
        );
        _useSse = false;
      }

      final response = await _sendJsonRpc('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'localmind', 'version': _version},
      });

      _capabilities = McpCapabilities.fromJson(
        response['result']['capabilities'] as Map<String, dynamic>,
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
      final payload = {
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': {},
      };

      if (_useSse) {
        if (_postUrl != null) {
          await _dio.post(
            _postUrl!,
            data: payload,
            options: Options(
              headers: {'Content-Type': 'application/json', ...?headers},
            ),
          );
        }
      } else {
        await _dio.post(
          serverUrl,
          data: payload,
          options: Options(
            headers: {'Content-Type': 'application/json', ...?headers},
          ),
        );
      }
    } catch (_) {}
  }

  Future<List<McpTool>> listTools() async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final response = await _sendJsonRpc('tools/list', {});

      final tools = response['result']['tools'] as List?;
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
      final response = await _sendJsonRpc('tools/call', {
        'name': name,
        'arguments': arguments,
      });

      final result = response['result'];
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
      final response = await _sendJsonRpc('resources/list', {});

      final resources = response['result']['resources'] as List?;
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
      final response = await _sendJsonRpc('resources/read', {'uri': uri});

      final contents = response['result']['contents'] as List?;
      if (contents == null || contents.isEmpty) {
        return '';
      }

      return contents.first['text'] as String? ?? '';
    } catch (e) {
      throw McpException('Failed to read resource $uri: $e');
    }
  }

  Future<void> close() async {
    await _closeSse();
    _initialized = false;
    _capabilities = null;
  }
}

class McpCapabilities {
  final bool tools;
  final bool resources;
  final bool prompts;

  const McpCapabilities({
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

  const McpTool({
    required this.name,
    this.description,
    this.inputSchema = const {},
  });

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
