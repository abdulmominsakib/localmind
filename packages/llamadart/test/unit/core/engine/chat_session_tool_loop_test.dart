import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/scripted_chat_engine.dart';

ToolDefinition _tool(String name, [ToolHandler? handler]) => ToolDefinition(
  name: name,
  description: 'The $name tool',
  parameters: [ToolParam.string('city')],
  handler: handler,
);

LlamaChatMessage _text(LlamaChatRole role, String text) =>
    LlamaChatMessage.fromText(role: role, text: text);

LlamaChatMessage _result(LlamaToolCallContent call, Object? result) =>
    LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: [
        LlamaToolResultContent(id: call.id, name: call.name, result: result),
      ],
    );

List<LlamaChatRole> _roles(Iterable<LlamaChatMessage> messages) => [
  for (final message in messages) message.role,
];

/// A [ChatSession] subclass that mirrors the history it is given.
class _PersistingSession extends ChatSession {
  _PersistingSession(super.engine) : super(maxContextTokens: 0);

  final List<LlamaChatMessage> stored = [];
  int resets = 0;

  @override
  void addMessage(LlamaChatMessage message) {
    super.addMessage(message);
    stored.add(message);
  }

  @override
  void reset({bool keepSystemPrompt = true}) {
    resets += 1;
    super.reset(keepSystemPrompt: keepSystemPrompt);
  }
}

/// A [ChatSession] subclass that stores a copy of each added message.
class _CopyingSession extends ChatSession {
  _CopyingSession(super.engine) : super(maxContextTokens: 0);

  @override
  void addMessage(LlamaChatMessage message) =>
      super.addMessage(_copyOf(message));
}

LlamaChatMessage _copyOf(LlamaChatMessage message) =>
    LlamaChatMessage.withContent(role: message.role, content: message.parts);

/// A [ChatSession] subclass whose [history] returns copies.
class _CopyingViewSession extends ChatSession {
  _CopyingViewSession(super.engine) : super(maxContextTokens: 0);

  @override
  List<LlamaChatMessage> get history =>
      List.unmodifiable(super.history.map(_copyOf));
}

/// A [_CopyingViewSession] that stores a note after each tool result.
class _NotingSession extends _CopyingViewSession {
  _NotingSession(super.engine);

  final List<LlamaChatMessage> notes = [];

  @override
  void addMessage(LlamaChatMessage message) {
    super.addMessage(message);
    if (message.role == LlamaChatRole.tool) {
      final note = _text(LlamaChatRole.system, 'note');
      notes.add(note);
      super.addMessage(note);
    }
  }
}

/// A [ChatSession] subclass that keeps only the last two messages when a
/// tool result is added.
class _WindowSession extends ChatSession {
  _WindowSession(super.engine) : super(maxContextTokens: 0);

