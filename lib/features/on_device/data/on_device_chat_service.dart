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
  _RetainedConversation? _retainedConversation;
  int _nextRunSequence = 0;
  int _latestRunSequence = 0;
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
    final sequence = ++_nextRunSequence;
    _latestRunSequence = sequence;
    run = _InferenceRun(controller, sequence);
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
      final input = _prepareInput(modelId, messages, params);
      if (input == null) {
        await _finishWithError(run, 'On-device chat requires a user message.');
        return;
      }
      run.input = input;

      final retained = _retainedConversation;

      late final OnDeviceInferenceSession session;
      late final bool reusedSession;
      if (retained != null && retained.canContinueWith(input, modelId)) {
        _retainedConversation = null;
        session = retained.session;
        reusedSession = true;
      } else {
        if (retained != null && !input.isAuxiliary) {
          _retainedConversation = null;
          await retained.session.close();
        }
        session = await _gemmaService.createChat(
          systemInstruction: input.baseSystemInstruction,
          tools: const [],
        );
        reusedSession = false;
      }
      run.session = session;

      if (run.isCancelled) {
        await _closeSession(run, stopGeneration: false);
        return;
      }

      await session.addQueryChunk(
        input.toGemmaMessage(includeHistory: !reusedSession),
      );

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
          run.generatedContent.write(content);
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
          run.generatedContent.write(finalToken);
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

    await _retainOrCloseSession(run);
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

  Future<void> _retainOrCloseSession(_InferenceRun run) async {
    final session = run.session;
    run.session = null;
    final input = run.input;
    if (session == null) return;

    if (run.isCancelled ||
        input == null ||
        input.isAuxiliary ||
        run.sequence != _latestRunSequence ||
        run.generatedContent.isEmpty) {
      await session.close();
      return;
    }

    final previous = _retainedConversation;
    _retainedConversation = _RetainedConversation(
      session: session,
      conversationId: input.conversationId,
      modelId: input.modelId,
      baseSystemInstruction: input.baseSystemInstruction,
      timeline: input.completedTimeline(run.generatedContent.toString()),
    );
    if (previous != null && !identical(previous.session, session)) {
      await previous.session.close();
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

  _PreparedInput? _prepareInput(
    String modelId,
    List<Message> messages,
    ChatParameters params,
  ) {
    final relevant = messages
        .where(
          (message) =>
              message.role == MessageRole.user ||
              message.role == MessageRole.assistant ||
              message.role == MessageRole.system,
        )
        .toList(growable: true);

    Message? pendingAssistant;
    if (relevant.isNotEmpty &&
        relevant.last.role == MessageRole.assistant &&
        relevant.last.content.isEmpty) {
      pendingAssistant = relevant.removeLast();
    }

    final systemMessages = relevant
        .where(
          (message) =>
              message.role == MessageRole.system &&
              message.content.trim().isNotEmpty,
        )
        .map((message) => message.content.trim())
        .toList(growable: false);
    final timeline = relevant
        .where(
          (message) =>
              message.role == MessageRole.user ||
              message.role == MessageRole.assistant,
        )
        .map(_MessageSnapshot.fromMessage)
        .toList(growable: false);
    if (timeline.isEmpty) return null;

    final currentMessage = timeline.last;
    final history = timeline.sublist(0, timeline.length - 1);
    final isAuxiliary = const {
      'title-generation-prompt',
      'smart-reply-prompt',
      'ai-user-response-prompt',
    }.contains(currentMessage.id);
    final messageSystemInstruction = systemMessages.isEmpty
        ? null
        : systemMessages.join('\n\n');
    final baseSystemInstruction = isAuxiliary
        ? _nonEmpty(params.systemPrompt) ?? messageSystemInstruction
        : messageSystemInstruction ?? _nonEmpty(params.systemPrompt);
    if (currentMessage.role != MessageRole.user) {
      Log.warning(
        'Rebuilding an on-device session for assistant continuation; '
        'history will be supplied as a transcript.',
      );
    }

    return _PreparedInput(
      conversationId: currentMessage.conversationId,
      modelId: modelId,
      baseSystemInstruction: baseSystemInstruction,
      history: history,
      currentMessage: currentMessage,
      pendingAssistantId: pendingAssistant?.id,
      isAuxiliary: isAuxiliary,
    );
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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
    final retained = _retainedConversation;
    _retainedConversation = null;
    if (retained != null) {
      unawaited(retained.session.close());
    }
  }
}

class _InferenceRun {
  _InferenceRun(this.controller, this.sequence);

  final StreamController<ChatResponse> controller;
  final int sequence;
  StreamSubscription<gemma.ModelResponse>? subscription;
  OnDeviceInferenceSession? session;
  Completer<void>? streamCompleter;
  BpeDecoder? textDecoder;
  BpeDecoder? reasoningDecoder;
  _PreparedInput? input;
  final StringBuffer generatedContent = StringBuffer();
  bool generationStarted = false;
  bool isCancelled = false;
  bool _isFinishing = false;

  bool beginFinishing() {
    if (_isFinishing) return false;
    _isFinishing = true;
    return true;
  }
}

class _PreparedInput {
  const _PreparedInput({
    required this.conversationId,
    required this.modelId,
    required this.baseSystemInstruction,
    required this.history,
    required this.currentMessage,
    required this.pendingAssistantId,
    required this.isAuxiliary,
  });

  final String conversationId;
  final String modelId;
  final String? baseSystemInstruction;
  final List<_MessageSnapshot> history;
  final _MessageSnapshot currentMessage;
  final String? pendingAssistantId;
  final bool isAuxiliary;

  gemma.Message toGemmaMessage({required bool includeHistory}) {
    if (!includeHistory || history.isEmpty) {
      return currentMessage.toGemmaMessage();
    }
    final transcript = history
        .map(
          (message) =>
              '${message.role == MessageRole.user ? 'User' : 'Assistant'}: '
              '${message.content}',
        )
        .join('\n\n');
    final currentLabel = currentMessage.role == MessageRole.user
        ? 'Current user message'
        : 'Assistant response to continue';
    return gemma.Message.text(
      text:
          'Earlier conversation transcript (context only):\n\n$transcript\n\n'
          '$currentLabel:\n${currentMessage.content}',
      isUser: currentMessage.role == MessageRole.user,
    );
  }

  List<_MessageSnapshot> completedTimeline(String response) {
    if (currentMessage.role == MessageRole.assistant) {
      return [
        ...history,
        currentMessage.copyWith(content: '${currentMessage.content}$response'),
      ];
    }
    return [
      ...history,
      currentMessage,
      _MessageSnapshot(
        id: pendingAssistantId ?? 'generated-${currentMessage.id}',
        conversationId: conversationId,
        role: MessageRole.assistant,
        content: response,
      ),
    ];
  }
}

class _RetainedConversation {
  const _RetainedConversation({
    required this.session,
    required this.conversationId,
    required this.modelId,
    required this.baseSystemInstruction,
    required this.timeline,
  });

  final OnDeviceInferenceSession session;
  final String conversationId;
  final String modelId;
  final String? baseSystemInstruction;
  final List<_MessageSnapshot> timeline;

  bool canContinueWith(_PreparedInput input, String requestedModelId) {
    return input.currentMessage.role == MessageRole.user &&
        conversationId == input.conversationId &&
        modelId == requestedModelId &&
        baseSystemInstruction == input.baseSystemInstruction &&
        _listEquals(timeline, input.history);
  }

  static bool _listEquals(
    List<_MessageSnapshot> first,
    List<_MessageSnapshot> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

class _MessageSnapshot {
  const _MessageSnapshot({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
  });

  factory _MessageSnapshot.fromMessage(Message message) => _MessageSnapshot(
    id: message.id,
    conversationId: message.conversationId,
    role: message.role,
    content: message.content,
  );

  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;

  gemma.Message toGemmaMessage() =>
      gemma.Message.text(text: content, isUser: role == MessageRole.user);

  _MessageSnapshot copyWith({String? content}) => _MessageSnapshot(
    id: id,
    conversationId: conversationId,
    role: role,
    content: content ?? this.content,
  );

  @override
  bool operator ==(Object other) {
    return other is _MessageSnapshot &&
        id == other.id &&
        conversationId == other.conversationId &&
        role == other.role &&
        content == other.content;
  }

  @override
  int get hashCode => Object.hash(id, conversationId, role, content);
}
