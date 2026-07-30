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
import '../utils/image_upload_utils.dart';
import 'tools/adapters/openai_tool_adapter.dart';
import 'tools/adapters/lm_studio_tool_adapter.dart';
import 'tools/adapters/openrouter_tool_adapter.dart';
import 'tools/adapters/ollama_tool_adapter.dart';
import 'chat_api_error.dart';
import 'chat_error_formatter.dart';

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
    bool imageCompressionEnabled = true,
    ImageCompressionLevel imageCompressionLevel = ImageCompressionLevel.medium,
  }) {
    switch (type) {
      case ServerType.lmStudio:
        return LMStudioChatService(
          dio,
          imageCompressionEnabled: imageCompressionEnabled,
          imageCompressionLevel: imageCompressionLevel,
        );
      case ServerType.openAICompatible:
        return OpenAICompatibleChatService(dio);
      case ServerType.ollama:
      case ServerType.ollamaCloud:
        return OllamaChatService(
          dio,
          imageCompressionEnabled: imageCompressionEnabled,
          imageCompressionLevel: imageCompressionLevel,
        );
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
  final bool imageCompressionEnabled;
  final ImageCompressionLevel imageCompressionLevel;
  CancelToken? _cancelToken;

  LMStudioChatService(
    this._dio, {
    this.imageCompressionEnabled = true,
    this.imageCompressionLevel = ImageCompressionLevel.medium,
  });

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
    final lmStudioToolAdapter = LmStudioToolAdapter();

    final apiMessages = <Map<String, dynamic>>[];
    for (final m in messages) {
      apiMessages.add(await _messageToApiMapWithImages(m));
    }

    // Strip trailing empty assistant messages to avoid "prefill incompatible
    // with enable_thinking" errors from servers running thinking models.
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
      // Keep the assistant prefill for continuation; ensure content is a
      // string (the model continues from exactly where this cuts off, and
      // the response contains only the newly generated continuation text).
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
      // Requests a final chunk with an empty `choices` array and a
      // `usage` object (prompt_tokens/completion_tokens) so tokens/sec and
      // token counts can still be computed after switching off the native
      // Responses-style endpoint's richer `chat.end` stats.
      'stream_options': {'include_usage': true},
    };

    if (params.topK != null) body['top_k'] = params.topK;
    if (params.minP != null) body['min_p'] = params.minP;
    if (params.repeatPenalty != null) {
      body['repeat_penalty'] = params.repeatPenalty;
    }
    _applyReasoningControl(body, params);

    if (integrations != null && integrations.isNotEmpty) {
      body['integrations'] = integrations.map((i) => i.toJson()).toList();
    }

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
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data == '[DONE]') {
            for (final call in toolAdapter.takeCompletedCalls()) {
              yield ChatResponse(
                type: ChatResponseType.toolCall,
                toolCall: ToolCallData(
                  tool: call.name,
                  arguments: call.arguments,
                ),
              );
            }
            for (final call in lmStudioToolAdapter.takeServerExecutedCalls()) {
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
          if (data.isEmpty) continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            toolAdapter.consumeDynamicChunk(json);

            final eventType = json['type'] as String?;
            if (eventType != null) {
              lmStudioToolAdapter.consumeEvent(eventType, json);
              for (final call in lmStudioToolAdapter.takeServerExecutedCalls()) {
                yield ChatResponse(
                  type: ChatResponseType.toolCall,
                  toolCall: ToolCallData(
                    tool: call.name,
                    arguments: call.arguments,
                  ),
                );
              }
            }

            if (json['error'] != null) {
              yield ChatResponse(
                type: ChatResponseType.error,
                content: _formatApiErrorContent(json['error']),
              );
              return;
            }

            final usage = json['usage'] as Map<String, dynamic>?;
            if (usage != null) {
              yield ChatResponse(
                type: ChatResponseType.done,
                stats: ChatStats(
                  inputTokens: usage['prompt_tokens'] as int? ?? 0,
                  totalOutputTokens: usage['completion_tokens'] as int? ?? 0,
                ),
              );
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
          } catch (e) {
            Log.error('LMStudio chat parsing error: $e');
          }
        }
      }

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
      Log.error('LMStudio connection error: $e');
      yield ChatResponse(
        type: ChatResponseType.error,
        content: _handleChatError(e),
      );
      return;
    }
    yield const ChatResponse(type: ChatResponseType.done);
  }

  Future<Map<String, dynamic>> _messageToApiMapWithImages(Message m) async {
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

    final imageParts = <Map<String, dynamic>>[];
    if (hasAttachments) {
      for (final path in m.attachmentPaths!) {
        if (!AttachmentHelpers.isImagePath(path)) continue;
        try {
          final file = File(path);
          if (!await file.exists()) continue;
          final fileBytes = await ImageUploadUtils.prepareImageBytes(
            file,
            enabled: imageCompressionEnabled,
            level: imageCompressionLevel,
          );
          final base64Image = await Isolate.run(() {
            try {
              return base64Encode(fileBytes);
            } catch (_) {
              return null;
            }
          });

          if (base64Image != null) {
            imageParts.add({
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,$base64Image'},
            });
          }
        } catch (e) {
          Log.error('Failed to read attachment for LMStudio format: $e');
        }
      }
    }

    dynamic content;
    if (imageParts.isEmpty) {
      content = textContent;
    } else {
      content = <Map<String, dynamic>>[
        if (textContent.trim().isNotEmpty)
          {'type': 'text', 'text': textContent},
        ...imageParts,
      ];
    }

    final map = <String, dynamic>{
      'role': _roleToString(m.role),
      'content': content,
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

    final body = <String, dynamic>{
      'model': modelId,
      'messages': apiMessages,
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_tokens': params.maxTokens,
      'stream': true,
    };
    _applyReasoningControl(body, params);

    if (integrations != null && integrations.isNotEmpty) {
      body['integrations'] = integrations.map((i) => i.toJson()).toList();
    }

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

String _formatOllamaErrorContent(dynamic error) {
  if (error is String) {
    return ChatErrorFormatter.formatBody(jsonEncode({'error': error}));
  }
  if (error is Map) {
    return ChatErrorFormatter.formatBody(jsonEncode({'error': error}));
  }
  return ChatApiError(message: error.toString()).encode();
}

Future<String> _handleOllamaChatError(DioException e) async {
  return ChatErrorFormatter.formatDioException(
    e,
    readBody: (data) async {
      if (data is ResponseBody) {
        return data.stream.cast<List<int>>().transform(utf8.decoder).join();
      }
      if (data is String) return data;
      return '';
    },
  );
}

String? _extractOllamaErrorMessage(dynamic data) {
  if (data == null) return null;
  final raw = data is String ? data : jsonEncode(data);
  if (raw.trim().isEmpty) return null;
  return ChatErrorFormatter.formatBody(raw);
}

class OllamaChatService implements ChatService {
  final Dio _dio;
  final bool imageCompressionEnabled;
  final ImageCompressionLevel imageCompressionLevel;
  CancelToken? _cancelToken;

  OllamaChatService(
    this._dio, {
    this.imageCompressionEnabled = true,
    this.imageCompressionLevel = ImageCompressionLevel.medium,
  });

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

    final apiMessages = <Map<String, dynamic>>[];
    for (final message in messages) {
      apiMessages.add(await _messageToOllamaMapWithImages(message));
    }

    final body = <String, dynamic>{
      'model': modelId,
      'messages': apiMessages,
      'stream': true,
      'options': {
        'temperature': params.temperature,
        'top_p': params.topP,
        'num_predict': params.maxTokens,
      },
    };
    _applyReasoningControl(body, params);

    if (tools != null && tools.isNotEmpty) {
      final toolsPayload = toolAdapter.buildToolDefinitionPayload(tools);
      if (toolsPayload.containsKey('tools')) {
        body['tools'] = toolsPayload['tools'];
      }
    }

    final imageCount = apiMessages.fold<int>(0, (count, message) {
      final images = message['images'];
      return count + (images is List ? images.length : 0);
    });
    Log.debug(
      'Ollama request: endpoint=${server.chatEndpoint}, model=$modelId, '
      'messages=${apiMessages.length}, images=$imageCount, '
      'tools=${tools?.length ?? 0}',
    );

    try {
      final response = await _dio.post<ResponseBody>(
        server.chatEndpoint,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          // Ollama returns useful JSON error bodies for 4xx responses. Keep
          // the stream available so the actual error reaches the UI.
          validateStatus: (status) => status != null,
          headers: {
            'Content-Type': 'application/json',
            ...buildServerAuthHeaders(server),
          },
        ),
        cancelToken: _cancelToken,
      );

      final responseBody = response.data!;
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        final rawError = await responseBody.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        final parsedError = _extractOllamaErrorMessage(rawError);
        Log.error('Ollama HTTP $statusCode: ${parsedError ?? rawError}');
        yield ChatResponse(
          type: ChatResponseType.error,
          content: parsedError ??
              (rawError.trim().isNotEmpty
                  ? rawError.trim()
                  : 'Ollama request failed (HTTP $statusCode).'),
        );
        return;
      }

      final stream = responseBody.stream.cast<List<int>>().transform(
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

              // Ollama surfaces mid-stream errors as a top-level `error`
              // field, often alongside HTTP 200. Surface them so the UI
              // shows something more specific than the generic
              // "unknown error" fallback when — for instance — the
              // selected model doesn't actually support images.
              final errorField = json['error'];
              if (errorField != null) {
                yield ChatResponse(
                  type: ChatResponseType.error,
                  content: _formatOllamaErrorContent(errorField),
                );
                return;
              }

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
      final content = e is DioException
          ? await _handleOllamaChatError(e)
          : _handleChatError(e);
      yield ChatResponse(type: ChatResponseType.error, content: content);
      return;
    }
    yield const ChatResponse(type: ChatResponseType.done);
  }

  Future<Map<String, dynamic>> _messageToOllamaMapWithImages(Message m) async {
    var textContent = m.content;
    final images = <String>[];

    for (final path in m.attachmentPaths ?? const <String>[]) {
      if (AttachmentHelpers.isTextPath(path)) {
        final text = await AttachmentHelpers.readTextFile(path);
        if (text != null) {
          textContent = AttachmentHelpers.appendTextAttachment(
            textContent,
            AttachmentHelpers.fileNameOf(path),
            text,
          );
        }
        continue;
      }

      if (!AttachmentHelpers.isImagePath(path)) continue;

      try {
        final file = File(path);
        if (!await file.exists()) continue;

        final fileBytes = await ImageUploadUtils.prepareImageBytes(
          file,
          enabled: imageCompressionEnabled,
          level: imageCompressionLevel,
        );
        final base64Image = await Isolate.run(() {
          try {
            return base64Encode(fileBytes);
          } catch (_) {
            return null;
          }
        });

        if (base64Image != null) images.add(base64Image);
      } catch (e) {
        Log.error('Failed to read attachment for Ollama format: $e');
      }
    }

    final map = <String, dynamic>{
      'role': _roleToString(m.role),
      'content': textContent,
    };
    if (images.isNotEmpty) map['images'] = images;

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

    final body = <String, dynamic>{
      'model': modelId,
      'messages': messages.map(_messageToApiMap).toList(),
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_tokens': params.maxTokens,
      'stream': true,
    };
    _applyReasoningControl(body, params);

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

/// Applies the Think toggle to a request body. Different local/hosted
/// backends expose "disable reasoning for this hybrid model" a handful of
/// different ways (a `reasoning` object, a top-level `reasoning_effort`,
/// llama.cpp's `enable_thinking`, Ollama's `think`) — send all of them so
/// whichever one the connected server actually understands takes effect.
/// No-op when [ChatParameters.reasoningEnabled] is null, i.e. the active
/// model doesn't support reasoning.
void _applyReasoningControl(Map<String, dynamic> body, ChatParameters params) {
  if (params.reasoningEnabled == false) {
    body['reasoning'] = {
      'enabled': false,
      'type': 'disabled',
      'effort': 'none',
    };
    body['reasoning_effort'] = 'none';
    body['think'] = false;
    body['enable_thinking'] = false;
  } else if (params.reasoningEnabled == true) {
    final effort = params.reasoningEffort.apiValue;
    body['reasoning'] = {'effort': effort};
    body['reasoning_effort'] = effort;
  }
}

String _formatApiErrorContent(dynamic error) {
  if (error is Map) {
    final map = Map<String, dynamic>.from(error);
    final parsed = ChatApiError.fromErrorMap(map);
    if (parsed != null) {
      // Use the unified formatter so the bubble benefits from humanising
      // and structured metadata even when the body is already shaped like
      // an OpenAI error.
      try {
        return ChatErrorFormatter.formatBody(jsonEncode(map));
      } catch (_) {
        return parsed.encode();
      }
    }
  }
  return ChatApiError(message: error.toString()).encode();
}

String _handleChatError(dynamic e) {
  if (e is DioException) {
    if (e.response != null) {
      final status = e.response!.statusCode;
      final data = e.response!.data;
      if (data is String && data.trim().isNotEmpty) {
        return ChatErrorFormatter.formatBody(data, statusCode: status);
      }
      final parsed = ChatApiError.fromResponseBody(data);
      if (parsed != null) {
        return parsed.copyWithCodeIfMissing(status?.toString()).encode();
      }
      // Let the unified formatter map known HTTP status codes.
      return ChatErrorFormatter.formatBody('', statusCode: status);
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ChatApiError(
          message: 'The model took too long to respond.',
          type: 'timeout',
        ).encode();
      case DioExceptionType.connectionError:
        return const ChatApiError(
          message:
              'Could not reach the AI server. Confirm it is running and the address in Settings is correct.',
          type: 'connection_error',
        ).encode();
      case DioExceptionType.cancel:
        return const ChatApiError(
          message: 'Request cancelled.',
          type: 'cancelled',
        ).encode();
      default:
        return ChatApiError(
          message: e.message ?? 'Connection error.',
          type: e.type.name,
        ).encode();
    }
  }
  return ChatApiError(message: e.toString()).encode();
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
  ServerType.ollamaCloud => OllamaToolAdapter(),
};
