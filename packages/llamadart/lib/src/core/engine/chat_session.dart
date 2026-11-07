import 'dart:async';
import 'dart:convert';
import 'engine.dart';
import '../llama_logger.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/completion_chunk.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/content_part.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';

/// Convenience wrapper for multi-turn chat with automatic history management.
///
/// [ChatSession] wraps [LlamaEngine] and automatically manages conversation
/// history and context window limits. For stateless usage (like OpenAI's
/// Chat Completions API), use [LlamaEngine.create] directly.
///
/// Example:
/// ```dart
/// final engine = LlamaEngine(LlamaBackend());
/// await engine.loadModel('model.gguf');
///
/// final session = ChatSession(engine);
/// session.systemPrompt = 'You are a helpful assistant.';
///
/// await for (final chunk in session.create([LlamaTextContent('Hello!')])) {
///   final text = chunk.choices.first.delta.content;
///   if (text != null) {
///     print(text);
///   }
/// }
/// ```
class ChatSession {
  final LlamaEngine _engine;
  final List<LlamaChatMessage> _history = [];
  bool _lastRequestFitContext = true;

  /// The maximum number of tokens allowed in the context window.
  ///
  /// If null, this value will be automatically retrieved from the engine's
  /// model metadata.
  int? maxContextTokens;

  /// Creates a new [ChatSession] wrapping the given [engine].
  ChatSession(this._engine, {this.maxContextTokens, this.systemPrompt});

  /// The underlying engine instance.
  LlamaEngine get engine => _engine;

  /// The current message history, excluding the [systemPrompt].
  ///
  /// Returns an unmodifiable list of [LlamaChatMessage].
  List<LlamaChatMessage> get history => List.unmodifiable(_history);

  /// Whether the most recently rendered request fit its prompt token budget.
  ///
  /// A `false` value means even the active turn could not be compacted enough;
  /// callers that execute model-proposed side effects should fail closed.
  bool get lastRequestFitContext => _lastRequestFitContext;

  /// The system prompt for this session.
  ///
  /// If set, this prompt is automatically prepended to the message list
  /// during every [create] request.
  String? systemPrompt;

  /// Adds a custom [message] directly to the history.
  ///
  /// Useful for:
  /// - Pre-seeding a conversation
  /// - Adding tool results after parsing tool calls
  /// - Restoring a previous session state
  void addMessage(LlamaChatMessage message) {
    _history.add(message);
  }

  /// Resets the session state.
  ///
  /// By default, [keepSystemPrompt] is true, meaning only the message history
  /// is cleared.
  void reset({bool keepSystemPrompt = true}) {
    _history.clear();
    if (!keepSystemPrompt) {
      systemPrompt = null;
    }
  }

