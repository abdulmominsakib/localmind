@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/core/engine/engine.dart';
import 'package:test/test.dart';

const _firstCall = '[TOOL_CALLS]weather[ARGS]{"city":"Paris"}';
const _secondCall = '[TOOL_CALLS]weather[ARGS]{"city":"Seoul"}';
const _thinking = '[THINK]Check both cities.[/THINK]';
const _incompleteReply =
    '$_thinking$_firstCall[TOOL_CALLS]weather[ARGS]{"city":"Seo';

/// Supplies raw model bytes and a limit only after that generation ends.
/// The real engine renders the vendored template and parses every reply.
class _RawReplyBackend
    implements LlamaBackend, BackendGenerationLimitReporting {
  final replies = <(String, BackendGenerationLimit?)>[];
  final prompts = <String>[];
  final _limits = Expando<BackendGenerationLimit>();
  VoidCallback? onEnded;

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<int> getContextSize(int contextHandle) async => 4096;

  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<String> getBackendName() async => 'RawReply';

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {
    'general.architecture': 'mistral3',
    'tokenizer.chat_template': File(
      'test/fixtures/templates/Ministral-3-3B-Reasoning.jinja',
    ).readAsStringSync(),
  };

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async => [1];

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    prompts.add(prompt);
    expect(replies, isNotEmpty, reason: 'Unexpected additional generation');
    final (output, limit) = replies.removeAt(0);
    late Stream<List<int>> stream;
    Stream<List<int>> tokens() async* {
      // Give partial parsing a complete first call before starting the second.
      for (final character in output.split('')) {
        yield utf8.encode(character);
      }
      if (limit != null) _limits[stream] = limit;
      onEnded?.call();
    }

    stream = tokens();
    return stream;
  }

  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) =>
      _limits[generation];

  @override
  void cancelGeneration() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

typedef VoidCallback = void Function();

