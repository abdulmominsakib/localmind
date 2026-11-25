import 'dart:async';
import 'dart:convert';

import '../../backends/backend.dart';
import 'chat_completion_request_planner.dart';
import '../template/response_format.dart';
import 'engine.dart';
import 'generation_cancellation.dart';
import '../exceptions.dart';
import '../llama_logger.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/completion_chunk.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/completion.dart';
import '../models/chat/content_part.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/structured_output.dart';
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
/// final engine = await LlamaEngine.load(
///   LlamaModel(ModelSource.path('model.gguf')),
/// );
///
/// final session = ChatSession(engine);
/// session.systemPrompt = 'You are a helpful assistant.';
///
/// await for (final chunk in session.create([LlamaTextContent('Hello!')])) {
///   stdout.write(chunk.text);
/// }
///
/// // Or wait for the whole reply.
/// final reply = await session.send('And in one word?');
/// print(reply.text);
/// ```
class ChatSession {
  final LlamaEngine _engine;
  final List<LlamaChatMessage> _history = [];
  bool _lastRequestFitContext = true;
  int _resetEpoch = 0;

  /// The maximum number of tokens allowed in the context window.
  ///
  /// If null, this value will be automatically retrieved from the engine's
  /// model metadata.
  int? maxContextTokens;

