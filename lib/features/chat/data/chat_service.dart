import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../servers/data/models/server.dart';
import 'models/message.dart';
import 'models/chat_parameters.dart';
import 'models/mcp_integration.dart';
import '../../../core/models/enums.dart';
import '../../../core/logger/app_logger.dart';
import '../../on_device/data/on_device_engine_service.dart';
import '../../on_device/data/on_device_chat_service.dart';

abstract class ChatService {
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    String? previousResponseId,
  });

  void cancelStream();

  static ChatService forServer(
    ServerType type,
    Dio dio, {
    OnDeviceEngineService? onDeviceEngine,
  }) {
    switch (type) {
      case ServerType.lmStudio:
        return LMStudioChatService(dio);
      case ServerType.openAICompatible:
        return OpenAICompatibleChatService(dio);
      case ServerType.ollama:
        return OllamaChatService(dio);
      case ServerType.openRouter:
        return OpenRouterChatService(dio);
      case ServerType.onDevice:
        if (onDeviceEngine == null) {
          throw StateError(
            'OnDeviceEngineService is required for onDevice server type',
          );
        }
        return OnDeviceChatService(onDeviceEngine);
    }
  }
}

class ChatResponse {
  final ChatResponseType type;
  final String? content;
  final String? reasoningContent;
  final ToolCallData? toolCall;
  final InvalidToolCallData? invalidToolCall;
  final ChatStats? stats;

  const ChatResponse({
    required this.type,
    this.content,
    this.reasoningContent,
    this.toolCall,
    this.invalidToolCall,
    this.stats,
  });
}

enum ChatResponseType {
  message,
  reasoning,
  toolCall,
  invalidToolCall,
  done,
  processing,
  timeoutError,
  error,
}

class ToolCallData {
  final String tool;
  final Map<String, dynamic> arguments;
  final String? output;
  final ToolProviderInfo? providerInfo;

  const ToolCallData({
    required this.tool,
    required this.arguments,
    this.output,
    this.providerInfo,
  });
}

class ToolProviderInfo {
  final String type;
  final String? pluginId;
  final String? serverLabel;

  const ToolProviderInfo({required this.type, this.pluginId, this.serverLabel});
}

class InvalidToolCallData {
  final String reason;
  final String? metadataType;
  final String? toolName;
  final Map<String, dynamic>? arguments;
  final ToolProviderInfo? providerInfo;

  const InvalidToolCallData({
    required this.reason,
    this.metadataType,
    this.toolName,
    this.arguments,
    this.providerInfo,
  });
}

class ChatStats {
  final int inputTokens;
  final int totalOutputTokens;
  final int? reasoningOutputTokens;
  final double? tokensPerSecond;
  final double? timeToFirstTokenSeconds;
  final double? modelLoadTimeSeconds;

  const ChatStats({
    required this.inputTokens,
    required this.totalOutputTokens,
    this.reasoningOutputTokens,
    this.tokensPerSecond,
    this.timeToFirstTokenSeconds,
    this.modelLoadTimeSeconds,
  });
}

class LMStudioChatService implements ChatService {
  final Dio _dio;
  CancelToken? _cancelToken;

