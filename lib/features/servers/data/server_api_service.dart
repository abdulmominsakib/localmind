import 'dart:convert';
import 'package:dio/dio.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../models/data/models/model_info.dart';
import 'models/server.dart';

class ServerApiService {
  final Dio _dio;

  ServerApiService(this._dio);

  Future<bool> testConnection(Server server) async {
    if (server.type == ServerType.onDevice) {
      return true;
    }

    final endpointsToTry = <String>[];
    if (server.modelsEndpoint.isNotEmpty) {
      endpointsToTry.add(server.modelsEndpoint);
    }

    if (server.type == ServerType.lmStudio) {
      endpointsToTry.add('${server.baseUrl}/v1/models');
      endpointsToTry.add('${server.baseUrl}/api/v0/models');
    } else if (server.type == ServerType.openAICompatible) {
      endpointsToTry.add('${server.baseUrl}/models');
    } else if (server.type == ServerType.ollama) {
      endpointsToTry.add('${server.baseUrl}/api/tags');
      endpointsToTry.add('${server.baseUrl}/api/version');
    }

    for (final endpoint in endpointsToTry.toSet()) {
      if (endpoint.isEmpty) continue;
      try {
        final response = await _dio.get(
          endpoint,
          options: Options(
            headers: buildServerAuthHeaders(server),
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        if (response.statusCode == 200) {
          return true;
        }
      } catch (_) {
        // Try next endpoint
      }
    }
    return false;
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
      Response response;
      try {
        response = await _dio.get(
          server.modelsEndpoint,
          options: Options(headers: buildServerAuthHeaders(server)),
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 404 &&
            server.type == ServerType.lmStudio) {
          response = await _dio.get(
            '${server.baseUrl}/v1/models',
            options: Options(headers: buildServerAuthHeaders(server)),
          );
        } else {
          rethrow;
        }
      }

      List<ModelInfo> models;
      switch (server.type) {
        case ServerType.lmStudio:
        case ServerType.openAICompatible:
          models = _parseOpenAICompatibleModels(response.data, server);
          break;
        case ServerType.ollama:
        case ServerType.ollamaCloud:
          models = await _parseAndEnrichOllamaModels(response.data, server);
          break;
        case ServerType.openRouter:
          models = _parseOpenRouterModels(response.data, server);
          break;
        case ServerType.onDevice:
          models = [];
          break;
      }
      return models;
    } catch (e) {
      if (e is DioException) {
        final apiMsg = _extractApiErrorMessage(e.response?.data);
        if (apiMsg != null) {
          throw Exception('Failed to fetch models: $apiMsg');
        }
      }
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
      case ServerType.ollamaCloud:
        // Ollama (and Ollama Cloud) auto-loads models on /api/chat. Calling
        // /api/generate here would trigger an auto-pull (download) when the
        // model is not already present on the server, which is not what the
        // user wants.
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
      case ServerType.ollamaCloud:
        // Ollama (and Ollama Cloud) auto-loads models on /api/chat. Calling
        // /api/generate here would trigger an auto-pull (download) when the
        // model is not already present on the server, which is not what the
        // user wants.
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
      case ServerType.ollamaCloud:
        // Ollama Cloud manages model lifecycle server-side; no client-side
        // unload action is supported.
        return;
      case ServerType.openRouter:
      case ServerType.onDevice:
        break;
    }
  }

  /// Returns the context length the currently loaded model was actually
  /// loaded with — verified live against LM Studio's `/api/v0/models/{id}`,
  /// which reports `loaded_context_length` (e.g. 15000) separately from
  /// `max_context_length` (the model's architectural maximum, e.g. 131072).
  /// The loaded value can be much smaller than the max if the user picked a
  /// smaller context window at load time, so it's what "percent of context
  /// used" should be measured against. Falls back to `max_context_length`
  /// if the model isn't reported as loaded. Only supported for LM Studio;
  /// other server types return null so callers can fall back to their own
  /// configured context length.
  Future<int?> fetchLoadedContextLength(Server server, String modelId) async {
    if (server.type != ServerType.lmStudio) return null;

    try {
      final response = await _dio.get(
        '${server.baseUrl}/api/v0/models/${Uri.encodeComponent(modelId)}',
        options: Options(
          headers: buildServerAuthHeaders(server),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final data = response.data;
      if (data is! Map) return null;
      return _toInt(data['loaded_context_length']) ??
          _toInt(data['max_context_length']);
    } catch (e) {
      Log.warning('Failed to fetch loaded context length: $e');
      return null;
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

  Future<List<ModelInfo>> _parseAndEnrichOllamaModels(
    dynamic data,
    Server server,
  ) async {
    final models = _parseOllamaModels(data, server);
    if (models.isEmpty) return models;

    return Future.wait(
      models.map((model) async {
        try {
          final response = await _dio.post(
            server.modelDetailsEndpoint,
            data: {'name': model.id},
            options: Options(headers: buildServerAuthHeaders(server)),
          );
          final capabilities = _parseOllamaCapabilityList(response.data);
          return model.copyWith(
            supportsVision: capabilities.supportsVision,
            supportsToolUse: capabilities.supportsToolUse,
          );
        } catch (error) {
          Log.warning(
            'Unable to read Ollama capabilities for ${model.id}: $error',
          );
          return model;
        }
      }),
    );
  }

  ({bool supportsVision, bool supportsToolUse}) _parseOllamaCapabilityList(
    dynamic data,
  ) {
    if (data is! Map) {
      return (supportsVision: false, supportsToolUse: false);
    }
    final rawCapabilities = data['capabilities'];
    if (rawCapabilities is! List) {
      return (supportsVision: false, supportsToolUse: false);
    }
    final capabilities = rawCapabilities
        .map((value) => value.toString().trim().toLowerCase())
        .toSet();
    return (
      supportsVision: capabilities.contains('vision'),
      supportsToolUse: capabilities.contains('tools'),
    );
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
        final capabilities = _parseOpenRouterCapabilities(item);
        final pricing = _parseOpenRouterPricing(item['pricing']);
        models.add(
          ModelInfo(
            id: item['id']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            description: item['description'] as String?,
            contextLength: item['context_length'] as int?,
            architecture: item['architecture']?['tokenizer'] as String?,
            serverType: server.type,
            serverId: server.id,
            supportsVision: capabilities.supportsVision,
            supportsReasoning: capabilities.supportsReasoning,
            supportsToolUse: capabilities.supportsToolUse,
            supportedReasoningEfforts: capabilities.supportedReasoningEfforts,
            defaultReasoningEffort: capabilities.defaultReasoningEffort,
            reasoningMandatory: capabilities.reasoningMandatory,
            inputPricePerMillion: pricing.inputPricePerMillion,
            outputPricePerMillion: pricing.outputPricePerMillion,
          ),
        );
      }
    }
    return models;
  }

  ({
    bool supportsVision,
    bool supportsReasoning,
    bool supportsToolUse,
    List<String>? supportedReasoningEfforts,
    String? defaultReasoningEffort,
    bool reasoningMandatory,
  }) _parseOpenRouterCapabilities(Map<dynamic, dynamic> item) {
    final architecture = item['architecture'];
    final arch = architecture is Map ? architecture : const <String, dynamic>{};
    final inputModalities = (arch['input_modalities'] as List?)
            ?.map((e) => e.toString().trim().toLowerCase())
            .toSet() ??
        <String>{};
    final modality = arch['modality']?.toString().toLowerCase() ?? '';
    final supportsVision =
        inputModalities.contains('image') || modality.contains('image');

    final supportedParams = (item['supported_parameters'] as List?)
            ?.map((e) => e.toString().trim().toLowerCase())
            .toSet() ??
        <String>{};
    final supportsToolUse = supportedParams.contains('tools') ||
        supportedParams.contains('tool_choice');

    final reasoningField = item['reasoning'];
    final reasoning = reasoningField is Map ? reasoningField : null;
    final supportedEffortsRaw = reasoning?['supported_efforts'];
    final supportedReasoningEfforts = supportedEffortsRaw is List
        ? supportedEffortsRaw
            .map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : null;
    final defaultReasoningEffort =
        reasoning?['default_effort']?.toString().trim().toLowerCase();
    final reasoningMandatory = reasoning?['mandatory'] == true;
    final supportsReasoning = reasoning != null && reasoning.isNotEmpty ||
        supportedReasoningEfforts != null && supportedReasoningEfforts.isNotEmpty ||
        reasoningMandatory ||
        supportedParams.contains('reasoning') ||
        supportedParams.contains('include_reasoning');

    return (
      supportsVision: supportsVision,
      supportsReasoning: supportsReasoning,
      supportsToolUse: supportsToolUse,
      supportedReasoningEfforts: supportedReasoningEfforts,
      defaultReasoningEffort: defaultReasoningEffort,
      reasoningMandatory: reasoningMandatory,
    );
  }

  /// Parses OpenRouter `pricing` into USD-per-1M-token prices. OpenRouter
  /// quotes prices per token (e.g. `0.0000025`), so the value is scaled by
  /// 1,000,000 for display-friendly numbers.
  ({double? inputPricePerMillion, double? outputPricePerMillion})
      _parseOpenRouterPricing(dynamic raw) {
    if (raw is! Map) {
      return (inputPricePerMillion: null, outputPricePerMillion: null);
    }
    return (
      inputPricePerMillion: _openRouterPricePerMillion(raw['prompt']),
      outputPricePerMillion: _openRouterPricePerMillion(raw['completion']),
    );
  }

  double? _openRouterPricePerMillion(dynamic value) {
    if (value == null) return null;
    final parsed = double.tryParse(value.toString());
    if (parsed == null || !parsed.isFinite || parsed < 0) return null;
    return parsed * 1000000;
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
    if (data == null) return null;
    dynamic map = data;
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.startsWith('{')) {
        try {
          map = jsonDecode(trimmed);
        } catch (_) {
          return trimmed.isNotEmpty ? trimmed : null;
        }
      } else {
        return trimmed.isNotEmpty ? trimmed : null;
      }
    }
    if (map is! Map) return null;

    final error = map['error'];
    if (error is Map) {
      final type = error['type']?.toString();
      final message = error['message']?.toString();
      final code = error['code']?.toString();
      if (message != null && message.trim().isNotEmpty) {
        if (type != null && type.trim().isNotEmpty) return '$type: $message';
        if (code != null && code.trim().isNotEmpty) return 'Error $code: $message';
        return message;
      }
      return type ?? code;
    } else if (error is String && error.trim().isNotEmpty) {
      return error;
    }

    final message = map['message']?.toString();
    final type = map['type']?.toString();
    final detail = map['detail']?.toString();
    if (message != null && message.trim().isNotEmpty) {
      if (type != null && type.trim().isNotEmpty) return '$type: $message';
      return message;
    }
    if (detail != null && detail.trim().isNotEmpty) {
      return detail;
    }
    if (type != null && type.trim().isNotEmpty) {
      return type;
    }

    return null;
  }
}
