import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_handler.dart';
import 'package:test/test.dart';

import '../../../support/scripted_chat_engine.dart';

const _opening = '<|tool_call_start|>';
const _closing = '<|tool_call_end|>';
const _tool = ToolDefinition(
  name: 'weather',
  description: 'Weather',
  parameters: [],
);

Stream<LlamaCompletionChunk> _parse(
  List<String> chunks, {
  bool length = true,
  bool cancel = false,
  bool enabled = true,
  bool forcedOpen = false,
  List<ToolDefinition> tools = const [_tool],
}) => ChatCompletionStreamParser.parse(
  tokenStream: Stream.fromIterable(chunks),
  templateResult: LlamaChatTemplateResult(
    prompt: 'prompt',
    format: ChatFormat.lfm2.index,
    thinkingForcedOpen: forcedOpen,
  ),
  parseToolCallsEnabled: enabled,
  enableThinking: true,
  modelName: 'lfm2',
  completionId: 'partial',
  tools: tools,
  stoppedAtLimit: () => length,
  cancelled: () => cancel,
);

void main() {
  final samples = <(String, List<(String, String)>)>[
    ('[weather(city="Montréal 🌧', [('weather', 'city="Montréal 🌧')]),
    ('[{"name":"weather","arguments":', [('weather', '')]),
    ('[weather(', [('weather', '')]),
    ('[weather(city=', [('weather', 'city=')]),
    ('[weather(city="Par', [('weather', 'city="Par')]),
    ('[unknown(city={"a":[1,', [('unknown', 'city={"a":[1,')]),
    (
      '[weather(city="literal $_closing still quoted',
      [('weather', 'city="literal $_closing still quoted')],
    ),
    (r'[weather(city="a\"b\\', [('weather', r'city="a\"b\\')]),
    ('[weather(city="last )', [('weather', 'city="last )')]),
    (
      '[weather(city="Paris"), unknown(data=[1,',
      [('weather', 'city="Paris"'), ('unknown', 'data=[1,')],
    ),
    (
      '[{"name":"weather","arguments": {"city":"Par',
      [('weather', ' {"city":"Par')],
    ),
    (
      '[{"id":"raw-id","type":"function","function":{"name":"unknown",'
          '"arguments":{"n":[1,',
      [('unknown', '{"n":[1,')],
    ),
    (
      '[{"name":"weather","arguments":{}},{"name":"unknown","arguments":[1,',
      [('weather', '{}'), ('unknown', '[1,')],
    ),
  ];

  for (final (payload, expected) in samples) {
    test(
      'length preserves raw argument stages and every split: $payload',
      () async {
        final output = '<think>Plan.</think>Before.$_opening$payload';
        final partitions = <List<String>>[
          [output],
          output.split(''),
          for (var i = 0; i <= output.length; i++)
            [output.substring(0, i), output.substring(i)],
        ];
        for (final parts in partitions) {
          final chunks = await _parse(parts).toList();
          final completion = await Stream.fromIterable(chunks).collect();
          expect(completion.text, 'Before.', reason: '$parts');
          expect(completion.thinking, 'Plan.');
          expect(completion.finishReason, LlamaFinishReason.length);
          expect(completion.toolCalls, isEmpty);
          expect(
            completion.partialToolCalls.map(
              (c) => (c.function!.name, c.function!.arguments),
            ),
            expected,
          );
          expect(
            completion.partialToolCalls.map((c) => c.index),
            List.generate(expected.length, (i) => i),
          );
          expect(
            chunks.take(chunks.length - 1).expand((c) => c.partialToolCalls),
            isEmpty,
          );
          expect(chunks.last.partialToolCalls, hasLength(expected.length));
          expect(
            completion.partialToolCalls.map((c) => c.id),
            List.generate(
              expected.length,
              (i) => payload.contains('raw-id') ? 'raw-id' : null,
            ),
          );

          expect(
            completion.message.parts.whereType<LlamaToolCallContent>(),
            isEmpty,
          );
          expect(completion.message.content, 'Before.');
          final roundTrip = LlamaCompletionChunk.fromJson(
            jsonDecode(jsonEncode(chunks.last.toJson())),
          );
          expect(roundTrip.toJson(), chunks.last.toJson());
          expect(
            roundTrip.partialToolCalls.map(
              (c) => (c.function!.name, c.function!.arguments),
            ),
            expected,
          );
        }
      },
    );
  }

  test('partial parse messages never decode diagnostic arguments', () {
    final parsed = Lfm2Handler().parse(
      'Before.$_opening[weather(city="invalid',
      isPartial: true,
    );
    expect(parsed.partialToolCalls.single.function!.arguments, 'city="invalid');
    expect(
      parsed.toAssistantMessage().parts.whereType<LlamaToolCallContent>(),
      isEmpty,
    );
  });

  test(
    'forced-open thought closure preserves preceding reasoning and answer',
    () async {
      final reply = await _parse(
        'Plan.</think>Before.$_opening[weather(city="cut'.split(''),
        forcedOpen: true,
      ).collect();
      expect(reply.thinking, 'Plan.');
      expect(reply.text, 'Before.');
      expect(reply.partialToolCalls.single.function!.arguments, 'city="cut');
      expect(reply.toolCalls, isEmpty);
    },
  );

  test('name-only prefixes never invent diagnostics', () async {
    for (final payload in [
      '[',
      '[wea',
      '[weather',
      '[{"name":"wea',
      '[{"name":"weather"',
      '[{"function":{"name":"weather"',
    ]) {
      final output = 'Before.$_opening$payload';
      final reply = await _parse(output.split('')).collect();
      expect(reply.partialToolCalls, isEmpty, reason: payload);
      expect(reply.toolCalls, isEmpty);
      expect(reply.text, output, reason: payload);
    }
  });

  test(
    'closed calls stay withheld at length before unfinished envelope',
    () async {
      const output =
          'Before.$_opening[weather()]$_closing$_opening[unknown(x="cut';
      final reply = await _parse(output.split('')).collect();
      expect(reply.toolCalls, isEmpty);
      expect(reply.partialToolCalls.single.index, 1);
      expect(reply.partialToolCalls.single.function!.name, 'unknown');
      expect(reply.partialToolCalls.single.function!.arguments, 'x="cut');
      expect(reply.text, 'Before.');
    },
  );

  test('natural EOF and cancellation retain existing terminal policy', () async {
    for (final output in [
      'Before.$_opening[weather(city="cut',
      '$_opening[weather()]$_closing$_opening[unknown(x="cut',
    ]) {
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.lfm2.index,
        output,
        tools: [_tool],
      );
      for (final cancel in [false, true]) {
        final reply = await _parse(
          output.split(''),
          length: false,
          cancel: cancel,
        ).collect();
        expect(reply.partialToolCalls, isEmpty);
        expect(reply.text, parsed.content);
        expect(
          reply.toolCalls.map((c) => c.name),
          parsed.toolCalls.map((c) => c.function!.name),
        );
        expect(
          reply.finishReason,
          parsed.hasToolCalls
              ? LlamaFinishReason.toolCalls
              : LlamaFinishReason.stop,
        );
      }
    }
    // Cancellation wins diagnostic extraction even if a source also reports a limit.
    final reply = await _parse([
      '$_opening[weather(x="cut',
    ], cancel: true).collect();
    expect(reply.partialToolCalls, isEmpty);
    expect(reply.text, '$_opening[weather(x="cut');
  });

  test(
    'diagnostic arguments stay out of automatic logging and parent strings',
    () async {
      const sensitive =
          'https://example.invalid/private-model?token=diagnostic-test-secret';
      const output = 'Before.$_opening[unknown(path="$sensitive';
      final records = <LlamaLogRecord>[];
      final logger = LlamaLogger.instance;
      final previousLevel = logger.level;
      logger.setLevel(LlamaLogLevel.debug);
      logger.setHandler(records.add);
      try {
        final chunks = await _parse(output.split('')).toList();
        final completion = await Stream.fromIterable(chunks).collect();
        final parsed = Lfm2Handler().parse(output, isPartial: true);
        expect(
          completion.partialToolCalls.single.function!.arguments,
          'path="$sensitive',
        );
        for (final text in [
          chunks.last.toString(),
          chunks.last.choices.single.toString(),
          chunks.last.choices.single.delta.toString(),
          completion.toString(),
          parsed.toString(),
          ...records.map((r) => r.toString()),
        ]) {
          expect(text, isNot(contains(sensitive)));
          expect(text, isNot(contains('diagnostic-test-secret')));
        }
        expect(records, isNotEmpty);
        expect(chunks.last.toJson().toString(), contains(sensitive));
      } finally {
        logger.setHandler(null);
        logger.setLevel(previousLevel);
      }
    },
  );

  test(
    'a missing finish-cause reporter never infers length from syntax',
    () async {
      const output = 'Before.$_opening[weather(city="cut';
      final reply = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.value(output),
        templateResult: LlamaChatTemplateResult(
          prompt: '',
          format: ChatFormat.lfm2.index,
        ),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'unknown-cause',
        completionId: 'no-limit-probe',
        tools: [_tool],
      ).collect();
      expect(reply.partialToolCalls, isEmpty);
      expect(reply.toolCalls, isEmpty);
      expect(reply.text, output);
      expect(reply.finishReason, LlamaFinishReason.stop);
    },
  );

  test('cancelled partial fallback never leaks diagnostic records', () async {
    const output = '$_opening[unknown()]$_closing$_opening[unknown(x="cut';
    final reply = await _parse(
      [output],
      cancel: true,
      tools: [
        ToolDefinition.fromJsonSchema(
          name: 'weather',
          description: 'Weather',
          schema: const {'type': 'object', 'properties': {}},
        ),
      ],
    ).collect();
    expect(reply.partialToolCalls, isEmpty);
    expect(reply.toolCalls, isEmpty);
  });

  test(
    'none and parsing disabled remain literal without diagnostics',
    () async {
      const output = 'Before.$_opening[weather(city="cut';
      final reply = await _parse(output.split(''), enabled: false).collect();
      expect(reply.text, output);
      expect(reply.partialToolCalls, isEmpty);
      expect(reply.toolCalls, isEmpty);
      final direct = Lfm2Handler().parse(
        output,
        isPartial: true,
        parseToolCalls: false,
      );
      expect(direct.content, output);
      expect(direct.partialToolCalls, isEmpty);
    },
  );

  test(
    'reasoning markers and unclosed forced thoughts are never diagnostics',
    () async {
      for (final (output, forced) in [
        ('<think>Plan $_opening[weather(x="cut', false),
        ('Plan $_opening[weather(x="cut', true),
        ('<think>Plan $_opening[weather(x="cut</think>Answer.', false),
      ]) {
        final reply = await _parse(
          output.split(''),
          forcedOpen: forced,
        ).collect();
        expect(reply.partialToolCalls, isEmpty);
        expect(reply.toolCalls, isEmpty);
        expect(reply.thinking, contains('$_opening[weather(x="cut'));
      }
    },
  );

  test(
    'public completion/session and tool-loop paths keep diagnostics out of history and dispatch',
    () async {
      Stream<LlamaCompletionChunk> reply() =>
          _parse(['Before.$_opening[weather(city="cut']);
      final engine = ScriptedChatEngine()
        ..replies.addAll([reply, reply, reply, scriptedAnswer('next')]);
      final direct = await engine.complete(const []);
      expect(direct.partialToolCalls.single.function!.arguments, 'city="cut');
      final session = ChatSession(engine, maxContextTokens: 0);
      final collected = await session.send('hi');
      expect(collected.partialToolCalls, hasLength(1));
      expect(session.history.last.content, 'Before.');
      expect(
        session.history
            .expand((m) => m.parts)
            .whereType<LlamaToolCallContent>(),
        isEmpty,
      );
      var executions = 0;
      final loop = await session.sendWithTools(
        'again',
        tools: [
          ToolDefinition(
            name: 'weather',
            description: 'Weather',
            parameters: [],
            handler: (_) async {
              executions++;
              return 'unsafe';
            },
          ),
        ],
      );
      expect(executions, 0);
      expect(loop.stopReason, LlamaToolLoopStopReason.truncated);
      expect(loop.completion.partialToolCalls, hasLength(1));
      expect(loop.rolledBack, isTrue);
      final next = await session.send('reuse');
      expect(next.partialToolCalls, isEmpty);
      expect(
        engine.requests.last
            .expand((m) => m.parts)
            .whereType<LlamaToolCallContent>(),
        isEmpty,
      );
    },
  );
}
