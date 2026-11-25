import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import '../../backends/backend.dart';
import 'chat_session.dart';
import 'generation_cancellation.dart';
import '../exceptions.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/completion.dart';
import '../models/chat/completion_chunk.dart';
import '../models/chat/content_part.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';
import '../models/tools/tool_output.dart';
import '../models/tools/tool_params.dart';

/// Runs a tool call that has no [ToolDefinition.handler], or that names a
/// tool missing from the `tools` list, and returns its result.
///
/// The result may be any JSON-compatible value, or a [LlamaToolOutput] for
/// text or media after it.
typedef LlamaToolCallCallback =
    FutureOr<Object?> Function(LlamaToolCallContent call);

/// Turns an error thrown while running [call] into the tool result the model
/// sees, or rethrows it to stop the tool loop.
///
/// Without this callback the result is `{'error': message}`, where message
/// is the exception's text. That text then reaches the prompt and
/// `ChatSession.history`; return a redacted result here when an error can
/// carry secrets such as tokens, signed URLs or file paths.
typedef LlamaToolErrorCallback =
    FutureOr<Object?> Function(
      LlamaToolCallContent call,
      Object error,
      StackTrace stackTrace,
    );

/// Why `ChatSession.sendWithTools` stopped.
///
/// Only [completed], [unhandledToolCalls] and a [cancelled] stop that kept a
/// partial answer leave the turn in `ChatSession.history`. Every other stop
/// rolls the turn back; see [LlamaToolLoopResult.rolledBack].
enum LlamaToolLoopStopReason {
  /// The model replied without calling a tool. The turn stays in the
  /// history.
  completed,

  /// The model called tools after `maxRounds` tool rounds had already run.
  /// The calls were not run, and the turn was rolled back.
  maxRounds,

  /// A call names a tool with no [ToolDefinition.handler] and no
  /// `onToolCall` was given. No call of that reply was run. The turn stays
  /// in the history, ending with the reply's calls, for the app to answer.
  unhandledToolCalls,

  /// The request did not fit its context budget
  /// ([ChatSession.lastRequestFitContext] is `false`), so the model may not
  /// have seen the whole turn. Its calls were not run, and the turn was
  /// rolled back.
  contextExceeded,

  /// Generation was cancelled while the loop ran by
  /// `LlamaEngine.cancelGeneration`, model unload/replacement or disposal. A
  /// reply without tool calls stays in the history as the turn's answer, even
  /// an empty one; otherwise the turn was rolled back.
  ///
  /// Which of the two a cancel near the start of a reply gives depends on
  /// its timing, the backend, the chat template and its parser: an empty
  /// reply that parses stays as an empty answer. Check
  /// [LlamaToolLoopResult.rolledBack].
  cancelled,

  /// The reply was cut off ([LlamaFinishReason.length]): it reached
  /// `GenerationParams.maxTokens` or filled the context before the model
  /// ended it. Its text may be an unfinished tool call or thinking rather
  /// than an answer, so its calls were not run and the turn was rolled back.
  /// Complete calls before an incomplete parallel call are withheld too.
  /// [LlamaToolLoopResult.completion] keeps the partial reply; raise
  /// `maxTokens` and send the turn again.
  truncated,
}

/// The outcome of `ChatSession.sendWithTools`.
class LlamaToolLoopResult {
  /// The model's last reply. Its [LlamaCompletion.toolCalls] are the calls
  /// of the last reply, whether or not they were run.
  final LlamaCompletion completion;

  /// Why the loop stopped.
  final LlamaToolLoopStopReason stopReason;

  /// The number of tool rounds that ran: replies whose calls were run and
  /// whose results were added to the turn.
  final int rounds;

  /// The calls of [completion] that were not run, in call order.
  ///
  /// Empty when [stopReason] is [LlamaToolLoopStopReason.completed]. After
  /// [LlamaToolLoopStopReason.unhandledToolCalls], answer each call with a
  /// `LlamaChatRole.tool` message through `ChatSession.addMessage`, then call
  /// `completeWithTools(const [], ...)`.
  final List<LlamaToolCallContent> pendingToolCalls;

  /// The messages of the turn, in order: its user message, each reply and
  /// each tool result, including those of an open turn that
  /// `completeWithTools(const [], ...)` continued.
  ///
  /// When [rolledBack] is `true`, none of them is in the history any more,
  /// but tools that ran keep their effects and their results are here.
  final List<LlamaChatMessage> messages;