  LMStudioChatService(this._dio);

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    String? previousResponseId,
  }) async* {
    _cancelToken = CancelToken();

    final body = <String, dynamic>{
      'model': modelId,
      'input': _formatInput(messages),
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_output_tokens': params.maxTokens,
      'context_length': params.contextLength,
      'stream': true,
      'store': true,
    };

    if (params.systemPrompt != null && params.systemPrompt!.isNotEmpty) {
      body['system_prompt'] = params.systemPrompt;
    }
    if (params.topK != null) body['top_k'] = params.topK;
    if (params.minP != null) body['min_p'] = params.minP;
    if (params.repeatPenalty != null) {
      body['repeat_penalty'] = params.repeatPenalty;
    }
    if (params.reasoningLevel != null) {
      body['reasoning'] = params.reasoningLevel;
    }
    if (integrations != null && integrations.isNotEmpty) {
      body['integrations'] = integrations.map((i) => i.toJson()).toList();
    }
    if (previousResponseId != null) {
      body['previous_response_id'] = previousResponseId;
    }

    try {
      final response = await _dio.post<ResponseBody>(
        server.chatEndpoint,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/json',
            if (server.apiKey != null)
              'Authorization': 'Bearer ${server.apiKey}',
          },
        ),
        cancelToken: _cancelToken,
      );

      final stream = response.data!.stream.cast<List<int>>().transform(
        utf8.decoder,
      );
      String buffer = '';
      String currentEventType = '';

      await for (final chunk in stream) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isEmpty) continue;

          if (trimmedLine.startsWith('event: ')) {
            currentEventType = trimmedLine.substring(7);
          } else if (trimmedLine.startsWith('data: ')) {
            final data = trimmedLine.substring(6);
            if (data.isEmpty) continue;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              await for (final response in _handleSseEvent(
                currentEventType,
                json,
              )) {
                yield response;
              }
              currentEventType = '';
            } catch (e) {
              currentEventType = '';
            }
          }
        }
      }
    } catch (e) {
      Log.error('LMStudio connection error: $e');
      yield ChatResponse(
        type: ChatResponseType.error,
        content: _handleChatError(e),
      );
    }
  }

  Stream<ChatResponse> _handleSseEvent(
    String eventType,
    Map<String, dynamic> json,
  ) async* {
    switch (eventType) {
      case 'message.delta':
        final content = json['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield ChatResponse(type: ChatResponseType.message, content: content);
        }
        break;

      case 'reasoning.delta':
        final content = json['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield ChatResponse(
            type: ChatResponseType.reasoning,
            reasoningContent: content,
          );
        }
        break;

      case 'tool_call.start':
        final tool = json['tool'] as String?;
        final providerInfo = json['provider_info'] as Map<String, dynamic>?;
        if (tool != null) {
          yield ChatResponse(
            type: ChatResponseType.toolCall,
            toolCall: ToolCallData(
              tool: tool,
              arguments: {},
              providerInfo: providerInfo != null
                  ? ToolProviderInfo(
                      type: providerInfo['type'] as String? ?? '',
                      pluginId: providerInfo['plugin_id'] as String?,
                      serverLabel: providerInfo['server_label'] as String?,
                    )
                  : null,
            ),
          );
        }
        break;

      case 'tool_call.arguments':
        final tool = json['tool'] as String?;
        final arguments = json['arguments'] as Map<String, dynamic>?;
        final providerInfo = json['provider_info'] as Map<String, dynamic>?;
        if (tool != null && arguments != null) {
          yield ChatResponse(
            type: ChatResponseType.toolCall,
            toolCall: ToolCallData(
              tool: tool,
              arguments: arguments,
              providerInfo: providerInfo != null
                  ? ToolProviderInfo(
                      type: providerInfo['type'] as String? ?? '',
                      pluginId: providerInfo['plugin_id'] as String?,
                      serverLabel: providerInfo['server_label'] as String?,
                    )
                  : null,
            ),
          );
        }
        break;

      case 'tool_call.success':
        final tool = json['tool'] as String?;
        final arguments = json['arguments'] as Map<String, dynamic>?;
        final output = json['output'] as String?;
        final providerInfo = json['provider_info'] as Map<String, dynamic>?;
        if (tool != null) {
          yield ChatResponse(
            type: ChatResponseType.toolCall,
            toolCall: ToolCallData(
              tool: tool,
              arguments: arguments ?? {},
              output: output,
              providerInfo: providerInfo != null
                  ? ToolProviderInfo(
                      type: providerInfo['type'] as String? ?? '',
                      pluginId: providerInfo['plugin_id'] as String?,
                      serverLabel: providerInfo['server_label'] as String?,
                    )
                  : null,
            ),
          );
        }
        break;

      case 'tool_call.failure':
        final reason = json['reason'] as String?;
        final metadata = json['metadata'] as Map<String, dynamic>?;
        if (reason != null) {
          final providerInfo =
              metadata?['provider_info'] as Map<String, dynamic>?;
          yield ChatResponse(
            type: ChatResponseType.invalidToolCall,
            invalidToolCall: InvalidToolCallData(
              reason: reason,
              metadataType: metadata?['type'] as String?,
              toolName: metadata?['tool_name'] as String?,
              arguments: metadata?['arguments'] as Map<String, dynamic>?,
              providerInfo: providerInfo != null
                  ? ToolProviderInfo(
                      type: providerInfo['type'] as String? ?? '',
                      pluginId: providerInfo['plugin_id'] as String?,
                      serverLabel: providerInfo['server_label'] as String?,
                    )
                  : null,
            ),
          );
        }
        break;

      case 'chat.end':
        final result = json['result'] as Map<String, dynamic>?;
        if (result != null) {
          final stats = result['stats'] as Map<String, dynamic>?;
          yield ChatResponse(
            type: ChatResponseType.done,
            stats: stats != null
                ? ChatStats(
                    inputTokens: stats['input_tokens'] as int? ?? 0,
                    totalOutputTokens:
                        stats['total_output_tokens'] as int? ?? 0,
                    reasoningOutputTokens:
                        stats['reasoning_output_tokens'] as int?,
                    tokensPerSecond: (stats['tokens_per_second'] as num?)
                        ?.toDouble(),
                    timeToFirstTokenSeconds:
                        (stats['time_to_first_token_seconds'] as num?)
                            ?.toDouble(),
                    modelLoadTimeSeconds:
                        (stats['model_load_time_seconds'] as num?)?.toDouble(),
                  )
                : null,
          );
        }
        break;

      case 'error':
        final error = json['error'] as Map<String, dynamic>?;
        if (error != null) {
          yield ChatResponse(
            type: ChatResponseType.message,
            content: 'Error: ${error['message'] ?? 'Unknown error'}',
          );
        }
        break;
    }
  }

  dynamic _formatInput(List<Message> messages) {
    final formattedInputs = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (m.role != MessageRole.system) {
        formattedInputs.add({'type': 'text', 'content': m.content});
      }
    }
    return formattedInputs;
  }

  @override
  void cancelStream() {
    _cancelToken?.cancel('User cancelled');
  }
}

