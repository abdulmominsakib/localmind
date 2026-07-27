import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/data/server_api_service.dart';
import 'dart:convert';

class TestInterceptor extends Interceptor {
  final dynamic responseData;
  TestInterceptor(this.responseData);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(Response(
      requestOptions: options,
      data: responseData,
      statusCode: 200,
    ));
  }
}

class RequestRecordingInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];
  final int statusCode;
  RequestRecordingInterceptor({this.statusCode = 200});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: statusCode,
        data: {'status': 'ok'},
      ),
    );
  }
}

class FailingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'connection refused',
      ),
    );
  }
}

class RoutingInterceptor extends Interceptor {
  RoutingInterceptor(this.responses);

  /// Maps a request key ("METHOD /path" or "METHOD /path:body-name") to a
  /// mock response body. Keys match against the request's path suffix so
  /// tests don't need a baseUrl.
  final Map<String, dynamic> responses;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final key = _matchKey(options);
    final body = key == null ? null : responses[key];
    if (body == null) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          message: 'No mock for ${options.method} ${options.path}',
        ),
      );
      return;
    }
    handler.resolve(
      Response(requestOptions: options, statusCode: 200, data: body),
    );
  }

  String? _matchKey(RequestOptions options) {
    final method = options.method.toUpperCase();
    final path = options.path;
    final base = '$method $path';
    final suffix = '$method ${_suffix(path)}';
    for (final candidate in responses.keys) {
      if (candidate == base || candidate == suffix) return candidate;
    }
    final name = _bodyName(options.data);
    if (name == null) return null;
    final baseKey = '$base:$name';
    if (responses.containsKey(baseKey)) return baseKey;
    return '$suffix:$name';
  }

  String _suffix(String path) {
    final idx = path.indexOf('/api/');
    if (idx < 0) return path;
    return path.substring(idx);
  }

  String? _bodyName(dynamic data) {
    if (data is Map) return data['name']?.toString();
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return decoded['name']?.toString();
      } catch (_) {
        // Not JSON — leave name null.
      }
    }
    return null;
  }
}