  /// Whether the turn was removed from `ChatSession.history`.
  ///
  /// To resume a rolled-back turn, add [messages] back with
  /// `ChatSession.addMessage`, answer [pendingToolCalls], and call
  /// `completeWithTools(const [], ...)`. After
  /// [LlamaToolLoopStopReason.truncated], raise `maxTokens` and send the
  /// turn again instead: [messages] ends with the partial reply, and
  /// templates such as Ministral 3's can reject the next user turn after it.
  final bool rolledBack;

  /// Creates a tool loop result.
  const LlamaToolLoopResult({
    required this.completion,
    required this.stopReason,
    required this.rounds,
    this.pendingToolCalls = const [],
    this.messages = const [],
    this.rolledBack = false,
  });

  /// The text of the last reply.
  String get text => completion.text;

  @override
  String toString() =>
      'LlamaToolLoopResult(stopReason: ${stopReason.name}, rounds: $rounds, '
      'pendingToolCalls: ${pendingToolCalls.length}, '
      'rolledBack: $rolledBack, '
      'completion: $completion)';
}

/// Tool-calling loops for [ChatSession].
extension ChatSessionToolLoopExtension on ChatSession {
  /// Sends [text] as a user message and runs the model's tool calls until it
  /// answers without one.
  ///
  /// This is [completeWithTools] with a single [LlamaTextContent].
  ///
  /// ```dart
  /// final result = await session.sendWithTools(
  ///   'What is the weather in Seoul?',
  ///   tools: [weatherTool],
  /// );
  /// if (result.stopReason == LlamaToolLoopStopReason.completed) {
  ///   print(result.text);
  /// }
  /// ```
  Future<LlamaToolLoopResult> sendWithTools(
    String text, {
    required List<ToolDefinition> tools,
    int maxRounds = 5,
    LlamaToolCallCallback? onToolCall,
    LlamaToolErrorCallback? onToolError,
    GenerationParams? params,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) {
    return completeWithTools(
      [LlamaTextContent(text)],
      tools: tools,
      maxRounds: maxRounds,
      onToolCall: onToolCall,
      onToolError: onToolError,
      params: params,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      chatTemplateKwargs: chatTemplateKwargs,
      onMessageAdded: onMessageAdded,
    );
  }

  /// Sends [parts] as a user message and runs the model's tool calls until it
  /// answers without one.
  ///
  /// Each round collects a reply with [ChatSession.create]. When the reply
  /// calls tools, the calls run concurrently, and each result is added to
  /// [ChatSession.history], in call order, as a `LlamaChatRole.tool` message
  /// holding a [LlamaToolResultContent] with the call's id and name; a
  /// [LlamaToolOutput] result becomes its `result` and `content`. The
  /// next round continues the turn without a new user message. Empty [parts]
  /// continue the current turn, for example after the caller added results
  /// for [LlamaToolLoopResult.pendingToolCalls].
  ///
  /// A call runs the [ToolDefinition.handler] of the tool it names. A call
  /// to a tool without a handler, or to a name missing from [tools], runs
  /// [onToolCall] instead. Without [onToolCall], a reply calling a tool that
  /// has no handler stops the loop before any of its calls runs, with
  /// [LlamaToolLoopStopReason.unhandledToolCalls], and a call to an unknown
  /// name fails as described below.
  ///
  /// A call fails when its tool throws, when it names an unknown tool, or
  /// when its arguments are not a JSON object; the last two fail with a
  /// [LlamaArgumentException]. [onToolError] turns the error into the tool
  /// result the model sees, so the model can recover. By default that
  /// result is `{'error': message}`, which puts the exception's text into
  /// the prompt and [ChatSession.history]; use [onToolError] to redact it.
  /// Rethrow from [onToolError] to stop the loop: this call then fails with
  /// that error once every call of the round has finished.
  ///
  /// The loop stops with a [LlamaToolLoopResult] when the model answers
  /// without a tool call, when it calls tools after [maxRounds] tool rounds,
  /// when a request did not fit its context budget (calls proposed from a
  /// trimmed prompt are not run), when a reply is cut off at
  /// `GenerationParams.maxTokens` or the end of the context, or when
  /// `LlamaEngine.cancelGeneration` is called. A cancel does not interrupt
  /// running tools. [maxRounds] must not be negative, or this throws
  /// [LlamaArgumentException]; `0` returns the first reply's calls unrun.
  ///
  /// After every stop, [ChatSession.history] ends with a reply without tool
  /// calls, so a new user turn can follow, except after
  /// [LlamaToolLoopStopReason.unhandledToolCalls], where it ends with the
  /// calls for the app to answer: add a tool message per call, then call
  /// `completeWithTools(const [], ...)`. Templates such as Ministral 3's
  /// reject a user turn that follows unanswered calls or tool results. So
  /// the other stops that end without an answer (`maxRounds`,
  /// `contextExceeded`, `truncated`, a cancel that left no reply without
  /// tool calls) and
  /// any error this call throws roll the whole turn back, from its user
  /// message on. A cancel during a reply without tool calls keeps that reply
  /// as the answer, which can be empty when the cancel came before its first
  /// token; whether such a cancel keeps an empty answer or rolls back
  /// depends on timing, backend, template and parser, so check
  /// [LlamaToolLoopResult.rolledBack].
  /// For empty [parts] that is the open turn being continued, including the
  /// messages added before this call, such as the app's tool results.
  /// Messages that other callers added meanwhile stay. Every message that a
  /// [ChatSession.addMessage] override stores while the loop adds a message,
  /// including a copy of that message and those a synchronous listener adds
  /// from inside the override, belongs to the turn: a rollback removes it
  /// too, and it is neither in [LlamaToolLoopResult.messages] nor reported
  /// to [onMessageAdded]. The one exception is a message the override places
  /// before the turn in place of a message from before the turn that it
  /// removed, such as a summary of earlier turns. Messages from before the
  /// turn that the override kept stay, even if it moved them; those it
  /// removed stay removed, as after [ChatSession.create].
  /// [LlamaToolLoopResult.rolledBack] reports a rollback,
  /// [LlamaToolLoopResult.messages] keeps the turn, and [onMessageAdded] has
  /// already reported the messages this call added.
  ///
  /// Each reply enters the history through [ChatSession.create], so its
  /// stored text has no trailing whitespace, while
  /// [LlamaToolLoopResult.completion] keeps the text as generated.
  /// [LlamaToolLoopResult.messages] and [onMessageAdded] hold the stored
  /// messages.
  ///
  /// Tool results are added with [ChatSession.addMessage]. A rollback edits
  /// the history without calling [ChatSession.addMessage] or
  /// [ChatSession.reset], so a subclass that mirrors the history should use
  /// [LlamaToolLoopResult.rolledBack]. A class that implements
  /// [ChatSession] without extending it is rolled back by calling
  /// [ChatSession.reset] and adding the remaining messages again. If its
  /// [ChatSession.history] returns different instances for the same message
  /// on two consecutive reads, the turn's messages are matched by role and
  /// content rather than identity.
  ///
  /// A cancel that a backend reports as a stream error, as WebGPU does,
  /// also stops the loop with [LlamaToolLoopStopReason.cancelled]. An error
  /// thrown by [onMessageAdded], or one raised before the cancel, still
  /// fails this call.
  ///
  /// To start a new chat while the loop runs, call
  /// `LlamaEngine.cancelGeneration`, await this call, then call
  /// [ChatSession.reset]: a reset while a reply is generating can leave that
  /// reply in the new chat
  /// ([#888](https://github.com/leehack/llamadart/issues/888)).
  ///
  /// [toolChoice] applies to the first request only; later rounds use
  /// [ToolChoice.auto] so the model can answer. The other arguments have the
  /// same meaning as in [ChatSession.create], and [onMessageAdded] also
  /// reports each tool result message. Use [ChatSession.create] directly to
  /// stream replies as they are generated.
  ///
  /// Throws [LlamaUnsupportedException] before changing history or generating
  /// when the backend declares that it cannot reliably report generation
  /// limits.
  Future<LlamaToolLoopResult> completeWithTools(
    List<LlamaContentPart> parts, {
    required List<ToolDefinition> tools,
    int maxRounds = 5,
    LlamaToolCallCallback? onToolCall,
    LlamaToolErrorCallback? onToolError,
    GenerationParams? params,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    void Function(LlamaChatMessage message)? onMessageAdded,
  }) {
    if (maxRounds < 0) {
      return Future.error(
        LlamaArgumentException(
          'maxRounds must not be negative.',
          name: 'maxRounds',
          invalidValue: maxRounds,
        ),
      );
    }
    final backend = engine.backend;
    if (backend is BackendGenerationLimitSupport) {
      final reason = (backend as BackendGenerationLimitSupport)
          .generationLimitUnsupportedReason;
      if (reason != null) {
        return Future.error(
          LlamaUnsupportedException(
            'Automatic tool loops require reliable generation-limit reporting. '
            '$reason Use a backend/runtime that reports why generation stopped.',
          ),
        );
      }
    }
    final cancellation = GenerationCancellation.forEngine(engine);
    return cancellation.request<LlamaToolLoopResult>((request) async* {
      final turn = _ToolLoopTurn(
        this,
        onMessageAdded,
        continuesTurn: parts.isEmpty,
      );
      try {
        var rounds = 0;
        var nextParts = parts;
        while (true) {
          final accumulator = LlamaCompletionAccumulator();
          bool? cancelledAtReply;
          try {
            final stream = cancellation.inherit(
              request,
              () => create(
                nextParts,
                params: params,
                tools: tools,
                toolChoice: rounds == 0 ? toolChoice : null,
                parallelToolCalls: parallelToolCalls,
                enableThinking: enableThinking,
                chatTemplateKwargs: chatTemplateKwargs,
                onMessageAdded: (message) {
                  if (message.role == LlamaChatRole.assistant) {
                    cancelledAtReply = request.isCancelled();
                  }
                  turn.report(message);
                },
              ),
            );
            await for (final chunk in stream) {
              accumulator.add(chunk);
            }
          } catch (error) {
            // Some backends, such as WebGPU, end a cancelled generation with
            // an error instead of closing the stream. `create` adds a partial
            // reply, and runs the app's callback, before that error reaches
            // here, so a cancel is judged from when the reply was added.
            final cancelled = cancelledAtReply ?? request.isCancelled();
            if (!cancelled || turn.isCallbackError(error)) rethrow;
          }
          final reply = accumulator.build();
          LlamaToolLoopResult stop(
            LlamaToolLoopStopReason reason, {
            bool rollBack = true,
            List<LlamaToolCallContent>? pendingToolCalls,
          }) {
            if (rollBack) turn.rollBack();
            return LlamaToolLoopResult(
              completion: reply,
              stopReason: reason,
              rounds: rounds,
              pendingToolCalls: pendingToolCalls ?? reply.toolCalls,
              messages: List.unmodifiable(turn.messages),
              rolledBack: rollBack,
            );
          }

          if (request.isCancelled()) {
            // A limited reply may contain reasoning but no executable calls;
            // it still cannot close the turn with a trustworthy answer.
            yield stop(
              LlamaToolLoopStopReason.cancelled,
              rollBack:
                  reply.finishReason == LlamaFinishReason.length ||
                  reply.toolCalls.isNotEmpty ||
                  !turn.endsWithReply,
            );
            return;
          }
          if (reply.finishReason == LlamaFinishReason.length) {
            yield stop(LlamaToolLoopStopReason.truncated);
            return;
          }
          if (reply.toolCalls.isEmpty) {
            yield stop(LlamaToolLoopStopReason.completed, rollBack: false);
            return;
          }
          if (!lastRequestFitContext) {
            yield stop(LlamaToolLoopStopReason.contextExceeded);
            return;
          }
          if (rounds >= maxRounds) {
            yield stop(LlamaToolLoopStopReason.maxRounds);
            return;
          }
          final runs = [
            for (final call in reply.toolCalls)
              _toolRun(call, tools, onToolCall),
          ];
          if (runs.contains(null)) {
            yield stop(
              LlamaToolLoopStopReason.unhandledToolCalls,
              rollBack: false,
            );
            return;
          }

          final results = await Future.wait([
            for (final (index, call) in reply.toolCalls.indexed)
              _runTool(call, runs[index]!, onToolError),
          ]);
          for (final (index, call) in reply.toolCalls.indexed) {
            final message = LlamaChatMessage.withContent(
              role: LlamaChatRole.tool,
              content: [_toolResult(call, results[index])],
            );
            turn.add(message);
          }
          rounds += 1;

          if (request.isCancelled()) {
            yield stop(
              LlamaToolLoopStopReason.cancelled,
              pendingToolCalls: const [],
            );
            return;
          }
          nextParts = const [];
        }
      } catch (_) {
        turn.rollBack();
        rethrow;
      }
    }).single;
  }
}

/// The turn one tool loop works on, so it can be rolled back without
/// removing messages that other callers added meanwhile.
class _ToolLoopTurn {
  _ToolLoopTurn(
    this._session,
    this._onMessageAdded, {
    required bool continuesTurn,
  }) {
    if (continuesTurn) {
      final history = _storedHistory;
      messages.addAll(history.skip(_openTurnStart(history)));
    }
  }

