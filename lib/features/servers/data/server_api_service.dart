import 'package:dio/dio.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/core/models/enums.dart';

class ServerApiService {
  final Dio _dio;

  ServerApiService(this._dio);

  Future<bool> testConnection(Server server) async {
    try {
      final response = await _dio.get(
        server.modelsEndpoint,
        options: Options(
          headers: _getAuthHeaders(server),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<int?> pingServer(Server server) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _dio.head(
        server.baseUrl,
        options: Options(headers: _getAuthHeaders(server)),
      );
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return null;
    }
  }

  Future<List<ModelInfo>> fetchModels(Server server) async {
    try {
      final response = await _dio.get(
        server.modelsEndpoint,
        options: Options(headers: _getAuthHeaders(server)),
      );

      switch (server.type) {
        case ServerType.lmStudio:
          return _parseLMStudioModels(response.data, server);
        case ServerType.ollama:
          return _parseOllamaModels(response.data, server);
        case ServerType.openRouter:
          return _parseOpenRouterModels(response.data, server);
      }
    } catch (e) {
      throw Exception('Failed to fetch models: $e');
    }
  }

  Map<String, String>? _getAuthHeaders(Server server) {
    if (server.apiKey != null && server.apiKey!.isNotEmpty) {
      return {'Authorization': 'Bearer ${server.apiKey}'};
    }
    return null;
  }

  List<ModelInfo> _parseLMStudioModels(dynamic data, Server server) {
    final List<ModelInfo> models = [];
    if (data['data'] != null) {
      for (final item in data['data']) {
        final id = item['id'] as String? ?? '';
        models.add(
          ModelInfo(
            id: id,
            name: _formatModelName(id),
            serverType: server.type,
            serverId: server.id,
            parameterCount: _extractParameterCount(id),
          ),
        );
      }
    }
    return models;
  }

  List<ModelInfo> _parseOllamaModels(dynamic data, Server server) {
    final List<ModelInfo> models = [];
    if (data['models'] != null) {
      for (final item in data['models']) {
        final details = item['details'] ?? {};
        final paramSize = details['parameter_size'] as String? ?? '';
        models.add(
          ModelInfo(
            id: item['name'] ?? '',
            name: _formatModelName(item['name'] ?? ''),
            fileSize: item['size'] as int?,
            parameterCount: _parseParameterSize(paramSize),
            quantization: details['quantization_level'] as String?,
            architecture: details['family'] as String?,
            serverType: server.type,
            serverId: server.id,
            modifiedAt: item['modified_at'] != null
                ? DateTime.tryParse(item['modified_at'])
                : null,
          ),
        );
      }
    }
    return models;
  }

  List<ModelInfo> _parseOpenRouterModels(dynamic data, Server server) {
    final List<ModelInfo> models = [];
    if (data['data'] != null) {
      for (final item in data['data']) {
        if (item['architecture']?['modality'] == 'text->text') {
          models.add(
            ModelInfo(
              id: item['id'] ?? '',
              name: item['name'] ?? '',
              description: item['description'] as String?,
              contextLength: item['context_length'] as int?,
              architecture: item['architecture']?['tokenizer'] as String?,
              serverType: server.type,
              serverId: server.id,
            ),
          );
        }
      }
    }
    return models;
  }

  String _formatModelName(String id) {
    return id
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
        )
        .join(' ');
  }

  int? _extractParameterCount(String id) {
    final regex = RegExp(r'(\d+(?:\.\d+)?)\s*[Bb]');
    final match = regex.firstMatch(id);
    if (match != null) {
      final value = double.tryParse(match.group(1) ?? '');
      return value?.toInt();
    }
    return null;
  }

  int? _parseParameterSize(String size) {
    final cleaned = size.replaceAll('B', '').replaceAll('b', '').trim();
    return int.tryParse(cleaned);
  }
}
