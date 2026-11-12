@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/scripted_chat_engine.dart';

/// Templates that reject a user turn unless every earlier user turn has an
/// assistant reply without tool calls.
const _vendoredTemplates = <String>[
  'test/fixtures/templates/Ministral-3-3B-Reasoning.jinja',
  'test/fixtures/llama_cpp_templates/mistralai-Ministral-3-14B-Reasoning-2512.jinja',
];

/// Templates that reject the `tool` role, so tool results reach them as user
/// turns.
const _toolRoleRejectingTemplates = <String>[
  'test/fixtures/templates/gemma-3-4b-it.jinja',
  'test/fixtures/templates/Mistral-7B-Instruct-v0_2.jinja',
];

/// Strict templates from the full llama.cpp set; see
/// `test/fixtures/llama_cpp_templates/README.md`.
const _upstreamTemplates = <String>[
  'Mistral-Small-3.2-24B-Instruct-2506.jinja',
  'mistralai-Mistral-Nemo-Instruct-2407.jinja',
];

Directory _upstreamTemplatesDir() {
  final path = Platform.environment['LLAMA_CPP_TEMPLATES_DIR']?.trim();
  return Directory(
    path == null || path.isEmpty
        ? '.dart_tool/llama_cpp/models/templates'
        : path,
  );
}

LlamaChatMessage _result(LlamaToolCallContent call, Object? result) =>
    LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: [
        LlamaToolResultContent(id: call.id, name: call.name, result: result),
      ],
    );

ToolDefinition _tool(String name, [ToolHandler? handler]) => ToolDefinition(
  name: name,
  description: 'The $name tool',
  parameters: [ToolParam.string('city')],
  handler: handler,
);