  final ChatSession _session;
  final void Function(LlamaChatMessage message)? _onMessageAdded;

  /// The open turn a continuation picks up, then every message the loop
  /// added.
  final List<LlamaChatMessage> messages = [];
  final List<LlamaChatMessage> _appended = [];
  LlamaChatMessage? _lastAdded;
  Object? _callbackError;

  /// Whether the latest message the loop added is a reply.
  bool get endsWithReply => _lastAdded?.role == LlamaChatRole.assistant;

  /// Whether [error] was thrown by the app's `onMessageAdded`.
  bool isCallbackError(Object error) => identical(error, _callbackError);

  /// Adds [message] with [ChatSession.addMessage] and reports it.
  ///
  /// Everything the call put into the stored history belongs to the turn,
  /// so a rollback removes it: the stored [message] or a copy of it, copies
  /// of the turn's earlier messages, and every other new message, except
  /// one placed before the turn in place of a message from before the turn
  /// that the call removed: a copy of that message, or, while removed
  /// messages remain without a copy, another message such as a summary of
  /// earlier turns. Messages from before the turn that the call kept stay,
  /// even if it moved them.
  void add(LlamaChatMessage message) {
    final byContent = _historyReturnsCopies;
    final bool Function(LlamaChatMessage, LlamaChatMessage) same = byContent
        ? _sameContent
        : identical;
    final before = _storedHistory.toList();
    _session.addMessage(message);
    final after = _storedHistory;

    final members = [...messages, ..._appended];
    final (added, removed) = byContent
        ? _diffInOrder(before, after, members, message)
        : _diffInstances(before, after);
    final unmatched = [...members];
    final replacedTurn = <LlamaChatMessage>[];
    final removedOutside = <LlamaChatMessage>[];
    for (final stored in removed) {
      final member = unmatched.indexWhere((member) => same(member, stored));
      if (member < 0) {
        removedOutside.add(stored);
      } else {
        unmatched.removeAt(member);
        replacedTurn.add(stored);
      }
    }

    var own = [
      for (final index in added)
        if (identical(after[index], message)) index,
    ];
    if (own.isEmpty) {
      final copy = added.lastWhere(
        (index) => _sameContent(after[index], message),
        orElse: () => -1,
      );
      if (copy >= 0) own = [copy];
    }
    final turn = {...own};
    final turnCopies = <int>[];
    final freshFromEnd = <int>[];
    for (final index in added.reversed) {
      if (own.contains(index)) continue;
      final original = replacedTurn.isEmpty
          ? -1
          : replacedTurn.lastIndexWhere(
              (stored) => _sameContent(stored, after[index]),
            );
      if (original < 0) {
        freshFromEnd.add(index);
      } else {
        replacedTurn.removeAt(original);
        turnCopies.add(index);
      }
    }
    final fresh = freshFromEnd.reversed.toList();
    turn.addAll(turnCopies);
    if (fresh.isNotEmpty) {
      // The turn starts at its first loop message; notes the override added
      // earlier in the turn may sit before it.
      final start = [
        ...own,
        for (final index in turnCopies)
          if (messages.any((loop) => _sameContent(loop, after[index]))) index,
        ..._turnIndices(after, messages, same),
      ].fold(after.length, min);
      final copies = _copiesOf(
        [
          for (final index in fresh)
            if (index < start) index,
        ],
        after,
        removedOutside,
      );
      var replacements = removedOutside.length - copies.length;
      for (final index in fresh) {
        if (copies.contains(index)) continue;
        if (index < start && replacements > 0) {
          replacements--;
        } else {
          turn.add(index);
        }
      }
    }
    final appended = [for (final index in turn.toList()..sort()) after[index]];
    final reported = appended.indexWhere((stored) => same(stored, message));
    if (reported >= 0) appended.removeAt(reported);
    _appended.addAll(appended);
    report(message);
  }