  /// Creates a new [ChatSession] wrapping the given [engine].
  ChatSession(this._engine, {this.maxContextTokens, this.systemPrompt}) {
    _mutableHistories[this] = _history;
  }

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
    _resetEpoch++;
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
  /// Pass [responseFormat] to request strict structured output for this turn,
  /// with the same shapes and backend checks as [LlamaEngine.create]. An
  /// unrecognised shape, or a strict format on a backend without
  /// grammar-constrained decoding such as LiteRT-LM, throws
  /// `LlamaUnsupportedException` before the user message is added to
  /// [history]. Use [createStructuredJson] to also validate and decode the
  /// reply.
  ///
  /// If the stream ends before the engine yields any reply content, through an
  /// error such as the backend rejecting the rendered request or through a
  /// cancelled subscription, this call undoes its own [history] changes: it
  /// removes the user message it added, and puts back the turns its context
  /// check trimmed when [history] has not changed since. A retry then does
  /// not repeat the user message. [onMessageAdded] has already reported that
  /// message. If the stream ends that way after the first chunk, the reply
  /// generated so far is added as the assistant turn, so roles keep
  /// alternating. Empty terminal chunks do not count as reply content.
  /// Cancelling generation before any content throws [LlamaStateException]
  /// and rolls back this turn. A reply never enters history after [reset]
  /// or after its initiating message has been removed. A history edit while
  /// preparing the context throws [LlamaStateException] instead of trimming
  /// messages from the changed conversation.
  ///
  /// The stream delivers the reply's text in full, including whitespace the
  /// model ended it with. The assistant turn added to [history], which
  /// [onMessageAdded] receives, holds that text without the trailing
  /// whitespace, so it does not reach the next prompt through a template that
  /// does not trim; leading whitespace, reasoning and tool calls are stored
  /// as generated. Messages added with [addMessage] are stored as given.
  ///
  /// To run the tools' handlers until the model answers, use
  /// `sendWithTools`. Running the calls yourself:
  /// ```dart
  /// final reply = await session.create(
  ///   [LlamaTextContent('What time is it?')],
  ///   tools: [getTimeTool],
  /// ).collect();
  /// if (reply.text.isNotEmpty) print(reply.text);
  ///
  /// for (final call in reply.toolCalls) {
  ///   final result = await getTimeTool.invoke(call.arguments);
  ///   session.addMessage(
  ///     LlamaChatMessage.withContent(
  ///       role: LlamaChatRole.tool,
  ///       content: [
  ///         LlamaToolResultContent(
  ///           id: call.id,
  ///           name: call.name,
  ///           result: result,
  ///         ),
  ///       ],
  ///     ),
  ///   );
  /// }
  /// if (reply.toolCalls.isNotEmpty) {
  ///   await session.create([]).textDeltas().forEach(stdout.write);
  /// }
  /// ```
  /// A handler's `LlamaToolOutput` goes in as `result: output.output` and
  /// `content: output.content`; a `LlamaToolOutput` `result` throws
  /// [LlamaArgumentException].
  Stream<LlamaCompletionChunk> create(
    List<LlamaContentPart> parts, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    Map<String, dynamic>? chatTemplateKwargs,
    void Function(LlamaChatMessage message)? onMessageAdded,
    bool continuesPreviousTurn = false,
  }) {
    final cancellation = GenerationCancellation.forEngine(_engine);
    final zone = Zone.current;
    return cancellation.request((request) async* {
      final templateNow = switch (this) {
        TemplateTimeChatSession(:final templateNow) => templateNow,
        _ => null,
      };
      if (_engine.backend is BackendJsonSchemaChatGeneration &&
          !ChatCompletionRequestPlanner.supportsGrammarConstraints(
            _engine.backend,
          ) &&
          responseFormatSchema(responseFormat) != null) {
        await ChatCompletionRequestPlanner.prepareResponseFormat(
          _engine.backend,
          responseFormat,
        );
      } else {
        ChatCompletionRequestPlanner.rejectUnsupportedResponseFormat(
          _engine.backend,
          responseFormat,
        );
      }
      final edits = _TurnEdits(this);

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
        edits.add(userMsg);
        onMessageAdded?.call(userMsg);
      }

      final reply = LlamaCompletionAccumulator();
      var started = false;
      var completed = false;
      // Chunks that reach this generator after its subscription is cancelled
      // are never delivered, so they neither start nor extend the reply.
      var unsubscribed = false;
      request.onSubscriptionCancel(() async => unsubscribed = true);
      try {
        // Ensure the rendered request, including tool schemas, leaves enough
        // room for the configured response rather than using a fixed small
        // reserve.
        _lastRequestFitContext = await _enforceContextLimit(
          edits,
          params: params,
          tools: tools,
          toolChoice: toolChoice,
          parallelToolCalls: parallelToolCalls,
          enableThinking: enableThinking,
          responseFormat: responseFormat,
          chatTemplateKwargs: chatTemplateKwargs,
          templateNow: templateNow,
        );

        final messages = _buildMessages();
        final completion = zone.run(
          () => cancellation.inherit(
            request,
            () => _engine.create(
              messages,
              params: params,
              tools: tools,
              toolChoice: toolChoice,
              parallelToolCalls: parallelToolCalls,
              enableThinking: enableThinking,
              responseFormat: responseFormat,
              chatTemplateKwargs: chatTemplateKwargs,
              templateNow: templateNow,
            ),
          ),
        );
        await for (final chunk in completion) {
          if (unsubscribed) break;
          started |= chunk.choices.any(
            (choice) =>
                (choice.delta.content?.isNotEmpty ?? false) ||
                (choice.delta.thinking?.isNotEmpty ?? false) ||
                (choice.delta.toolCalls?.isNotEmpty ?? false),
          );
          reply.add(chunk);
          yield chunk;
        }
        if (!started && request.isCancelled() && !unsubscribed) {
          throw LlamaStateException(
            'Generation was cancelled before any output.',
          );
        }
        completed = true;
      } finally {
        // Runs on completion, on an error and on a cancelled subscription.
        if (edits.canCommit &&
            (started || (completed && !request.isCancelled()))) {
          final completion = reply.build();
          // The text keeps the whitespace the model ended it with, and a
          // template that does not trim would render it into the next
          // prompt. Stored without it, the turn renders as it did before
          // replies kept that whitespace.
          final assistantMsg = LlamaCompletion(
            text: completion.text.trimRight(),
            thinking: completion.thinking,
            toolCalls: completion.toolCalls,
          ).message;
          _history.add(assistantMsg);
          onMessageAdded?.call(assistantMsg);
        } else {
          edits.undo();
        }
      }
    });
  }

  /// Sends a user message, generates strict structured JSON, and decodes it.
  ///
  /// This is [create] with `output.responseFormat`, followed by
  /// [LlamaStructuredOutput.parse] on the completed reply, matching
  /// [LlamaEngine.createStructuredJson]. The raw JSON reply is added to
  /// [history] like any other assistant turn.
  Future<T> createStructuredJson<T>(
    List<LlamaContentPart> parts, {
    required LlamaStructuredOutput<T> output,
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    void Function(LlamaChatMessage message)? onMessageAdded,
    bool continuesPreviousTurn = false,
  }) {
    return create(
      parts,
      params: params,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: output.responseFormat,
      chatTemplateKwargs: chatTemplateKwargs,
      onMessageAdded: onMessageAdded,
      continuesPreviousTurn: continuesPreviousTurn,
    ).parseStructuredJson(output);
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
  Future<bool> _enforceContextLimit(
    _TurnEdits edits, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    required bool parallelToolCalls,
    required bool enableThinking,
    Map<String, dynamic>? responseFormat,
    Map<String, dynamic>? chatTemplateKwargs,
    required DateTime? templateNow,
  }) async {
    edits.beginContextPreparation();
    final limit = maxContextTokens ?? await _engine.getContextSize();
    edits.ensureUnchanged();
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
      responseFormat: responseFormat,
      chatTemplateKwargs: chatTemplateKwargs,
      templateNow: templateNow,
    );
    edits.ensureUnchanged();
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
          responseFormat: responseFormat,
          chatTemplateKwargs: chatTemplateKwargs,
          templateNow: templateNow,
        );

        edits.ensureUnchanged();
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
        edits.removeRange(0, removeUntil);
      }
      if (foundFit) {
        return true;
      }
    }

    final compacted = await _trimCompletedProtocolExchanges(
      edits,
      targetLimit: targetLimit,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: responseFormat,
      chatTemplateKwargs: chatTemplateKwargs,
      templateNow: templateNow,
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

  Future<bool> _trimCompletedProtocolExchanges(
    _TurnEdits edits, {
    required int targetLimit,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    required bool parallelToolCalls,
    required bool enableThinking,
    Map<String, dynamic>? responseFormat,
    Map<String, dynamic>? chatTemplateKwargs,
    required DateTime? templateNow,
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
        responseFormat: responseFormat,
        chatTemplateKwargs: chatTemplateKwargs,
        templateNow: templateNow,
      );
      edits.ensureUnchanged();
      if (tokenCount <= targetLimit) {
        bestBoundary = boundary;
        foundFit = true;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }

    edits.removeRange(anchorIndex + 1, bestBoundary);
    return foundFit;
  }

  Future<int> _getTemplateTokenCount(
    List<LlamaChatMessage> messages, {
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    required bool parallelToolCalls,
    required bool enableThinking,
    Map<String, dynamic>? responseFormat,
    Map<String, dynamic>? chatTemplateKwargs,
    required DateTime? templateNow,
  }) async {
    final template = await _engine.chatTemplate(
      messages,
      tools: tools,
      toolChoice: toolChoice ?? ToolChoice.auto,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: responseFormat,
      chatTemplateKwargs: chatTemplateKwargs,
      templateNow: templateNow,
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

/// The [ChatSession.history] changes one [ChatSession.create] call made, so
/// it can undo them without discarding changes made by anyone else.
class _TurnEdits {
  _TurnEdits(this._session)
    : _resetEpoch = _session._resetEpoch,
      _anchor = _session._history.lastOrNull,
      _historyAfter = List.of(_session._history);

  final ChatSession _session;
  final int _resetEpoch;
  final LlamaChatMessage? _anchor;
  final List<(int, List<LlamaChatMessage>)> _removals = [];
  LlamaChatMessage? _added;
  List<LlamaChatMessage> _historyAfter;
  List<LlamaChatMessage> _contextHistory = [];

  List<LlamaChatMessage> get _history => _session._history;

  bool get canCommit {
    if (_session._resetEpoch != _resetEpoch) return false;
    final anchor = _added ?? _anchor;
    return anchor == null ||
        _history.any((message) => identical(message, anchor));
  }

  void add(LlamaChatMessage message) {
    _history.add(message);
    _added = message;
    _historyAfter = List.of(_history);
  }

  void removeRange(int start, int end) {
    _removals.add((start, _history.sublist(start, end)));
    _history.removeRange(start, end);
    _historyAfter = List.of(_history);
    _contextHistory = List.of(_history);
  }

  bool get isUnchanged =>
      _session._resetEpoch == _resetEpoch &&
      _history.length == _historyAfter.length &&
      Iterable<int>.generate(
        _history.length,
      ).every((i) => identical(_history[i], _historyAfter[i]));

  void beginContextPreparation() {
    _contextHistory = List.of(_history);
  }

  void ensureUnchanged() {
    if (_session._resetEpoch != _resetEpoch ||
        _history.length != _contextHistory.length ||
        !Iterable<int>.generate(
          _history.length,
        ).every((i) => identical(_history[i], _contextHistory[i]))) {
      throw LlamaStateException(
        'Chat history changed while preparing the request. Retry with the current session.',
      );
    }
  }

  /// Puts back the removed turns when no one else changed the history since,
  /// then removes the added message wherever it now is.
  void undo() {
    final unchanged = isUnchanged;
    if (unchanged) {
      for (final (start, removed) in _removals.reversed) {
        _history.insertAll(start, removed);
      }
    }
    final added = _added;
    if (added == null) return;
    final index = _history.lastIndexWhere(
      (message) => identical(message, added),
    );
    if (index >= 0) _history.removeAt(index);
  }
}

final Expando<List<LlamaChatMessage>> _mutableHistories = Expando(
  'llamadart.chatSessionHistory',
);

/// Package-internal: the list behind [ChatSession.history], or `null` for a
/// class that implements [ChatSession] without extending it.
List<LlamaChatMessage>? mutableChatSessionHistory(ChatSession session) =>
    _mutableHistories[session];

/// A chat session with an explicit template clock.
///
/// Each listened request snapshots [templateNow] before context preparation,
/// and uses it for every budget render and the generation request. Changing it
/// during a request affects the next request only. Tool-loop rounds each start
/// a request. [ChatSession.reset] keeps this setting.
///
/// The separate type preserves the public interface of [ChatSession] and does
/// not introduce an extension that can collide with application extensions.
final class TemplateTimeChatSession extends ChatSession {
  /// Time supplied to the template; null preserves the engine's normal clock.
  DateTime? templateNow;

  /// Creates a session whose prompts use [templateNow].
  TemplateTimeChatSession(
    super.engine, {
    this.templateNow,
    super.maxContextTokens,
    super.systemPrompt,
  });
}

/// One-shot replies for [ChatSession].
extension ChatSessionCompletionExtension on ChatSession {
  /// Sends [text] as a user message and returns the whole reply.
  ///
  /// This is [ChatSession.create] with a single [LlamaTextContent], collected
  /// with `collect()`. The user message and the reply are added to
  /// [ChatSession.history] as they are with [ChatSession.create]. Use
  /// [ChatSession.create] to stream the reply or to send media parts.
  Future<LlamaCompletion> send(
    String text, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    Map<String, dynamic>? chatTemplateKwargs,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) {
    return create(
      [LlamaTextContent(text)],
      params: params,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: responseFormat,
      chatTemplateKwargs: chatTemplateKwargs,
      onMessageAdded: onMessageAdded,
    ).collect();
  }
}
