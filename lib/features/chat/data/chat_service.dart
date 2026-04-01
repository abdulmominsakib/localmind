import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/mcp_integration.dart';
import 'package:localmind/core/models/enums.dart';

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

  static ChatService forServer(ServerType type, Dio dio) {
    switch (type) {
      case ServerType.lmStudio:
        return LMStudioChatService(dio);
      case ServerType.openAICompatible:
        return OpenAICompatibleChatService(dio);
      case ServerType.ollama:
        return OllamaChatService(dio);
      case ServerType.openRouter:
        return OpenRouterChatService(dio);
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

enum ChatResponseType { message, reasoning, toolCall, invalidToolCall, done }

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
    if (params.repeatPenalty != null)
      body['repeat_penalty'] = params.repeatPenalty;
    if (params.reasoningLevel != null)
      body['reasoning'] = params.reasoningLevel;
    if (integrations != null && integrations.isNotEmpty) {
      body['integrations'] = integrations.map((i) => i.toJson()).toList();
    }
    if (previousResponseId != null)
      body['previous_response_id'] = previousResponseId;

    final response = await _dio.post<ResponseBody>(
      server.chatEndpoint,
      data: body,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Content-Type': 'application/json',
          if (server.apiKey != null) 'Authorization': 'Bearer ${server.apiKey}',
        },
      ),
      cancelToken: _cancelToken,
    );

    final stream = response.data!.stream;
    String buffer = '';
    String currentEventType = '';

    await for (final chunk in stream) {
      buffer += String.fromCharCodes(chunk);
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
      if (m.role == MessageRole.system) {
        formattedInputs.add({'type': 'system_prompt', 'content': m.content});
      } else {
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

    final response = await _dio.post<ResponseBody>(
      server.chatEndpoint,
      data: body,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Content-Type': 'application/json',
          if (server.apiKey != null) 'Authorization': 'Bearer ${server.apiKey}',
        },
      ),
      cancelToken: _cancelToken,
    );

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += String.fromCharCodes(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data == '[DONE]') {
            yield const ChatResponse(type: ChatResponseType.done);
            return;
          }
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final content = json['choices']?[0]?['delta']?['content'];
            if (content != null && content is String) {
              yield ChatResponse(
                type: ChatResponseType.message,
                content: content,
              );
            }
          } catch (e) {}
        }
      }
    }
  }

  @override
  void cancelStream() {
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

    final response = await _dio.post<ResponseBody>(
      server.chatEndpoint,
      data: body,
      options: Options(responseType: ResponseType.stream),
      cancelToken: _cancelToken,
    );

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += String.fromCharCodes(chunk);
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
          } catch (e) {}
        }
      }
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

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += String.fromCharCodes(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data == '[DONE]') {
            yield const ChatResponse(type: ChatResponseType.done);
            return;
          }
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final content = json['choices']?[0]?['delta']?['content'];
            if (content != null && content is String) {
              yield ChatResponse(
                type: ChatResponseType.message,
                content: content,
              );
            }
          } catch (e) {}
        }
      }
    }
  }

  @override
  void cancelStream() {
    _cancelToken?.cancel('User cancelled');
  }
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
