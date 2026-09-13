import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../../core/utils/bpe_decoder.dart';
import '../../chat/data/chat_service.dart';
import '../../chat/data/models/chat_parameters.dart';
import '../../chat/data/models/mcp_integration.dart';
import '../../chat/data/models/message.dart' hide ToolCallData;
import '../../chat/data/tools/tool_definition.dart';
import '../../chat/utils/attachment_helpers.dart';
import '../../chat/utils/image_upload_utils.dart';
import '../../servers/data/models/server.dart';
import 'on_device_gemma_service.dart';

/// Synthetic message ids whose presence signals an auxiliary generation
/// (title, smart-reply, AI-suggested user message) rather than a real chat
/// turn. Auxiliary runs are isolated from any retained chat session so their
/// system prompts and context do not bleed into the user's primary
/// conversation. Keep this list in sync with the synthetic ids emitted by
/// `title_generation_service.dart` and `smart_reply_service.dart`.
const Set<String> _auxiliaryMessageIds = {
  'title-generation-prompt',
  'smart-reply-prompt',
  'ai-user-response-prompt',
};

/// How long an on-device chat session is retained after a successful turn
/// without further activity. Retained sessions keep their KV cache in memory;
/// this bounds the cost of background retention when a user abandons a
/// conversation mid-stream.
const Duration _defaultRetainedSessionTtl = Duration(minutes: 10);

class OnDeviceChatService implements ChatService {
  OnDeviceChatService(
    this._gemmaService, {
    Duration retainedSessionTtl = _defaultRetainedSessionTtl,
    this.imageCompressionEnabled = true,
    this.imageCompressionLevel = ImageCompressionLevel.medium,
    // The retained-session TTL is a separate constructor parameter (rather
    // than an initializing formal) so it can have a default value; the
    // lint suggestion doesn't apply when a default is involved.
    // ignore: prefer_initializing_formals
  }) : _retainedSessionTtl = retainedSessionTtl;

  final OnDeviceInferenceService _gemmaService;
  final Duration _retainedSessionTtl;
  final bool imageCompressionEnabled;
  final ImageCompressionLevel imageCompressionLevel;
  final Set<_InferenceRun> _activeRuns = <_InferenceRun>{};
  _RetainedConversation? _retainedConversation;
  Timer? _retainedExpirationTimer;
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
      final input = await _prepareInput(modelId, messages, params);
      if (run.isCancelled) {
        await _closeSession(run, stopGeneration: false);
        return;
      }
      if (input == null ||
          (input.currentMessage.content.trim().isEmpty && !input.hasImages)) {
        final lastMsg = messages.isNotEmpty ? messages.last : null;
        final hasImageAttachment =
            lastMsg?.attachmentPaths?.any(AttachmentHelpers.isImagePath) ??
            false;
        if (hasImageAttachment && !_gemmaService.currentModelSupportsVision) {
          await _finishWithError(
            run,
            'The active model does not support image attachments. '
            'Please select a vision-supported model like Gemma 4 or FastVLM.',
          );
          return;
        }
        await _finishWithError(run, 'On-device chat requires a user message.');
        return;
      }
      run.input = input;

      final retained = _retainedConversation;