  List<LlamaChatMessage> get _storedHistory =>
      mutableChatSessionHistory(_session) ?? _session.history;

  /// How a turn message is found in [_storedHistory]: by identity, or by
  /// content when a class that implements [ChatSession] returns new copies
  /// from each [ChatSession.history] read, which identity can never match.
  bool Function(LlamaChatMessage, LlamaChatMessage) _sameMessage() =>
      _historyReturnsCopies ? _sameContent : identical;

  bool get _historyReturnsCopies {
    if (mutableChatSessionHistory(_session) != null) return false;
    final first = _session.history;
    final second = _session.history;
    for (var index = 0; index < min(first.length, second.length); index++) {
      if (!identical(first[index], second[index])) return true;
    }
    return false;
  }

  void report(LlamaChatMessage message) {
    messages.add(message);
    _lastAdded = message;
    try {
      _onMessageAdded?.call(message);
    } catch (error) {
      _callbackError = error;
      rethrow;
    }
  }

  /// Removes the turn's messages from the history.
  ///
  /// A [ChatSession] is edited in place, without calling its overridable
  /// [ChatSession.addMessage] or [ChatSession.reset]; a class that only
  /// implements [ChatSession] is rebuilt through those two methods.
  void rollBack() {
    final turn = [...messages, ..._appended];
    final history = mutableChatSessionHistory(_session);
    if (history != null) {
      _removeTurn(history, turn);
      return;
    }
    final same = _sameMessage();
    final rebuilt = _session.history.toList();
    _removeTurn(rebuilt, turn, same);
    _session.reset(keepSystemPrompt: true);
    rebuilt.forEach(_session.addMessage);
  }
}

/// The indices of the messages in [after] that are not in [before], and
/// the messages of [before] that are not in [after], matching instances.
(List<int>, List<LlamaChatMessage>) _diffInstances(
  List<LlamaChatMessage> before,
  List<LlamaChatMessage> after,
) {
  final leftover = HashMap<LlamaChatMessage, int>.identity();
  for (final stored in before) {
    leftover.update(stored, (count) => count + 1, ifAbsent: () => 1);
  }
  final added = <int>[];
  for (final (index, stored) in after.indexed) {
    final count = leftover[stored] ?? 0;
    if (count > 0) {
      leftover[stored] = count - 1;
    } else {
      added.add(index);
    }
  }
  final removed = <LlamaChatMessage>[];
  for (final stored in before) {
    final count = leftover[stored] ?? 0;
    if (count > 0) {
      leftover[stored] = count - 1;
      removed.add(stored);
    }
  }
  return (added, removed);
}

/// The indices in [candidates] of copies of [removed] messages, each removed
/// message standing for at most one copy.
Set<int> _copiesOf(
  List<int> candidates,
  List<LlamaChatMessage> after,
  List<LlamaChatMessage> removed,
) {
  final copies = <int>{};
  final used = List.filled(removed.length, false);
  var first = 0;
  for (final index in candidates) {
    while (first < removed.length && used[first]) {
      first++;
    }
    for (var match = first; match < removed.length; match++) {
      if (!used[match] && _sameContent(removed[match], after[index])) {
        used[match] = true;
        copies.add(index);
        break;
      }
    }
  }
  return copies;
}

/// [_diffInstances] for a history that returns copies: the turn's [members]
/// are found by content in both lists and left out, and the other messages
/// match by content and in order, so one that moved past another counts as
/// new, and so does every message after the stored [message].
(List<int>, List<LlamaChatMessage>) _diffInOrder(
  List<LlamaChatMessage> before,
  List<LlamaChatMessage> after,
  List<LlamaChatMessage> members,
  LlamaChatMessage message,
) {
  final turnBefore = _turnIndices(before, members, _sameContent).toSet();
  final turnAfter = _turnIndices(after, members, _sameContent).toSet();
  var stored = after.length - 1;
  while (stored >= 0 &&
      (turnAfter.contains(stored) || !_sameContent(after[stored], message))) {
    stored--;
  }
  final newest = stored < 0 ? after.length : stored;
  final olds = [
    for (final (index, stored) in before.indexed)
      if (!turnBefore.contains(index)) stored,
  ];
  final added = <int>[];
  final removed = <LlamaChatMessage>[];
  var next = 0;
  for (final (index, stored) in after.indexed) {
    if (turnAfter.contains(index)) continue;
    var match = index >= newest ? olds.length : next;
    while (match < olds.length && !_sameContent(olds[match], stored)) {
      match++;
    }
    if (match == olds.length) {
      added.add(index);
    } else {
      removed.addAll(olds.sublist(next, match));
      next = match + 1;
    }
  }
  removed.addAll(olds.sublist(next));
  return (added, removed);
}

/// Removes [turn] from [history], matching each message with [same]
/// (identity by default) from the end, so an earlier turn that holds the
/// same (for example `const`) instance, or equal content, keeps it.
void _removeTurn(
  List<LlamaChatMessage> history,
  List<LlamaChatMessage> turn, [
  bool Function(LlamaChatMessage, LlamaChatMessage) same = identical,
]) {
  for (final index in _turnIndices(history, turn, same)) {
    history.removeAt(index);
  }
}

/// The indices in [history] that [_removeTurn] removes, from the last one.
List<int> _turnIndices(
  List<LlamaChatMessage> history,
  List<LlamaChatMessage> turn,
  bool Function(LlamaChatMessage, LlamaChatMessage) same,
) {
  final remaining = List.of(turn);
  final indices = <int>[];
  for (var index = history.length - 1; index >= 0; index--) {
    if (remaining.isEmpty) break;
    final match = remaining.lastIndexWhere(
      (message) => same(message, history[index]),
    );
    if (match < 0) continue;
    remaining.removeAt(match);
    indices.add(index);
  }
  return indices;
}

bool _sameContent(LlamaChatMessage a, LlamaChatMessage b) {
  if (identical(a, b)) return true;
  if (a.role != b.role) return false;
  final aParts = a.parts;
  final bParts = b.parts;
  if (aParts.length != bParts.length) return false;
  for (var index = 0; index < aParts.length; index++) {
    final aPart = aParts[index];
    final bPart = bParts[index];
    if (identical(aPart, bPart)) continue;
    if (aPart.runtimeType != bPart.runtimeType ||
        jsonEncode(aPart.toJson()) != jsonEncode(bPart.toJson())) {
      return false;
    }
  }
  return true;
}

/// The index where the turn that ends [history] starts, or `history.length`
/// when that turn already has an answer: a reply without tool calls.
int _openTurnStart(List<LlamaChatMessage> history) {
  for (var index = history.length - 1; index >= 0; index--) {
    final message = history[index];
    if (message.role == LlamaChatRole.assistant &&
        !message.parts.any((part) => part is LlamaToolCallContent)) {
      break;
    }
    if (message.role == LlamaChatRole.user && !message.continuesPreviousTurn) {
      return index;
    }
  }
  return history.length;
}

/// Returns how to run [call], or `null` when the app must run it itself.
FutureOr<Object?> Function()? _toolRun(
  LlamaToolCallContent call,
  List<ToolDefinition> tools,
  LlamaToolCallCallback? onToolCall,
) {
  final tool = tools.where((tool) => tool.name == call.name).firstOrNull;
  final handler = tool?.handler;
  if (handler != null) {
    return () => handler(ToolParams(_argumentsOf(call)));
  }
  if (onToolCall != null) return () => onToolCall(call);
  if (tool != null) return null;
  return () => throw LlamaArgumentException(
    'The model called the unknown tool "${call.name}".',
    name: 'name',
    invalidValue: call.name,
  );
}

/// The arguments of [call]; throws [LlamaArgumentException] when the model
/// generated something other than a JSON object.
Map<String, dynamic> _argumentsOf(LlamaToolCallContent call) {
  final raw = call.rawJson.trim();
  if (call.arguments.isNotEmpty || raw.isEmpty) return call.arguments;
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    decoded = null;
  }
  if (decoded is Map<String, dynamic>) return decoded;
  throw LlamaArgumentException(
    'The arguments of the call to "${call.name}" are not a JSON object.',
    name: 'arguments',
    invalidValue: call.rawJson,
  );
}

LlamaToolResultContent _toolResult(LlamaToolCallContent call, Object? result) =>
    switch (result) {
      LlamaToolOutput(:final output, :final content) => LlamaToolResultContent(
        id: call.id,
        name: call.name,
        result: output,
        content: content,
      ),
      _ => LlamaToolResultContent(id: call.id, name: call.name, result: result),
    };

Future<Object?> _runTool(
  LlamaToolCallContent call,
  FutureOr<Object?> Function() run,
  LlamaToolErrorCallback? onToolError,
) async {
  try {
    return await run();
  } catch (error, stackTrace) {
    if (onToolError != null) return onToolError(call, error, stackTrace);
    return {'error': error is LlamaException ? error.message : '$error'};
  }
}