class OpenAICompatibleChatService implements ChatService {
  final Dio _dio;
  CancelToken? _cancelToken;
  Timer? _timeoutTimer;

  OpenAICompatibleChatService(this._dio);

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    String? previousResponseId,
  }) async* {
    _cancelToken = CancelToken();

    final body = {
      'model': modelId,
      'messages': messages
          .map((m) => {'role': _roleToString(m.role), 'content': m.content})
          .toList(),
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_tokens': params.maxTokens,
      'stream': true,
    };

    Log.debug(
      'OpenAICompatible: Sending request to ${server.chatEndpoint} with model: $modelId',
    );

    try {
      final response = await _dio.post<ResponseBody>(
        server.chatEndpoint,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/json',
            if (server.apiKey != null)
              'Authorization': 'Bearer ${server.apiKey}',
          },
        ),
        cancelToken: _cancelToken,
      );

      final stream = response.data!.stream.cast<List<int>>().transform(
        utf8.decoder,
      );
      String buffer = '';
      DateTime? lastContentReceived;
      int emptyDeltaCount = 0;
      int logCounter = 0;
      bool timeoutTriggered = false;

      // Start timeout timer
      _timeoutTimer = Timer(const Duration(seconds: 45), () {
        timeoutTriggered = true;
      });

      Log.debug('OpenAICompatible: Starting to receive stream...');

      await for (final chunk in stream) {
        // Check if timeout was triggered
        if (timeoutTriggered && lastContentReceived == null) {
          _timeoutTimer?.cancel();
          yield const ChatResponse(
            type: ChatResponseType.timeoutError,
            content:
                'Model is taking too long to respond. This may happen with free tier models.',
          );
          return;
        }

        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          logCounter++;
          if (logCounter % 10 == 0) {
            Log.debug('OpenAICompatible SSE line #$logCounter');
          }

          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') {
              _timeoutTimer?.cancel();
              Log.debug('OpenAICompatible: Received [DONE]');
              yield const ChatResponse(type: ChatResponseType.done);
              return;
            }
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;

              // Check for errors in the response
              if (json['error'] != null) {
                final error = json['error'] as Map<String, dynamic>;
                final errorMsg = error['message'] ?? 'Unknown API error';
                Log.error('OpenAICompatible mid-stream error: $errorMsg');
                yield ChatResponse(
                  type: ChatResponseType.error,
                  content: 'API Error: $errorMsg',
                );
                return;
              }

              final choices = json['choices'] as List<dynamic>?;
              if (choices == null || choices.isEmpty) {
                continue;
              }

              final firstChoice = choices[0] as Map<String, dynamic>?;
              if (firstChoice == null) continue;

              final delta = firstChoice['delta'];
              if (delta == null || delta is! Map<String, dynamic>) continue;

              final content = (delta['content'] ?? delta['text']) as String?;
              final reasoning =
                  (delta['reasoning'] ?? delta['reasoning_content']) as String?;
              final refusal = delta['refusal'] as String?;

              // Check if content is empty/null (processing but not outputting)
              final hasContent = content != null && content.isNotEmpty;
              final hasReasoning = reasoning != null && reasoning.isNotEmpty;
              final hasRefusal = refusal != null && refusal.isNotEmpty;

              if (!hasContent && !hasReasoning && !hasRefusal) {
                emptyDeltaCount++;
                if (emptyDeltaCount % 10 == 0) {
                  yield const ChatResponse(type: ChatResponseType.processing);
                }
              } else {
                emptyDeltaCount = 0;
                lastContentReceived = DateTime.now();

                if (hasRefusal) {
                  yield ChatResponse(
                    type: ChatResponseType.error,
                    content: 'Refusal: $refusal',
                  );
                  return;
                }
                if (hasContent) {
                  yield ChatResponse(
                    type: ChatResponseType.message,
                    content: content,
                  );
                }
                if (hasReasoning) {
                  yield ChatResponse(
                    type: ChatResponseType.reasoning,
                    reasoningContent: reasoning,
                  );
                }
              }
            } catch (e) {
              Log.error('OpenAICompatible parsing error: $e');
            }
          }
        }
      }
    } catch (e) {
      Log.error('OpenAICompatible connection error: $e');
      yield ChatResponse(
        type: ChatResponseType.error,
        content: _handleChatError(e),
      );
    }

    _timeoutTimer?.cancel();
    Log.debug('OpenAICompatible: Stream ended');
  }

  @override
  void cancelStream() {
    _timeoutTimer?.cancel();
    _cancelToken?.cancel('User cancelled');
  }
}

