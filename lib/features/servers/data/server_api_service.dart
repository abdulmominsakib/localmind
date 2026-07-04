import 'package:dio/dio.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../models/data/models/model_info.dart';
import 'models/server.dart';

class ServerApiService {
  final Dio _dio;

  ServerApiService(this._dio);

  Future<bool> testConnection(Server server) async {
    try {
      final response = await _dio.get(
        server.modelsEndpoint,
        options: Options(
          headers: buildServerAuthHeaders(server),
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
        options: Options(headers: buildServerAuthHeaders(server)),
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
        options: Options(headers: buildServerAuthHeaders(server)),
      );

      switch (server.type) {
        case ServerType.lmStudio:
        case ServerType.openAICompatible:
          return _parseOpenAICompatibleModels(response.data, server);
        case ServerType.ollama:
          return _parseOllamaModels(response.data, server);
        case ServerType.openRouter:
          return _parseOpenRouterModels(response.data, server);
        case ServerType.onDevice:
          return [];
      }
    } catch (e) {
      throw Exception('Failed to fetch models: $e');
    }
  }

  Future<Set<String>> fetchRunningModels(Server server) async {
    if (server.type == ServerType.openRouter ||
        server.type == ServerType.openAICompatible ||
        server.type == ServerType.onDevice) {
      return {};
    }

    try {
      final response = await _dio.get(
        server.runningModelsEndpoint,
        options: Options(headers: buildServerAuthHeaders(server)),
      );

      if (server.type == ServerType.lmStudio) {
        return _parseRunningOpenAICompatibleModels(response.data);
      }
      return _parseRunningOllamaModels(response.data);
    } catch (e) {
      return {};
    }
  }

  Future<void> loadModel(Server server, String modelId) async {
    if (server.type == ServerType.openRouter ||
        server.type == ServerType.onDevice) {
      return;
    }

    switch (server.type) {
      case ServerType.lmStudio:
      case ServerType.openAICompatible:
        try {
          await _dio.post(
            server.loadModelEndpoint,
            data: {'model': modelId},
            options: Options(headers: buildServerAuthHeaders(server)),
          );
        } catch (_) {
          // Not all OpenAI-compatible servers support this endpoint
        }
        break;
      case ServerType.ollama:
        // Ollama auto-loads models on /api/chat. Calling /api/generate here
        // would trigger an auto-pull (download) when the model is not already
        // present on the Ollama server, which is not what the user wants.
        return;
      case ServerType.openRouter:
      case ServerType.onDevice:
        break;
    }
  }

  Future<String?> loadModelWithInstanceId(
    Server server,
    String modelId, {
    int? contextLength,
  }) async {
    if (server.type == ServerType.openRouter ||
        server.type == ServerType.onDevice) {
      return null;
    }

    switch (server.type) {
      case ServerType.lmStudio:
      case ServerType.openAICompatible:
        try {
          final payload = <String, dynamic>{
            'model': modelId,
            'echo_load_config': true,
          };
          if (contextLength != null) {
            payload['context_length'] = contextLength;
          }
          final response = await _dio.post(
            server.loadModelEndpoint,
            data: payload,
            options: Options(headers: buildServerAuthHeaders(server)),
          );
          _throwIfErrorResponse(response.data);
          return response.data['instance_id'] as String?;
        } on DioException catch (e) {
          throw Exception(_extractApiErrorMessage(e.response?.data) ?? e.message);
        }
      case ServerType.ollama:
        // Ollama auto-loads models on /api/chat. Calling /api/generate here
        // would trigger an auto-pull (download) when the model is not already
        // present on the Ollama server, which is not what the user wants.
        return null;
      case ServerType.openRouter:
      case ServerType.onDevice:
        return null;
    }
  }

  Future<void> unloadAllInstances(Server server, Set<String> instanceIds) async {
    for (final instanceId in instanceIds) {
      await unloadModel(server, instanceId, instanceId: instanceId);
    }
  }

  Future<void> unloadInstancesForModelKey(
    Server server,
    String modelKey,
    Set<String> instanceIds,
  ) async {
    final targets = instanceIds
        .where((id) => id == modelKey || id.startsWith('$modelKey:'))
        .toList();
    for (final instanceId in targets) {
      await unloadModel(server, modelKey, instanceId: instanceId);
    }
  }

  Future<void> unloadModel(
    Server server,
    String modelId, {
    String? instanceId,
  }) async {
    if (server.type == ServerType.openRouter ||
        server.type == ServerType.onDevice) {
      return;
    }

    switch (server.type) {
      case ServerType.lmStudio:
      case ServerType.openAICompatible:
        try {
          await _dio.post(
            server.unloadModelEndpoint,
            data: {'instance_id': instanceId ?? modelId},
            options: Options(headers: buildServerAuthHeaders(server)),
          );
        } catch (_) {
          // Not all OpenAI-compatible servers support this endpoint
        }
        break;
      case ServerType.ollama:
        await _dio.post(
          server.unloadModelEndpoint,
          data: {
            'model': modelId,
            'keep_alive': 0,
            'prompt': '',
          },
          options: Options(headers: buildServerAuthHeaders(server)),
        );
        break;
      case ServerType.openRouter:
      case ServerType.onDevice:
        break;
    }
  }

  Set<String> _parseRunningOpenAICompatibleModels(dynamic data) {
    final runningModels = <String>{};
    if (data == null) return runningModels;
    final modelItems = data['models'] ?? data['data'];
    if (modelItems is List) {
      for (final item in modelItems) {
        if (item is! Map) continue;
        final id = item['key']?.toString() ??
            item['name']?.toString() ??
            item['id']?.toString() ??
            '';
        if (id.isEmpty) continue;

        final loadedInstances = item['loaded_instances'];
        if (loadedInstances is List) {
          for (final instance in loadedInstances) {
            if (instance is! Map) continue;
            final instanceId = instance['id']?.toString();
            if (instanceId != null && instanceId.isNotEmpty) {
              runningModels.add(instanceId);
            }
          }
        } else {
          // Servers without loaded_instances (e.g. llama.cpp) always have
          // their model running if it appears in the model list
          runningModels.add(id);
        }
      }
    }
    return runningModels;
  }

  Set<String> _parseRunningOllamaModels(dynamic data) {
    final runningModels = <String>{};
    final models = data['models'];
    if (models is List) {
      for (final item in models) {
        if (item is! Map) continue;
        final name = item['name'];
        if (name != null) runningModels.add(name.toString());
      }
    }
    return runningModels;
  }

  List<ModelInfo> _parseOpenAICompatibleModels(dynamic data, Server server) {
    final List<ModelInfo> models = [];
    if (data == null) return models;

    // Build a lookup from the OpenAI-style 'data' array for metadata
    // that may be missing from the 'models' array (e.g. llama.cpp)
    final Map<String, Map<String, dynamic>> metaById = {};
    if (data['data'] is List) {
      for (final item in data['data']) {
        if (item is Map) {
          final id = item['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            metaById[id] = (item['meta'] as Map<String, dynamic>?) ?? {};
          }
        }
      }
    }

    final modelItems = data['models'] ?? data['data'];
    if (modelItems != null && modelItems is List) {
      for (final item in modelItems) {
        if (item is! Map) continue;
        final id = item['key']?.toString() ??
            item['name']?.toString() ??
            item['id']?.toString() ??
            '';
        if (id.isEmpty) continue;

        final displayName = item['display_name']?.toString();
        final quantization = item['quantization'];
        final paramsString = item['params_string']?.toString();
        
        final meta = metaById[id] ?? (item['meta'] as Map<String, dynamic>?);
        if (meta == null && metaById.isNotEmpty && data['models'] != null) {
          Log.warning('Metadata join failed for model: $id');
        }
        final finalMeta = meta ?? {};

        String? quantName;
        if (quantization is Map) {
          quantName = quantization['name']?.toString();
        } else if (quantization is String) {
          quantName = quantization;
        }

        final archValue = item['architecture'];
        String? archName;
        if (archValue is String) {
          archName = archValue;
        }

        final capabilities = _parseModelCapabilities(item['capabilities']);

        models.add(
          ModelInfo(
            id: id,
            name: displayName ?? _formatModelName(id),
            description: item['description']?.toString(),
            parameterCount: _parseParameterString(paramsString) ??
                _paramCountFromMeta(finalMeta['n_params']),
            contextLength: _toInt(item['max_context_length']) ??
                _toInt(finalMeta['n_ctx_train']),
            fileSize: _toInt(item['size_bytes']) ??
                _toInt(finalMeta['size']),
            quantization: quantName,
            architecture: archName,
            serverType: server.type,
            serverId: server.id,
            supportsVision: capabilities.supportsVision,
            supportsReasoning: capabilities.supportsReasoning,
            supportsToolUse: capabilities.supportsToolUse,
          ),
        );
      }
    }
    return models;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  ({
    bool supportsVision,
    bool supportsReasoning,
    bool supportsToolUse,
  }) _parseModelCapabilities(dynamic raw) {
    if (raw is! Map) {
      return (
        supportsVision: false,
        supportsReasoning: false,
        supportsToolUse: false,
      );
    }

    final reasoning = raw['reasoning'];
    return (
      supportsVision: raw['vision'] == true,
      supportsReasoning: reasoning is Map && reasoning.isNotEmpty,
      supportsToolUse: raw['trained_for_tool_use'] == true,
    );
  }

  double? _paramCountFromMeta(dynamic nParams) {
    if (nParams == null) return null;
    if (nParams is int) return nParams / 1000000000;
    if (nParams is double) return nParams / 1000000000;
    if (nParams is String) {
      final parsedDouble = double.tryParse(nParams);
      if (parsedDouble != null) return parsedDouble / 1000000000;
    }
    return null;
  }

  List<ModelInfo> _parseOllamaModels(dynamic data, Server server) {
    final List<ModelInfo> models = [];
    final modelsData = data['models'];
    if (modelsData is List) {
      for (final item in modelsData) {
        if (item is! Map) continue;
        final detailsVal = item['details'];
        final details = (detailsVal is Map) ? detailsVal : <String, dynamic>{};
        final paramSize = details['parameter_size'] as String? ?? '';
        models.add(
          ModelInfo(
            id: item['name']?.toString() ?? '',
            name: _formatModelName(item['name']?.toString() ?? ''),
            fileSize: item['size'] as int?,
            parameterCount: _parseParameterSize(paramSize),
            quantization: details['quantization_level'] as String?,
            architecture: details['family'] as String?,
            serverType: server.type,
            serverId: server.id,
            modifiedAt: item['modified_at'] != null
                ? DateTime.tryParse(item['modified_at']?.toString() ?? '')
                : null,
          ),
        );
      }
    }
    return models;
  }

  List<ModelInfo> _parseOpenRouterModels(dynamic data, Server server) {
    final List<ModelInfo> models = [];
    if (data == null) return models;
    final items = data['data'];
    if (items is! List) return models;
    for (final item in items) {
      if (item is! Map) continue;
      final modality = item['architecture']?['modality'] as String?;
      final isTextModel = modality == null ||
          modality.isEmpty ||
          !modality.contains('->') ||
          modality.split('->').last.contains('text');
      if (isTextModel) {
        models.add(
          ModelInfo(
            id: item['id']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            description: item['description'] as String?,
            contextLength: item['context_length'] as int?,
            architecture: item['architecture']?['tokenizer'] as String?,
            serverType: server.type,
            serverId: server.id,
          ),
        );
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

  double? _parseParameterSize(String size) {
    final cleaned = size.trim();
    if (cleaned.endsWith('B') || cleaned.endsWith('b')) {
      return double.tryParse(
        cleaned.substring(0, cleaned.length - 1).trim(),
      );
    }
    if (cleaned.endsWith('M') || cleaned.endsWith('m')) {
      final val = double.tryParse(
        cleaned.substring(0, cleaned.length - 1).trim(),
      );
      return val != null ? val / 1000 : null;
    }
    return double.tryParse(cleaned);
  }

  double? _parseParameterString(String? paramsString) {
    if (paramsString == null) return null;
    final regex = RegExp(r'(\d+(?:\.\d+)?)\s*[Bb]');
    final match = regex.firstMatch(paramsString);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '');
    }
    return null;
  }

  void _throwIfErrorResponse(dynamic data) {
    final message = _extractApiErrorMessage(data);
    if (message != null) {
      throw Exception(message);
    }
  }

  String? _extractApiErrorMessage(dynamic data) {
    if (data is! Map) return null;
    final error = data['error'];
    if (error is Map) {
      final type = error['type']?.toString();
      final message = error['message']?.toString();
      if (type != null && message != null) return '$type: $message';
      return message ?? type;
    }
    return null;
  }
}