void main() {
  final upstreamDir = _upstreamTemplatesDir();
  final upstreamSkip =
      upstreamDir.existsSync() ||
          Platform.environment['REQUIRE_LLAMA_CPP_TEMPLATES']?.trim() == '1'
      ? null
      : 'Requires llama.cpp template fixtures (run '
            'tool/testing/prepare_llama_cpp_source.sh).';
  final templates = <(String, String?)>[
    for (final path in [..._vendoredTemplates, ..._toolRoleRejectingTemplates])
      (path, null),
    for (final name in _upstreamTemplates)
      ('${upstreamDir.path}/$name', upstreamSkip),
  ];
  for (final (path, skip) in templates) {
    group(path.split('/').last, skip: skip, () {
      late ScriptedChatEngine engine;
      late ChatSession session;

      setUp(() {
        final source = File(path).readAsStringSync();
        engine = ScriptedChatEngine()
          ..onRequest = (messages, tools) => ChatTemplateEngine.render(
            templateSource: source,
            messages: messages,
            metadata: const {},
            tools: tools,
          );
        session = ChatSession(engine, maxContextTokens: 0);
      });

      Future<void> expectNextTurnRenders() async {
        engine.replies.add(scriptedAnswer('4'));
        final next = await session.send('And 2 + 2?');
        expect(next.text, '4');
      }

      final weather = _tool('weather', (_) async => 'sunny');

      test('the manual flow after the app adds the results', () async {
        engine.replies
          ..add(scriptedCalls([('call00001', 'weather', '{}')]))
          ..add(scriptedAnswer('Sunny.'));
        final reply = await session
            .create(const [LlamaTextContent('Weather?')], tools: [weather])
            .collect();
        for (final call in reply.toolCalls) {
          session.addMessage(
            _result(call, await weather.invoke(call.arguments)),
          );
        }
        final answer = await session
            .create(const [], tools: [weather])
            .collect();
        expect(answer.text, 'Sunny.');
        await expectNextTurnRenders();
      });

      test('completed', () async {
        engine.replies
          ..add(scriptedCalls([('call00001', 'weather', '{}')]))
          ..add(scriptedAnswer('Sunny.'));
        final result = await session.sendWithTools('Hi', tools: [weather]);
        expect(result.stopReason, LlamaToolLoopStopReason.completed);
        await expectNextTurnRenders();
      });

      for (final maxRounds in [0, 1]) {
        test('maxRounds $maxRounds', () async {
          engine.replies.addAll([
            for (var round = 0; round <= maxRounds; round++)
              scriptedCalls([('call0000$round', 'weather', '{}')]),
          ]);
          final result = await session.sendWithTools(
            'Hi',
            tools: [weather],
            maxRounds: maxRounds,
          );
          expect(result.stopReason, LlamaToolLoopStopReason.maxRounds);
          await expectNextTurnRenders();
        });
      }

      test('contextExceeded', () async {
        session = ChatSession(engine, maxContextTokens: 256);
        engine
          ..promptTokens = 10000
          ..replies.add(scriptedCalls([('call00001', 'weather', '{}')]));
        final result = await session.sendWithTools('Hi', tools: [weather]);
        expect(result.stopReason, LlamaToolLoopStopReason.contextExceeded);
        engine.promptTokens = 0;
        await expectNextTurnRenders();
      });

      test('truncated mid tool call', () async {
        engine.replies.add(scriptedTruncated('[TOOL_CALLS]weather[ARGS]{"ci'));
        final result = await session.sendWithTools('Hi', tools: [weather]);
        expect(result.stopReason, LlamaToolLoopStopReason.truncated);
        await expectNextTurnRenders();
      });

      test('truncated after a tool round', () async {
        engine.replies
          ..add(scriptedCalls([('call00001', 'weather', '{}')]))
          ..add(scriptedTruncated('[THINK]The user asks'));
        final result = await session.sendWithTools('Hi', tools: [weather]);
        expect(result.stopReason, LlamaToolLoopStopReason.truncated);
        await expectNextTurnRenders();
      });

      test('unhandledToolCalls, after the app answers the calls', () async {
        engine.replies
          ..add(scriptedCalls([('call00001', 'approve', '{}')]))
          ..add(scriptedAnswer('Approved.'));
        final tools = [_tool('approve')];
        final result = await session.sendWithTools('Hi', tools: tools);
        expect(result.stopReason, LlamaToolLoopStopReason.unhandledToolCalls);

        final call = result.pendingToolCalls.single;
        session.addMessage(
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: call.id,
                name: call.name,
                result: 'denied',
              ),
            ],
          ),
        );
        final answered = await session.completeWithTools(
          const [],
          tools: tools,
        );
        expect(answered.stopReason, LlamaToolLoopStopReason.completed);
        await expectNextTurnRenders();
      });

      test('cancelled during a tool', () async {
        engine.replies.add(scriptedCalls([('call00001', 'weather', '{}')]));
        final result = await session.sendWithTools(
          'Hi',
          tools: [
            _tool('weather', (_) async {
              engine.cancelGeneration();
              return 'sunny';
            }),
          ],
        );
        expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
        await expectNextTurnRenders();
      });

      test('cancelled before the next reply starts', () async {
        engine.replies
          ..add(scriptedCalls([('call00001', 'weather', '{}')]))
          ..add(() async* {
            engine.cancelGeneration();
          });
        final result = await session.sendWithTools('Hi', tools: [weather]);
        expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
        await expectNextTurnRenders();
      });

      test('cancelled while generating calls', () async {
        engine.replies.add(() async* {
          engine.cancelGeneration();
          yield* scriptedCalls([('call00001', 'weather', '{}')])();
        });
        final result = await session.sendWithTools('Hi', tools: [weather]);
        expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
        await expectNextTurnRenders();
      });

      test('cancelled during the answer', () async {
        engine.replies
          ..add(scriptedCalls([('call00001', 'weather', '{}')]))
          ..add(() async* {
            yield scriptedChunk(content: 'Sun');
            engine.cancelGeneration();
          });
        final result = await session.sendWithTools('Hi', tools: [weather]);
        expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
        expect(session.history.last.content, 'Sun');
        await expectNextTurnRenders();
      });

      test('a rethrow from onToolError', () async {
        engine.replies.add(scriptedCalls([('call00001', 'weather', '{}')]));
        await expectLater(
          session.sendWithTools(
            'Hi',
            tools: [_tool('weather', (_) async => throw StateError('down'))],
            onToolError: (call, error, stackTrace) =>
                Error.throwWithStackTrace(error, stackTrace),
          ),
          throwsStateError,
        );
        await expectNextTurnRenders();
      });

      test('an error in a later round', () async {
        engine.replies
          ..add(scriptedCalls([('call00001', 'weather', '{}')]))
          ..add(() => Stream.error(LlamaInferenceException('boom')));
        await expectLater(
          session.sendWithTools('Hi', tools: [weather]),
          throwsA(isA<LlamaInferenceException>()),
        );
        await expectNextTurnRenders();
      });

      group('a continuation that stops early', () {
        final approve = _tool('approve');

        Future<void> answerApproval(List<ToolDefinition> tools) async {
          engine.replies.add(scriptedCalls([('call00001', 'approve', '{}')]));
          final first = await session.sendWithTools('Hi', tools: tools);
          expect(first.stopReason, LlamaToolLoopStopReason.unhandledToolCalls);
          session.addMessage(_result(first.pendingToolCalls.single, 'ok'));
        }

        test('maxRounds', () async {
          final tools = [approve, weather];
          await answerApproval(tools);
          engine.replies.add(scriptedCalls([('call00002', 'weather', '{}')]));
          final result = await session.completeWithTools(
            const [],
            tools: tools,
            maxRounds: 0,
          );
          expect(result.stopReason, LlamaToolLoopStopReason.maxRounds);
          await expectNextTurnRenders();
        });

        test('contextExceeded', () async {
          final tools = [approve, weather];
          await answerApproval(tools);
          session.maxContextTokens = 256;
          engine
            ..promptTokens = 10000
            ..replies.add(scriptedCalls([('call00002', 'weather', '{}')]));
          final result = await session.completeWithTools(
            const [],
            tools: tools,
          );
          expect(result.stopReason, LlamaToolLoopStopReason.contextExceeded);
          engine.promptTokens = 0;
          await expectNextTurnRenders();
        });

        test('cancelled during a tool', () async {
          final tools = [
            approve,
            _tool('weather', (_) async {
              engine.cancelGeneration();
              return 'sunny';
            }),
          ];
          await answerApproval(tools);
          engine.replies.add(scriptedCalls([('call00002', 'weather', '{}')]));
          final result = await session.completeWithTools(
            const [],
            tools: tools,
          );
          expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
          await expectNextTurnRenders();
        });

        test('cancelled before the answer starts', () async {
          final tools = [approve];
          await answerApproval(tools);
          engine.replies.add(() async* {
            engine.cancelGeneration();
          });
          final result = await session.completeWithTools(
            const [],
            tools: tools,
          );
          expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
          await expectNextTurnRenders();
        });

        test('truncated', () async {
          final tools = [approve];
          await answerApproval(tools);
          engine.replies.add(scriptedTruncated('Approv'));
          final result = await session.completeWithTools(
            const [],
            tools: tools,
          );
          expect(result.stopReason, LlamaToolLoopStopReason.truncated);
          await expectNextTurnRenders();
        });

        test('a rethrow from onToolError', () async {
          final tools = [
            approve,
            _tool('weather', (_) async => throw StateError('down')),
          ];
          await answerApproval(tools);
          engine.replies.add(scriptedCalls([('call00002', 'weather', '{}')]));
          await expectLater(
            session.completeWithTools(
              const [],
              tools: tools,
              onToolError: (call, error, stackTrace) =>
                  Error.throwWithStackTrace(error, stackTrace),
            ),
            throwsStateError,
          );
          await expectNextTurnRenders();
        });

        test('an error', () async {
          final tools = [approve];
          await answerApproval(tools);
          engine.replies.add(
            () => Stream.error(LlamaInferenceException('boom')),
          );
          await expectLater(
            session.completeWithTools(const [], tools: tools),
            throwsA(isA<LlamaInferenceException>()),
          );
          await expectNextTurnRenders();
        });

        test('resumed from a rolled-back turn', () async {
          engine.replies.add(scriptedCalls([('call00001', 'weather', '{}')]));
          final stopped = await session.sendWithTools(
            'Hi',
            tools: [weather],
            maxRounds: 0,
          );
          expect(stopped.rolledBack, isTrue);
          stopped.messages.forEach(session.addMessage);
          session.addMessage(_result(stopped.pendingToolCalls.single, 'ok'));
          engine.replies.add(scriptedCalls([('call00002', 'weather', '{}')]));
          final resumed = await session.completeWithTools(
            const [],
            tools: [weather],
            maxRounds: 0,
          );
          expect(resumed.stopReason, LlamaToolLoopStopReason.maxRounds);
          await expectNextTurnRenders();
        });
      });
    });
  }

  group('a reply that ends with whitespace', () {
    const user = LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'Hi',
    );
    const next = LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'And 2 + 2?',
    );
    LlamaChatMessage assistant(String text) =>
        LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: text);

    for (final path in const [
      'test/fixtures/templates/Phi-4-mini-instruct-reasoning.jinja',
      'test/fixtures/templates/LFM2_5-1_2B-Thinking.jinja',
    ]) {
      final name = path.split('/').last;
      final weather = _tool('weather', (_) async => 'sunny');

      test('leaves the prompts of $name as they were', () async {
        final source = File(path).readAsStringSync();
        String render(
          List<LlamaChatMessage> messages, [
          List<ToolDefinition>? tools,
        ]) => ChatTemplateEngine.render(
          templateSource: source,
          messages: messages,
          metadata: const {},
          tools: tools,
        ).prompt;

        Future<
          ({
            List<String> prompts,
            LlamaToolLoopResult result,
            LlamaCompletion sent,
            ChatSession session,
          })
        >
        run(String checking, String answer, String second) async {
          final prompts = <String>[];
          final engine = ScriptedChatEngine()
            ..onRequest = (messages, tools) =>
                prompts.add(render(messages, tools));
          final session = ChatSession(engine, maxContextTokens: 0);
          engine.replies
            ..add(() async* {
              yield scriptedChunk(content: checking);
              yield* scriptedCalls([
                ('call00001', 'weather', '{"city": "Seoul"}'),
              ])();
            })
            ..add(scriptedAnswer(answer))
            ..add(scriptedAnswer(second))
            ..add(scriptedAnswer('Bye.'));
          final result = await session.sendWithTools('Hi', tools: [weather]);
          final sent = await session.send('And 2 + 2?');
          await session.send('Thanks.');
          return (
            prompts: prompts,
            result: result,
            sent: sent,
            session: session,
          );
        }

        final base = await run('Checking.', 'Sunny.', '4');
        final spaced = await run('Checking. \n', 'Sunny.  \n ', '4\n\n');

        expect(
          render([user, assistant('Sunny.  \n '), next]),
          isNot(render([user, assistant('Sunny.'), next])),
        );
        expect(spaced.prompts, hasLength(4));
        expect(spaced.prompts, base.prompts);

        expect(spaced.result.stopReason, LlamaToolLoopStopReason.completed);
        expect(spaced.result.text, 'Sunny.  \n ');
        expect(spaced.sent.text, '4\n\n');
        final history = spaced.session.history;
        expect(
          [for (final message in history) message.content],
          [for (final message in base.session.history) message.content],
        );
        expect(
          history[1].parts.whereType<LlamaTextContent>().single.text,
          'Checking.',
        );
        expect(
          history[1].parts.whereType<LlamaToolCallContent>().single.rawJson,
          '{"city": "Seoul"}',
        );
        expect(spaced.result.messages.last, same(history[3]));
        expect(history[3].content, 'Sunny.');
      });
    }
  });
}