class OllamaChatService implements ChatService {
  final Dio _dio;
  CancelToken? _cancelToken;

  OllamaChatService(this._dio);

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    String? previousResponseId,
  }) async* {
    _cancelToken = CancelToken();

    final body = {
      'model': modelId,
      'messages': messages
          .map((m) => {'role': _roleToString(m.role), 'content': m.content})
          .toList(),
      'stream': true,
      'options': {
        'temperature': params.temperature,
        'top_p': params.topP,
        'num_predict': params.maxTokens,
      },
    };

    try {
      final response = await _dio.post<ResponseBody>(
        server.chatEndpoint,
        data: body,
        options: Options(responseType: ResponseType.stream),
        cancelToken: _cancelToken,
      );

      final stream = response.data!.stream.cast<List<int>>().transform(
        utf8.decoder,
      );
      String buffer = '';

      await for (final chunk in stream) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          if (line.isNotEmpty) {
            try {
              final json = jsonDecode(line) as Map<String, dynamic>;
              final content = json['message']?['content'];
              if (content != null && content is String) {
                yield ChatResponse(
                  type: ChatResponseType.message,
                  content: content,
                );
              }
              if (json['done'] == true) {
                yield const ChatResponse(type: ChatResponseType.done);
                return;
              }
            } catch (e) {
              // ignore: empty_catches
            }
          }
        }
      }
    } catch (e) {
      Log.error('Ollama connection error: $e');
      yield ChatResponse(
        type: ChatResponseType.error,
        content: _handleChatError(e),
      );
    }
  }

  @override
  void cancelStream() {
    _cancelToken?.cancel('User cancelled');
  }
}

class OpenRouterChatService implements ChatService {
  final Dio _dio;
  CancelToken? _cancelToken;
  Timer? _timeoutTimer;