void main() {
  group('ServerApiService - OpenAI/llama.cpp model list parsing', () {
    late Server testServer;

    setUp(() {
      testServer = Server(
        id: 'test-openai',
        name: 'Test OpenAI Compatible',
        type: ServerType.openAICompatible,
        host: 'localhost',
        port: 8080,
        createdAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );
    });

    test('parses models successfully using fallback data array (llama.cpp / OpenAI standard)', () async {
      final mockData = {
        "object": "list",
        "data": [
          {
            "id": "meta-llama/Llama-3-8B-Instruct",
            "object": "model",
            "created": 1677610602,
            "owned_by": "openai",
            "meta": {
              "n_ctx_train": 8192,
              "n_params": 8000000000,
              "size": 4800000000
            }
          }
        ]
      };

      final dio = Dio()..interceptors.add(TestInterceptor(mockData));
      final service = ServerApiService(dio);

      final models = await service.fetchModels(testServer);

      expect(models, hasLength(1));
      final model = models.first;
      expect(model.id, "meta-llama/Llama-3-8B-Instruct");
      expect(model.name, "Meta Llama/Llama 3 8B Instruct");
      expect(model.contextLength, 8192);
      expect(model.parameterCount, 8.0); // 8000000000 / 1000000000
      expect(model.fileSize, 4800000000);
      expect(model.serverType, ServerType.openAICompatible);
      expect(model.serverId, testServer.id);
    });

    test('parses models successfully using custom models array (LM Studio)', () async {
      final mockData = {
        "models": [
          {
            "key": "lmstudio-community/Meta-Llama-3-8B-Instruct-GGUF",
            "display_name": "Llama 3 8B Instruct",
            "description": "LM Studio test model",
            "params_string": "8B",
            "max_context_length": 4096,
            "size_bytes": 5000000000,
            "quantization": {
              "name": "Q4_K_M"
            },
            "architecture": "llama"
          }
        ]
      };

      final dio = Dio()..interceptors.add(TestInterceptor(mockData));
      final service = ServerApiService(dio);

      final models = await service.fetchModels(testServer);

      expect(models, hasLength(1));
      final model = models.first;
      expect(model.id, "lmstudio-community/Meta-Llama-3-8B-Instruct-GGUF");
      expect(model.name, "Llama 3 8B Instruct");
      expect(model.description, "LM Studio test model");
      expect(model.parameterCount, 8.0);
      expect(model.contextLength, 4096);
      expect(model.fileSize, 5000000000);
      expect(model.quantization, "Q4_K_M");
      expect(model.architecture, "llama");
    });

    test('parses model capabilities from LM Studio models array', () async {
      final mockData = {
        "models": [
          {
            "key": "google/gemma-4-e2b",
            "display_name": "Gemma 4 E2B",
            "capabilities": {
              "vision": true,
              "trained_for_tool_use": true,
            },
          },
          {
            "key": "mistralai/ministral-3-14b-reasoning",
            "display_name": "Ministral 3 14B Reasoning",
            "capabilities": {
              "vision": true,
              "trained_for_tool_use": true,
              "reasoning": {
                "allowed_options": ["off", "on"],
                "default": "on",
              },
            },
          },
          {
            "key": "mradermacher/kimi-vl-a3b-thinking-2506-i1",
            "display_name": "Kimi VL A3B Thinking 2506 I1",
            "capabilities": {
              "vision": false,
              "trained_for_tool_use": false,
            },
          },
        ],
      };

      final dio = Dio()..interceptors.add(TestInterceptor(mockData));
      final service = ServerApiService(dio);

      final models = await service.fetchModels(testServer);

      expect(models, hasLength(3));

      expect(models[0].supportsVision, isTrue);
      expect(models[0].supportsToolUse, isTrue);
      expect(models[0].supportsReasoning, isFalse);

      expect(models[1].supportsVision, isTrue);
      expect(models[1].supportsToolUse, isTrue);
      expect(models[1].supportsReasoning, isTrue);

      expect(models[2].supportsVision, isFalse);
      expect(models[2].supportsToolUse, isFalse);
      expect(models[2].supportsReasoning, isFalse);
    });

    test('handles running models with fallback data array (llama.cpp)', () async {
      final mockData = {
        "object": "list",
        "data": [
          {
            "id": "active-model",
            "object": "model"
          }
        ]
      };

      final dio = Dio()..interceptors.add(TestInterceptor(mockData));
      final service = ServerApiService(dio);

      final lmStudioServer = testServer.copyWith(type: ServerType.lmStudio);
      final running = await service.fetchRunningModels(lmStudioServer);

      expect(running, contains("active-model"));
    });

    test('handles running models with custom models array and loaded instances (LM Studio)', () async {
      final mockData = {
        "models": [
          {
            "key": "active-model-lm",
            "loaded_instances": [
              {"id": "inst_1"}
            ]
          },
          {
            "key": "inactive-model-lm",
            "loaded_instances": []
          }
        ]
      };

      final dio = Dio()..interceptors.add(TestInterceptor(mockData));
      final service = ServerApiService(dio);

      final lmStudioServer = testServer.copyWith(type: ServerType.lmStudio);
      final running = await service.fetchRunningModels(lmStudioServer);

      expect(running, contains("inst_1"));
      expect(running, isNot(contains("inactive-model-lm")));
    });

    test('handles custom string quantization value gracefully', () async {
      final mockData = {
        "data": [
          {
            "id": "model-with-string-quant",
            "quantization": "Q5_K_M"
          }
        ]
      };

      final dio = Dio()..interceptors.add(TestInterceptor(mockData));
      final service = ServerApiService(dio);

      final models = await service.fetchModels(testServer);
      expect(models.first.quantization, "Q5_K_M");
    });

    test('handles actual user llama.cpp endpoint output successfully with Map architecture', () async {
      final mockData = {
        "data": [
          {
            "id": "Gemma-4-31B:IQ4_XS",
            "aliases": [],
            "tags": [],
            "object": "model",
            "owned_by": "llamacpp",
            "created": 1779851034,
            "status": {
              "value": "unloaded",
              "args": [
                "D:\\llamacpp\\llama-server.exe",
                "--host",
                "127.0.0.1",
                "--jinja",
                "--mlock",
                "--no-mmap",
                "--port",
                "0",
                "--alias",
                "Gemma-4-31B:IQ4_XS",
                "--ctx-size",
                "65536",
                "--cache-type-k",
                "q4_0",
                "--cache-type-v",
                "q4_0",
                "--flash-attn",
                "true",
                "--model",
                "./models/gemma-4-31B-it-llmfan-i1-IQ4_XS.gguf",
                "--parallel",
                "1",
                "--reasoning",
                "off"
              ],
              "preset": "[Gemma-4-31B:IQ4_XS]\njinja = true\nmlock = 1\nmmap = 0\nctx-size = 65536\ncache-type-k = q4_0\ncache-type-v = q4_0\nflash-attn = true\nmodel = ./models/gemma-4-31B-it-llmfan-i1-IQ4_XS.gguf\nparallel = 1\nreasoning = off\n\n"
            },
            "architecture": {
              "input_modalities": ["text"],
              "output_modalities": ["text"]
            }
          }
        ],
        "object": "list"
      };

      final dio = Dio()..interceptors.add(TestInterceptor(mockData));
      final service = ServerApiService(dio);

      final models = await service.fetchModels(testServer);
      expect(models, hasLength(1));
      expect(models.first.id, "Gemma-4-31B:IQ4_XS");
      expect(models.first.architecture, isNull);
    });
  });

  group('ServerApiService - Ollama load behavior', () {
    test('loadModel is a no-op for Ollama (does not POST /api/generate)', () async {
      final ollamaServer = Server(
        id: 'test-ollama',
        name: 'Test Ollama',
        type: ServerType.ollama,
        host: 'localhost',
        port: 11434,
        createdAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );

      final dio = Dio()..interceptors.add(RequestRecordingInterceptor());
      final service = ServerApiService(dio);

      await service.loadModel(ollamaServer, 'llama3.2:latest');
      await service.loadModelWithInstanceId(ollamaServer, 'llama3.2:latest');

      final recorder =
          dio.interceptors.firstWhere((i) => i is RequestRecordingInterceptor)
              as RequestRecordingInterceptor;
      expect(recorder.requests, isEmpty,
          reason: 'Ollama should not issue an explicit load request; '
              'calling /api/generate without a prompt can trigger an '
              'auto-pull of the model from the Ollama registry.');
    });

    test('unloadModel for Ollama posts keep_alive=0 and a valid payload', () async {
      final ollamaServer = Server(
        id: 'test-ollama',
        name: 'Test Ollama',
        type: ServerType.ollama,
        host: 'localhost',
        port: 11434,
        createdAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );

      final dio = Dio()..interceptors.add(RequestRecordingInterceptor());
      final service = ServerApiService(dio);

      await service.unloadModel(ollamaServer, 'llama3.2:latest');

      final recorder =
          dio.interceptors.firstWhere((i) => i is RequestRecordingInterceptor)
              as RequestRecordingInterceptor;
      expect(recorder.requests, hasLength(1));
      expect(recorder.requests.first.path, endsWith('/api/generate'));
      expect(recorder.requests.first.data, containsPair('keep_alive', 0));
      expect(recorder.requests.first.data, containsPair('model', 'llama3.2:latest'));
      expect(recorder.requests.first.data, containsPair('prompt', ''));
    });

    test(
      'fetchModels enriches Ollama models with vision capability from /api/show',
      () async {
        final ollamaServer = Server(
          id: 'test-ollama',
          name: 'Test Ollama',
          type: ServerType.ollama,
          host: 'localhost',
          port: 11434,
          createdAt: DateTime.now(),
          lastConnectedAt: DateTime.now(),
        );

        final interceptor = RoutingInterceptor({
          'GET /api/tags': {
            'models': [
              {
                'name': 'qwen3-vl:2b',
                'size': 1800000000,
                'details': {
                  'parameter_size': '2.1B',
                  'quantization_level': 'Q4_K_M',
                  'family': 'qwen3',
                },
              },
              {
                'name': 'llama3.2:3b',
                'size': 2000000000,
                'details': {
                  'parameter_size': '3B',
                  'quantization_level': 'Q4_K_M',
                  'family': 'llama',
                },
              },
            ],
          },
          'POST /api/show:qwen3-vl:2b': {
            'capabilities': ['completion', 'vision'],
          },
          'POST /api/show:llama3.2:3b': {
            'capabilities': ['completion'],
          },
        });

        final service = ServerApiService(Dio()..interceptors.add(interceptor));
        final models = await service.fetchModels(ollamaServer);

        expect(models, hasLength(2));
        final byId = {for (final m in models) m.id: m};
        expect(byId['qwen3-vl:2b']?.supportsVision, isTrue);
        expect(byId['llama3.2:3b']?.supportsVision, isFalse);
      },
    );

    test('unloadModel for Ollama surfaces failures', () async {
      final ollamaServer = Server(
        id: 'test-ollama',
        name: 'Test Ollama',
        type: ServerType.ollama,
        host: 'localhost',
        port: 11434,
        createdAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );

      final dio = Dio()..interceptors.add(FailingInterceptor());
      final service = ServerApiService(dio);

      expect(
        () => service.unloadModel(ollamaServer, 'llama3.2:latest'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
