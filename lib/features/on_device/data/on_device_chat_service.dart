import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../../core/utils/bpe_decoder.dart';
import '../../chat/data/chat_service.dart';
import '../../chat/data/models/chat_parameters.dart';
import '../../chat/data/models/mcp_integration.dart';
import '../../chat/data/models/message.dart' hide ToolCallData;
import '../../chat/data/tools/tool_definition.dart';
import '../../servers/data/models/server.dart';
import 'on_device_gemma_service.dart';

class OnDeviceChatService implements ChatService {
  OnDeviceChatService(this._gemmaService);

  final OnDeviceInferenceService _gemmaService;
  final Set<_InferenceRun> _activeRuns = <_InferenceRun>{};
  bool _isDisposed = false;

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    List<ToolDefinition>? tools,
    bool continueGeneration = false,
  }) {
    late final _InferenceRun run;
    final controller = StreamController<ChatResponse>();
    run = _InferenceRun(controller);
    controller.onCancel = () => _cancelRun(run, notifyListener: false);

    if (_isDisposed) {
      scheduleMicrotask(() async {
        controller.add(
          const ChatResponse(
            type: ChatResponseType.error,
            content: 'On-device chat service has been disposed',
          ),
        );
        controller.add(const ChatResponse(type: ChatResponseType.done));
        await controller.close();
      });
      return controller.stream;
    }

    _activeRuns.add(run);
    unawaited(_startInference(run, modelId, messages, params));
    return controller.stream;
  }

  Future<void> _startInference(
    _InferenceRun run,
    String modelId,
    List<Message> messages,
    ChatParameters params,
  ) async {
    try {
      final systemInstruction = params.systemPrompt?.isNotEmpty == true
          ? params.systemPrompt
          : null;
      final session = await _gemmaService.createChat(
        systemInstruction: systemInstruction,
        tools: const [],
      );
      run.session = session;

      if (run.isCancelled) {
        await _closeSession(run, stopGeneration: false);
        return;
      }

      for (final message in _convertMessages(messages)) {
        if (run.isCancelled) {
          await _closeSession(run, stopGeneration: false);
          return;
        }
        await session.addQueryChunk(message);
      }

      if (run.isCancelled) {
        await _closeSession(run, stopGeneration: false);
        return;
      }

      final isBpeModel =
          modelId.toLowerCase().contains('qwen') ||
          modelId.toLowerCase().contains('deepseek');
      run.textDecoder = isBpeModel ? BpeDecoder() : null;
      run.reasoningDecoder = isBpeModel ? BpeDecoder() : null;
      run.generationStarted = true;

      final completer = Completer<void>();
      run.streamCompleter = completer;
      run.subscription = session.generateChatResponseAsync().listen(
        (response) => _handleResponse(run, response),
        onDone: () async {
          run.subscription = null;
          await _finishSuccessfully(run);
        },
        onError: (Object error, StackTrace stackTrace) async {
          run.subscription = null;
          Log.error('OnDevice stream error: $error');
          await _finishWithError(run, 'Inference error: $error');
        },
        cancelOnError: true,
      );
      await completer.future;
    } catch (error, stackTrace) {
      if (run.isCancelled) {
        await _closeSession(run, stopGeneration: run.generationStarted);
        return;
      }
      Log.error('OnDevice inference error: $error\n$stackTrace');
      await _finishWithError(run, 'Inference error: $error');
    }
  }

  void _handleResponse(_InferenceRun run, gemma.ModelResponse response) {
    if (run.isCancelled || run.controller.isClosed) return;

    try {
      if (response is gemma.TextResponse && response.token.isNotEmpty) {
        final content =
            run.textDecoder?.decodeChunk(response.token) ?? response.token;
        if (content.isNotEmpty) {
          run.controller.add(
            ChatResponse(type: ChatResponseType.message, content: content),
          );
        }
      } else if (response is gemma.FunctionCallResponse) {
        run.controller.add(
          ChatResponse(
            type: ChatResponseType.toolCall,
            toolCall: ToolCallData(
              tool: response.name,
              arguments: response.args,
            ),
          ),
        );
      } else if (response is gemma.ThinkingResponse &&
          response.content.isNotEmpty) {
        final content =
            run.reasoningDecoder?.decodeChunk(response.content) ??
            response.content;
        if (content.isNotEmpty) {
          run.controller.add(
            ChatResponse(
              type: ChatResponseType.reasoning,
              reasoningContent: content,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      Log.error('OnDevice stream handling error: $error\n$stackTrace');
      unawaited(
        _finishWithError(run, 'Inference error: $error', abortGeneration: true),
      );
    }
  }

  Future<void> _finishSuccessfully(_InferenceRun run) async {
    if (!run.beginFinishing()) return;

    if (!run.isCancelled && !run.controller.isClosed) {
      try {
        final finalToken = run.textDecoder?.flush() ?? '';
        final finalReasoning = run.reasoningDecoder?.flush() ?? '';
        if (finalToken.isNotEmpty) {
          run.controller.add(
            ChatResponse(type: ChatResponseType.message, content: finalToken),
          );
        }
        if (finalReasoning.isNotEmpty) {
          run.controller.add(
            ChatResponse(
              type: ChatResponseType.reasoning,
              reasoningContent: finalReasoning,
            ),
          );
        }
      } catch (error) {
        Log.error('Error flushing BPE decoders: $error');
      }
    }

    await _closeSession(run, stopGeneration: false);
    await _closeController(run, notifyListener: !run.isCancelled);
    _activeRuns.remove(run);
    _completeRunFuture(run);
  }

  Future<void> _finishWithError(
    _InferenceRun run,
    String message, {
    bool abortGeneration = false,
  }) async {
    if (!run.beginFinishing()) return;

    if (abortGeneration) {
      final session = run.session;
      if (session != null && run.generationStarted) {
        try {
          await session.stopGeneration();
        } catch (error) {
          Log.warning('Error stopping failed on-device generation: $error');
        }
      }
      final subscription = run.subscription;
      run.subscription = null;
      await subscription?.cancel();
    }
    await _closeSession(run, stopGeneration: false);
    if (!run.isCancelled && !run.controller.isClosed) {
      run.controller.add(
        ChatResponse(type: ChatResponseType.error, content: message),
      );
    }
    await _closeController(run, notifyListener: !run.isCancelled);
    _activeRuns.remove(run);
    _completeRunFuture(run);
  }

  Future<void> _cancelRun(
    _InferenceRun run, {
    required bool notifyListener,
  }) async {
    // StreamController.onCancel may re-enter while cleanup is closing the
    // controller. Waiting on that same cleanup future would deadlock the
    // controller close, so repeated cancellation is deliberately a no-op.
    if (run.isCancelled) return;
    run.isCancelled = true;
    if (!run.beginFinishing()) {
      return;
    }

    final cleanup = () async {
      final subscription = run.subscription;
      run.subscription = null;
      if (run.generationStarted) {
        final session = run.session;
        if (session != null) {
          try {
            await session.stopGeneration();
          } catch (error) {
            Log.warning('Error stopping on-device generation: $error');
          }
        }
      }
      await subscription?.cancel();
      await _closeSession(run, stopGeneration: false);
      await _closeController(run, notifyListener: notifyListener);
      _activeRuns.remove(run);
      _completeRunFuture(run);
    }();
    await cleanup;
  }

  void _completeRunFuture(_InferenceRun run) {
    final completer = run.streamCompleter;
    run.streamCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _closeSession(
    _InferenceRun run, {
    required bool stopGeneration,
  }) async {
    final session = run.session;
    run.session = null;
    if (session == null) return;

    if (stopGeneration) {
      try {
        await session.stopGeneration();
      } catch (error) {
        Log.warning('Error stopping on-device generation: $error');
      }
    }
    try {
      await session.close();
    } catch (error) {
      Log.warning('Error closing on-device chat session: $error');
    }
  }

  Future<void> _closeController(
    _InferenceRun run, {
    required bool notifyListener,
  }) async {
    if (run.controller.isClosed) return;
    if (notifyListener) {
      run.controller.add(const ChatResponse(type: ChatResponseType.done));
    }
    await run.controller.close();
  }

  List<gemma.Message> _convertMessages(List<Message> messages) {
    var list = messages;
    if (list.isNotEmpty &&
        list.last.role == MessageRole.assistant &&
        list.last.content.isEmpty) {
      list = list.sublist(0, list.length - 1);
    }
    return list
        .where(
          (message) =>
              message.role == MessageRole.user ||
              message.role == MessageRole.assistant ||
              message.role == MessageRole.system,
        )
        .map(
          (message) => gemma.Message.text(
            text: message.content,
            isUser: message.role == MessageRole.user,
          ),
        )
        .toList();
  }

  @override
  void cancelStream() {
    for (final run in _activeRuns.toList()) {
      unawaited(_cancelRun(run, notifyListener: true));
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    cancelStream();
  }
}

class _InferenceRun {
  _InferenceRun(this.controller);

  final StreamController<ChatResponse> controller;
  StreamSubscription<gemma.ModelResponse>? subscription;
  OnDeviceInferenceSession? session;
  Completer<void>? streamCompleter;
  BpeDecoder? textDecoder;
  BpeDecoder? reasoningDecoder;
  bool generationStarted = false;
  bool isCancelled = false;
  bool _isFinishing = false;

  bool beginFinishing() {
    if (_isFinishing) return false;
    _isFinishing = true;
    return true;
  }
}