  @override
  void addMessage(LlamaChatMessage message) {
    super.addMessage(message);
    if (message.role != LlamaChatRole.tool) return;
    final kept = history.skip(history.length - 2).toList();
    reset();
    kept.forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that keeps an app-owned note last by moving it
/// behind each added message.
class _PinningSession extends ChatSession {
  _PinningSession(super.engine) : super(maxContextTokens: 0);

  final LlamaChatMessage pinned = _text(LlamaChatRole.system, 'Pinned');

  @override
  void addMessage(LlamaChatMessage message) {
    final kept = [
      for (final stored in history)
        if (!identical(stored, pinned)) stored,
    ];
    reset();
    kept.forEach(super.addMessage);
    super.addMessage(message);
    if (!identical(message, pinned)) super.addMessage(pinned);
  }
}

/// A [ChatSession] subclass that stores copies of every message, earlier
/// ones included, on each add.
class _RewritingSession extends ChatSession {
  _RewritingSession(super.engine) : super(maxContextTokens: 0);

  @override
  void addMessage(LlamaChatMessage message) {
    final copies = history.map(_copyOf).toList();
    reset();
    copies.forEach(super.addMessage);
    super.addMessage(_copyOf(message));
  }
}

/// A [ChatSession] subclass that drops the oldest message when a tool result
/// is added, then stores the result and an audit note. With [pinsFirst] it
/// keeps its first message; with [summarizes] it puts a new summary first.
class _TrimmingSession extends ChatSession {
  _TrimmingSession(
    super.engine, {
    this.pinsFirst = false,
    this.summarizes = false,
  }) : super(maxContextTokens: 0);

  final bool pinsFirst;
  final bool summarizes;

  @override
  void addMessage(LlamaChatMessage message) {
    if (message.role != LlamaChatRole.tool) return super.addMessage(message);
    final stored = [
      for (final stored in history)
        if (!summarizes || stored.content != 'Summary') stored,
    ];
    final kept = [
      if (pinsFirst) stored.first,
      ...stored.skip(pinsFirst ? 2 : 1),
    ];
    reset();
    [
      if (summarizes) _text(LlamaChatRole.system, 'Summary'),
      ...kept,
      message,
      _text(LlamaChatRole.system, 'Audit'),
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that drops its oldest message when a tool result
/// is added, then stores the result, or a copy of it, with an audit note.
/// With [keepsLength] it drops two messages, so the history does not grow;
/// with [atFront] it stores the result and note before the kept messages;
/// with [copiesAll] it stores copies of the kept messages; with [allRoles] it
/// does this for every message, not only tool results.
class _AuditingSession extends ChatSession {
  _AuditingSession(
    super.engine, {
    this.copiesResult = false,
    this.noteFirst = false,
    this.keepsLength = false,
    this.atFront = false,
    this.copiesAll = false,
    this.allRoles = false,
  }) : super(maxContextTokens: 0);

  final bool copiesResult;
  final bool noteFirst;
  final bool keepsLength;
  final bool atFront;
  final bool copiesAll;
  final bool allRoles;

  @override
  void addMessage(LlamaChatMessage message) {
    if (!allRoles && message.role != LlamaChatRole.tool) {
      return super.addMessage(message);
    }
    final kept = [
      for (final stored in history.skip(keepsLength ? 2 : 1))
        copiesAll ? _copyOf(stored) : stored,
    ];
    final result = copiesResult ? _copyOf(message) : message;
    final note = _text(LlamaChatRole.system, 'Audit');
    reset();
    [
      if (!atFront) ...kept,
      if (noteFirst) note,
      result,
      if (!noteFirst) note,
      if (atFront) ...kept,
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that keeps an app-owned note last by replacing
/// it with a fresh copy on every add.
class _RenotingSession extends ChatSession {
  _RenotingSession(super.engine) : super(maxContextTokens: 0);

  @override
  void addMessage(LlamaChatMessage message) {
    final kept = [
      for (final stored in history)
        if (stored.content != 'Note') stored,
    ];
    reset();
    [
      ...kept,
      message,
      _text(LlamaChatRole.system, 'Note'),
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that keeps one app-owned note just ahead of the
/// newest message, storing copies of the other messages with [copies].
class _NoteAheadSession extends ChatSession {
  _NoteAheadSession(super.engine, {this.copies = false})
    : super(maxContextTokens: 0);

  final bool copies;

  @override
  void addMessage(LlamaChatMessage message) {
    final kept = [
      for (final stored in history)
        if (stored.content != 'Note') copies ? _copyOf(stored) : stored,
    ];
    reset();
    [
      ...kept,
      _text(LlamaChatRole.system, 'Note'),
      message,
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that replaces its [summarized] oldest messages
/// with a summary when a tool result, or a copy of it, is added.
class _SummarizingSession extends ChatSession {
  _SummarizingSession(
    super.engine, {
    this.summarized = 2,
    this.copiesResult = false,
    this.notes = false,
  }) : super(maxContextTokens: 0);

  final int summarized;
  final bool copiesResult;
  final bool notes;

  @override
  void addMessage(LlamaChatMessage message) {
    if (message.role != LlamaChatRole.tool) return super.addMessage(message);
    final kept = history.skip(summarized).toList();
    reset();
    [
      _text(LlamaChatRole.system, 'Summary'),
      if (notes) _text(LlamaChatRole.system, 'Note'),
      ...kept,
      copiesResult ? _copyOf(message) : message,
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that keeps one header first, replacing it with
/// a new numbered one on every add.
class _HeaderSession extends ChatSession {
  _HeaderSession(super.engine) : super(maxContextTokens: 0);

  int headers = 0;

  @override
  void addMessage(LlamaChatMessage message) {
    final kept = [
      for (final stored in history)
        if (!stored.content.startsWith('Header')) stored,
    ];
    headers += 1;
    reset();
    [
      _text(LlamaChatRole.system, 'Header $headers'),
      ...kept,
      message,
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that puts a new note first when a tool result
/// is added.
class _PrependingSession extends ChatSession {
  _PrependingSession(super.engine) : super(maxContextTokens: 0);

  @override
  void addMessage(LlamaChatMessage message) {
    if (message.role != LlamaChatRole.tool) return super.addMessage(message);
    final kept = history.toList();
    reset();
    [
      _text(LlamaChatRole.system, 'Note'),
      ...kept,
      message,
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that stores copies of every message and puts a
/// header first when a tool result is added. With [systemFirst] it also
/// moves system messages ahead of the others; with [keepsHeaders] it keeps
/// the headers it stored before.
class _CopyingHeaderSession extends ChatSession {
  _CopyingHeaderSession(
    super.engine, {
    this.systemFirst = false,
    this.keepsHeaders = false,
  }) : super(maxContextTokens: 0);

  final bool systemFirst;
  final bool keepsHeaders;

  @override
  void addMessage(LlamaChatMessage message) {
    if (message.role != LlamaChatRole.tool) return super.addMessage(message);
    final copies = [
      for (final stored in history)
        if (keepsHeaders || stored.content != 'Header') _copyOf(stored),
    ];
    if (systemFirst) {
      copies.sort(
        (a, b) =>
            (a.role == LlamaChatRole.system ? 0 : 1) -
            (b.role == LlamaChatRole.system ? 0 : 1),
      );
    }
    reset();
    [
      _text(LlamaChatRole.system, 'Header'),
      ...copies,
      _copyOf(message),
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that moves user messages ahead of the others
/// when a tool result is added.
class _UserFirstSession extends ChatSession {
  _UserFirstSession(super.engine) : super(maxContextTokens: 0);

  @override
  void addMessage(LlamaChatMessage message) {
    if (message.role != LlamaChatRole.tool) return super.addMessage(message);
    final stored = history.toList();
    reset();
    [
      ...stored.where((stored) => stored.role == LlamaChatRole.user),
      ...stored.where((stored) => stored.role != LlamaChatRole.user),
      message,
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that puts a note first when a tool result is
/// first added and, on later ones, keeps that note first and replaces the
/// oldest other message with a summary after it.
class _NoteThenSummarySession extends ChatSession {
  _NoteThenSummarySession(super.engine) : super(maxContextTokens: 0);

  @override
  void addMessage(LlamaChatMessage message) {
    if (message.role != LlamaChatRole.tool) return super.addMessage(message);
    final stored = history.toList();
    final notes = [
      for (final note in stored)
        if (note.content == 'Note') note,
    ];
    final others = [
      for (final other in stored)
        if (other.content != 'Note') other,
    ];
    reset();
    [
      if (notes.isEmpty) ...[
        _text(LlamaChatRole.system, 'Note'),
        ...others,
      ] else ...[
        notes.first,
        _text(LlamaChatRole.system, 'Summary'),
        ...others.skip(1),
      ],
      message,
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that swaps its two latest messages when a tool
/// result is added.
class _SwappingSession extends ChatSession {
  _SwappingSession(super.engine) : super(maxContextTokens: 0);

  @override
  void addMessage(LlamaChatMessage message) {
    if (message.role != LlamaChatRole.tool) return super.addMessage(message);
    final stored = history.toList();
    final last = stored.length - 1;
    reset();
    [
      ...stored.take(last - 1),
      stored[last],
      stored[last - 1],
      message,
    ].forEach(super.addMessage);
  }
}

/// A [ChatSession] subclass that stores a shared marker after each tool
/// result.
class _MarkingSession extends ChatSession {
  _MarkingSession(super.engine) : super(maxContextTokens: 0);

  static const LlamaChatMessage marker = LlamaChatMessage.fromText(
    role: LlamaChatRole.system,
    text: 'Marker',
  );

  @override
  void addMessage(LlamaChatMessage message) {
    super.addMessage(message);
    if (message.role == LlamaChatRole.tool) super.addMessage(marker);
  }
}

/// A [ChatSession] subclass that stores each tool result twice.
class _DoublingSession extends ChatSession {
  _DoublingSession(super.engine) : super(maxContextTokens: 0);

  @override
  void addMessage(LlamaChatMessage message) {
    super.addMessage(message);
    if (message.role == LlamaChatRole.tool) super.addMessage(message);
  }
}

/// A `ChatSession` that only forwards its public members, and whose [reset]
/// drops the system prompt unless told otherwise.
class _DelegatingSession implements ChatSession {
  _DelegatingSession(this._inner);

  final ChatSession _inner;

  @override
  LlamaEngine get engine => _inner.engine;

  @override
  List<LlamaChatMessage> get history => _inner.history;

  @override
  bool get lastRequestFitContext => _inner.lastRequestFitContext;

  @override
  void addMessage(LlamaChatMessage message) => _inner.addMessage(message);

  @override
  void reset({bool keepSystemPrompt = false}) =>
      _inner.reset(keepSystemPrompt: keepSystemPrompt);

  @override
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
  }) => _inner.create(
    parts,
    params: params,
    tools: tools,
    toolChoice: toolChoice,
    parallelToolCalls: parallelToolCalls,
    enableThinking: enableThinking,
    responseFormat: responseFormat,
    chatTemplateKwargs: chatTemplateKwargs,
    onMessageAdded: onMessageAdded,
    continuesPreviousTurn: continuesPreviousTurn,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A [_DelegatingSession] whose [history] returns copies.
class _CopyingDelegateSession extends _DelegatingSession {
  _CopyingDelegateSession(super.inner);

  @override
  List<LlamaChatMessage> get history =>
      List.unmodifiable(super.history.map(_copyOf));
}

/// A [_DelegatingSession] whose [history] rebuilds every message and part.
class _DeepCopyingDelegateSession extends _DelegatingSession {
  _DeepCopyingDelegateSession(super.inner);

  @override
  List<LlamaChatMessage> get history => List.unmodifiable(
    super.history.map(
      (message) => LlamaChatMessage.withContent(
        role: message.role,
        content: message.parts.map(_rebuilt).toList(),
      ),
    ),
  );

  static LlamaContentPart _rebuilt(LlamaContentPart part) => switch (part) {
    LlamaTextContent() => LlamaTextContent(part.text),
    LlamaThinkingContent() => LlamaThinkingContent(part.thinking),
    LlamaToolCallContent() => LlamaToolCallContent(
      id: part.id,
      name: part.name,
      arguments: Map.of(part.arguments),
      rawJson: part.rawJson,
    ),
    LlamaToolResultContent() => LlamaToolResultContent(
      id: part.id,
      name: part.name,
      result: part.result,
    ),
    _ => part,
  };
}

List<LlamaToolResultContent> _toolResults(ChatSession session) => [
  for (final message in session.history)
    if (message.role == LlamaChatRole.tool)
      ...message.parts.whereType<LlamaToolResultContent>(),
];

void main() {
  late ScriptedChatEngine engine;
  late ChatSession session;

  setUp(() {
    engine = ScriptedChatEngine();
    session = ChatSession(engine, maxContextTokens: 0);
  });

  test('runs a handler and returns the final answer', () async {
    engine.replies
      ..add(scriptedCalls([('call_1', 'weather', '{"city":"Seoul"}')]))
      ..add(scriptedAnswer('Sunny in Seoul.'));
    final added = <LlamaChatMessage>[];

    final result = await session.sendWithTools(
      'Weather?',
      tools: [
        _tool('weather', (params) async => {'city': params.getString('city')}),
      ],
      toolChoice: ToolChoice.required,
      onMessageAdded: added.add,
    );

    expect(result.stopReason, LlamaToolLoopStopReason.completed);
    expect(result.text, 'Sunny in Seoul.');
    expect(result.rounds, 1);
    expect(result.pendingToolCalls, isEmpty);
    expect(engine.toolChoices, [ToolChoice.required, null]);
    expect(session.history.map((message) => message.role), [
      LlamaChatRole.user,
      LlamaChatRole.assistant,
      LlamaChatRole.tool,
      LlamaChatRole.assistant,
    ]);
    expect(added.map((message) => message.role), [
      LlamaChatRole.user,
      LlamaChatRole.assistant,
      LlamaChatRole.tool,
      LlamaChatRole.assistant,
    ]);
    final toolResult = _toolResults(session).single;
    expect(toolResult.id, 'call_1');
    expect(toolResult.name, 'weather');
    expect(toolResult.result, {'city': 'Seoul'});
    // The second request continues the turn: no new user message.
    expect(engine.requests[1].last.role, LlamaChatRole.tool);
  });

  test('every round carries enableThinking and chatTemplateKwargs', () async {
    const kwargs = {'locale': 'en_CA'};
    final budgeted = ChatSession(engine, maxContextTokens: 1000);
    engine.replies
      ..add(scriptedCalls([('call_1', 'weather', '{"city":"Seoul"}')]))
      ..add(scriptedAnswer('Sunny in Seoul.'));

    final result = await budgeted.sendWithTools(
      'Weather?',
      tools: [_tool('weather', (params) async => 'sunny')],
      enableThinking: false,
      chatTemplateKwargs: kwargs,
    );

    List<List<Object?>> options(List<(bool, Map<String, dynamic>?)> calls) => [
      for (final (thinking, kwargs) in calls) [thinking, kwargs],
    ];
    expect(result.stopReason, LlamaToolLoopStopReason.completed);
    expect(options(engine.createOptions), [
      [false, kwargs],
      [false, kwargs],
    ]);
    expect(engine.templateOptions, hasLength(2));
    expect(
      options(engine.templateOptions),
      everyElement(equals([false, kwargs])),
    );
  });

  test('every round carries the session templateNow', () async {
    final now = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final budgeted = TemplateTimeChatSession(engine, maxContextTokens: 1000)
      ..templateNow = now;
    engine.replies
      ..add(scriptedCalls([('call_1', 'weather', '{"city":"Seoul"}')]))
      ..add(scriptedAnswer('Sunny in Seoul.'));

    await budgeted.sendWithTools(
      'Weather?',
      tools: [_tool('weather', (params) async => 'sunny')],
    );

    expect(engine.createTemplateNows, [now, now]);
    expect(engine.templateTemplateNows, isNotEmpty);
    expect(engine.templateTemplateNows, everyElement(now));
  });

  test('completeWithTools carries the session templateNow', () async {
    final now = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final budgeted = TemplateTimeChatSession(engine, maxContextTokens: 1000)
      ..templateNow = now;
    engine.replies.add(scriptedAnswer('Done.'));

    await budgeted.completeWithTools(
      [const LlamaTextContent('Hi')],
      tools: [_tool('weather', (params) async => 'sunny')],
    );

    expect(engine.createTemplateNows, [now]);
  });

  test('templateNow is stored per session', () {
    final a = TemplateTimeChatSession(engine)..templateNow = DateTime.utc(2026);
    final b = TemplateTimeChatSession(engine);

    expect(a.templateNow, DateTime.utc(2026));
    expect(b.templateNow, isNull);
  });

  test('runs parallel calls concurrently and records them in order', () async {
    engine.replies
      ..add(
        scriptedCalls([
          ('a', 'slow', '{"city":"A"}'),
          ('b', 'fast', '{"city":"B"}'),
        ]),
      )
      ..add(scriptedAnswer('done'));
    final slowGate = Completer<void>();
    final started = <String>[];

    final result = await session.sendWithTools(
      'Both',
      tools: [
        _tool('slow', (params) async {
          started.add('slow');
          await slowGate.future;
          return 'slow:${params.getString('city')}';
        }),
        _tool('fast', (params) async {
          started.add('fast');
          slowGate.complete();
          return 'fast:${params.getString('city')}';
        }),
      ],
      parallelToolCalls: true,
    );

    expect(result.stopReason, LlamaToolLoopStopReason.completed);
    expect(started, ['slow', 'fast']);
    expect(_toolResults(session).map((result) => (result.id, result.result)), [
      ('a', 'slow:A'),
      ('b', 'fast:B'),
    ]);
  });

  test('stops at maxRounds with the calls left unrun', () async {
    engine.replies
      ..add(scriptedCalls([('1', 'weather', '{}')]))
      ..add(scriptedCalls([('2', 'weather', '{}')]));
    var runs = 0;

    final result = await session.sendWithTools(
      'Loop',
      tools: [_tool('weather', (_) async => runs += 1)],
      maxRounds: 1,
    );

    expect(result.stopReason, LlamaToolLoopStopReason.maxRounds);
    expect(result.rounds, 1);
    expect(runs, 1);
    expect(result.pendingToolCalls.single.id, '2');
    expect(engine.requests, hasLength(2));
    expect(result.rolledBack, isTrue);
    expect(session.history, isEmpty);
    expect(_roles(result.messages), [
      LlamaChatRole.user,
      LlamaChatRole.assistant,
      LlamaChatRole.tool,
      LlamaChatRole.assistant,
    ]);
  });

  test('a rolled-back turn keeps earlier turns and can be resumed', () async {
    final earlier = [
      _text(LlamaChatRole.user, 'Hi'),
      _text(LlamaChatRole.assistant, 'Hello'),
    ];
    earlier.forEach(session.addMessage);
    engine.replies
      ..add(scriptedCalls([('1', 'weather', '{}')]))
      ..add(scriptedAnswer('Sunny.'));
    final tools = [_tool('weather', (_) async => fail('ran'))];

    final stopped = await session.sendWithTools(
      'Weather',
      tools: tools,
      maxRounds: 0,
    );

    expect(stopped.stopReason, LlamaToolLoopStopReason.maxRounds);
    expect(session.history, orderedEquals(earlier));

    stopped.messages.forEach(session.addMessage);
    session.addMessage(_result(stopped.pendingToolCalls.single, 'sunny'));
    final resumed = await session.completeWithTools(const [], tools: tools);

    expect(resumed.stopReason, LlamaToolLoopStopReason.completed);
    expect(resumed.rolledBack, isFalse);
    expect(resumed.text, 'Sunny.');
    expect(_roles(session.history), [
      LlamaChatRole.user,
      LlamaChatRole.assistant,
      LlamaChatRole.user,
      LlamaChatRole.assistant,
      LlamaChatRole.tool,
      LlamaChatRole.assistant,
    ]);
    expect(resumed.messages, orderedEquals(session.history.skip(2)));
  });

  group('a continuation', () {
    final earlier = [
      _text(LlamaChatRole.user, 'Hi'),
      _text(LlamaChatRole.assistant, 'Hello'),
    ];

    Future<List<LlamaChatMessage>> openTurn(List<ToolDefinition> tools) async {
      earlier.forEach(session.addMessage);
      engine.replies.add(scriptedCalls([('1', 'approve', '{}')]));
      final first = await session.sendWithTools('Delete it', tools: tools);
      expect(first.stopReason, LlamaToolLoopStopReason.unhandledToolCalls);
      expect(first.rolledBack, isFalse);
      session.addMessage(_result(first.pendingToolCalls.single, 'approved'));
      return session.history.skip(2).toList();
    }

    test('that stops early rolls back the whole open turn', () async {
      final tools = [_tool('approve'), _tool('weather', (_) async => 'x')];
      final open = await openTurn(tools);
      engine.replies.add(scriptedCalls([('2', 'weather', '{}')]));

      final result = await session.completeWithTools(
        const [],
        tools: tools,
        maxRounds: 0,
      );

      expect(result.stopReason, LlamaToolLoopStopReason.maxRounds);
      expect(result.rolledBack, isTrue);
      expect(session.history, orderedEquals(earlier));
      expect(result.messages.take(3), orderedEquals(open));
      expect(_roles(result.messages), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
        LlamaChatRole.tool,
        LlamaChatRole.assistant,
      ]);
    });

    test('that throws rolls back the whole open turn', () async {
      final tools = [_tool('approve')];
      await openTurn(tools);
      engine.replies.add(() => Stream.error(LlamaInferenceException('boom')));

      await expectLater(
        session.completeWithTools(const [], tools: tools),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(session.history, orderedEquals(earlier));
    });

    test('includes user-role continuations of the open turn', () async {
      final call = LlamaToolCallContent(
        id: '1',
        name: 'approve',
        arguments: const {},
        rawJson: '{}',
      );
      earlier.forEach(session.addMessage);
      session
        ..addMessage(_text(LlamaChatRole.user, 'Delete it'))
        ..addMessage(
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [call],
          ),
        )
        ..addMessage(
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'approved',
            continuesPreviousTurn: true,
          ),
        );
      engine.replies.add(scriptedCalls([('2', 'weather', '{}')]));

      final result = await session.completeWithTools(
        const [],
        tools: [_tool('weather', (_) async => 'x')],
        maxRounds: 0,
      );

      expect(result.rolledBack, isTrue);
      expect(session.history, orderedEquals(earlier));
      expect(result.messages, hasLength(4));
    });

    test('keeps an earlier turn that shares a const message', () async {
      const question = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Delete it',
      );
      const answer = LlamaChatMessage.fromText(
        role: LlamaChatRole.assistant,
        text: 'Done.',
      );
      final call = LlamaToolCallContent(
        id: '1',
        name: 'approve',
        arguments: const {},
        rawJson: '{}',
      );
      session
        ..addMessage(question)
        ..addMessage(answer)
        ..addMessage(question)
        ..addMessage(
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [call],
          ),
        )
        ..addMessage(_result(call, 'approved'));
      engine.replies.add(scriptedCalls([('2', 'weather', '{}')]));

      await session.completeWithTools(
        const [],
        tools: [_tool('weather', (_) async => 'x')],
        maxRounds: 0,
      );

      expect(session.history, orderedEquals([question, answer]));
    });

    test('of an answered turn rolls back only its own messages', () async {
      earlier.forEach(session.addMessage);
      engine.replies.add(scriptedCalls([('1', 'weather', '{}')]));

      final result = await session.completeWithTools(
        const [],
        tools: [_tool('weather', (_) async => 'x')],
        maxRounds: 0,
      );

      expect(result.rolledBack, isTrue);
      expect(session.history, orderedEquals(earlier));
      expect(_roles(result.messages), [LlamaChatRole.assistant]);
    });
  });

  test('a rollback keeps a turn another caller completed meanwhile', () async {
    engine.replies
      ..add(scriptedCalls([('1', 'weather', '{}')]))
      ..add(scriptedAnswer('Side answer'))
      ..add(scriptedCalls([('2', 'weather', '{}')]));
    var runs = 0;

    final result = await session.sendWithTools(
      'Weather',
      maxRounds: 1,
      tools: [
        _tool('weather', (_) async {
          runs += 1;
          if (runs == 1) await session.send('Side question');
          return 'sunny';
        }),
      ],
    );

    expect(result.stopReason, LlamaToolLoopStopReason.maxRounds);
    expect(session.history.map((message) => message.content), [
      'Side question',
      'Side answer',
    ]);
  });

  test('maxRounds 0 returns the first calls unrun', () async {
    engine.replies.add(scriptedCalls([('1', 'weather', '{}')]));

    final result = await session.sendWithTools(
      'Loop',
      tools: [_tool('weather', (_) async => fail('ran'))],
      maxRounds: 0,
    );

    expect(result.stopReason, LlamaToolLoopStopReason.maxRounds);
    expect(result.rounds, 0);
    expect(result.pendingToolCalls.single.name, 'weather');
    expect(session.history, isEmpty);
  });

  test('rejects a negative maxRounds before sending', () async {
    await expectLater(
      session.sendWithTools('Hi', tools: const [], maxRounds: -1),
      throwsA(
        isA<LlamaArgumentException>().having(
          (e) => e.name,
          'name',
          'maxRounds',
        ),
      ),
    );
    expect(engine.requests, isEmpty);
    expect(session.history, isEmpty);
  });

  group('a tool without a handler', () {
    test('surfaces the round and runs none of its calls', () async {
      engine.replies.add(
        scriptedCalls([
          ('a', 'weather', '{}'),
          ('b', 'approve', '{"city":"X"}'),
        ]),
      );
      var ran = false;

      final result = await session.sendWithTools(
        'Do it',
        tools: [_tool('weather', (_) async => ran = true), _tool('approve')],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.unhandledToolCalls);
      expect(ran, isFalse);
      expect(result.pendingToolCalls.map((call) => call.id), ['a', 'b']);
      expect(_toolResults(session), isEmpty);
      expect(_roles(session.history), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
      ]);
      expect(
        session.history.last.parts.whereType<LlamaToolCallContent>(),
        hasLength(2),
      );
    });

    test('continues after the caller adds the results', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'approve', '{}')]))
        ..add(scriptedAnswer('Approved.'));
      final tools = [_tool('approve')];

      final first = await session.sendWithTools('Approve', tools: tools);
      final call = first.pendingToolCalls.single;
      session.addMessage(
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            LlamaToolResultContent(id: call.id, name: call.name, result: 'ok'),
          ],
        ),
      );
      final second = await session.completeWithTools(const [], tools: tools);

      expect(second.stopReason, LlamaToolLoopStopReason.completed);
      expect(second.text, 'Approved.');
      expect(
        session.history.where((m) => m.role == LlamaChatRole.user),
        hasLength(1),
      );
    });

    test('runs onToolCall instead', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'approve', '{"city":"X"}')]))
        ..add(scriptedAnswer('ok'));
      final seen = <LlamaToolCallContent>[];

      final result = await session.sendWithTools(
        'Approve',
        tools: [_tool('approve')],
        onToolCall: (call) {
          seen.add(call);
          return 'approved ${call.arguments['city']}';
        },
      );

      expect(result.stopReason, LlamaToolLoopStopReason.completed);
      expect(seen.single.id, 'a');
      expect(_toolResults(session).single.result, 'approved X');
    });

    test('onToolCall does not replace a handler', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{"city":"X"}')]))
        ..add(scriptedAnswer('ok'));

      await session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'from handler')],
        onToolCall: (call) => fail('onToolCall ran'),
      );

      expect(_toolResults(session).single.result, 'from handler');
    });

    test('onToolCall runs a call to an unknown tool', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'missing', '{"city":"X"}')]))
        ..add(scriptedAnswer('ok'));
      final seen = <String>[];

      final result = await session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => fail('handler ran'))],
        onToolCall: (call) {
          seen.add(call.name);
          return 'from onToolCall';
        },
      );

      expect(result.stopReason, LlamaToolLoopStopReason.completed);
      expect(seen, ['missing']);
      expect(_toolResults(session).single.result, 'from onToolCall');
    });
  });

  group('tool errors', () {
    test('become the tool result by default', () async {
      engine.replies
        ..add(
          scriptedCalls([
            ('a', 'weather', '{}'),
            ('b', 'missing', '{}'),
            ('c', 'weather', '[1]'),
          ]),
        )
        ..add(scriptedAnswer('sorry'));

      final result = await session.sendWithTools(
        'Weather',
        tools: [
          _tool('weather', (params) async => params.getRequiredString('city')),
        ],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.completed);
      final results = _toolResults(session);
      expect(results.map((result) => result.id), ['a', 'b', 'c']);
      expect(results[0].result, {
        'error': contains('Required parameter "city" is missing'),
      });
      expect(results[1].result, {
        'error': 'The model called the unknown tool "missing".',
      });
      expect(results[2].result, {
        'error':
            'The arguments of the call to "weather" are not a JSON object.',
      });
    });

    test('onToolError maps the error', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(scriptedAnswer('sorry'));
      final errors = <Object>[];

      await session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => throw StateError('offline'))],
        onToolError: (call, error, stackTrace) {
          errors.add(error);
          return 'failed: ${call.name}';
        },
      );

      expect(errors.single, isA<StateError>());
      expect(_toolResults(session).single.result, 'failed: weather');
    });

    test('a rethrow from onToolError fails the loop', () async {
      engine.replies.add(
        scriptedCalls([('a', 'weather', '{}'), ('b', 'ok', '{}')]),
      );
      var okFinished = false;

      await expectLater(
        session.sendWithTools(
          'Weather',
          tools: [
            _tool('weather', (_) async => throw StateError('offline')),
            _tool('ok', (_) async {
              await Future<void>.delayed(Duration.zero);
              okFinished = true;
              return 'fine';
            }),
          ],
          onToolError: (call, error, stackTrace) =>
              Error.throwWithStackTrace(error, stackTrace),
        ),
        throwsA(isA<StateError>()),
      );

      expect(okFinished, isTrue);
      expect(session.history, isEmpty);
    });
  });

  group('a reply cut off at maxTokens', () {
    test('mid tool call rolls the turn back without an answer', () async {
      final earlier = [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ];
      earlier.forEach(session.addMessage);
      engine.replies.add(
        scriptedTruncated('<tool_call>{"name": "weather", "argu'),
      );

      final result = await session.sendWithTools(
        'Weather?',
        tools: [_tool('weather', (_) async => fail('ran'))],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.truncated);
      expect(result.completion.finishReason, LlamaFinishReason.length);
      expect(result.text, '<tool_call>{"name": "weather", "argu');
      expect(result.rounds, 0);
      expect(result.pendingToolCalls, isEmpty);
      expect(result.rolledBack, isTrue);
      expect(session.history, orderedEquals(earlier));
      expect(_roles(result.messages), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
      ]);
    });

    test('after a tool round rolls back the whole turn', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(scriptedTruncated('It is sun'));
      var runs = 0;

      final result = await session.sendWithTools(
        'Weather?',
        tools: [_tool('weather', (_) async => runs += 1)],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.truncated);
      expect(result.rounds, 1);
      expect(runs, 1);
      expect(result.rolledBack, isTrue);
      expect(session.history, isEmpty);
      expect(_roles(result.messages), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
        LlamaChatRole.tool,
        LlamaChatRole.assistant,
      ]);
    });

    test('does not run the calls it reports', () async {
      engine.replies.add(
        () => Stream.value(
          scriptedChunk(
            toolCalls: [
              LlamaCompletionChunkToolCall(
                index: 0,
                id: 'a',
                type: 'function',
                function: LlamaCompletionChunkFunction(
                  name: 'weather',
                  arguments: '{}',
                ),
              ),
            ],
            finishReason: 'length',
          ),
        ),
      );

      final result = await session.sendWithTools(
        'Weather?',
        tools: [_tool('weather', (_) async => fail('ran'))],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.truncated);
      expect(result.pendingToolCalls.single.id, 'a');
      expect(result.rolledBack, isTrue);
      expect(session.history, isEmpty);
    });
  });

  test('does not run calls proposed from a trimmed prompt', () async {
    session = ChatSession(engine, maxContextTokens: 256);
    engine.promptTokens = 10000;
    engine.replies.add(scriptedCalls([('a', 'weather', '{}')]));

    final result = await session.sendWithTools(
      'Weather',
      tools: [_tool('weather', (_) async => fail('ran'))],
    );

    expect(session.lastRequestFitContext, isFalse);
    expect(result.stopReason, LlamaToolLoopStopReason.contextExceeded);
    expect(result.pendingToolCalls.single.id, 'a');
    expect(session.history, isEmpty);
  });

  test('a rollback leaves turns trimmed for context dropped', () async {
    session = ChatSession(engine, maxContextTokens: 256);
    final note = _text(LlamaChatRole.system, 'note');
    [
      _text(LlamaChatRole.user, 'Hi'),
      _text(LlamaChatRole.assistant, 'Hello'),
    ].forEach(session.addMessage);
    engine.promptTokens = 10000;
    engine.replies.add(scriptedCalls([('a', 'weather', '{}')]));

    final result = await session.sendWithTools(
      'Weather',
      tools: [_tool('weather', (_) async => fail('ran'))],
      onMessageAdded: (message) {
        if (message.role == LlamaChatRole.user) session.addMessage(note);
      },
    );

    expect(result.stopReason, LlamaToolLoopStopReason.contextExceeded);
    expect(engine.requests.single.first.content, 'Weather');
    expect(session.history, orderedEquals([note]));
  });

  group('a reset during the loop', () {
    final oldQuestion = _text(LlamaChatRole.user, 'OLD secret question');
    final oldAnswer = _text(LlamaChatRole.assistant, 'OLD secret answer');

    setUp(() {
      session = ChatSession(engine, maxContextTokens: 256);
      session
        ..addMessage(oldQuestion)
        ..addMessage(oldAnswer);
      // The old turn no longer fits, so the first request trims it.
      engine.countFor = (messages) =>
          messages.any((message) => identical(message, oldQuestion))
          ? 10000
          : 10;
    });

    List<String?> contents() => [
      for (final message in session.history) message.content,
    ];

    test('during a tool, then maxRounds, keeps the new chat', () async {
      final fresh = _text(LlamaChatRole.user, 'New chat');
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(scriptedCalls([('b', 'weather', '{}')]));
      var runs = 0;

      final result = await session.sendWithTools(
        'Weather',
        maxRounds: 1,
        tools: [
          _tool('weather', (_) async {
            runs += 1;
            if (runs == 1) {
              session
                ..reset()
                ..addMessage(fresh);
            }
            return 'sunny';
          }),
        ],
      );

      expect(result.rolledBack, isTrue);
      expect(session.history, orderedEquals([fresh]));
    });

    test('during the next request, then an error, stays empty', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(() async* {
          session.reset();
          throw LlamaInferenceException('boom');
        });

      await expectLater(
        session.sendWithTools(
          'Weather',
          tools: [_tool('weather', (_) async => 'sunny')],
        ),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(contents(), isEmpty);
    });

    for (final during in ['a tool', 'the next request']) {
      test('with a cancel during $during stays empty', () async {
        void newChat() {
          engine.cancelGeneration();
          session.reset();
        }

        engine.replies.add(scriptedCalls([('a', 'weather', '{}')]));
        if (during == 'the next request') {
          engine.replies.add(() async* {
            newChat();
            yield scriptedChunk(content: '', finishReason: 'stop');
          });
        }

        final result = await session.sendWithTools(
          'Weather',
          tools: [
            _tool('weather', (_) async {
              if (during == 'a tool') newChat();
              return 'sunny';
            }),
          ],
        );

        expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
        expect(contents(), isNot(contains(oldQuestion.content)));
        expect(contents(), isNot(contains(oldAnswer.content)));
        if (during == 'a tool') expect(contents(), isEmpty);
      });
    }
  });

  group('cancelGeneration', () {
    test('during a tool rolls the turn back and returns its results', () async {
      engine.replies.add(scriptedCalls([('a', 'weather', '{}')]));

      final result = await session.sendWithTools(
        'Weather',
        tools: [
          _tool('weather', (_) async {
            engine.cancelGeneration();
            return 'sunny';
          }),
        ],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
      expect(result.rounds, 1);
      expect(result.pendingToolCalls, isEmpty);
      expect(engine.requests, hasLength(1));
      expect(session.history, isEmpty);
      final results = result.messages
          .expand((message) => message.parts)
          .whereType<LlamaToolResultContent>();
      expect(results.single.result, 'sunny');
    });

    test('keeps a partial answer as the turn reply', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(() async* {
          yield scriptedChunk(content: 'Sunny');
          engine.cancelGeneration();
        });

      final result = await session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
      expect(result.rolledBack, isFalse);
      expect(result.text, 'Sunny');
      expect(_roles(session.history), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
        LlamaChatRole.tool,
        LlamaChatRole.assistant,
      ]);
      expect(session.history.last.content, 'Sunny');
    });

    test('takes precedence over a cut-off reply and rolls it back', () async {
      final earlier = [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ];
      earlier.forEach(session.addMessage);
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(() async* {
          engine.cancelGeneration();
          yield scriptedChunk(content: 'It is sun', finishReason: 'length');
        });

      final result = await session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
      expect(result.completion.finishReason, LlamaFinishReason.length);
      expect(result.text, 'It is sun');
      expect(result.rounds, 1);
      expect(result.rolledBack, isTrue);
      expect(session.history, orderedEquals(earlier));
      expect(_roles(result.messages), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
        LlamaChatRole.tool,
        LlamaChatRole.assistant,
      ]);
    });

    test('reported as a stream error keeps a partial answer', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(() async* {
          yield scriptedChunk(content: 'Sun');
          engine.cancelGeneration();
          throw LlamaInferenceException('aborted');
        });

      final result = await session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
      expect(result.rolledBack, isFalse);
      expect(result.text, 'Sun');
      expect(session.history.last.content, 'Sun');
    });

    test('does not hide an error from onMessageAdded', () async {
      engine.replies.add(() async* {
        yield scriptedChunk(content: 'partial');
        engine.cancelGeneration();
      });

      await expectLater(
        session.sendWithTools(
          'Hi',
          tools: const [],
          onMessageAdded: (message) {
            if (message.role == LlamaChatRole.assistant) {
              throw StateError('persisting failed');
            }
          },
        ),
        throwsStateError,
      );
      expect(session.history, isEmpty);
    });

    test('after a stream error does not hide that error', () async {
      engine.replies.add(() async* {
        yield scriptedChunk(content: 'partial');
        throw LlamaInferenceException('boom');
      });

      await expectLater(
        session.sendWithTools(
          'Hi',
          tools: const [],
          onMessageAdded: (message) {
            if (message.role == LlamaChatRole.assistant) {
              engine.cancelGeneration();
            }
          },
        ),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(session.history, isEmpty);
    });

    test('reported as a stream error before a reply rolls back', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(() async* {
          engine.cancelGeneration();
          throw LlamaInferenceException('aborted');
        });

      final result = await session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
      expect(result.rolledBack, isTrue);
      expect(session.history, isEmpty);
    });

    test(
      'reported as a stream error before the first reply rolls back',
      () async {
        engine.replies.add(() async* {
          engine.cancelGeneration();
          throw LlamaInferenceException('aborted');
        });

        final result = await session.sendWithTools('Hi', tools: const []);

        expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
        expect(result.rolledBack, isTrue);
        expect(session.history, isEmpty);
      },
    );

    test('before the next reply starts rolls the turn back', () async {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(() async* {
          engine.cancelGeneration();
        });

      final result = await session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
      expect(result.rounds, 1);
      expect(session.history, isEmpty);
    });

    test('after an app reset removes only the loop messages', () async {
      final kept = _text(LlamaChatRole.user, 'Kept');
      engine.replies.add(scriptedCalls([('a', 'weather', '{}')]));

      await session.sendWithTools(
        'Weather',
        tools: [
          _tool('weather', (_) async {
            session
              ..reset()
              ..addMessage(kept);
            engine.cancelGeneration();
            return 'sunny';
          }),
        ],
      );

      expect(session.history, orderedEquals([kept]));
    });

    test('after an app reset during generation keeps the reset', () async {
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(session.addMessage);
      engine.replies.add(() async* {
        session.reset();
        engine.cancelGeneration();
        yield* scriptedCalls([('a', 'weather', '{}')])();
      });

      await session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => fail('ran'))],
      );

      expect(session.history, isEmpty);
    });

    test('during generation stops without running calls', () async {
      engine.replies.add(() async* {
        engine.cancelGeneration();
        yield* scriptedCalls([('a', 'weather', '{}')])();
      });

      final result = await session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => fail('ran'))],
      );

      expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
      expect(result.rounds, 0);
      expect(result.pendingToolCalls.single.id, 'a');
      expect(session.history, isEmpty);
    });

    test('issued before the loop does not affect it', () async {
      engine.cancelGeneration();
      engine.replies.add(scriptedAnswer('hi'));

      final result = await session.sendWithTools('Hi', tools: const []);

      expect(result.stopReason, LlamaToolLoopStopReason.completed);
      expect(result.text, 'hi');
    });
  });

  test('an error from create fails the loop', () async {
    engine.replies.add(() => Stream.error(LlamaInferenceException('boom')));

    await expectLater(
      session.sendWithTools('Hi', tools: const []),
      throwsA(isA<LlamaInferenceException>()),
    );
    expect(session.history, isEmpty);
  });

  test('an error in a later round rolls the turn back', () async {
    engine.replies
      ..add(scriptedCalls([('a', 'weather', '{}')]))
      ..add(() async* {
        yield scriptedChunk(content: 'Sun');
        throw LlamaInferenceException('boom');
      });
    final added = <LlamaChatMessage>[];

    await expectLater(
      session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
        onMessageAdded: added.add,
      ),
      throwsA(isA<LlamaInferenceException>()),
    );
    expect(session.history, isEmpty);
    expect(_roles(added), [
      LlamaChatRole.user,
      LlamaChatRole.assistant,
      LlamaChatRole.tool,
      LlamaChatRole.assistant,
    ]);
  });

  test(
    'a rollback does not replay a subclass\'s addMessage or reset',
    () async {
      final persisting = _PersistingSession(engine);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(persisting.addMessage);
      engine.replies.add(scriptedCalls([('a', 'weather', '{}')]));

      final result = await persisting.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => fail('ran'))],
        maxRounds: 0,
      );

      expect(result.rolledBack, isTrue);
      expect(persisting.history, hasLength(2));
      expect(persisting.stored, hasLength(2));
      expect(persisting.resets, 0);
    },
  );

  test('a rollback removes the copies a subclass stored', () async {
    final copying = _CopyingSession(engine);
    engine.replies.add(scriptedCalls([('a', 'weather', '{}')]));

    final result = await copying.sendWithTools(
      'Weather',
      tools: [
        _tool('weather', (_) async {
          engine.cancelGeneration();
          return 'sunny';
        }),
      ],
    );

    expect(result.rolledBack, isTrue);
    expect(copying.history, isEmpty);
  });

  group('a rollback on a subclass', () {
    Future<LlamaToolLoopResult> stopAtMaxRounds(ChatSession session) {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(scriptedCalls([('b', 'weather', '{}')]));
      return session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
        maxRounds: 1,
      );
    }

    test('whose history returns copies removes the turn', () async {
      final viewing = _CopyingViewSession(engine);

      final result = await stopAtMaxRounds(viewing);

      expect(result.rolledBack, isTrue);
      expect(viewing.history, isEmpty);
    });

    test('removes what its addMessage appended after a result', () async {
      final noting = _NotingSession(engine);

      final result = await stopAtMaxRounds(noting);

      expect(result.rolledBack, isTrue);
      expect(noting.history, isEmpty);
      expect(noting.notes, hasLength(1));
      expect(_roles(result.messages), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
        LlamaChatRole.tool,
        LlamaChatRole.assistant,
      ]);
    });

    test('whose addMessage moves an earlier message keeps it', () async {
      final pinning = _PinningSession(engine);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(pinning.addMessage);

      final result = await stopAtMaxRounds(pinning);

      expect(result.rolledBack, isTrue);
      expect(
        [for (final message in pinning.history) message.content],
        ['Hi', 'Hello', 'Pinned'],
      );
      expect(pinning.history.last, same(pinning.pinned));
    });

    test('whose addMessage copies earlier messages keeps them', () async {
      final rewriting = _RewritingSession(engine);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(rewriting.addMessage);

      final result = await stopAtMaxRounds(rewriting);

      expect(result.rolledBack, isTrue);
      expect(
        [for (final message in rewriting.history) message.content],
        ['Hi', 'Hello'],
      );
    });

    test('whose addMessage copies earlier messages keeps an earlier turn '
        'with an equal result', () async {
      final rewriting = _RewritingSession(engine);
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(scriptedAnswer('Done'));
      await rewriting.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
      );
      final before = [for (final message in rewriting.history) message.content];

      final result = await stopAtMaxRounds(rewriting);

      expect(result.rolledBack, isTrue);
      expect([
        for (final message in rewriting.history) message.content,
      ], before);
      expect(_roles(rewriting.history), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
        LlamaChatRole.tool,
        LlamaChatRole.assistant,
      ]);
    });

    for (final copies in [false, true]) {
      test(
        'whose addMessage moves a fresh note ahead of each message'
        '${copies ? ' and copies the others' : ''} removes the note',
        () async {
          final noting = _NoteAheadSession(engine, copies: copies);
          [
            _text(LlamaChatRole.user, 'Hi'),
            _text(LlamaChatRole.assistant, 'Hello'),
          ].forEach(noting.addMessage);

          final result = await stopAtMaxRounds(noting);

          expect(result.rolledBack, isTrue);
          expect(
            [for (final message in noting.history) message.content],
            ['Hi', 'Hello'],
          );
        },
      );
    }

    for (final (description, session, first) in [
      (
        'drops an earlier equal note first',
        (LlamaEngine engine) => _TrimmingSession(engine),
        <String>[],
      ),
      (
        'pins its first message and drops an earlier equal note after it',
        (LlamaEngine engine) => _TrimmingSession(engine, pinsFirst: true),
        ['Pinned'],
      ),
      (
        'puts a new summary first and drops an earlier equal note after it',
        (LlamaEngine engine) => _TrimmingSession(engine, summarizes: true),
        ['Summary'],
      ),
    ]) {
      test(
        'whose addMessage $description removes the note it appended',
        () async {
          final trimming = session(engine);
          [
            for (final text in first) _text(LlamaChatRole.system, text),
            _text(LlamaChatRole.system, 'Audit'),
            _text(LlamaChatRole.user, 'Hi'),
            _text(LlamaChatRole.assistant, 'Hello'),
          ].forEach(trimming.addMessage);

          final result = await stopAtMaxRounds(trimming);

          expect(result.rolledBack, isTrue);
          expect(
            [for (final message in trimming.history) message.content],
            [...first, 'Hi', 'Hello'],
          );
        },
      );
    }

    for (final pinsFirst in [false, true]) {
      test('whose addMessage drops the oldest message'
          '${pinsFirst ? ' after a pinned one' : ''} ends with the last reply '
          'after completed tool turns', () async {
        final trimming = _TrimmingSession(engine, pinsFirst: pinsFirst);
        if (pinsFirst) {
          trimming.addMessage(_text(LlamaChatRole.system, 'Pinned'));
        }
        final tools = [_tool('weather', (_) async => 'sunny')];
        for (var turn = 0; turn < 3; turn++) {
          engine.replies
            ..add(scriptedCalls([('a$turn', 'weather', '{}')]))
            ..add(scriptedAnswer('Done $turn'));
          await trimming.sendWithTools('Weather $turn', tools: tools);
        }
        expect(trimming.history[pinsFirst ? 1 : 0].content, 'Audit');

        final result = await stopAtMaxRounds(trimming);

        expect(result.rolledBack, isTrue);
        expect(trimming.history.last.content, 'Done 2');
      });
    }

    test('whose addMessage drops the oldest message removes the note it '
        'appended', () async {
      final trimming = _TrimmingSession(engine);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(trimming.addMessage);

      final result = await stopAtMaxRounds(trimming);

      expect(result.rolledBack, isTrue);
      expect(
        [for (final message in trimming.history) message.content],
        ['Hello'],
      );
    });

    for (final (description, session) in [
      (
        'stores a copy of the result removes the copy and the note',
        (LlamaEngine engine) => _AuditingSession(engine, copiesResult: true),
      ),
      (
        'stores a note before the result removes the note',
        (LlamaEngine engine) => _AuditingSession(engine, noteFirst: true),
      ),
      (
        'stores a copy of the result and the note first removes both',
        (LlamaEngine engine) =>
            _AuditingSession(engine, copiesResult: true, atFront: true),
      ),
      (
        'stores copies and a note before the result removes the note',
        (LlamaEngine engine) =>
            _AuditingSession(engine, copiesAll: true, noteFirst: true),
      ),
    ]) {
      test(
        'whose addMessage drops the oldest message and $description',
        () async {
          final auditing = session(engine);
          [
            _text(LlamaChatRole.user, 'Hi'),
            _text(LlamaChatRole.assistant, 'Hello'),
          ].forEach(auditing.addMessage);

          final result = await stopAtMaxRounds(auditing);

          expect(result.rolledBack, isTrue);
          expect(
            [for (final message in auditing.history) message.content],
            ['Hello'],
          );
        },
      );
    }

    test('whose addMessage drops the turn\'s first messages and stores a note '
        'before the result removes the note', () async {
      final windowed = _AuditingSession(
        engine,
        keepsLength: true,
        noteFirst: true,
      );

      final result = await stopAtMaxRounds(windowed);

      expect(result.rolledBack, isTrue);
      expect(windowed.history, isEmpty);
    });

    test(
      'whose addMessage keeps the length removes the note it appended',
      () async {
        final windowed = _AuditingSession(engine, keepsLength: true);
        [
          _text(LlamaChatRole.user, 'Hi'),
          _text(LlamaChatRole.assistant, 'Hello'),
        ].forEach(windowed.addMessage);

        final result = await stopAtMaxRounds(windowed);

        expect(result.rolledBack, isTrue);
        expect(windowed.history, isEmpty);
      },
    );

    test(
      'whose addMessage replaces a note with a copy removes the copy',
      () async {
        final renoting = _RenotingSession(engine);
        [
          _text(LlamaChatRole.user, 'Hi'),
          _text(LlamaChatRole.assistant, 'Hello'),
        ].forEach(renoting.addMessage);

        final result = await stopAtMaxRounds(renoting);

        expect(result.rolledBack, isTrue);
        expect(
          [for (final message in renoting.history) message.content],
          ['Hi', 'Hello'],
        );
      },
    );

    for (final (description, session, kept) in [
      (
        'summarizes earlier turns',
        (LlamaEngine engine) => _SummarizingSession(engine),
        ['Summary'],
      ),
      (
        'summarizes the oldest message while the history grows',
        (LlamaEngine engine) => _SummarizingSession(engine, summarized: 1),
        ['Summary', 'Hello'],
      ),
      (
        'summarizes the oldest message and stores a copy of the result',
        (LlamaEngine engine) =>
            _SummarizingSession(engine, summarized: 1, copiesResult: true),
        ['Summary', 'Hello'],
      ),
      (
        'summarizes the oldest message and adds a note after the summary',
        (LlamaEngine engine) =>
            _SummarizingSession(engine, summarized: 1, notes: true),
        ['Summary', 'Hello'],
      ),
    ]) {
      test('whose addMessage $description keeps the summary', () async {
        final summarizing = session(engine);
        [
          _text(LlamaChatRole.user, 'Hi'),
          _text(LlamaChatRole.assistant, 'Hello'),
        ].forEach(summarizing.addMessage);

        final result = await stopAtMaxRounds(summarizing);

        expect(result.rolledBack, isTrue);
        expect([
          for (final message in summarizing.history) message.content,
        ], kept);
      });
    }

    test('whose addMessage puts a summary after a note it added in an earlier '
        'round keeps the summary', () async {
      final summarizing = _NoteThenSummarySession(engine);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(summarizing.addMessage);
      for (var round = 0; round <= 2; round++) {
        engine.replies.add(scriptedCalls([('c$round', 'weather', '{}')]));
      }

      final result = await summarizing.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
        maxRounds: 2,
      );

      expect(result.rolledBack, isTrue);
      expect(
        [for (final message in summarizing.history) message.content],
        ['Summary', 'Hello'],
      );
    });

    test('whose addMessage copies earlier messages and adds another equal '
        'header removes the new one', () async {
      final heading = _CopyingHeaderSession(engine, keepsHeaders: true);
      [
        _text(LlamaChatRole.system, 'Header'),
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(heading.addMessage);

      final result = await stopAtMaxRounds(heading);

      expect(result.rolledBack, isTrue);
      expect(
        [for (final message in heading.history) message.content],
        ['Header', 'Hi', 'Hello'],
      );
    });

    test('whose addMessage copies earlier messages, moves system messages '
        'first and adds a header keeps the copies', () async {
      final heading = _CopyingHeaderSession(engine, systemFirst: true);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.system, 'Rule'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(heading.addMessage);

      final result = await stopAtMaxRounds(heading);

      expect(result.rolledBack, isTrue);
      expect(
        [for (final message in heading.history) message.content],
        ['Rule', 'Hi', 'Hello'],
      );
    });

    for (final rounds in [1, 2]) {
      test('whose addMessage copies earlier messages and adds a header keeps '
          'the copies and removes the header after $rounds rounds', () async {
        final heading = _CopyingHeaderSession(engine);
        [
          _text(LlamaChatRole.user, 'Hi'),
          _text(LlamaChatRole.assistant, 'Hello'),
        ].forEach(heading.addMessage);
        for (var round = 0; round <= rounds; round++) {
          engine.replies.add(scriptedCalls([('c$round', 'weather', '{}')]));
        }

        final result = await heading.sendWithTools(
          'Weather',
          tools: [_tool('weather', (_) async => 'sunny')],
          maxRounds: rounds,
        );

        expect(result.rolledBack, isTrue);
        expect(
          [for (final message in heading.history) message.content],
          ['Hi', 'Hello'],
        );
      });
    }

    test(
      'whose addMessage replaces a header first keeps the latest header',
      () async {
        final heading = _HeaderSession(engine);
        [
          _text(LlamaChatRole.user, 'Hi'),
          _text(LlamaChatRole.assistant, 'Hello'),
        ].forEach(heading.addMessage);

        final result = await stopAtMaxRounds(heading);

        expect(result.rolledBack, isTrue);
        expect(
          [for (final message in heading.history) message.content],
          ['Header ${heading.headers}', 'Hi', 'Hello'],
        );
      },
    );

    test('whose addMessage puts a new note first removes the note', () async {
      final prepending = _PrependingSession(engine);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(prepending.addMessage);

      final result = await stopAtMaxRounds(prepending);

      expect(result.rolledBack, isTrue);
      expect(
        [for (final message in prepending.history) message.content],
        ['Hi', 'Hello'],
      );
    });

    test('removes an instance its addMessage appended that an earlier turn '
        'holds, and keeps the earlier one', () async {
      final marking = _MarkingSession(engine);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _MarkingSession.marker,
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(marking.addMessage);

      final result = await stopAtMaxRounds(marking);

      expect(result.rolledBack, isTrue);
      expect(
        [for (final message in marking.history) message.content],
        ['Hi', 'Marker', 'Hello'],
      );
      expect(marking.history[1], same(_MarkingSession.marker));
    });

    test('whose addMessage stores a result twice removes both', () async {
      final doubling = _DoublingSession(engine);

      final result = await stopAtMaxRounds(doubling);

      expect(result.rolledBack, isTrue);
      expect(doubling.history, isEmpty);
    });

    test('whose history returns copies rolls back a continued turn', () async {
      final viewing = _CopyingViewSession(engine);
      final call = LlamaToolCallContent(
        id: '1',
        name: 'approve',
        arguments: const {},
        rawJson: '{}',
      );
      [
        _text(LlamaChatRole.user, 'Delete it'),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [call],
        ),
        _result(call, 'approved'),
      ].forEach(viewing.addMessage);
      engine.replies.add(scriptedCalls([('2', 'weather', '{}')]));

      final result = await viewing.completeWithTools(
        const [],
        tools: [_tool('weather', (_) async => 'sunny')],
        maxRounds: 0,
      );

      expect(result.rolledBack, isTrue);
      expect(viewing.history, isEmpty);
      expect(_roles(result.messages), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
        LlamaChatRole.tool,
        LlamaChatRole.assistant,
      ]);
    });

    test('whose addMessage shrinks the history removes the turn', () async {
      final windowed = _WindowSession(engine);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(windowed.addMessage);

      final result = await stopAtMaxRounds(windowed);

      expect(result.stopReason, LlamaToolLoopStopReason.maxRounds);
      expect(result.rolledBack, isTrue);
      expect(windowed.history, isEmpty);
    });
  });

  test('runs on a class that implements ChatSession', () async {
    engine.replies
      ..add(scriptedCalls([('a', 'weather', '{}')]))
      ..add(scriptedCalls([('b', 'weather', '{}')]));
    session.systemPrompt = 'Be brief.';
    final delegate = _DelegatingSession(session);

    final result = await delegate.sendWithTools(
      'Weather',
      tools: [_tool('weather', (_) async => 'sunny')],
      maxRounds: 1,
    );

    expect(result.stopReason, LlamaToolLoopStopReason.maxRounds);
    expect(session.history, isEmpty);
    expect(session.systemPrompt, 'Be brief.');
  });

  test('a class that implements ChatSession over an addMessage that stores '
      'copies rolls the copies back', () async {
    final copying = _CopyingSession(engine);
    [
      _text(LlamaChatRole.user, 'Hi'),
      _text(LlamaChatRole.assistant, 'Hello'),
    ].forEach(copying.addMessage);
    final delegate = _DelegatingSession(copying);
    engine.replies
      ..add(scriptedCalls([('a', 'weather', '{}')]))
      ..add(scriptedCalls([('b', 'weather', '{}')]));

    final result = await delegate.sendWithTools(
      'Weather',
      tools: [_tool('weather', (_) async => 'sunny')],
      maxRounds: 1,
    );

    expect(result.stopReason, LlamaToolLoopStopReason.maxRounds);
    expect(result.rolledBack, isTrue);
    expect(_roles(result.messages), [
      LlamaChatRole.user,
      LlamaChatRole.assistant,
      LlamaChatRole.tool,
      LlamaChatRole.assistant,
    ]);
    expect(_toolResults(copying), isEmpty);
    expect(
      [for (final message in copying.history) message.content],
      ['Hi', 'Hello'],
    );
  });

  test('a class that implements ChatSession keeps an equal message another '
      'caller added meanwhile', () async {
    final sideQuestion = _text(LlamaChatRole.user, 'Weather');
    final sideAnswer = _text(LlamaChatRole.assistant, 'Side answer');
    engine.replies
      ..add(scriptedCalls([('a', 'weather', '{}')]))
      ..add(scriptedCalls([('b', 'weather', '{}')]));

    final result = await _DelegatingSession(session).sendWithTools(
      'Weather',
      tools: [
        _tool('weather', (_) async {
          session
            ..addMessage(sideQuestion)
            ..addMessage(sideAnswer);
          return 'sunny';
        }),
      ],
      maxRounds: 1,
    );

    expect(result.rolledBack, isTrue);
    expect(session.history, orderedEquals([sideQuestion, sideAnswer]));
  });

  group('a class that implements ChatSession whose history returns copies', () {
    final call = LlamaToolCallContent(
      id: '1',
      name: 'approve',
      arguments: const {},
      rawJson: '{}',
    );

    List<String> contents(ChatSession session) => [
      for (final message in session.history) message.content,
    ];

    Future<LlamaToolLoopResult> stopAtMaxRounds(ChatSession session) {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(scriptedCalls([('b', 'weather', '{}')]));
      return session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
        maxRounds: 1,
      );
    }

    test('rolls back a continued turn', () async {
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
        _text(LlamaChatRole.user, 'Delete it'),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [call],
        ),
        _result(call, 'approved'),
      ].forEach(session.addMessage);
      engine.replies.add(scriptedCalls([('2', 'weather', '{}')]));

      final result = await _CopyingDelegateSession(session).completeWithTools(
        const [],
        tools: [_tool('weather', (_) async => 'sunny')],
        maxRounds: 0,
      );

      expect(result.rolledBack, isTrue);
      expect(contents(session), ['Hi', 'Hello']);
      expect(_roles(result.messages), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
        LlamaChatRole.tool,
        LlamaChatRole.assistant,
      ]);
    });

    test('rolls back a new turn', () async {
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(session.addMessage);

      final result = await stopAtMaxRounds(_CopyingDelegateSession(session));

      expect(result.rolledBack, isTrue);
      expect(contents(session), ['Hi', 'Hello']);
    });

    test('keeps an earlier turn with the same content', () async {
      [
        _text(LlamaChatRole.user, 'Weather'),
        _text(LlamaChatRole.assistant, 'Sunny.'),
      ].forEach(session.addMessage);

      final result = await stopAtMaxRounds(_CopyingDelegateSession(session));

      expect(result.rolledBack, isTrue);
      expect(contents(session), ['Weather', 'Sunny.']);
    });

    for (final (description, wrapped) in [
      ('', (ChatSession session) => session),
      (
        ' when its addMessage moves a note last',
        (ChatSession session) => _RenotingSession(session.engine),
      ),
      (
        ' when its addMessage swaps the turn\'s messages',
        (ChatSession session) => _SwappingSession(session.engine),
      ),
      (
        ' when its addMessage moves the user messages first',
        (ChatSession session) => _UserFirstSession(session.engine),
      ),
    ]) {
      test(
        'keeps an earlier tool turn with the same content$description',
        () async {
          final inner = wrapped(session);
          final copying = _CopyingDelegateSession(inner);
          engine.replies
            ..add(scriptedCalls([('a', 'weather', '{}')]))
            ..add(scriptedAnswer('Done'));
          await copying.sendWithTools(
            'Weather',
            tools: [_tool('weather', (_) async => 'sunny')],
          );
          final before = [
            for (final message in inner.history)
              (message.role, message.content, message.parts.length),
          ];

          final result = await stopAtMaxRounds(copying);

          expect(result.rolledBack, isTrue);
          // Rebuilding through this addMessage moves the note last again.
          expect([
            for (final message in inner.history)
              (message.role, message.content, message.parts.length),
          ], unorderedEquals(before));
        },
      );
    }

    test('keeps earlier messages that repeat each other', () async {
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(session.addMessage);

      final result = await stopAtMaxRounds(_CopyingDelegateSession(session));

      expect(result.rolledBack, isTrue);
      expect(contents(session), ['Hi', 'Hello', 'Hi', 'Hello']);
    });

    test('rolls back the note its addMessage moves after the result', () async {
      final renoting = _RenotingSession(engine);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(renoting.addMessage);

      final result = await stopAtMaxRounds(_CopyingDelegateSession(renoting));

      expect(result.rolledBack, isTrue);
      // The rollback rebuilds through this addMessage, which adds one note.
      expect(contents(renoting), ['Hi', 'Hello', 'Note']);
    });

    test(
      'rolls back the notes its addMessage puts first over two rounds',
      () async {
        final prepending = _PrependingSession(engine);
        [
          _text(LlamaChatRole.user, 'Hi'),
          _text(LlamaChatRole.assistant, 'Hello'),
        ].forEach(prepending.addMessage);
        for (var round = 0; round <= 2; round++) {
          engine.replies.add(scriptedCalls([('c$round', 'weather', '{}')]));
        }

        final result = await _CopyingDelegateSession(prepending).sendWithTools(
          'Weather',
          tools: [_tool('weather', (_) async => 'sunny')],
          maxRounds: 2,
        );

        expect(result.rolledBack, isTrue);
        expect(contents(prepending), ['Hi', 'Hello']);
      },
    );

    test('keeps earlier messages its addMessage moves after a system message '
        'it moves first', () async {
      final heading = _CopyingHeaderSession(engine, systemFirst: true);
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
        _text(LlamaChatRole.system, 'Rule'),
      ].forEach(heading.addMessage);

      final result = await stopAtMaxRounds(_CopyingDelegateSession(heading));

      expect(result.rolledBack, isTrue);
      expect(contents(heading), ['Rule', 'Hi', 'Hello']);
    });

    test('rolls back two rounds of an addMessage that drops the oldest '
        'message and puts a note before each message', () async {
      final auditing = _AuditingSession(
        engine,
        noteFirst: true,
        allRoles: true,
      );
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(auditing.addMessage);
      for (var round = 0; round <= 2; round++) {
        engine.replies.add(scriptedCalls([('c$round', 'weather', '{}')]));
      }

      final result = await _CopyingDelegateSession(auditing).sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
        maxRounds: 2,
      );

      expect(result.rolledBack, isTrue);
      // The rollback rebuilds through this addMessage, which adds one note.
      expect(contents(auditing), ['Audit', 'Hello']);
    });

    test('rolls back a turn whose parts are rebuilt on each read', () async {
      [
        _text(LlamaChatRole.user, 'Hi'),
        _text(LlamaChatRole.assistant, 'Hello'),
      ].forEach(session.addMessage);

      final result = await stopAtMaxRounds(
        _DeepCopyingDelegateSession(session),
      );

      expect(result.rolledBack, isTrue);
      expect(contents(session), ['Hi', 'Hello']);
    });

    Future<LlamaToolLoopResult> addDuringLoop(
      ChatSession delegate,
      LlamaChatMessage added,
    ) {
      engine.replies
        ..add(scriptedCalls([('a', 'weather', '{}')]))
        ..add(scriptedCalls([('b', 'weather', '{}')]));
      return delegate.sendWithTools(
        'Weather',
        tools: [
          _tool('weather', (_) async {
            session.addMessage(added);
            return 'sunny';
          }),
        ],
        maxRounds: 1,
      );
    }

    test('keeps a message of the same role but other content that another '
        'caller added meanwhile', () async {
      final added = _text(LlamaChatRole.user, 'Forecast');

      final result = await addDuringLoop(
        _DeepCopyingDelegateSession(session),
        added,
      );

      expect(result.rolledBack, isTrue);
      expect(_roles(session.history), [LlamaChatRole.user]);
      expect(contents(session), ['Forecast']);
    });

    test('keeps a message of the same content but another role that '
        'another caller added meanwhile', () async {
      final added = _text(LlamaChatRole.assistant, 'Weather');

      final result = await addDuringLoop(
        _DeepCopyingDelegateSession(session),
        added,
      );

      expect(result.rolledBack, isTrue);
      expect(_roles(session.history), [LlamaChatRole.assistant]);
      expect(contents(session), ['Weather']);
    });

    test('removes what its addMessage appended after a result, and keeps '
        'an earlier equal result', () async {
      final noting = _NotingSession(engine);
      final delegate = _DelegatingSession(noting);
      final earlierCall = LlamaToolCallContent(
        id: 'a',
        name: 'weather',
        arguments: const {},
        rawJson: '{}',
      );
      [
        _text(LlamaChatRole.user, 'Weather'),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [earlierCall],
        ),
        _result(earlierCall, 'sunny'),
        _text(LlamaChatRole.assistant, 'Sunny.'),
      ].forEach(delegate.addMessage);

      final result = await stopAtMaxRounds(delegate);

      expect(result.rolledBack, isTrue);
      expect(_toolResults(noting).single.id, 'a');
      expect(noting.history.last.content, 'Sunny.');
    });
  });

  test('completeWithTools sends media parts as the user turn', () async {
    engine.replies.add(scriptedAnswer('A cat.'));

    final result = await session.completeWithTools([
      const LlamaTextContent('What is this?'),
      LlamaImageContent(url: 'https://example.com/cat.png'),
    ], tools: const []);

    expect(result.text, 'A cat.');
    expect(session.history.first.parts, hasLength(2));
  });

  group('a rollback on a long history', () {
    const earlier = 10000;

    void fill(ChatSession session) {
      for (var index = 0; index < earlier; index += 2) {
        session.addMessage(_text(LlamaChatRole.user, 'Question $index'));
        session.addMessage(_text(LlamaChatRole.assistant, 'Answer $index'));
      }
    }

    Future<LlamaToolLoopResult> stopAtMaxRounds(ChatSession session) {
      for (var round = 0; round <= 3; round++) {
        engine.replies.add(scriptedCalls([('c$round', 'weather', '{}')]));
      }
      return session.sendWithTools(
        'Weather',
        tools: [_tool('weather', (_) async => 'sunny')],
        maxRounds: 3,
      );
    }

    test('of a subclass whose addMessage trims keeps the rest', () async {
      final trimming = _TrimmingSession(engine);
      fill(trimming);
      final before = [for (final message in trimming.history) message.content];

      final result = await stopAtMaxRounds(trimming);

      expect(result.rolledBack, isTrue);
      expect([
        for (final message in trimming.history) message.content,
      ], before.skip(3));
    });

    test('of a subclass whose addMessage copies every message keeps the '
        'copies', () async {
      final heading = _CopyingHeaderSession(engine);
      fill(heading);
      final before = [for (final message in heading.history) message.content];

      final result = await stopAtMaxRounds(heading);

      expect(result.rolledBack, isTrue);
      expect([for (final message in heading.history) message.content], before);
    });

    test('of a class that implements ChatSession whose history returns '
        'copies keeps it', () async {
      final copying = _CopyingDelegateSession(session);
      fill(copying);
      final before = [for (final message in session.history) message.content];

      final result = await stopAtMaxRounds(copying);

      expect(result.rolledBack, isTrue);
      expect([for (final message in session.history) message.content], before);
    });
  });
}