void main() {
  late _RawReplyBackend backend;
  late LlamaEngine engine;
  late ChatSession session;
  late List<String> executed;
  late List<ToolDefinition> tools;

  setUp(() async {
    backend = _RawReplyBackend();
    engine = LlamaEngine(backend);
    await engine.loadModel('Ministral-3-3B-Reasoning.gguf');
    session = ChatSession(engine, maxContextTokens: 0)
      ..addMessage(
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
      )
      ..addMessage(
        LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: 'Hello'),
      );
    executed = [];
    tools = [
      ToolDefinition(
        name: 'weather',
        description: 'Get the weather for a city.',
        parameters: [ToolParam.string('city', required: true)],
        handler: (params) async {
          final city = params.getRequiredString('city');
          executed.add(city);
          return 'Sunny in $city';
        },
      ),
    ];
  });

  tearDown(() async => engine.dispose());

  for (final choice in [null, ...ToolChoice.values]) {
    test('hidden unfinished Ministral thought: $choice', () async {
      backend.replies.add((
        '[THINK]Check the city.[/TH',
        BackendGenerationLimit.maxTokens,
      ));
      final reply = await session
          .create(
            const [LlamaTextContent('Weather?')],
            tools: choice == null ? null : tools,
            toolChoice: choice ?? ToolChoice.auto,
            enableThinking: false,
          )
          .collect();
      expect(reply.text, isEmpty);
      expect(reply.thinking, isEmpty);
      expect(reply.toolCalls, isEmpty);
      expect(reply.finishReason, LlamaFinishReason.length);
    });
    for (final ending in ['stop', 'limit', 'cancel']) {
      for (final suffix in ['', '[/TH']) {
        test('unfinished Ministral thought: $choice $ending $suffix', () async {
          backend.replies.add((
            '[THINK]Check the city.$suffix',
            ending == 'limit' ? BackendGenerationLimit.maxTokens : null,
          ));
          if (ending == 'cancel') backend.onEnded = engine.cancelGeneration;
          final stream = session.create(
            const [LlamaTextContent('Weather?')],
            tools: choice == null ? null : tools,
            toolChoice: choice ?? ToolChoice.auto,
          );
          if (choice == ToolChoice.required && ending == 'stop') {
            await expectLater(
              stream.toList(),
              throwsA(isA<LlamaInferenceException>()),
            );
            expect(executed, isEmpty);
            return;
          }
          final chunks = await stream.toList();
          expect(chunks.map((chunk) => chunk.text).join(), isEmpty);
          expect(
            chunks.map((chunk) => chunk.thinking).join(),
            'Check the city.',
          );
          final reply = await Stream.fromIterable(chunks).collect();
          expect(reply.text, isEmpty);
          expect(reply.thinking, 'Check the city.');
          expect(reply.toolCalls, isEmpty);
          expect(
            reply.finishReason,
            ending == 'limit'
                ? LlamaFinishReason.length
                : LlamaFinishReason.stop,
          );
          expect(session.history.last.content, isEmpty);
          expect(
            session.history.last.toJson()['reasoning_content'],
            'Check the city.',
          );

          backend.onEnded = null;
          backend.replies.add(('[THINK]Done.[/THINK]Sunny.', null));
          final next = await session.send('And now?');
          expect(next.text, 'Sunny.');
          expect(next.thinking, 'Done.');
          expect(
            backend.prompts.last,
            contains('[THINK]Check the city.[/THINK]'),
          );
          expect(backend.prompts.last, isNot(contains('[THINK][THINK]')));
        });
      }
    }
  }

  for (final choice in ToolChoice.values) {
    for (final limit in <BackendGenerationLimit?>[
      null,
      BackendGenerationLimit.maxTokens,
    ]) {
      test(
        'thinking-prefixed complete call set respects $choice and $limit',
        () async {
          backend.replies.add(('$_thinking$_firstCall$_secondCall', limit));
          final reply = await engine.complete(
            [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'Both cities?',
              ),
            ],
            tools: tools,
            toolChoice: choice,
            parallelToolCalls: true,
          );
          expect(reply.thinking, 'Check both cities.');
          expect(
            reply.toolCalls,
            hasLength(limit == null && choice != ToolChoice.none ? 2 : 0),
          );
          expect(
            reply.finishReason,
            limit != null
                ? LlamaFinishReason.length
                : choice == ToolChoice.none
                ? LlamaFinishReason.stop
                : LlamaFinishReason.toolCalls,
          );
        },
      );
    }
  }

  for (final limit in BackendGenerationLimit.values) {
    test(
      'engine keeps $limit and withholds a complete first parallel call',
      () async {
        backend.replies.add((_incompleteReply, limit));
        final chunks = await engine
            .create(
              [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'Both cities?',
                ),
              ],
              tools: tools,
              parallelToolCalls: true,
            )
            .toList();
        expect(chunks.last.finishReason, LlamaFinishReason.length);
        expect(completionGenerationLimit(chunks.last), limit);
        expect(
          chunks.take(chunks.length - 1).map(completionGenerationLimit),
          everyElement(isNull),
        );
        expect(
          chunks.expand((chunk) => chunk.choices.single.delta.toolCalls ?? []),
          isEmpty,
        );
      },
    );

    test(
      'tool loop rolls back the whole turn at $limit without executing the first call',
      () async {
        final history = session.history;
        backend.replies.addAll([(_incompleteReply, limit), ('4', null)]);
        final result = await session.sendWithTools(
          'Both cities?',
          tools: tools,
          parallelToolCalls: true,
        );
        expect(result.stopReason, LlamaToolLoopStopReason.truncated);
        expect(result.completion.finishReason, LlamaFinishReason.length);
        expect(result.pendingToolCalls, isEmpty);
        expect(executed, isEmpty);
        expect(result.rounds, 0);
        expect(result.rolledBack, isTrue);
        expect(session.history, history);
        expect(result.messages.last.role, LlamaChatRole.assistant);
        expect((await session.send('And 2 + 2?')).text, '4');
      },
    );
  }

  test(
    'complete parallel call set executes once and leaves normal history',
    () async {
      backend.replies.addAll([
        ('$_thinking$_firstCall$_secondCall', null),
        ('Both sunny.', null),
      ]);
      final result = await session.sendWithTools(
        'Both cities?',
        tools: tools,
        parallelToolCalls: true,
      );
      expect(result.stopReason, LlamaToolLoopStopReason.completed);
      expect(result.rounds, 1);
      expect(result.rolledBack, isFalse);
      expect(executed, ['Paris', 'Seoul']);
      final calls = result.messages
          .where((message) => message.role == LlamaChatRole.assistant)
          .first;
      expect(calls.parts.whereType<LlamaToolCallContent>(), hasLength(2));
      expect(
        result.messages.where((message) => message.role == LlamaChatRole.tool),
        hasLength(2),
      );
      expect(result.completion.text, 'Both sunny.');
    },
  );

  test(
    'truncation after a completed round removes the entire open turn',
    () async {
      final history = session.history;
      backend.replies.addAll([
        ('$_thinking$_firstCall', null),
        (_incompleteReply, BackendGenerationLimit.maxTokens),
        ('Both sunny.', null),
      ]);
      final result = await session.sendWithTools(
        'Both cities?',
        tools: tools,
        parallelToolCalls: true,
      );
      expect(result.stopReason, LlamaToolLoopStopReason.truncated);
      expect(result.rounds, 1);
      expect(executed, ['Paris']);
      expect(result.rolledBack, isTrue);
      expect(session.history, history);
      expect(
        result.messages.where((message) => message.role == LlamaChatRole.tool),
        hasLength(1),
      );
    },
  );

  test(
    'cancellation takes precedence over a limit and rolls back the incomplete turn',
    () async {
      final history = session.history;
      backend.replies.add((_incompleteReply, BackendGenerationLimit.maxTokens));
      backend.onEnded = engine.cancelGeneration;
      final result = await session.sendWithTools(
        'Both cities?',
        tools: tools,
        parallelToolCalls: true,
      );
      expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
      expect(executed, isEmpty);
      expect(result.rolledBack, isTrue);
      expect(session.history, history);
    },
  );

  test(
    'cancellation without a limit keeps a meaningful partial answer',
    () async {
      backend.replies.add(('[THINK]Done.[/THINK]Both cities are sunny.', null));
      backend.onEnded = engine.cancelGeneration;
      final result = await session.sendWithTools('Both cities?', tools: tools);
      expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
      expect(result.rolledBack, isFalse);
      expect(executed, isEmpty);
      expect(session.history.last.content, 'Both cities are sunny.');
    },
  );
}