  OpenRouterChatService(this._dio);

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    String? previousResponseId,
  }) async* {
    _cancelToken = CancelToken();

    final body = {
      'model': modelId,
      'messages': messages
          .map((m) => {'role': _roleToString(m.role), 'content': m.content})
          .toList(),
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_tokens': params.maxTokens,
      'stream': true,
    };

    Log.debug(
      'OpenRouter: Sending request to ${server.chatEndpoint} with model: $modelId',
    );

    try {
      final response = await _dio.post<ResponseBody>(
        server.chatEndpoint,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${server.apiKey}',
            'HTTP-Referer': 'https://localmind.app',
            'X-Title': 'LocalMind',
          },
        ),
        cancelToken: _cancelToken,
      );

      final stream = response.data!.stream.cast<List<int>>().transform(
        utf8.decoder,
      );
      String buffer = '';
      DateTime? lastContentReceived;
      int emptyDeltaCount = 0;
      int logCounter = 0;
      bool timeoutTriggered = false;

      // Start timeout timer
      _timeoutTimer = Timer(const Duration(seconds: 45), () {
        timeoutTriggered = true;
      });

      Log.debug('OpenRouter: Starting to receive stream...');

      await for (final chunk in stream) {
        // Check if timeout was triggered
        if (timeoutTriggered && lastContentReceived == null) {
          _timeoutTimer?.cancel();
          yield const ChatResponse(
            type: ChatResponseType.timeoutError,
            content:
                'Model is taking too long to respond. This may happen with free tier models.',
          );
          return;
        }

        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          logCounter++;
          if (logCounter % 10 == 0) {
            Log.debug('OpenRouter SSE line #$logCounter: $line');
          }

          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') {
              _timeoutTimer?.cancel();
              Log.debug('OpenRouter: Received [DONE]');
              yield const ChatResponse(type: ChatResponseType.done);
              return;
            }
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;

              // Check for errors in the response
              if (json['error'] != null) {
                final error = json['error'] as Map<String, dynamic>;
                final errorMsg = error['message'] ?? 'Unknown API error';
                Log.error('OpenRouter mid-stream error: $errorMsg');
                yield ChatResponse(
                  type: ChatResponseType.error,
                  content: 'API Error: $errorMsg',
                );
                return;
              }

              final choices = json['choices'] as List<dynamic>?;
              if (choices == null || choices.isEmpty) {
                continue;
              }

              final firstChoice = choices[0] as Map<String, dynamic>?;
              if (firstChoice == null) continue;

              final delta = firstChoice['delta'];
              if (delta == null || delta is! Map<String, dynamic>) continue;

              final content = (delta['content'] ?? delta['text']) as String?;
              final reasoning =
                  (delta['reasoning'] ?? delta['reasoning_content']) as String?;
              final refusal = delta['refusal'] as String?;

              // Check if content is empty/null (processing but not outputting)
              final hasContent = content != null && content.isNotEmpty;
              final hasReasoning = reasoning != null && reasoning.isNotEmpty;
              final hasRefusal = refusal != null && refusal.isNotEmpty;

              if (!hasContent && !hasReasoning && !hasRefusal) {
                emptyDeltaCount++;
                if (emptyDeltaCount % 10 == 0) {
                  yield const ChatResponse(type: ChatResponseType.processing);
                }
              } else {
                emptyDeltaCount = 0;
                lastContentReceived = DateTime.now();

                if (hasRefusal) {
                  yield ChatResponse(
                    type: ChatResponseType.error,
                    content: 'Refusal: $refusal',
                  );
                  return;
                }
                if (hasContent) {
                  yield ChatResponse(
                    type: ChatResponseType.message,
                    content: content,
                  );
                }
                if (hasReasoning) {
                  yield ChatResponse(
                    type: ChatResponseType.reasoning,
                    reasoningContent: reasoning,
                  );
                }
              }
            } catch (e) {
              Log.error('OpenRouter parsing error: $e');
            }
          } else if (line.startsWith(': ')) {
            // SSE comment (keep-alive)
            if (logCounter % 50 == 0) {
              Log.debug('OpenRouter SSE comment: $line');
            }
          }
        }
      }
    } catch (e) {
      Log.error('OpenRouter connection error: $e');
      yield ChatResponse(
        type: ChatResponseType.error,
        content: _handleChatError(e),
      );
    }

    _timeoutTimer?.cancel();
    Log.debug('OpenRouter: Stream ended');
  }

  @override
  void cancelStream() {
    _timeoutTimer?.cancel();
    _cancelToken?.cancel('User cancelled');
  }
}

String _handleChatError(dynamic e) {
  if (e is DioException) {
    if (e.response != null) {
      final status = e.response!.statusCode;

      switch (status) {
        case 401:
          return 'Invalid API key or unauthorized.';
        case 402:
          return 'Monthly credit limit reached or insufficient balance.';
        case 403:
          return 'Access forbidden. Your API key might not have permission for this model.';
        case 404:
          return 'Model not found or API endpoint is incorrect.';
        case 408:
          return 'Request timeout. The server took too long to respond.';
        case 429:
          return 'Rate limit exceeded. Please wait a moment before trying again.';
        case 500:
          return 'Internal server error from the AI provider.';
        case 502:
          return 'Bad gateway. The provider is having issues.';
        case 503:
          return 'Service unavailable. The provider might be overloaded.';
        case 504:
          return 'Gateway timeout. The model took too long to respond.';
      }
      return 'Server error ($status): ${e.message}';
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Check your internet connection.';
      case DioExceptionType.connectionError:
        return 'Connection failed. Check if the server is accessible.';
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      default:
        return 'Connection error: ${e.message}';
    }
  }
  return e.toString();
}

String _roleToString(MessageRole role) {
  switch (role) {
    case MessageRole.user:
      return 'user';
    case MessageRole.assistant:
      return 'assistant';
    case MessageRole.system:
      return 'system';
    case MessageRole.tool:
      return 'tool';
  }
}