      late final OnDeviceInferenceSession session;
      late final bool reusedSession;
      if (retained != null && retained.canContinueWith(input, modelId)) {
        _retainedConversation = null;
        _cancelRetainedExpiration();
        session = retained.session;
        reusedSession = true;
      } else {
        if (retained != null && !input.isAuxiliary) {
          _retainedConversation = null;
          _cancelRetainedExpiration();
          await retained.session.close();
        }
        final modelSupportsVision = _gemmaService.currentModelSupportsVision;
        session = await _gemmaService.createChat(
          systemInstruction: input.baseSystemInstruction,
          tools: const [],
          supportImage: modelSupportsVision && input.hasImages,
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
    _cancelRetainedExpiration();
    _retainedConversation = _RetainedConversation(
      session: session,
      conversationId: input.conversationId,
      modelId: input.modelId,
      baseSystemInstruction: input.baseSystemInstruction,
      timeline: input.completedTimeline(run.generatedContent.toString()),
      supportsImages:
          input.hasImages || _gemmaService.currentModelSupportsVision,
    );
    _armRetainedExpiration();
    if (previous != null && !identical(previous.session, session)) {
      await previous.session.close();
    }
  }

  void _armRetainedExpiration() {
    _retainedExpirationTimer?.cancel();
    _retainedExpirationTimer = Timer(_retainedSessionTtl, () {
      if (_isDisposed) return;
      final retained = _retainedConversation;
      _retainedConversation = null;
      _retainedExpirationTimer = null;
      if (retained != null) {
        unawaited(retained.session.close());
      }
    });
  }

  void _cancelRetainedExpiration() {
    _retainedExpirationTimer?.cancel();
    _retainedExpirationTimer = null;
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

  Future<_PreparedInput?> _prepareInput(
    String modelId,
    List<Message> messages,
    ChatParameters params,
  ) async {
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

    final systemMessages = <String>[];
    for (final message in relevant) {
      if (message.role == MessageRole.system) {
        var content = message.content.trim();
        final paths = message.attachmentPaths;
        if (paths != null && paths.isNotEmpty) {
          for (final path in paths) {
            if (AttachmentHelpers.isDocumentPath(path)) {
              final text = await AttachmentHelpers.readDocumentFile(path);
              if (text != null && text.trim().isNotEmpty) {
                content = AttachmentHelpers.appendTextAttachment(
                  content,
                  AttachmentHelpers.fileNameOf(path),
                  text,
                );
              }
            }
          }
        }
        if (content.isNotEmpty) {
          systemMessages.add(content);
        }
      }
    }

    final timelineMessages = relevant
        .where(
          (message) =>
              message.role == MessageRole.user ||
              message.role == MessageRole.assistant,
        )
        .toList(growable: false);

    final modelSupportsVision = _gemmaService.currentModelSupportsVision;
    final timeline = <_MessageSnapshot>[];
    for (final message in timelineMessages) {
      final snapshot = await _MessageSnapshot.fromMessage(
        message,
        supportsVision: modelSupportsVision,
        imageCompressionEnabled: imageCompressionEnabled,
        imageCompressionLevel: imageCompressionLevel,
      );
      timeline.add(snapshot);
    }
    if (timeline.isEmpty) return null;

    final currentMessage = timeline.last;
    final history = timeline.sublist(0, timeline.length - 1);
    final isAuxiliary = _auxiliaryMessageIds.contains(currentMessage.id);
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
    _cancelRetainedExpiration();
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

  bool get hasImages =>
      currentMessage.images.isNotEmpty ||
      history.any((message) => message.images.isNotEmpty);

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
    final fullText =
        'Earlier conversation transcript (context only):\n\n$transcript\n\n'
        '$currentLabel:\n${currentMessage.content}';

    final images = currentMessage.images.isNotEmpty
        ? currentMessage.images
        : history.reversed
              .expand((message) => message.images)
              .toList(growable: false)
              .reversed
              .toList(growable: false);

    if (images.isNotEmpty) {
      var text = fullText;
      if (text.trim().isEmpty) {
        text = 'Describe the image.';
      }
      return gemma.Message.withImages(
        text: text,
        imageBytes: images,
        isUser: currentMessage.role == MessageRole.user,
      );
    }

    return gemma.Message.text(
      text: fullText,
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
    required this.supportsImages,
  });

  final OnDeviceInferenceSession session;
  final String conversationId;
  final String modelId;
  final String? baseSystemInstruction;
  final List<_MessageSnapshot> timeline;
  final bool supportsImages;

  bool canContinueWith(_PreparedInput input, String requestedModelId) {
    if (input.hasImages && !supportsImages) {
      return false;
    }
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
    this.images = const [],
    this.attachmentPaths = const [],
  });

  static Future<_MessageSnapshot> fromMessage(
    Message message, {
    bool supportsVision = false,
    bool imageCompressionEnabled = true,
    ImageCompressionLevel imageCompressionLevel = ImageCompressionLevel.medium,
  }) async {
    var content = message.content;
    final images = <Uint8List>[];

    final paths = message.attachmentPaths ?? const <String>[];

    for (final path in paths) {
      if (AttachmentHelpers.isDocumentPath(path)) {
        final text = await AttachmentHelpers.readDocumentFile(path);
        if (text != null && text.trim().isNotEmpty) {
          content = AttachmentHelpers.appendTextAttachment(
            content,
            AttachmentHelpers.fileNameOf(path),
            text,
          );
        }
      } else if (supportsVision && AttachmentHelpers.isImagePath(path)) {
        final file = File(path);
        try {
          if (await file.exists()) {
            final bytes = await ImageUploadUtils.prepareImageBytes(
              file,
              enabled: imageCompressionEnabled,
              level: imageCompressionLevel,
            );
            images.add(bytes);
          }
        } catch (e) {
          Log.warning('Failed to prepare image bytes for $path: $e');
          try {
            if (await file.exists()) {
              images.add(await file.readAsBytes());
            }
          } catch (_) {}
        }
      }
    }

    return _MessageSnapshot(
      id: message.id,
      conversationId: message.conversationId,
      role: message.role,
      content: content,
      images: List.unmodifiable(images),
      attachmentPaths: List.unmodifiable(paths),
    );
  }

  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final List<Uint8List> images;
  final List<String> attachmentPaths;

  gemma.Message toGemmaMessage({String? promptOverride}) {
    var text = promptOverride ?? content;
    final isUser = role == MessageRole.user;
    if (images.isNotEmpty) {
      if (text.trim().isEmpty) {
        text = 'Describe the image.';
      }
      return gemma.Message.withImages(
        text: text,
        imageBytes: images,
        isUser: isUser,
      );
    }
    return gemma.Message.text(text: text, isUser: isUser);
  }

  _MessageSnapshot copyWith({
    String? content,
    List<Uint8List>? images,
    List<String>? attachmentPaths,
  }) => _MessageSnapshot(
    id: id,
    conversationId: conversationId,
    role: role,
    content: content ?? this.content,
    images: images ?? this.images,
    attachmentPaths: attachmentPaths ?? this.attachmentPaths,
  );

  @override
  bool operator ==(Object other) {
    return other is _MessageSnapshot &&
        id == other.id &&
        conversationId == other.conversationId &&
        role == other.role &&
        content == other.content &&
        _listEquals(attachmentPaths, other.attachmentPaths) &&
        images.length == other.images.length;
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    role,
    content,
    Object.hashAll(attachmentPaths),
    images.length,
  );

  static bool _listEquals(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }
}