  /// Sends a user message and returns a stream of generated response tokens.
  ///
  /// The [parts] list contains the message content. For text-only messages,
  /// use `[LlamaTextContent('your message')]`. For multimodal content,
  /// include `LlamaImageContent` or `LlamaAudioContent` parts.
  ///
  /// Pass [tools] to enable function calling. Use [toolChoice] to control
  /// whether the model should use tools:
  /// - [ToolChoice.none]: Model won't call any tool
  /// - [ToolChoice.auto]: Model can choose (default when tools present)
  /// - [ToolChoice.required]: Model must call at least one tool
  ///
  /// Set [parallelToolCalls] to allow multiple tool calls in one response for
  /// templates that support it.
  ///
  /// Set [continuesPreviousTurn] when non-empty [parts] are a user-role
  /// protocol continuation of the preceding request, rather than a new user
  /// turn. This keeps text-based tool-result prompts attached to the original
  /// turn when older context is trimmed.
  ///
  /// Example with tools:
  /// ```dart
  /// final response = StringBuffer();
  /// await for (final chunk in session.create(
  ///   [LlamaTextContent('What time is it?')],
  ///   tools: [getTimeTool],
  /// )) {
  ///   final text = chunk.choices.first.delta.content;
  ///   if (text != null) {
  ///     response.write(text);
  ///   }
  /// }
  ///
  /// if (isToolCall(response.toString())) {
  ///   final result = await executeMyTool(parseToolCall(response.toString()));
  ///   session.addMessage(
  ///     LlamaChatMessage.withContent(
  ///       role: LlamaChatRole.tool,
  ///       content: [
  ///         LlamaToolResultContent(name: getTimeTool.name, result: result),
  ///       ],
  ///     ),
  ///   );
  ///   await for (final chunk in session.create([])) {
  ///     final text = chunk.choices.first.delta.content;
  ///     if (text != null) {
  ///       print(text);
  ///     }
  ///   }
  /// }
  /// ```
  Stream<LlamaCompletionChunk> create(
    List<LlamaContentPart> parts, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    void Function(LlamaChatMessage message)? onMessageAdded,
    bool continuesPreviousTurn = false,
  }) async* {
    // Add user message if parts provided
    if (parts.isNotEmpty) {
      final userMsg = parts.length == 1 && parts.first is LlamaTextContent
          ? LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: (parts.first as LlamaTextContent).text,
              continuesPreviousTurn: continuesPreviousTurn,
            )
          : LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: parts,
              continuesPreviousTurn: continuesPreviousTurn,
            );
      _history.add(userMsg);
      onMessageAdded?.call(userMsg);
    }

    // Ensure the rendered request, including tool schemas, leaves enough room
    // for the configured response rather than using a fixed small reserve.
    _lastRequestFitContext = await _enforceContextLimit(
      params: params,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      chatTemplateKwargs: chatTemplateKwargs,
    );

    // Build messages for engine
    final messages = _buildMessages();

    // Generate response
    final fullContent = StringBuffer();
    final fullThinking = StringBuffer();
    final Map<int, _ToolCallBuilder> toolCallBuilders = {};

    await for (final chunk in _engine.create(
      messages,
      params: params,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      chatTemplateKwargs: chatTemplateKwargs,
    )) {
      // Guard against an empty-choices chunk (e.g. a keep-alive) which would
      // otherwise throw "Bad state: No element" mid-stream.
      if (chunk.choices.isEmpty) {
        yield chunk;
        continue;
      }
      final delta = chunk.choices.first.delta;
      if (delta.content != null) fullContent.write(delta.content!);
      if (delta.thinking != null) fullThinking.write(delta.thinking!);

      if (delta.toolCalls != null) {
        for (final tc in delta.toolCalls!) {
          toolCallBuilders.putIfAbsent(tc.index, () => _ToolCallBuilder());
          final builder = toolCallBuilders[tc.index]!;
          if (tc.id != null) builder.id = tc.id;
          if (tc.type != null) builder.type = tc.type;
          if (tc.function?.name != null) builder.name = tc.function!.name;
          if (tc.function?.arguments != null) {
            builder.arguments.write(tc.function!.arguments!);
          }
        }
      }

      yield chunk;
    }

    // Reconstruct final message with all parts
    final contentParts = <LlamaContentPart>[];

    if (fullThinking.isNotEmpty) {
      contentParts.add(LlamaThinkingContent(fullThinking.toString()));
    }

    if (fullContent.isNotEmpty) {
      contentParts.add(LlamaTextContent(fullContent.toString()));
    }

    // Add tool calls
    final sortedIndices = toolCallBuilders.keys.toList()..sort();
    for (final index in sortedIndices) {
      final b = toolCallBuilders[index]!;
      Map<String, dynamic> args = {};
      try {
        if (b.arguments.isNotEmpty) {
          args = jsonDecode(b.arguments.toString());
        }
      } catch (_) {
        // Keep empty if parse fails
      }

      contentParts.add(
        LlamaToolCallContent(
          id: b.id,
          name: b.name ?? "",
          arguments: args,
          rawJson: b.arguments.toString(),
        ),
      );
    }

    final assistantMsg = LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: contentParts,
    );
    _history.add(assistantMsg);
    onMessageAdded?.call(assistantMsg);
  }

  /// Builds the message list for the engine, including system prompt.
  List<LlamaChatMessage> _buildMessages() {
    final messages = <LlamaChatMessage>[];

    // Add system prompt if set
    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      messages.add(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: systemPrompt!,
        ),
      );
    }

    // Add history (excluding any existing system messages - we use our own)
    messages.addAll(_history.where((m) => m.role != LlamaChatRole.system));
    return messages;
  }

  /// Truncates history if it exceeds the context limit.
  Future<bool> _enforceContextLimit({
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    required bool parallelToolCalls,
    required bool enableThinking,
    Map<String, dynamic>? chatTemplateKwargs,
  }) async {
    final limit = maxContextTokens ?? await _engine.getContextSize();
    if (limit <= 0) return true;

    final requestedResponseTokens =
        params?.maxTokens ?? const GenerationParams().maxTokens;
    // Preserve at least half of the context for the rendered prompt when a
    // caller asks for more output tokens than the context can realistically
    // hold. Within that bound, reserve the actual requested output budget
    // instead of the old fixed 512-token ceiling.
    final maximumReserve = limit > 1 ? limit ~/ 2 : 0;
    final reserve = maximumReserve == 0
        ? 0
        : requestedResponseTokens.clamp(
            maximumReserve < 128 ? 1 : 128,
            maximumReserve,
          );
    final targetLimit = limit - reserve;

    final turnOffsets = _buildTurnOffsets();

    final fullTokenCount = await _getTemplateTokenCount(
      _buildMessagesFromOffset(0),
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      chatTemplateKwargs: chatTemplateKwargs,
    );
    if (fullTokenCount <= targetLimit) return true;

    if (turnOffsets.length > 1) {
      int low = 1;
      int high = turnOffsets.length - 1;
      int bestDropCount = high;
      var foundFit = false;

      while (low <= high) {
        final mid = (low + high) >> 1;
        final tokenCount = await _getTemplateTokenCount(
          _buildMessagesFromOffset(turnOffsets[mid]),
          tools: tools,
          toolChoice: toolChoice,
          parallelToolCalls: parallelToolCalls,
          enableThinking: enableThinking,
          chatTemplateKwargs: chatTemplateKwargs,
        );

        if (tokenCount <= targetLimit) {
          bestDropCount = mid;
          foundFit = true;
          high = mid - 1;
        } else {
          low = mid + 1;
        }
      }

      final removeUntil = turnOffsets[bestDropCount];
      if (removeUntil > 0) {
        _history.removeRange(0, removeUntil);
      }
      if (foundFit) {
        return true;
      }
    }

    final compacted = await _trimCompletedProtocolExchanges(
      targetLimit: targetLimit,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      chatTemplateKwargs: chatTemplateKwargs,
    );
    if (!compacted) {
      // Even retaining the root request and newest coherent protocol exchange
      // exceeds the budget. Keep those messages intact and surface a warning
      // rather than orphaning a tool result or silently dropping the task.
      LlamaLogger.instance.warn(
        'ChatSession: the active turn still exceeds the context budget '
        '($targetLimit tokens) after compacting completed protocol exchanges. '
        'The prompt may be truncated or rejected by the backend; reduce the '
        'message or tool-result size, or increase the context window.',
      );
    }
    return compacted;
  }

  Future<bool> _trimCompletedProtocolExchanges({
    required int targetLimit,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    required bool parallelToolCalls,
    required bool enableThinking,
    Map<String, dynamic>? chatTemplateKwargs,
  }) async {
    final anchorIndex = _history.indexWhere(
      (message) =>
          message.role == LlamaChatRole.user && !message.continuesPreviousTurn,
    );
    if (anchorIndex < 0 || anchorIndex + 3 >= _history.length) {
      return false;
    }

    final boundaries = <int>[];
    for (var i = anchorIndex + 2; i < _history.length; i++) {
      if (_history[i].role != LlamaChatRole.assistant) {
        continue;
      }
      final previous = _history[i - 1];
      if (previous.role == LlamaChatRole.tool ||
          (previous.role == LlamaChatRole.user &&
              previous.continuesPreviousTurn)) {
        boundaries.add(i);
      }
    }
    if (boundaries.isEmpty) {
      return false;
    }

    var low = 0;
    var high = boundaries.length - 1;
    var bestBoundary = boundaries.last;
    var foundFit = false;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final boundary = boundaries[mid];
      final tokenCount = await _getTemplateTokenCount(
        _buildMessagesPreservingAnchor(anchorIndex, boundary),
        tools: tools,
        toolChoice: toolChoice,
        parallelToolCalls: parallelToolCalls,
        enableThinking: enableThinking,
        chatTemplateKwargs: chatTemplateKwargs,
      );
      if (tokenCount <= targetLimit) {
        bestBoundary = boundary;
        foundFit = true;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }

    _history.removeRange(anchorIndex + 1, bestBoundary);
    return foundFit;
  }

  Future<int> _getTemplateTokenCount(
    List<LlamaChatMessage> messages, {
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    required bool parallelToolCalls,
    required bool enableThinking,
    Map<String, dynamic>? chatTemplateKwargs,
  }) async {
    final template = await _engine.chatTemplate(
      messages,
      tools: tools,
      toolChoice: toolChoice ?? ToolChoice.auto,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      chatTemplateKwargs: chatTemplateKwargs,
      includeTokenCount: true,
    );
    return template.tokenCount ?? _estimateTokenCount(template.prompt);
  }

  int _estimateTokenCount(String prompt) {
    if (prompt.isEmpty) {
      return 0;
    }
    // Used only when the active backend cannot expose exact tokenization.
    // Overestimate slightly so history trimming stays conservative.
    final byteLength = utf8.encode(prompt).length;
    return (byteLength + 2) ~/ 3;
  }

  List<LlamaChatMessage> _buildMessagesFromOffset(int startOffset) {
    final messages = <LlamaChatMessage>[];

    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      messages.add(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: systemPrompt!,
        ),
      );
    }

    if (startOffset >= _history.length) {
      return messages;
    }

    for (int i = startOffset; i < _history.length; i++) {
      final message = _history[i];
      if (message.role != LlamaChatRole.system) {
        messages.add(message);
      }
    }

    return messages;
  }

  List<LlamaChatMessage> _buildMessagesPreservingAnchor(
    int anchorIndex,
    int continuationOffset,
  ) {
    final messages = <LlamaChatMessage>[];
    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      messages.add(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: systemPrompt!,
        ),
      );
    }
    for (var i = 0; i <= anchorIndex; i++) {
      if (_history[i].role != LlamaChatRole.system) {
        messages.add(_history[i]);
      }
    }
    for (var i = continuationOffset; i < _history.length; i++) {
      if (_history[i].role != LlamaChatRole.system) {
        messages.add(_history[i]);
      }
    }
    return messages;
  }

  // Returns the indices at which conversational turns begin, so history can be
  // trimmed only on clean turn boundaries. A turn starts at a user message and
  // includes the assistant/tool messages that follow it until the next user
  // message. Anchoring on user messages (rather than blindly consuming the
  // first message of each iteration) keeps a user prompt grouped with its reply
  // even when the history does not start with a user message.
  List<int> _buildTurnOffsets() {
    final offsets = <int>[0];

    for (int i = 1; i < _history.length; i++) {
      if (_history[i].role == LlamaChatRole.user &&
          !_history[i].continuesPreviousTurn) {
        offsets.add(i);
      }
    }

    return offsets;
  }
}

class _ToolCallBuilder {
  String? id;
  String? type;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
