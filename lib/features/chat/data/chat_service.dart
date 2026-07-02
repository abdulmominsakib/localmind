import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:dio/dio.dart';
import '../../servers/data/models/server.dart';
import 'models/message.dart';
import 'models/chat_parameters.dart';
import 'models/mcp_integration.dart';
import 'tools/tool_definition.dart';
import '../../../core/models/enums.dart';
import '../../../core/logger/app_logger.dart';
import '../../on_device/data/on_device_gemma_service.dart';
import '../../on_device/data/on_device_chat_service.dart';
import 'tools/adapters/tool_transport_adapter.dart';
import '../utils/attachment_helpers.dart';
import 'tools/adapters/openai_tool_adapter.dart';
import 'tools/adapters/openrouter_tool_adapter.dart';
import 'tools/adapters/ollama_tool_adapter.dart';
import 'chat_api_error.dart';

abstract class ChatService {
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    List<ToolDefinition>? tools,
    String? previousResponseId,
    bool continueGeneration = false,
  });

  void cancelStream();

  static ChatService forServer(
    ServerType type,
    Dio dio, {
    OnDeviceGemmaService? onDeviceGemma,
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
        if (onDeviceGemma == null) {
          throw StateError(
            'OnDeviceGemmaService is required for onDevice server type',
          );
        }
        return OnDeviceChatService(onDeviceGemma);
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
    List<ToolDefinition>? tools,
    String? previousResponseId,
    bool continueGeneration = false,
  }) async* {
    _cancelToken = CancelToken();

    if (continueGeneration) {
      yield* _streamV0ChatCompletions(
        server: server,
        modelId: modelId,
        messages: messages,
        params: params,
      );
      return;
    }

    final dynamic formattedInput = await _formatInputWithImages(messages);

    final body = <String, dynamic>{
      'model': modelId,
      'input': formattedInput,
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_output_tokens': params.maxTokens,
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
            ...buildServerAuthHeaders(server),
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
      return;
    }
    yield const ChatResponse(type: ChatResponseType.done);
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
          final parsed = ChatApiError.fromErrorMap(error);
          yield ChatResponse(
            type: ChatResponseType.error,
            content: parsed?.encode() ?? error['message']?.toString() ?? 'Unknown error',
          );
        }
        break;
    }
  }

  Stream<ChatResponse> _streamV0ChatCompletions({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  }) async* {
    _cancelToken = CancelToken();

    final apiMessages = messages.map(_messageToApiMap).toList();
    if (apiMessages.isNotEmpty && apiMessages.last['role'] == 'assistant') {
      final last = apiMessages.last;
      last['content'] = (last['content'] as String?) ?? '';
    }

    final body = <String, dynamic>{
      'model': modelId,
      'messages': apiMessages,
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_tokens': params.maxTokens,
      'stream': true,
    };

    final endpoint = '${server.baseUrl}/api/v0/chat/completions';

    try {
      final response = await _dio.post<ResponseBody>(
        endpoint,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/json',
            ...buildServerAuthHeaders(server),
          },
        ),
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
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data == '[DONE]') {
            yield const ChatResponse(type: ChatResponseType.done);
            return;
          }
          if (data.isEmpty) continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            if (json['error'] != null) {
              yield ChatResponse(
                type: ChatResponseType.error,
                content: _formatApiErrorContent(json['error']),
              );
              return;
            }

            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;

            final firstChoice = choices[0] as Map<String, dynamic>?;
            if (firstChoice == null) continue;

            final delta = firstChoice['delta'];
            if (delta == null || delta is! Map<String, dynamic>) continue;

            final content = (delta['content'] ?? delta['text']) as String?;
            final reasoning =
                (delta['reasoning'] ?? delta['reasoning_content']) as String?;

            if (content != null && content.isNotEmpty) {
              yield ChatResponse(type: ChatResponseType.message, content: content);
            }
            if (reasoning != null && reasoning.isNotEmpty) {
              yield ChatResponse(
                type: ChatResponseType.reasoning,
                reasoningContent: reasoning,
              );
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      Log.error('LMStudio v0 continue error: $e');
      yield ChatResponse(
        type: ChatResponseType.error,
        content: _handleChatError(e),
      );
      return;
    }

    yield const ChatResponse(type: ChatResponseType.done);
  }

  Future<dynamic> _formatInputWithImages(List<Message> messages) async {
    final formattedInputs = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (m.role == MessageRole.system) continue;

      var textContent = m.content;
      final hasAttachments =
          m.attachmentPaths != null && m.attachmentPaths!.isNotEmpty;

      if (hasAttachments) {
        for (final path in m.attachmentPaths!) {
          if (!AttachmentHelpers.isTextPath(path)) continue;
          final text = await AttachmentHelpers.readTextFile(path);
          if (text != null) {
            textContent = AttachmentHelpers.appendTextAttachment(
              textContent,
              AttachmentHelpers.fileNameOf(path),
              text,
            );
          }
        }
      }

      final isEmptyAssistant =
          m.role == MessageRole.assistant && textContent.trim().isEmpty;

      if (textContent.trim().isNotEmpty && !isEmptyAssistant) {
        formattedInputs.add({'type': 'text', 'content': textContent});
      }

      if (hasAttachments) {
        for (final path in m.attachmentPaths!) {
          if (!AttachmentHelpers.isImagePath(path)) continue;
          try {
            final file = File(path);
            if (!await file.exists()) continue;
            final fileBytes = await file.readAsBytes();
            final base64Image = await Isolate.run(() {
              try {
                return base64Encode(fileBytes);
              } catch (_) {
                return null;
              }
            });

            if (base64Image != null) {
              final mimeType = AttachmentHelpers.mimeTypeForImage(path);
              formattedInputs.add({
                'type': 'image',
                'data_url': 'data:$mimeType;base64,$base64Image',
              });
            }
          } catch (e) {
            Log.error('Failed to read attachment for LMStudio format: $e');
          }
        }
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
    List<ToolDefinition>? tools,
    String? previousResponseId,
    bool continueGeneration = false,
  }) async* {
    _cancelToken = CancelToken();
    final toolAdapter = OpenAiToolAdapter();

    final apiMessages = messages.map(_messageToApiMap).toList();
    // Strip trailing empty assistant messages to avoid "prefill incompatible
    // with enable_thinking" errors from servers running thinking models
    if (!continueGeneration) {
      while (apiMessages.isNotEmpty &&
          apiMessages.last['role'] == 'assistant' &&
          (apiMessages.last['content'] == null ||
              (apiMessages.last['content'] is String &&
                  (apiMessages.last['content'] as String).isEmpty))) {
        apiMessages.removeLast();
      }
    } else if (apiMessages.isNotEmpty &&
        apiMessages.last['role'] == 'assistant') {
      // Keep the assistant prefill for continuation; ensure content is a string.
      final last = apiMessages.last;
      last['content'] = (last['content'] as String?) ?? '';
    }

    final body = {
      'model': modelId,
      'messages': apiMessages,
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_tokens': params.maxTokens,
      'stream': true,
    };

    if (tools != null && tools.isNotEmpty) {
      final toolsPayload = toolAdapter.buildToolDefinitionPayload(tools);
      if (toolsPayload.containsKey('tools')) {
        body['tools'] = toolsPayload['tools'];
      }
    }

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
            ...buildServerAuthHeaders(server),
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

      try {
        await for (final chunk in stream) {
          // Check if timeout was triggered
          if (timeoutTriggered && lastContentReceived == null) {
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
                for (final call in toolAdapter.takeCompletedCalls()) {
                  yield ChatResponse(
                    type: ChatResponseType.toolCall,
                    toolCall: ToolCallData(
                      tool: call.name,
                      arguments: call.arguments,
                    ),
                  );
                }
                yield const ChatResponse(type: ChatResponseType.done);
                return;
              }
              try {
                final json = jsonDecode(data) as Map<String, dynamic>;
                toolAdapter.consumeDynamicChunk(json);

                // Check for errors in the response
                if (json['error'] != null) {
                  _timeoutTimer?.cancel();
                  final errorContent = _formatApiErrorContent(json['error']);
                  Log.error('OpenAICompatible mid-stream error: $errorContent');
                  yield ChatResponse(
                    type: ChatResponseType.error,
                    content: errorContent,
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
      } finally {
        _timeoutTimer?.cancel();
      }

      // Flush any tool calls accumulated without a [DONE] marker (e.g.
      // connection drop or server crash before sending [DONE]).
      for (final call in toolAdapter.takeCompletedCalls()) {
        yield ChatResponse(
          type: ChatResponseType.toolCall,
          toolCall: ToolCallData(
            tool: call.name,
            arguments: call.arguments,
          ),
        );
      }
    } catch (e) {
      Log.error('OpenAICompatible connection error: $e');
      yield ChatResponse(
        type: ChatResponseType.error,
        content: _handleChatError(e),
      );
      return;
    } finally {
      _timeoutTimer?.cancel();
    }

    yield const ChatResponse(type: ChatResponseType.done);
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
    List<ToolDefinition>? tools,
    String? previousResponseId,
    bool continueGeneration = false,
  }) async* {
    _cancelToken = CancelToken();
    final toolAdapter = OllamaToolAdapter();

    final body = {
      'model': modelId,
      'messages': messages.map(_messageToApiMap).toList(),
      'stream': true,
      'options': {
        'temperature': params.temperature,
        'top_p': params.topP,
        'num_predict': params.maxTokens,
      },
    };

    if (tools != null && tools.isNotEmpty) {
      final toolsPayload = toolAdapter.buildToolDefinitionPayload(tools);
      if (toolsPayload.containsKey('tools')) {
        body['tools'] = toolsPayload['tools'];
      }
    }

    try {
      final response = await _dio.post<ResponseBody>(
        server.chatEndpoint,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/json',
            ...buildServerAuthHeaders(server),
          },
        ),
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
              toolAdapter.consumeDynamicChunk(json);
              final message = json['message'];
              if (message != null && message is Map<String, dynamic>) {
                final content = message['content'] as String?;
                final thinking = message['thinking'] as String?;

                if (thinking != null && thinking.isNotEmpty) {
                  yield ChatResponse(
                    type: ChatResponseType.reasoning,
                    reasoningContent: thinking,
                  );
                }
                if (content != null && content.isNotEmpty) {
                  yield ChatResponse(
                    type: ChatResponseType.message,
                    content: content,
                  );
                }
              }
              if (json['done'] == true) {
                for (final call in toolAdapter.takeCompletedCalls()) {
                  yield ChatResponse(
                    type: ChatResponseType.toolCall,
                    toolCall: ToolCallData(
                      tool: call.name,
                      arguments: call.arguments,
                    ),
                  );
                }
                yield const ChatResponse(type: ChatResponseType.done);
                return;
              }
            } catch (e) {
              Log.error('Ollama chunk parsing error: $e');
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
      return;
    }
    yield const ChatResponse(type: ChatResponseType.done);
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
    List<ToolDefinition>? tools,
    String? previousResponseId,
    bool continueGeneration = false,
  }) async* {
    _cancelToken = CancelToken();
    final toolAdapter = OpenRouterToolAdapter();

    final body = {
      'model': modelId,
      'messages': messages.map(_messageToApiMap).toList(),
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_tokens': params.maxTokens,
      'stream': true,
    };

    if (tools != null && tools.isNotEmpty) {
      final toolsPayload = toolAdapter.buildToolDefinitionPayload(tools);
      if (toolsPayload.containsKey('tools')) {
        body['tools'] = toolsPayload['tools'];
      }
    }

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
            ...buildServerAuthHeaders(server),
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

      try {
        await for (final chunk in stream) {
          // Check if timeout was triggered
          if (timeoutTriggered && lastContentReceived == null) {
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
              for (final call in toolAdapter.takeCompletedCalls()) {
                yield ChatResponse(
                  type: ChatResponseType.toolCall,
                  toolCall: ToolCallData(
                    tool: call.name,
                    arguments: call.arguments,
                  ),
                );
              }
              yield const ChatResponse(type: ChatResponseType.done);
              return;
            }
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              toolAdapter.consumeDynamicChunk(json);

              // Check for errors in the response
              if (json['error'] != null) {
                _timeoutTimer?.cancel();
                final errorContent = _formatApiErrorContent(json['error']);
                Log.error('OpenRouter mid-stream error: $errorContent');
                yield ChatResponse(
                  type: ChatResponseType.error,
                  content: errorContent,
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
      } finally {
        _timeoutTimer?.cancel();
      }

      // Flush any tool calls accumulated without a [DONE] marker (e.g.
      // connection drop or server crash before sending [DONE]).
      for (final call in toolAdapter.takeCompletedCalls()) {
        yield ChatResponse(
          type: ChatResponseType.toolCall,
          toolCall: ToolCallData(
            tool: call.name,
            arguments: call.arguments,
          ),
        );
      }
    } catch (e) {
      Log.error('OpenRouter connection error: $e');
      yield ChatResponse(
        type: ChatResponseType.error,
        content: _handleChatError(e),
      );
      return;
    } finally {
      _timeoutTimer?.cancel();
    }

    yield const ChatResponse(type: ChatResponseType.done);
    Log.debug('OpenRouter: Stream ended');
  }

  @override
  void cancelStream() {
    _timeoutTimer?.cancel();
    _cancelToken?.cancel('User cancelled');
  }
}

String _formatApiErrorContent(dynamic error) {
  if (error is Map<String, dynamic>) {
    final parsed = ChatApiError.fromErrorMap(error);
    if (parsed != null) return parsed.encode();
  } else if (error is Map) {
    final parsed = ChatApiError.fromErrorMap(
      Map<String, dynamic>.from(error),
    );
    if (parsed != null) return parsed.encode();
  }
  return error.toString();
}

String _handleChatError(dynamic e) {
  if (e is DioException) {
    if (e.response != null) {
      final parsed = ChatApiError.fromResponseBody(e.response!.data);
      if (parsed != null) return parsed.encode();

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

Map<String, dynamic> _messageToApiMap(Message m) {
  final map = <String, dynamic>{
    'role': _roleToString(m.role),
    'content': m.content,
  };
  if (m.role == MessageRole.tool && m.toolCallId != null) {
    map['tool_call_id'] = m.toolCallId;
  }
  if (m.role == MessageRole.assistant &&
      m.toolCalls != null &&
      m.toolCalls!.isNotEmpty) {
    map['tool_calls'] = m.toolCalls!.map((tc) {
      return {
        'id': tc.id,
        'type': 'function',
        'function': {
          'name': tc.toolName,
          'arguments': jsonEncode(tc.arguments),
        },
      };
    }).toList();
  }
  return map;
}

/// Returns the streaming-parsing adapter for a server type.
///
/// OpenAI-compatible and Ollama servers use adapter-based tool call parsing
/// from streaming chunks. LM Studio and on-device servers collect tool calls
/// directly from [ChatResponseType.toolCall] events emitted during streaming
/// and feed them to the loop via [ToolExecutionLoop.run]'s [preParsedCalls].
ToolTransportAdapter createAdapterForServerType(ServerType type) => switch (type) {
  ServerType.openAICompatible => OpenAiToolAdapter(),
  ServerType.openRouter => OpenRouterToolAdapter(),
  ServerType.lmStudio => OpenAiToolAdapter(),
  ServerType.onDevice => OpenAiToolAdapter(),
  ServerType.ollama => OllamaToolAdapter(),
};
