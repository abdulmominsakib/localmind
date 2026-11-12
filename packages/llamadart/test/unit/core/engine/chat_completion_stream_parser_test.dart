import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/completion.dart';
import 'package:llamadart/src/core/models/chat/completion_chunk.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/chat_template_handler.dart';
import 'package:llamadart/src/core/template/handlers/ministral_handler.dart';
import 'package:llamadart/src/core/template/handlers/solar_open_handler.dart';
import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:llamadart/src/core/template/thinking_utils.dart';
import 'package:test/test.dart';

import '../../../support/peg_constructed_qwen_xml_parser.dart';

void main() {
  group('ChatCompletionStreamParser', () {
    for (final valid in [true, false]) {
      test(
        'fixed-clock prompt preserves split tool output (valid=$valid)',
        () async {
          final rendered = ChatTemplateEngine.render(
            templateSource:
                '{{ messages | tojson }}{{ tools | tojson }}'
                '<tool_call>'
                "{% if strftime_now('%Y') == '1984' %}<think>{% endif %}",
            messages: const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
            ],
            metadata: const {},
            tools: [_weatherTool],
            now: DateTime.utc(1984, 6, 1),
          );
          expect(rendered.prompt, endsWith('<think>'));
          expect(rendered.thinkingForcedOpen, isTrue);
          final envelope = valid
              ? '<tool_call>{"name":"weather","arguments":{"city":"Paris"}}'
                    '</tool_call>'
              : '<tool_call>{"name":"weather","arguments":{"city":"Par';
          final chunks = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable(
              'Plan.</think>Visible.$envelope'.split(''),
            ),
            templateResult: rendered,
            parseToolCallsEnabled: true,
            enableThinking: true,
            modelName: 'Hermes',
            completionId: 'fixed-clock-$valid',
            tools: [_weatherTool],
          ).toList();
          expect(
            chunks.map((c) => c.choices.single.delta.thinking ?? '').join(),
            'Plan.',
          );
          expect(
            chunks.map((c) => c.choices.single.delta.content ?? '').join(),
            valid ? 'Visible.' : 'Visible.$envelope',
          );
          final calls = chunks
              .expand(
                (c) =>
                    c.choices.single.delta.toolCalls ??
                    const <LlamaCompletionChunkToolCall>[],
              )
              .toList();
          expect(calls, hasLength(valid ? 1 : 0));
          if (valid) {
            expect(calls.single.function!.name, 'weather');
            expect(jsonDecode(calls.single.function!.arguments!), {
              'city': 'Paris',
            });
          }
          expect(
            chunks.last.finishReason,
            valid ? LlamaFinishReason.toolCalls : LlamaFinishReason.stop,
          );
        },
      );
    }

    LlamaCompletionChunkToolCall runtimeCall(String city) =>
        LlamaCompletionChunkToolCall(
          index: 0,
          type: 'function',
          function: LlamaCompletionChunkFunction(
            name: 'weather',
            arguments: jsonEncode({'city': city}),
          ),
        );

    test('runtime tool calls follow the calls parsed from the text', () async {
      final rendered = ChatTemplateEngine.render(
        templateSource:
            '{{ messages | tojson }}{{ tools | tojson }}<tool_call>',
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
        ],
        metadata: const {},
        tools: [_weatherTool],
      );
      final completion = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable([
          'Before ',
          '<tool_call>{"name":"weather","arguments":{"city":"Paris"}}',
          '</tool_call>',
        ]),
        templateResult: rendered,
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'runtime',
        completionId: 'runtime-calls',
        tools: [_weatherTool],
        runtimeToolCalls: () => [runtimeCall('Oslo')],
      ).collect();
      expect(completion.text.trim(), 'Before');
      expect(completion.finishReason, LlamaFinishReason.toolCalls);
      expect(completion.toolCalls.map((call) => call.arguments['city']), [
        'Paris',
        'Oslo',
      ]);
      expect(completion.toolCalls.map((call) => call.id), ['call_0', 'call_1']);
    });

    LlamaChatTemplateResult toolTemplate() => ChatTemplateEngine.render(
      templateSource: '{{ messages | tojson }}{{ tools | tojson }}<tool_call>',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
      ],
      metadata: const {},
      tools: [_weatherTool],
    );

    test('a runtime tool call keeps its own id', () async {
      final completion = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable([
          '<tool_call>{"name":"weather","arguments":{"city":"Paris"}}',
          '</tool_call>',
        ]),
        templateResult: toolTemplate(),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'runtime',
        completionId: 'runtime-call-id',
        tools: [_weatherTool],
        runtimeToolCalls: () => [
          LlamaCompletionChunkToolCall(
            index: 0,
            id: 'runtime-7',
            type: 'function',
            function: LlamaCompletionChunkFunction(
              name: 'weather',
              arguments: jsonEncode({'city': 'Oslo'}),
            ),
          ),
        ],
      ).collect();
      expect(completion.toolCalls.map((call) => call.id), [
        'call_0',
        'runtime-7',
      ]);
    });

    test('runtime tool calls keep content the stream withheld', () async {
      final completion = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(['Answer <tool_ca']),
        templateResult: toolTemplate(),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'runtime',
        completionId: 'runtime-call-content',
        tools: [_weatherTool],
        runtimeToolCalls: () => [runtimeCall('Oslo')],
      ).collect();
      expect(completion.text, 'Answer <tool_ca');
      expect(completion.toolCalls, hasLength(1));
    });

    test('runtime tool calls are ignored when tool parsing is off', () async {
      final completion = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(['plain']),
        templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
        parseToolCallsEnabled: false,
        enableThinking: true,
        modelName: 'runtime',
        completionId: 'runtime-calls-off',
        runtimeToolCalls: () => [runtimeCall('Oslo')],
      ).collect();
      expect(completion.text, 'plain');
      expect(completion.toolCalls, isEmpty);
      expect(completion.finishReason, LlamaFinishReason.stop);
    });

    test('streams plain content chunks and a final stop chunk', () async {
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(['hel', 'lo']),
        templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
        parseToolCallsEnabled: false,
        enableThinking: true,
        modelName: 'test-model',
        completionId: '123',
      ).toList();

      final content = chunks
          .map((chunk) => chunk.choices.single.delta.content ?? '')
          .join();

      expect(content, 'hello');
      expect(chunks.last.choices.single.finishReason, 'stop');
      expect(chunks.last.finishReason, LlamaFinishReason.stop);
      expect(chunks.last.model, 'test-model');
    });

    test('finishes with length when the stream ended at a limit', () async {
      var stoppedAtLimit = false;
      Stream<String> tokens() async* {
        yield 'par';
        yield 'tial';
        stoppedAtLimit = true;
      }

      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: tokens(),
        templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
        parseToolCallsEnabled: false,
        enableThinking: true,
        modelName: 'test-model',
        completionId: '124',
        stoppedAtLimit: () => stoppedAtLimit,
      ).toList();

      final content = chunks
          .map((chunk) => chunk.choices.single.delta.content ?? '')
          .join();
      expect(content, 'partial');
      expect(chunks.last.choices.single.finishReason, 'length');
      expect(chunks.last.finishReason, LlamaFinishReason.length);
    });

    test('finishes with stop when the stream ended without a limit', () async {
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(['done']),
        templateResult: const LlamaChatTemplateResult(prompt: 'prompt'),
        parseToolCallsEnabled: false,
        enableThinking: true,
        modelName: 'test-model',
        completionId: '125',
        stoppedAtLimit: () => false,
      ).toList();

      expect(chunks.last.choices.single.finishReason, 'stop');
    });

    test('emits each tool call once, complete, in the final chunk', () async {
      const call =
          '<tool_call>{"name":"weather","arguments":{"city":"Paris"}}'
          '</tool_call>';
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable([
          for (var i = 0; i < call.length; i += 4)
            call.substring(i, min(i + 4, call.length)),
        ]),
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: ChatFormat.hermes.index,
        ),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'test-model',
        completionId: 'complete-call',
      ).toList();

      final withCalls = chunks
          .where((chunk) => chunk.choices.single.delta.toolCalls != null)
          .toList();
      expect(withCalls, [same(chunks.last)]);
      expect(chunks.last.choices.single.finishReason, 'tool_calls');
      final calls = chunks.last.choices.single.delta.toolCalls!;
      expect(calls, hasLength(1));
      expect(calls.single.index, 0);
      expect(calls.single.id, 'call_0');
      expect(calls.single.function?.name, 'weather');
      expect(jsonDecode(calls.single.function!.arguments!), {'city': 'Paris'});
    });

    group('cancelled Qwen tool envelopes', () {
      const complete =
          '<tool_call>{"name":"weather","arguments":{"city":"Paris"}}'
          '</tool_call>';
      for (final prefix in ['', 'Checking. ']) {
        for (final earlierCall in ['', complete]) {
          test(
            'keeps answer and complete calls before cancel '
            '(text=${prefix.isNotEmpty}, call=${earlierCall.isNotEmpty})',
            () async {
              for (final tail in [
                '<tool_call>',
                '<tool_call>{"na',
                '<tool_call>{"name":"weather","arguments":{"city":"Seo',
                '<tool_call>{"name":"weather","arguments":{"city":"Seoul"}}',
              ]) {
                var cancelled = false;
                Stream<String> tokens() async* {
                  for (final character in '$prefix$earlierCall$tail'.split(
                    '',
                  )) {
                    yield character;
                  }
                  cancelled = true;
                }

                final chunks = await ChatCompletionStreamParser.parse(
                  tokenStream: tokens(),
                  templateResult: LlamaChatTemplateResult(
                    prompt: 'prompt',
                    format: ChatFormat.hermes.index,
                  ),
                  parseToolCallsEnabled: true,
                  enableThinking: false,
                  modelName: 'Qwen3',
                  completionId: 'cancel-tool',
                  cancelled: () => cancelled,
                ).toList();
                expect(
                  chunks
                      .map((c) => c.choices.single.delta.content ?? '')
                      .join(),
                  prefix.trimRight(),
                  reason: tail,
                );
                final calls = chunks
                    .expand(
                      (c) =>
                          c.choices.single.delta.toolCalls ??
                          const <LlamaCompletionChunkToolCall>[],
                    )
                    .toList();
                expect(calls, hasLength(earlierCall.isEmpty ? 0 : 1));
                if (calls.isNotEmpty) {
                  expect(calls.single.function?.arguments, '{"city":"Paris"}');
                }
                expect(
                  chunks.last.choices.single.finishReason,
                  earlierCall.isEmpty ? 'stop' : 'tool_calls',
                );
              }
            },
          );
        }
      }
    });

    for (final ending in ['natural', 'cancelled', 'length']) {
      for (final forcedOpen in [false, true]) {
        for (final choice in [ToolChoice.auto, ToolChoice.required]) {
          test('Hermes $ending with ${choice.name} after thinking '
              '(forcedOpen=$forcedOpen)', () async {
            const tail =
                '<tool_call>\n{"name":"weather","arguments":{"city":"Par';
            final prefix = forcedOpen
                ? 'Plan.</think>'
                : '<think>Plan.</think>';
            final rendered = ChatTemplateEngine.render(
              templateSource:
                  '{{ messages | tojson }}{{ tools | tojson }}<tool_call>',
              messages: const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
              ],
              metadata: const {},
              tools: [_weatherTool],
              toolChoice: choice,
            );
            final chunks = await ChatCompletionStreamParser.parse(
              tokenStream: Stream.fromIterable(
                '$prefix Checking. $tail'.split(''),
              ),
              templateResult: LlamaChatTemplateResult(
                prompt: rendered.prompt,
                format: rendered.format,
                parser: rendered.parser,
                thinkingForcedOpen: forcedOpen,
              ),
              parseToolCallsEnabled: true,
              enableThinking: true,
              modelName: 'Hermes',
              completionId: 'ending-reason',
              tools: [_weatherTool],
              cancelled: () => ending == 'cancelled',
              stoppedAtLimit: () => ending == 'length',
            ).toList();
            expect(
              chunks.map((c) => c.choices.single.delta.content ?? '').join(),
              ending == 'cancelled' ? 'Checking.' : 'Checking. $tail',
            );
            expect(
              chunks.map((c) => c.choices.single.delta.thinking ?? '').join(),
              'Plan.',
            );
            expect(
              chunks.expand((c) => c.choices.single.delta.toolCalls ?? []),
              isEmpty,
            );
            expect(
              chunks.last.choices.single.finishReason,
              ending == 'length' ? 'length' : 'stop',
            );
          });
        }
      }
    }

    test('fills call_<index> for parsed calls without an id', () async {
      const output =
          '[TOOL_CALLS][{"name":"weather","arguments":{"city":"Paris"}},'
          '{"name":"weather","arguments":{"city":"Seoul"},"id":"abcdefghi"}]';
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.mistralNemo.index,
        output,
        parseToolCalls: true,
      );
      expect(parsed.toolCalls.map((call) => call.id), [null, 'abcdefghi']);

      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable([output]),
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: ChatFormat.mistralNemo.index,
        ),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'test-model',
        completionId: 'fallback-id',
      ).toList();

      expect(chunks.last.choices.single.finishReason, 'tool_calls');
      final calls = chunks.last.choices.single.delta.toolCalls!;
      expect(calls.map((call) => call.id), ['call_0', 'abcdefghi']);
    });

    for (final endedAtLimit in [true, false]) {
      test('parallel Ministral calls preserve limit=$endedAtLimit', () async {
        const first = '[TOOL_CALLS]weather[ARGS]{"city":"Paris"}';
        const second = '[TOOL_CALLS]weather[ARGS]{"city":"Seoul"}';
        var ended = false;
        Stream<String> tokens() async* {
          yield '[THINK]Check both cities.[/THINK]';
          yield first;
          yield endedAtLimit ? second.substring(0, second.length - 3) : second;
          ended = true;
        }

        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: tokens(),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: ChatFormat.ministral.index,
          ),
          parseToolCallsEnabled: true,
          enableThinking: true,
          modelName: 'Ministral-3-3B-Reasoning',
          completionId: 'parallel-$endedAtLimit',
          stoppedAtLimit: () {
            expect(ended, isTrue);
            return endedAtLimit;
          },
        ).toList();

        expect(
          chunks.last.choices.single.finishReason,
          endedAtLimit ? 'length' : 'tool_calls',
        );
        final calls = chunks
            .expand(
              (chunk) =>
                  chunk.choices.single.delta.toolCalls ??
                  const <LlamaCompletionChunkToolCall>[],
            )
            .toList();
        expect(calls, hasLength(endedAtLimit ? 0 : 2));
        expect(
          chunks
              .map((chunk) => chunk.choices.single.delta.content ?? '')
              .join(),
          isEmpty,
          reason: 'Neither the complete nor the partial call leaks as text.',
        );
        expect(
          chunks
              .map((chunk) => chunk.choices.single.delta.thinking ?? '')
              .join(),
          'Check both cities.',
        );
        if (!endedAtLimit) {
          expect(calls.map((call) => call.function?.arguments), [
            '{"city":"Paris"}',
            '{"city":"Seoul"}',
          ]);
        }
      });
    }

    test('routes forced-open Qwen thinking into reasoning content', () async {
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(<String>[
          'reasoning',
          '</think>',
          'answer',
        ]),
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: ChatFormat.qwen3CoderXml.index,
          thinkingForcedOpen: true,
        ),
        parseToolCallsEnabled: false,
        enableThinking: true,
        modelName: 'test-model',
        completionId: '456',
      ).toList();

      final reasoning = chunks
          .map((chunk) => chunk.choices.single.delta.thinking ?? '')
          .join();
      final content = chunks
          .map((chunk) => chunk.choices.single.delta.content ?? '')
          .join();

      expect(reasoning, 'reasoning');
      expect(content, 'answer');
    });

    test(
      'does not stream a forced-open Qwen tool envelope as reasoning',
      () async {
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.fromIterable(<String>[
            'I should look this up.',
            '<',
            't',
            'o',
            'o',
            'l',
            '_',
            'c',
            'a',
            'll>\n<function=get_weather>\n',
            '<parameter=location>\nSeoul\n</parameter>\n',
            '</function>\n</tool_call>',
          ]),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: ChatFormat.qwen3CoderXml.index,
            thinkingForcedOpen: true,
          ),
          parseToolCallsEnabled: true,
          enableThinking: true,
          modelName: 'test-model',
          completionId: '789',
        ).toList();

        final reasoning = chunks
            .map((chunk) => chunk.choices.single.delta.thinking ?? '')
            .join();
        final content = chunks
            .map((chunk) => chunk.choices.single.delta.content ?? '')
            .join();
        final toolChunk = chunks.firstWhere(
          (chunk) => chunk.choices.single.delta.toolCalls != null,
        );

        expect(reasoning, 'I should look this up.');
        expect(reasoning, isNot(contains('<tool_call')));
        expect(content, isEmpty);
        expect(
          toolChunk.choices.single.delta.toolCalls!.single.function!.name,
          'get_weather',
        );
        expect(chunks.last.choices.single.finishReason, 'tool_calls');
        expect(chunks.last.finishReason, LlamaFinishReason.toolCalls);

        final completion = await Stream.fromIterable(chunks).collect();
        expect(completion.thinking, 'I should look this up.');
        expect(completion.text, isEmpty);
        expect(completion.finishReason, LlamaFinishReason.toolCalls);
        expect(completion.toolCalls.single.name, 'get_weather');
        expect(completion.toolCalls.single.arguments, {'location': 'Seoul'});
      },
    );

    test(
      'does not stream a Qwen tool envelope after a forced thought closes',
      () async {
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.fromIterable(<String>[
            'I should look this up.',
            '</think>',
            '<',
            't',
            'o',
            'o',
            'l',
            '_',
            'c',
            'a',
            'll>\n<function=get_weather>\n',
            '<parameter=location>\nSeoul\n</parameter>\n',
            '</function>\n</tool_call>',
          ]),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: ChatFormat.qwen3CoderXml.index,
            thinkingForcedOpen: true,
          ),
          parseToolCallsEnabled: true,
          enableThinking: true,
          modelName: 'test-model',
          completionId: '012',
        ).toList();

        final reasoning = chunks
            .map((chunk) => chunk.choices.single.delta.thinking ?? '')
            .join();
        final content = chunks
            .map((chunk) => chunk.choices.single.delta.content ?? '')
            .join();
        final toolChunk = chunks.firstWhere(
          (chunk) => chunk.choices.single.delta.toolCalls != null,
        );

        expect(reasoning, 'I should look this up.');
        expect(content, isEmpty);
        expect(
          toolChunk.choices.single.delta.toolCalls!.single.function!.name,
          'get_weather',
        );
        expect(chunks.last.choices.single.finishReason, 'tool_calls');
      },
    );

    for (final sample in [
      (
        format: ChatFormat.gptOss,
        output:
            'Let me check.\n'
            '<|start|>assistant to=functions.weather<|channel|>commentary'
            '<|message|>{"city":"Paris"}<|end|>',
        content: 'Let me check.',
      ),
      (
        format: ChatFormat.gemma4,
        output:
            '<|tool_call>call:weather{city:<|"|>Paris<|"|>}'
            '<tool_call|>\nDone.',
        content: '\nDone.',
      ),
    ]) {
      for (final size in [1, 2, 7, sample.output.length]) {
        test(
          '${sample.format.name} tool/content parity at chunk size $size',
          () async {
            final parsed = ChatTemplateEngine.parse(
              sample.format.index,
              sample.output,
              tools: [_weatherTool],
            );
            expect(parsed.content, sample.content);
            final chunks = await ChatCompletionStreamParser.parse(
              tokenStream: Stream.fromIterable([
                for (var i = 0; i < sample.output.length; i += size)
                  sample.output.substring(
                    i,
                    min(i + size, sample.output.length),
                  ),
              ]),
              templateResult: LlamaChatTemplateResult(
                prompt: 'prompt',
                format: sample.format.index,
              ),
              parseToolCallsEnabled: true,
              enableThinking: true,
              modelName: 'test-model',
              completionId: '${sample.format.name}-$size',
              tools: [_weatherTool],
            ).toList();
            expect(
              chunks.map((c) => c.choices.single.delta.content ?? '').join(),
              parsed.content,
            );
            expect(
              chunks.map((c) => c.choices.single.delta.thinking ?? '').join(),
              parsed.reasoningContent ?? '',
            );
            final calls = chunks
                .expand(
                  (c) =>
                      c.choices.single.delta.toolCalls ??
                      const <LlamaCompletionChunkToolCall>[],
                )
                .toList();
            expect(calls, hasLength(1));
            expect(calls.single.function?.name, 'weather');
            expect(jsonDecode(calls.single.function!.arguments!), {
              'city': 'Paris',
            });
            expect(chunks.last.choices.single.finishReason, 'tool_calls');
          },
        );
      }
    }

    test('GPT-OSS parses native assistant-header continuations', () async {
      for (final sample in [
        (
          output:
              '<|channel|>analysis to=functions.weather<|message|>{"city":"Montréal"}<|end|>',
          content: '',
          reasoning: '',
          calls: 1,
        ),
        (
          output:
              ' to=functions.weather<|channel|>commentary<|message|>{"city":"Montréal"}<|end|>',
          content: '',
          reasoning: '',
          calls: 1,
        ),
        (
          output:
              '<|channel|>analysis<|message|>Plan.<|end|><|start|>assistant<|channel|>final<|message|>4',
          content: '4',
          reasoning: 'Plan.',
          calls: 0,
        ),
        (output: '<|channel|>analysis', content: '', reasoning: '', calls: 0),
        (output: ' to=functions.weather', content: '', reasoning: '', calls: 0),
        (
          output: '<|channel|>analysis<|message|>Plan.',
          content: '',
          reasoning: 'Plan.',
          calls: 0,
        ),
        (
          output: '<|channel|>analysis to=functions.weather<|message|>{"city":',
          content: '',
          reasoning: '',
          calls: 0,
        ),
        (
          output:
              '<|channel|>analysis to=functions.weather<|message|>{"city":"<think>literal</think>"}<|end|>',
          content: '',
          reasoning: '',
          calls: 1,
        ),
      ]) {
        final parsed = ChatTemplateEngine.parse(
          ChatFormat.gptOss.index,
          sample.output,
        );
        expect(parsed.content, sample.content, reason: sample.output);
        expect(
          parsed.reasoningContent ?? '',
          sample.reasoning,
          reason: sample.output,
        );
        expect(
          parsed.toolCalls,
          hasLength(sample.calls),
          reason: sample.output,
        );
        for (final thinking in [true, false]) {
          for (final ending in ['natural', 'length', 'cancel']) {
            await _expectStreamMatchesParse(
              ChatFormat.gptOss,
              sample.output,
              enableThinking: thinking,
              atLimit: ending == 'length',
              cancelled: ending == 'cancel',
              openings: [
                '<|channel|>',
                ' to=functions.',
                '<|message|>',
                '<|start|>assistant',
              ],
            );
          }
        }
      }
      for (final tools in [false, true]) {
        for (final thinking in [false, true]) {
          await _expectStreamMatchesParse(
            ChatFormat.gptOss,
            '<|channel|>analysis<|message|>Plan.<|end|><|start|>assistant<|channel|>final<|message|>4',
            tools: tools,
            enableThinking: thinking,
            openings: ['<|channel|>', '<|start|>assistant'],
          );
        }
      }
    });

    test('Llama 3 withholds leading JSON calls from streamed content', () async {
      const call = '{"name":"weather","parameters":{"city":"Montréal 🌧"}}';
      const typed =
          '{"type":"function","name":"weather","parameters":{"city":"Paris"}}';
      for (final format in [ChatFormat.llama3, ChatFormat.llama3BuiltinTools]) {
        for (final output in [
          call,
          '$call\nDone.',
          '  \n$call',
          '{ "name" : "weather" , "parameters" : {"city":"Paris"} }',
          typed,
          '$typed\nDone.',
          '<think>Plan.</think>$call\nDone.',
          // Not calls: these stay content.
          '{"name":"Bob","age":3}',
          '{"type":"text","value":1}',
          'Let me check. $call\n',
          '{"name":"weather","parameters":{"city":"Paris"} }',
          '{"name":"weather","parameters":',
          '{"name":\u00a0"weather","parameters":{"city":"Paris"}}',
        ]) {
          for (final ending in ['natural', 'length', 'cancel']) {
            await _expectStreamMatchesParse(
              format,
              output,
              atLimit: ending == 'length',
              cancelled: ending == 'cancel',
              openings: ['"parameters"', '"function"'],
            );
          }
          await _expectStreamMatchesParse(format, output, tools: false);
        }
      }
    });

    test('forced-open thoughts never stream a partial end tag', () async {
      const xml =
          '<tool_call>weather\n<arg_key>city</arg_key>\n'
          '<arg_value>Paris</arg_value>\n</tool_call>';
      const dsml =
          '<｜DSML｜invoke name="weather">\n'
          '<｜DSML｜parameter name="city" string="true">Paris</｜DSML｜parameter>\n'
          '</｜DSML｜invoke>\n';
      for (final (format, call) in [
        (ChatFormat.glm45, xml),
        (ChatFormat.laguna, xml),
        (ChatFormat.deepseekV4, '<｜DSML｜tool_calls>\n$dsml</｜DSML｜tool_calls>'),
        (
          ChatFormat.deepseekV32,
          '<｜DSML｜function_calls>\n$dsml</｜DSML｜function_calls>',
        ),
        (ChatFormat.llama3, '{"name":"weather","parameters":{"city":"Paris"}}'),
      ]) {
        for (final output in [
          'Plan.\n</think>\n\nLet me check.\n$call',
          'Plan.\n</think>\n\nLet me check.',
          'Plan with a literal </thi and more.\n</think>Done.',
          'Plan ends at </th',
          '<think>Plan.</think>Answer.',
        ]) {
          for (final ending in ['natural', 'length', 'cancel']) {
            await _expectStreamMatchesParse(
              format,
              output,
              forcedOpen: true,
              atLimit: ending == 'length',
              cancelled: ending == 'cancel',
              openings: ['<think>', '</think>'],
            );
          }
        }
      }
    });

    test(
      'formats without reasoning keep thought tags and gate text-first calls',
      () async {
        for (final (format, call, openings) in [
          (
            ChatFormat.firefunctionV2,
            ' functools[{"name":"weather","arguments":{"city":"Montréal 🌧"}}]',
            [' functools['],
          ),
          (
            ChatFormat.functionaryV31Llama31,
            '<function=weather>{"city":"Montréal 🌧"}</function>',
            ['<function=', '<|python_tag|>'],
          ),
          (
            ChatFormat.functionGemma,
            '<start_function_call>call:weather{city:<escape>Paris<escape>}'
                '<end_function_call>',
            ['<start_function_call>'],
          ),
          (
            ChatFormat.gemma,
            '{"tool_call":{"name":"weather","arguments":{"city":"Paris"}}}',
            ['{"tool_call"'],
          ),
          (
            ChatFormat.functionaryV32,
            '>>>weather\n{"city":"Montréal 🌧"}',
            ['>>>', 'all\n'],
          ),
        ]) {
          for (final output in [
            'Let me check.\n$call',
            call.trimLeft(),
            'Let me check.\n$call\nDone.',
            '<think>Plan.</think>Let me check.\n$call',
            'Hi <think>literal</think> there',
            'Plain answer with a { brace } and <tag> text.',
            'Literal <start_func, <function=oops, functools[0] and a >>> b.',
          ]) {
            for (final ending in ['natural', 'length', 'cancel']) {
              await _expectStreamMatchesParse(
                format,
                output,
                atLimit: ending == 'length',
                cancelled: ending == 'cancel',
                openings: openings,
              );
            }
            await _expectStreamMatchesParse(format, output, tools: false);
          }
        }
        for (final output in [
          'all\nHello there.',
          'all\nHello.\n>>>weather\n{"city":"Paris"}\n>>>weather\n{"city":"Oslo"}',
          '>>>all\nHello.>>>weather\n{"city":"Paris"}',
          'weather\n{"city":"Paris"}',
          '>>>python\nprint(1)',
          'weather\n{"city":',
          'Hello',
        ]) {
          await _expectStreamMatchesParse(
            ChatFormat.functionaryV32,
            output,
            openings: ['>>>', '\n{'],
          );
        }
        for (final output in [
          '{"a":1} and then '
              '{"tool_call":{"name":"weather","arguments":{"city":"Paris"}}}',
          'Here is JSON: {"a": {"b": 1}} done.',
          'Text with "tool_call" literal and {x}.',
        ]) {
          await _expectStreamMatchesParse(ChatFormat.gemma, output);
        }
        for (final (format, output) in [
          (
            ChatFormat.functionaryV32,
            'all\nLet me check. >>>weather\n{"city":"Par',
          ),
          (ChatFormat.functionaryV32, 'all\nHi >>>all\nmore'),
          (
            ChatFormat.functionaryV32,
            'all\nA\n>>>weather\n{"city":"Paris"}\nB\n>>>weather\n{"city":"Pa',
          ),
          (
            ChatFormat.functionaryV32,
            'all\nLet me check.\n>>>weather\n{"city":"Paris"}\nIt is sunny.'
                '\n>>>all\nDone.',
          ),
          (ChatFormat.functionaryV32, 'weather\n{"city":"Paris"}B>>>all\nmore'),
          (
            ChatFormat.functionaryV32,
            'all\nA\n>>>weather\n{"city":"P"}\nB\n>>>weather\n{"city":"Q"}\nC'
                '\n>>>weather\n{"city":"Pa',
          ),
          (
            ChatFormat.functionaryV32,
            '>>> x = 2\n>>> print(x)\n2\nThat is it.',
          ),
          (ChatFormat.functionaryV31Llama31, 'Hi <|python_tag|>print(1)'),
          (
            ChatFormat.gemma,
            '{ "tool_call" : {"name":"weather","arguments":{"city":"Paris"}}}',
          ),
        ]) {
          for (final ending in ['natural', 'length', 'cancel']) {
            await _expectStreamMatchesParse(
              format,
              output,
              atLimit: ending == 'length',
              cancelled: ending == 'cancel',
            );
          }
        }
        await _expectContentAfterEachToken(ChatFormat.gemma, [
          ('int add(int a) {', 'int add(int a)'),
          ('\n  return a;\n}\n', 'int add(int a) {\n  return a;\n}'),
          ('This adds.', 'int add(int a) {\n  return a;\n}\nThis adds.'),
          (' {"tool_', 'int add(int a) {\n  return a;\n}\nThis adds.'),
        ]);

        await _expectContentAfterEachToken(ChatFormat.functionGemma, [
          ('Let me ', 'Let me'),
          ('check. <start_func', 'Let me check.'),
          ('tion_call>call:weather{', 'Let me check.'),
        ]);
      },
    );

    test(
      'LFM2 foreign closing diagnostics never stream executable calls',
      () async {
        for (final bracket in ['', ']']) {
          for (final tail in ['', '\n{"raw":true}', '<', '<x><<']) {
            final raw =
                '<|tool_call_start|>[weather(city=\\\\host)$bracket</function_call>$tail';
            for (final ending in ['natural', 'length', 'cancel']) {
              await _expectStreamMatchesParse(
                ChatFormat.lfm2,
                raw,
                everySplit: true,
                atLimit: ending == 'length',
                cancelled: ending == 'cancel',
                openings: ['<|tool_call_start|>', '</function_call>'],
              );
            }
            for (final tokens in _chunkings(raw, ['</function_call>'])) {
              final chunks = await ChatCompletionStreamParser.parse(
                tokenStream: Stream.fromIterable(tokens),
                templateResult: LlamaChatTemplateResult(
                  prompt: '',
                  format: ChatFormat.lfm2.index,
                ),
                parseToolCallsEnabled: true,
                enableThinking: false,
                modelName: 'LFM2',
                completionId: 'foreign-diagnostic',
                tools: [_weatherTool],
              ).toList();
              expect(
                chunks.expand(
                  (c) => c.choices.single.delta.toolCalls ?? const [],
                ),
                isEmpty,
              );
            }
          }
        }
      },
    );

    test('LFM2 and Kimi K2 gate tool calls in content and thoughts', () async {
      for (final (format, call, opening) in [
        (
          ChatFormat.lfm2,
          '<|tool_call_start|>[{"name":"weather",'
              '"arguments":{"city":"Montréal 🌧"}}]<|tool_call_end|>',
          '<|tool_call_start|>',
        ),
        (
          ChatFormat.kimiK2,
          '<|tool_calls_section_begin|><|tool_call_begin|>functions.weather:0'
              '<|tool_call_argument_begin|>{"city":"Montréal 🌧"}'
              '<|tool_call_end|><|tool_calls_section_end|>',
          '<|tool_calls_section_begin|>',
        ),
      ]) {
        for (final (output, forcedOpen) in [
          ('Let me check.\n$call', false),
          (call, false),
          ('Let me check.\n$call\nDone.', false),
          ('<think>Plan.</think>Let me check.\n$call', false),
          ('<think>Plan $call more.</think>Answer.', false),
          ('$call<think>After.</think>Done.', false),
          ('<think>A $call</think>B<think>C</think>D', false),
          (r'<think>Line\none and <|tool_c</think>Answer.', false),
          ('Literal <|tool_call and text.', false),
          ('Let me check.\n${call.substring(0, call.length ~/ 2)}', false),
          ('Plan.</think>Let me check.\n$call', true),
          ('Plan $call</think>Done.', true),
        ]) {
          for (final ending in ['natural', 'length', 'cancel']) {
            await _expectStreamMatchesParse(
              format,
              output,
              forcedOpen: forcedOpen,
              atLimit: ending == 'length',
              cancelled: ending == 'cancel',
              openings: [opening, '</think>'],
            );
          }
          // Raw streams without tools keep escaped newlines in reasoning
          // (a separate issue), so this output is checked with tools only.
          if (!forcedOpen && !output.contains(r'\n')) {
            await _expectStreamMatchesParse(format, output, tools: false);
          }
        }
      }
    });

    test(
      'LFM2 raw inner quotes stream like the final parse at every split',
      () async {
        for (final (raw, city) in [
          ('print(f"hi {name}")', 'print(f"hi {name}")'),
          ('it"s fine', 'it"s fine'),
          (r'say \"hi\" from C:\\temp', r'say "hi" from C:\temp'),
          ('{"a": 1, "b": "two"}', '{"a": 1, "b": "two"}'),
          ('Montréal "🌧" 東京', 'Montréal "🌧" 東京'),
          (r'it"s \u00e9 \\"q"', r'it"s é \"q"'),
        ]) {
          final output =
              '<|tool_call_start|>[{"name":"weather",'
              '"arguments":{"city":"$raw"}}]<|tool_call_end|>';
          final parsed = ChatTemplateEngine.parse(
            ChatFormat.lfm2.index,
            output,
            tools: [_weatherTool],
          );
          expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
            'city': city,
          }, reason: output);
          for (final ending in ['natural', 'length', 'cancel']) {
            await _expectStreamMatchesParse(
              ChatFormat.lfm2,
              output,
              everySplit: true,
              atLimit: ending == 'length',
              cancelled: ending == 'cancel',
              openings: ['<|tool_call_start|>', '<|tool_call_end|>'],
            );
          }
        }
      },
    );

    // Pins current behavior; llama.cpp has no oracle for this shape (#1933).
    test('LFM2 takes a thought after a call envelope as reasoning', () async {
      const call =
          '<|tool_call_start|>[{"name":"weather",'
          '"arguments":{"city":"Paris"}}]<|tool_call_end|>';
      for (final separator in ['', '\n']) {
        final output = '$call$separator<think>After.</think>Done.';
        final parsed = ChatTemplateEngine.parse(
          ChatFormat.lfm2.index,
          output,
          tools: [_weatherTool],
        );
        expect(parsed.toolCalls.single.function!.name, 'weather');
        expect(parsed.reasoningContent, 'After.');
        expect(parsed.content, 'Done.');
        await _expectStreamMatchesParse(
          ChatFormat.lfm2,
          output,
          everySplit: true,
          openings: ['<|tool_call_start|>', '</think>'],
        );
      }
    });

    test('unclosed forced thoughts keep reasoning after a held call', () async {
      for (final (format, call) in [
        (
          ChatFormat.lfm2,
          '<|tool_call_start|>[{"name":"weather",'
              '"arguments":{"city":"Paris"}}]<|tool_call_end|>',
        ),
        (
          ChatFormat.kimiK2,
          '<|tool_calls_section_begin|><|tool_call_begin|>functions.weather:0'
              '<|tool_call_argument_begin|>{"city":"Paris"}'
              '<|tool_call_end|><|tool_calls_section_end|>',
        ),
      ]) {
        for (final output in [
          '\nPlan. $call Then more thinking',
          '\nPlan. ${call.substring(0, call.length - 30)}',
        ]) {
          final parsed = ChatTemplateEngine.parse(
            format.index,
            output,
            thinkingForcedOpen: true,
            tools: [_weatherTool],
          );
          final chunks = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable([
              for (var i = 0; i < output.length; i += 4)
                output.substring(i, min(i + 4, output.length)),
            ]),
            templateResult: LlamaChatTemplateResult(
              prompt: 'prompt',
              format: format.index,
              thinkingForcedOpen: true,
            ),
            parseToolCallsEnabled: true,
            enableThinking: true,
            modelName: 'test-model',
            completionId: 'unclosed-thought',
            tools: [_weatherTool],
          ).toList();
          expect(
            chunks
                .map((chunk) => chunk.choices.single.delta.thinking ?? '')
                .join(),
            parsed.reasoningContent!.trimLeft(),
            reason: '${format.name} $output',
          );
        }
      }
    });

    test(
      'Kimi K3 and MiniMax M1 match final turn-end and post-call text',
      () async {
        const k3 =
            '<|open|>tools<|sep|><|open|>call tool="weather" index="1"<|sep|>'
            '<|open|>argument key="city" type="string"<|sep|>Montréal 🌧'
            '<|close|>argument<|sep|><|close|>call<|sep|><|close|>tools<|sep|>';
        const turnEnd = '<|close|>message<|sep|>';
        const think = '<|open|>think<|sep|>Plan ünï.<|close|>think<|sep|>';
        const response =
            '<|open|>response<|sep|>Body 🌧.<|close|>response<|sep|>';
        const m1 =
            '<tool_calls>\n{"name":"weather","arguments":{"city":"Paris"}}\n'
            '</tool_calls>';
        for (final (format, outputs, openings) in [
          (
            ChatFormat.kimiK3,
            [
              'Let me check.\n$k3$turnEnd',
              'Let me check.\n$k3',
              '${k3}Done.',
              'Plain answer.$turnEnd',
              'Plain answer.<|end_of_msg|>',
              'Plain answer.',
              'Literal <|close|>mess and more.',
              'Let me check.\n${k3.replaceFirst('weather', 'nope')}\n'
                  'Done.$turnEnd',
              'x$turnEnd$k3',
              response,
              '$think$response$turnEnd',
              '$think${response}Then.$k3',
              '<|open|>response<|sep|>unterminated body',
              '<|open|>think<|sep|>unterminated thought',
              '<|open|>think<|sep|>Plan.$k3',
            ],
            [
              turnEnd,
              '<|open|>tools<|sep|>',
              '<|end_of_msg|>',
              '<|close|>think<|sep|>',
              '<|open|>response<|sep|>',
              '<|close|>response<|sep|>',
            ],
          ),
          (
            ChatFormat.minimaxM1,
            [
              '$m1\nDone.',
              'Let me check.\n$m1',
              'Let me check.\n$m1\nDone.',
              m1,
              'Plain answer.',
              '<think>Plan.</think>$m1\nDone.',
              'Literal <tool_ca and more.',
            ],
            ['<tool_calls>', '</tool_calls>', '</think>'],
          ),
        ]) {
          for (final output in outputs) {
            for (final ending in ['natural', 'length', 'cancel']) {
              await _expectStreamMatchesParse(
                format,
                output,
                atLimit: ending == 'length',
                cancelled: ending == 'cancel',
                openings: openings,
              );
            }
            await _expectStreamMatchesParse(format, output, tools: false);
          }
        }
        for (final output in [
          'Plan ünï.<|close|>think<|sep|>$response',
          'a\nb<|close|>think<|sep|>Hi.',
          'Plan.<|open|>response<|sep|>Body.',
          'Plan only.',
        ]) {
          for (final tools in [true, false]) {
            for (final ending in ['natural', 'length', 'cancel']) {
              await _expectStreamMatchesParse(
                ChatFormat.kimiK3,
                output,
                forcedOpen: true,
                tools: tools,
                atLimit: ending == 'length',
                cancelled: ending == 'cancel',
                openings: [
                  '<|close|>think<|sep|>',
                  '<|open|>response<|sep|>',
                  '<|close|>response<|sep|>',
                ],
              );
            }
          }
        }
      },
    );

    test('Llama 3 builtin tools gate the python tag after prose', () async {
      const call = '<|python_tag|>code_interpreter.call(code="1+1")';
      for (final output in [
        'Let me check.\n$call',
        call,
        'Hi <|python_tag|>print(1)',
        'Let me check.\n<|python_tag|>code_interpreter.call(code=',
        'Literal <|python and more text.',
        '{"name":"weather","parameters":{"city":"Paris"}}$call',
        '{"name":"weather","parameters":{"city":"Paris"}} ok $call',
        '{"name":"weather","parameters":{"city":"Paris"}} ok <|python_tag|>\n',
      ]) {
        for (final ending in ['natural', 'length', 'cancel']) {
          await _expectStreamMatchesParse(
            ChatFormat.llama3BuiltinTools,
            output,
            atLimit: ending == 'length',
            cancelled: ending == 'cancel',
            openings: ['<|python_tag|>'],
          );
        }
        await _expectStreamMatchesParse(
          ChatFormat.llama3BuiltinTools,
          output,
          tools: false,
        );
      }
      await _expectContentAfterEachToken(ChatFormat.llama3BuiltinTools, [
        ('Let me ', 'Let me'),
        ('check.\n<|python', 'Let me check.'),
        ('_tag|>code_interpreter.call(', 'Let me check.'),
      ]);
    });

    test('GPT-OSS streams frame bodies as they arrive', () async {
      const call =
          '<|start|>assistant to=functions.weather<|channel|>commentary'
          '<|message|>{"city":"Paris"}<|end|>';
      const analysis =
          '<|start|>assistant<|channel|>analysis<|message|>Plan  it.<|end|>';
      const answer =
          '<|start|>assistant<|channel|>final<|message|> Done 🌧. <|end|>';
      for (final output in [
        '$analysis$answer',
        '$analysis$call',
        'Intro. $analysis Middle. $answer Tail. ',
        '$analysis<|start|>assistant<|channel|>analysis<|message|>More.<|end|>'
            '$answer',
        '<|channel|>analysis<|message|>Plan.<|end|>$answer',
        ' to=functions.weather<|channel|>commentary<|message|>{"city":"P"}'
            '<|end|>',
        '<|start|>assistant<|channel|>final<|message|>Unterminated <|en',
        '<|start|>assistant<|channel|>analysis<|message|>Half',
        '<|start|>assistant<|channel|>final',
        '<|start|>assistant<|channel|>final<|message|>  <|end|>Text.',
        '$answer<|start|>assistant<|channel|>commentary<|message|>Note.<|end|>',
        'Literal <|end|> and <|message|> outside frames.',
        '<|start|>assistant to=functions.weather<|channel|>commentary'
            '<|message|>{"city":"P"}<|end|>$answer',
        '<|start|>assistant to=functions.<|channel|>commentary'
            '<|message|>{}<|end|>$answer',
        '<|start|>assistant<|channel|>analysis<|channel|>final'
            '<|message|>Which?<|end|>',
      ]) {
        for (final tools in [true, false]) {
          for (final enableThinking in [true, false]) {
            for (final ending in ['natural', 'length', 'cancel']) {
              await _expectStreamMatchesParse(
                ChatFormat.gptOss,
                output,
                tools: tools,
                enableThinking: enableThinking,
                atLimit: ending == 'length',
                cancelled: ending == 'cancel',
                openings: [
                  '<|start|>assistant',
                  '<|channel|>',
                  '<|message|>',
                  '<|end|>',
                ],
              );
            }
          }
        }
      }
      final tokens = StreamController<String>();
      final thinking = StringBuffer();
      final subscription =
          ChatCompletionStreamParser.parse(
            tokenStream: tokens.stream,
            templateResult: LlamaChatTemplateResult(
              prompt: 'prompt',
              format: ChatFormat.gptOss.index,
            ),
            parseToolCallsEnabled: true,
            enableThinking: true,
            modelName: 'test-model',
            completionId: 'analysis-latency',
            tools: [_weatherTool],
          ).listen(
            (chunk) =>
                thinking.write(chunk.choices.single.delta.thinking ?? ''),
          );
      addTearDown(subscription.cancel);
      addTearDown(tokens.close);
      for (final (token, streamed) in [
        ('<|channel|>analysis<|message|>We', 'We'),
        (' need', 'We need'),
        (' weather.<|end|>', 'We need weather.'),
      ]) {
        tokens.add(token);
        await pumpEventQueue();
        expect(thinking.toString(), streamed, reason: token);
      }
      await _expectContentAfterEachToken(ChatFormat.gptOss, [
        ('<|start|>assistant<|channel|>final<|message|>Hello', 'Hello'),
        (' there', 'Hello there'),
        (' friend<|en', 'Hello there friend'),
        ('d|>', 'Hello there friend'),
      ]);
    });

    test('GPT-OSS gates split frames without swallowing ordinary text', () async {
      const call =
          '<|start|>assistant to=functions.weather<|channel|>commentary'
          '<|message|>{"city":"Paris"}<|end|>';
      for (final output in [
        'Let me check.\n$call\nDone.',
        '<|start|>assistant<|channel|>analysis<|message|>Plan.<|end|>'
            'Let me check.\n$call',
        'Let me check. <|start|>assistant<|channel|>final<|message|>Done.<|end|>',
        'Literal <|starfish and <|start|>not an assistant frame. ',
        'Let me check. <|start|>assistant to=functions.',
      ]) {
        await _expectStreamMatchesParse(
          ChatFormat.gptOss,
          output,
          openings: ['<|start|>assistant', '<|message|>', '<|end|>'],
        );
      }
      await _expectContentAfterEachToken(ChatFormat.gptOss, [
        ('Let me ', 'Let me'),
        ('check. <|sta', 'Let me check.'),
        ('rfish swims.', 'Let me check. <|starfish swims.'),
        (
          ' <|start|>assistant to=functions.',
          'Let me check. <|starfish swims.',
        ),
      ]);
    });

    test(
      'GPT-OSS keeps generic thought markers literal in framed streams',
      () async {
        for (final output in [
          '<think>unfinished',
          '<think>plan</thi',
          'Before <think>literal</think> after.',
          'Before </think> after.',
          'Let me check.\n<|start|>assistant to=functions.weather'
              '<|channel|>commentary<|message|>'
              '{"city":"<think>literal</think>"}<|end|>',
          '<|start|>assistant<|channel|>analysis<|message|>Plan.<|end|>'
              '<|start|>assistant<|channel|>final<|message|>'
              'Literal <think>text</think>.<|end|>',
        ]) {
          for (final forced in [false, true]) {
            for (final enabled in [false, true]) {
              for (final ending in ['natural', 'length', 'cancel']) {
                await _expectStreamMatchesParse(
                  ChatFormat.gptOss,
                  output,
                  forcedOpen: forced,
                  enableThinking: enabled,
                  atLimit: ending == 'length',
                  cancelled: ending == 'cancel',
                  openings: ['<think>', '</think>', '<|start|>assistant'],
                );
              }
            }
          }
        }
      },
    );

    test(
      'Gemma 4 preserves post-call text with thinking and disabled tools',
      () async {
        const call =
            '<|tool_call>call:weather{city:<|"|>Paris<|"|>}<tool_call|>';
        for (final tools in [true, false]) {
          for (final forced in [true, false]) {
            for (final suffix in [
              '\nDone.',
              '\nDone. \n',
              '',
              '<|tool_call>call:weather{',
            ]) {
              final output = '${forced ? 'Plan.<channel|>' : ''}$call$suffix';
              await _expectStreamMatchesParse(
                ChatFormat.gemma4,
                output,
                forcedOpen: forced,
                tools: tools,
                openings: ['<|tool_call>', '<tool_call|>', '<channel|>'],
              );
            }
          }
        }
      },
    );

    test(
      'Gemma 4 withholds a character-split tool envelope after thinking',
      () async {
        const output =
            'private reasoning<channel|>'
            '<|tool_call>call:weather{"city":"Seoul"}<tool_call|>';
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.fromIterable(output.split('')),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: ChatFormat.gemma4.index,
            thinkingForcedOpen: true,
          ),
          parseToolCallsEnabled: true,
          enableThinking: true,
          modelName: 'test-model',
          completionId: 'gemma4-character-split',
          tools: [_weatherTool],
        ).toList();

        final reasoning = chunks
            .map((chunk) => chunk.choices.single.delta.thinking ?? '')
            .join();
        final content = chunks
            .map((chunk) => chunk.choices.single.delta.content ?? '')
            .join();
        final toolCall = chunks
            .expand((chunk) => chunk.choices.single.delta.toolCalls ?? const [])
            .single;

        expect(reasoning, 'private reasoning');
        expect(content, isEmpty);
        expect(content, isNot(contains('<|tool_call>')));
        expect(toolCall.function?.name, 'weather');
        expect(jsonDecode(toolCall.function!.arguments!), {'city': 'Seoul'});
        expect(chunks.last.choices.single.finishReason, 'tool_calls');
      },
    );

    test(
      'Gemma 4 withholds a character-split tool envelope after content',
      () async {
        const output =
            'Visible answer.'
            '<|tool_call>call:weather{"city":"Seoul"}<tool_call|>';
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.fromIterable(output.split('')),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: ChatFormat.gemma4.index,
          ),
          parseToolCallsEnabled: true,
          enableThinking: true,
          modelName: 'test-model',
          completionId: 'gemma4-content-tool-split',
          tools: [_weatherTool],
        ).toList();

        final content = chunks
            .map((chunk) => chunk.choices.single.delta.content ?? '')
            .join();
        final toolCall = chunks
            .expand((chunk) => chunk.choices.single.delta.toolCalls ?? const [])
            .single;

        expect(content, 'Visible answer.');
        expect(content, isNot(contains('<|tool_call>')));
        expect(toolCall.function?.name, 'weather');
        expect(jsonDecode(toolCall.function!.arguments!), {'city': 'Seoul'});
      },
    );

    test(
      'Gemma 4 suppresses split tool controls when parsing is disabled',
      () async {
        const output =
            'Visible answer.'
            '<|tool_call>call:weather{"city":"Seoul"}<tool_call|>';
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.fromIterable(output.split('')),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: ChatFormat.gemma4.index,
          ),
          parseToolCallsEnabled: false,
          enableThinking: true,
          modelName: 'test-model',
          completionId: 'gemma4-no-tool-parse',
          tools: [_weatherTool],
        ).toList();

        final content = chunks
            .map((chunk) => chunk.choices.single.delta.content ?? '')
            .join();

        expect(content, 'Visible answer.');
        expect(content, isNot(contains('<|tool_call>')));
        expect(
          chunks.expand(
            (chunk) => chunk.choices.single.delta.toolCalls ?? const [],
          ),
          isEmpty,
        );
        expect(chunks.last.choices.single.finishReason, 'stop');
      },
    );

    test('Gemma 4 preserves ordinary raw whitespace exactly', () async {
      const output = ' \tVisible answer.  \n';

      for (final parseToolCallsEnabled in <bool>[true, false]) {
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.fromIterable(output.split('')),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: ChatFormat.gemma4.index,
          ),
          parseToolCallsEnabled: parseToolCallsEnabled,
          enableThinking: true,
          modelName: 'test-model',
          completionId: 'gemma4-raw-whitespace-$parseToolCallsEnabled',
          tools: [_weatherTool],
        ).toList();

        final content = chunks
            .map((chunk) => chunk.choices.single.delta.content ?? '')
            .join();

        expect(content, output, reason: 'parse tools: $parseToolCallsEnabled');
        expect(
          chunks.expand(
            (chunk) => chunk.choices.single.delta.toolCalls ?? const [],
          ),
          isEmpty,
        );
      }
    });

    test(
      'Gemma 4 character-split explicit thinking never becomes content',
      () async {
        const output = '<|channel>thought\ninternal draft<channel|>';

        for (final enableThinking in <bool>[true, false]) {
          final chunks = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable(output.split('')),
            templateResult: LlamaChatTemplateResult(
              prompt: 'prompt',
              format: ChatFormat.gemma4.index,
            ),
            parseToolCallsEnabled: true,
            enableThinking: enableThinking,
            modelName: 'test-model',
            completionId: 'gemma4-thinking-$enableThinking',
            tools: [_weatherTool],
          ).toList();

          final reasoning = chunks
              .map((chunk) => chunk.choices.single.delta.thinking ?? '')
              .join();
          final content = chunks
              .map((chunk) => chunk.choices.single.delta.content ?? '')
              .join();

          expect(content, isEmpty);
          expect(content, isNot(contains('<|channel>')));
          expect(content, isNot(contains('<channel|>')));
          expect(reasoning, enableThinking ? 'internal draft' : isEmpty);
        }
      },
    );

    test('debug logging records only parsed output metadata', () async {
      final messages = <String>[];
      LlamaLogger.instance
        ..setLevel(LlamaLogLevel.debug)
        ..setHandler((record) => messages.add(record.message));

      try {
        await ChatCompletionStreamParser.parse(
          tokenStream: Stream.value(
            '<|channel>thought\ninternal draft<channel|>'
            '<|tool_call>call:weather{"city":"Seoul"}<tool_call|>',
          ),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: ChatFormat.gemma4.index,
          ),
          parseToolCallsEnabled: true,
          enableThinking: true,
          modelName: 'test-model',
          completionId: 'safe-debug-log',
          tools: [_weatherTool],
        ).toList();
      } finally {
        LlamaLogger.instance
          ..setHandler(null)
          ..setLevel(LlamaLogLevel.none);
      }

      expect(messages, [
        'Parsed completion: contentChars=0, reasoningChars=14, '
            'toolCallCount=1',
      ]);
    });

    for (final (name, format, forced, content, thinking) in [
      ('gpt-oss', ChatFormat.gptOss, false, '<think>a</thi', ''),
      ('GLM-4.7-Flash', ChatFormat.glm45, true, '', '<think>a</thi'),
      ('MiniMax-M2', ChatFormat.minimaxM2, true, '', 'a</thi'),
    ]) {
      for (final tokens in [
        ['<think>a</thi'],
        ['<think>', 'a', '</thi'],
        '<think>a</thi'.split(''),
      ]) {
        test(
          '$name preserves its partial closing tag at EOF: $tokens',
          () async {
            final chunks = await ChatCompletionStreamParser.parse(
              tokenStream: Stream.fromIterable(tokens),
              templateResult: LlamaChatTemplateResult(
                prompt: 'prompt',
                format: format.index,
                thinkingForcedOpen: forced,
              ),
              parseToolCallsEnabled: false,
              enableThinking: true,
              modelName: name,
              completionId: 'other-reasoning-format',
            ).toList();

            expect(
              chunks
                  .map((chunk) => chunk.choices.single.delta.content ?? '')
                  .join(),
              content,
            );
            expect(
              chunks
                  .map((chunk) => chunk.choices.single.delta.thinking ?? '')
                  .join(),
              thinking,
            );
            expect(chunks.last.choices.single.finishReason, 'stop');
            expect(
              chunks.expand(
                (chunk) =>
                    chunk.choices.single.delta.toolCalls ??
                    const <LlamaCompletionChunkToolCall>[],
              ),
              isEmpty,
            );
          },
        );
      }
    }

    group('a Ministral PEG reply cut short', () {
      LlamaChatTemplateResult ministral(ToolChoice toolChoice) =>
          MinistralHandler().render(
            templateSource: '{{ messages[0]["content"] }}',
            messages: const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            metadata: {internalToolChoiceMetadataKey: toolChoice.name},
            tools: [_weatherTool],
          );

      Future<List<LlamaCompletionChunk>> parse(
        ToolChoice toolChoice,
        List<String> tokens, {
        bool atLimit = false,
        bool cancelled = false,
      }) => ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(tokens),
        templateResult: ministral(toolChoice),
        parseToolCallsEnabled: toolChoice != ToolChoice.none,
        enableThinking: true,
        modelName: 'Ministral-3-3B-Reasoning',
        completionId: 'cut-short',
        tools: [_weatherTool],
        stoppedAtLimit: () => atLimit,
        cancelled: () => cancelled,
      ).toList();

      String joined(
        List<LlamaCompletionChunk> chunks,
        String? Function(LlamaCompletionChunkDelta delta) field,
      ) =>
          chunks.map((chunk) => field(chunk.choices.single.delta) ?? '').join();

      List<LlamaCompletionChunkToolCall> calls(
        List<LlamaCompletionChunk> chunks,
      ) => chunks
          .expand(
            (chunk) =>
                chunk.choices.single.delta.toolCalls ??
                const <LlamaCompletionChunkToolCall>[],
          )
          .toList();

      const partialCall = '[TOOL_CALLS]weather[ARGS]{"city":"Par';
      const completeCall = '[TOOL_CALLS]weather[ARGS]{"city":"Paris"}';

      for (final suffix in ['[', '[/TH']) {
        test(
          'none preserves EOF markup after a tool marker: $suffix',
          () async {
            final output =
                '[THINK]a[TOOL_CALLS]weather[ARGS]{"city":"x"}$suffix';
            final chunks = await parse(ToolChoice.none, [output]);
            expect(joined(chunks, (delta) => delta.content), output);
            expect(
              joined(chunks, (delta) => delta.thinking),
              'a[TOOL_CALLS]weather[ARGS]{"city":"x"}$suffix',
            );
            expect(calls(chunks), isEmpty);
            expect(chunks.last.choices.single.finishReason, 'stop');
          },
        );
      }

      for (final toolChoice in [ToolChoice.required, ToolChoice.auto]) {
        group('with ${toolChoice.name}', () {
          test('preserves a natural call after an unclosed thought', () async {
            final chunks = await parse(toolChoice, const [
              '[THINK]a[TOOL_CALLS]weather[ARGS]{"city":"x"}',
            ]);
            expect(chunks.last.choices.single.finishReason, 'tool_calls');
            expect(joined(chunks, (delta) => delta.content), isEmpty);
            expect(
              joined(chunks, (delta) => delta.thinking),
              'a[TOOL_CALLS]weather[ARGS]{"city":"x"}',
            );
            final call = calls(chunks).single;
            expect(call.function?.name, 'weather');
            expect(call.function?.arguments, '{"city":"x"}');
          });

          for (final (name, atLimit, cancelled, finishReason) in const [
            ('at a limit', true, false, 'length'),
            ('by a cancel', false, true, 'stop'),
          ]) {
            test('ends $name before any output with $finishReason', () async {
              final chunks = await parse(
                toolChoice,
                const [],
                atLimit: atLimit,
                cancelled: cancelled,
              );

              expect(chunks.last.choices.single.finishReason, finishReason);
              expect(joined(chunks, (delta) => delta.content), isEmpty);
              expect(calls(chunks), isEmpty);
            });

            test('ends $name in a tool call with $finishReason and no '
                'calls', () async {
              final chunks = await parse(
                toolChoice,
                const ['[THINK]Check.[/THINK]', partialCall],
                atLimit: atLimit,
                cancelled: cancelled,
              );

              expect(chunks.last.choices.single.finishReason, finishReason);
              expect(joined(chunks, (delta) => delta.thinking), 'Check.');
              expect(joined(chunks, (delta) => delta.content), isEmpty);
              expect(calls(chunks), isEmpty);
            });
          }

          test('keeps a complete call after a cancel', () async {
            final chunks = await parse(toolChoice, const [
              completeCall,
            ], cancelled: true);

            expect(chunks.last.choices.single.finishReason, 'tool_calls');
            expect(
              calls(chunks).single.function?.arguments,
              '{"city":"Paris"}',
            );
          });
        });
      }

      for (final toolChoice in ToolChoice.values) {
        for (final cancelled in [false, true]) {
          test('${toolChoice.name} streams an unfinished thought '
              'without markup (cancelled=$cancelled)', () async {
            final chunks = await parse(
              toolChoice,
              const ['[TH', 'INK]Check', ' the city.', '[/TH'],
              atLimit: !cancelled,
              cancelled: cancelled,
            );
            expect(joined(chunks, (delta) => delta.content), isEmpty);
            expect(
              joined(chunks, (delta) => delta.thinking),
              'Check the city.',
            );
            expect(calls(chunks), isEmpty);
          });
        }
      }

      test('ends a required reply cut short in its thought without a '
          'call', () async {
        final chunks = await parse(ToolChoice.required, const [
          '[THINK]Check',
          ' the city.',
        ], atLimit: true);

        expect(chunks.last.choices.single.finishReason, 'length');
        expect(joined(chunks, (delta) => delta.thinking), 'Check the city.');
        expect(joined(chunks, (delta) => delta.content), isEmpty);
        expect(calls(chunks), isEmpty);
      });

      for (final (name, tokens) in const [
        ('no output', <String>[]),
        ('text without a call', ['It is sunny.']),
        ('a partial call', [partialCall]),
        ('an unclosed thought', ['[THINK]a']),
        ('a closed thought', ['[THINK]a[/THINK]']),
      ]) {
        test('throws a typed exception for a required reply that ended '
            'normally with $name', () async {
          await expectLater(
            parse(ToolChoice.required, tokens),
            throwsA(
              isA<LlamaInferenceException>().having(
                (error) => error.message,
                'message',
                startsWith(
                  'The model output does not match the expected peg-native '
                  'format: the parse failed at character ',
                ),
              ),
            ),
          );
        });
      }

      test('throws a typed exception for deeply nested call output', () async {
        String arguments(int depth) => '{"city":${'[' * depth}0${']' * depth}}';
        List<String> tokens(int depth) {
          final call = '[TOOL_CALLS]weather[ARGS]${arguments(depth)}';
          final half = call.length ~/ 2;
          return [call.substring(0, half), call.substring(half)];
        }

        final nested = await parse(ToolChoice.auto, tokens(64));
        expect(calls(nested).single.function?.arguments, arguments(64));
        for (final atLimit in [false, true]) {
          await expectLater(
            parse(ToolChoice.auto, tokens(5000), atLimit: atLimit),
            throwsA(
              isA<LlamaInferenceException>().having(
                (error) => error.message,
                'message',
                'The model output is nested too deeply to parse.',
              ),
            ),
          );
        }
      });

      test('none and auto replies that ended normally still parse', () async {
        final none = await parse(ToolChoice.none, const ['It is sunny.']);
        expect(none.last.choices.single.finishReason, 'stop');
        expect(joined(none, (delta) => delta.content), 'It is sunny.');

        final auto = await parse(ToolChoice.auto, const ['It is sunny.']);
        expect(auto.last.choices.single.finishReason, 'stop');
        expect(joined(auto, (delta) => delta.content), 'It is sunny.');
      });
    });

    test('carries tool schemas into specialized final parsing', () async {
      const namespace = ']<]minimax[>[';
      final tool = ToolDefinition(
        name: 'inspect',
        description: 'Inspect',
        parameters: [ToolParam.string('code', required: true)],
        handler: (_) async => null,
      );
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.value(
          '$namespace<tool_call>$namespace<invoke name="inspect">'
          '$namespace<code>123$namespace</code>'
          '$namespace</invoke>$namespace</tool_call>',
        ),
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: ChatFormat.minimaxM3.index,
        ),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'test-model',
        completionId: 'schema',
        tools: [tool],
      ).toList();

      final toolCall = chunks
          .expand((chunk) => chunk.choices.single.delta.toolCalls ?? const [])
          .single;
      expect(jsonDecode(toolCall.function!.arguments!), {'code': '123'});
      expect(chunks.last.choices.single.finishReason, 'tool_calls');
    });

    for (final (name, tokens) in <(String, List<String>)>[
      ('one token', [_hermesDoubleBrace]),
      ('characters', _hermesDoubleBrace.split('')),
    ]) {
      test(
        'streams no content for a double-brace Hermes call as $name',
        () async {
          final chunks = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable(tokens),
            templateResult: LlamaChatTemplateResult(
              prompt: 'prompt',
              format: ChatFormat.hermes.index,
            ),
            parseToolCallsEnabled: true,
            enableThinking: true,
            modelName: 'test-model',
            completionId: 'double-brace',
            tools: [_weatherTool],
          ).toList();

          expect(
            chunks
                .map((chunk) => chunk.choices.single.delta.content ?? '')
                .join(),
            isEmpty,
          );
          final toolCall = chunks
              .expand(
                (chunk) => chunk.choices.single.delta.toolCalls ?? const [],
              )
              .single;
          expect(toolCall.function?.name, 'weather');
          expect(jsonDecode(toolCall.function!.arguments!), {'city': 'Paris'});
          expect(chunks.last.choices.single.finishReason, 'tool_calls');
        },
      );
    }

    group('Hermes content matches the final parse', () {
      const call =
          '<tool_call>\n'
          '{"name": "weather", "arguments": {"city": "Paris"}}\n'
          '</tool_call>';
      const doubleBraceCall =
          '<tool_call>\n'
          '{{"name": "weather", "arguments": {"city": "Paris"}}}\n'
          '</tool_call>';
      const londonCall =
          '<tool_call>\n'
          '{"name": "weather", "arguments": {"city": "London"}}\n'
          '</tool_call>';
      const outputs = <String, String>{
        'text then a call': 'Let me check.\n$call',
        'text then a double-brace call': 'Let me check.\n$doubleBraceCall',
        'text then two calls': 'Checking both.\n$call\n$londonCall',
        'text after the call': 'Let me check.\n$call\nOne moment.',
        'padded text then a call': ' \n Let me check.  $call\n',
        'thinking, text, then a call':
            '<think>\nPlan.\n</think>\n\nLet me check.\n$call',
        'a bare < then a call': 'If a < b, b > a.\n$call',
        'a fenced call':
            'Sure:\n```json\n'
            '{"name": "weather", "arguments": {"city": "Paris"}}\n```',
        'a call first': '$call\nDone.',
      };
      const forcedOpenOutputs = <String>[
        'Plan.\n</think>\n\nLet me check.\n$call',
        'Plan. $call',
      ];

      Future<void> expectParsedContent(String output, bool forcedOpen) {
        return _expectStreamMatchesParse(
          ChatFormat.hermes,
          output,
          forcedOpen: forcedOpen,
          openings: const ['<tool_call>'],
        );
      }

      for (final MapEntry(key: name, value: output) in outputs.entries) {
        test(name, () => expectParsedContent(output, false));
      }

      test('plain text', () async {
        for (final output in const [
          'If a < b, use {x} or {"a": 1}.\n',
          'Let me check.\n<th',
        ]) {
          await expectParsedContent(output, false);
        }
      });

      test('after a forced-open thought', () async {
        for (final output in forcedOpenOutputs) {
          await expectParsedContent(output, true);
        }
      });

      test('trims each thought', () async {
        for (final output in const [
          '<think>\nPlan it.\n</think>\n\n$call',
          '<think>\n  Plan it.  \n</think>\n\nIt is sunny.',
          '<think>\n Plan \n\n it. \n',
          '<think>\nA.\n</think>\nOk.<think> </think>\n<think>\tB. </think>$call',
          r'<think> Use "a\nb" \</think>Done.',
          r'<think>a\\nb\r</think>',
          '<think>Plan </thi',
        ]) {
          await expectParsedContent(output, false);
        }
      });

      test('trims a forced-open thought that ends', () async {
        for (final output in const [
          '\nPlan it.\n</think>\n\n$call',
          '  </think>\nOk.\n<think>\nMore.\n</think>\n$call',
        ]) {
          await expectParsedContent(output, true);
        }
      });

      test('keeps trailing space of a forced-open thought that never ends', () {
        return expectParsedContent('Plan it.  \n\n', true);
      });

      test('holds back only a possible envelope opening', () {
        return _expectContentAfterEachToken(ChatFormat.hermes, const [
          ('If a', 'If a'),
          (' <', 'If a'),
          (' b,', 'If a < b,'),
          (' use {', 'If a < b, use'),
          ('x}.', 'If a < b, use {x}.'),
          ('\n', 'If a < b, use {x}.'),
          ('Let me check.\n<tool', 'If a < b, use {x}.\nLet me check.'),
          ('_call>\n{"name', 'If a < b, use {x}.\nLet me check.'),
        ]);
      });

      test('keeps an end tag before any start tag as content after a prompt '
          'that opens no thought', () async {
        // After a prompt that opens no thought, llama.cpp takes a thought
        // only from the start of the reply (#1858).
        for (final format in const [
          ChatFormat.hermes,
          ChatFormat.qwen3CoderXml,
          ChatFormat.deepseekV3,
        ]) {
          final tags = ChatTemplateEngine.thinkingTagsFor(format.index);
          final s = tags.startTag;
          final e = tags.endTag;
          for (final output in [
            'Plan.${e}Answer.',
            'Plan\n$e\n\nAnswer.',
            '${e}Text $e more.',
            'Plan.${e}A${e}B${s}X${e}C',
            'Plan.${e}Use 3 <',
          ]) {
            for (final tools in const [true, false]) {
              final parsed = parseRenderedOutput(
                format.index,
                output,
                parseToolCalls: tools,
                thoughtClosedForThinkingOff: false,
                tools: tools ? [_weatherTool] : null,
              );
              expect(parsed.content, output, reason: '${format.name} $output');
              expect(parsed.reasoningContent, isNull, reason: output);
              await _expectStreamMatchesParse(
                format,
                output,
                tools: tools,
                openings: [e],
                everySplit: true,
              );
            }
          }
        }
      });
    });

    group('text-first tool calls match the final parse', () {
      const qwenXmlCall =
          '<tool_call>\n'
          '<function=weather>\n'
          '<parameter=city>\nParis\n</parameter>\n'
          '</function>\n'
          '</tool_call>';
      const commandRCall =
          '<|START_ACTION|>'
          '[{"tool_call_id":"0","tool_name":"weather",'
          '"parameters":{"city":"Paris"}}]'
          '<|END_ACTION|>';
      const deepseekCalls = '<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>';
      // Formats whose streams are gated, with a call their parse extracts.
      const gatedCalls = <ChatFormat, String>{
        ChatFormat.mistralNemo:
            '[TOOL_CALLS][{"name": "weather", "arguments": {"city": "Paris"}, '
            '"id": "abcdefghi"}]',
        ChatFormat.magistral:
            '[TOOL_CALLS][{"name":"weather","arguments":{"city":"Paris"}}]',
        ChatFormat.qwen3CoderXml: qwenXmlCall,
        ChatFormat.deepseekR1:
            '${deepseekCalls}function<｜tool▁sep｜>weather\n'
            '```json\n{"city":"Paris"}\n```<｜tool▁call▁end｜>'
            '<｜tool▁calls▁end｜>',
        ChatFormat.deepseekV3:
            '${deepseekCalls}weather<｜tool▁sep｜>{"city":"Paris"}'
            '<｜tool▁call▁end｜><｜tool▁calls▁end｜>',
        ChatFormat.commandR7B: commandRCall,
        ChatFormat.cohere2Moe: commandRCall,
        ChatFormat.granite:
            '<|tool_call|>[{"name":"weather","arguments":{"city":"Paris"}}]',
        ChatFormat.nemotronV2:
            '<TOOLCALL>[{"name":"weather","arguments":{"city":"Paris"}}]'
            '</TOOLCALL>',
        ChatFormat.apertus:
            '<|tools_prefix|>[{"weather":{"city":"Paris"}}]<|tools_suffix|>',
        ChatFormat.seedOss:
            '<seed:tool_call>\n<function=weather><parameter=city>Paris'
            '</parameter></function></seed:tool_call>',
        ChatFormat.minimaxM2:
            '<minimax:tool_call>\n<invoke name="weather">\n'
            '<parameter name="city">Paris</parameter>\n</invoke>\n'
            '</minimax:tool_call>',
        ChatFormat.apriel15:
            '<tool_calls>[{"name": "weather", "arguments": {"city": "Paris"}}]'
            '</tool_calls>',
        ChatFormat.xiaomiMimo:
            '<tool_call>\n{"name": "weather", "arguments": {"city": "Paris"}\n'
            '</tool_call>',
        ChatFormat.exaoneMoe:
            '<tool_call>{"name":"weather","arguments":{"city":"Paris"}}'
            '</tool_call>',
        ChatFormat.minicpm5:
            '<function name="weather"><param name="city">Paris</param>'
            '</function>',
        ChatFormat.hunyuanV3:
            '<tool_calls:opensource>\n'
            '<tool_call:opensource>weather<tool_sep:opensource>\n'
            '<arg_key:opensource>city</arg_key:opensource>\n'
            '<arg_value:opensource>Paris</arg_value:opensource>\n'
            '</tool_call:opensource>\n'
            '</tool_calls:opensource>',
      };

      /// Text-first and other outputs around [call], with the format's tags.
      List<String> outputs(ChatFormat format, String call) {
        final tags = ChatTemplateEngine.thinkingTagsFor(format.index);
        return [
          'Let me check.\n$call',
          ' \n Let me check.  $call\n',
          'Let me check.\n$call\nDone.',
          '$call\nDone.',
          'If a < b, use {x} or [y].\n',
          'Let me check.\n${call.substring(0, 6)}',
          '${tags.startTag}\nPlan.\n${tags.endTag}\n\nLet me check.\n$call',
        ];
      }

      List<String> openings(String call) => [call.substring(0, 16)];

      for (final MapEntry(key: format, value: call) in gatedCalls.entries) {
        test(format.name, () async {
          for (final output in outputs(format, call)) {
            await _expectStreamMatchesParse(
              format,
              output,
              openings: openings(call),
            );
          }
        });

        final tags = ChatTemplateEngine.thinkingTagsFor(format.index);
        test('${format.name} after a forced-open thought', () async {
          for (final output in [
            'Plan.\n${tags.endTag}\n\nLet me check.\n$call',
            'Plan. $call',
            'Plan it.\n',
          ]) {
            await _expectStreamMatchesParse(
              format,
              output,
              forcedOpen: true,
              openings: openings(call),
            );
          }
        });
      }

      test('Qwen3-Coder XML ends a forced-open thought at a call', () async {
        for (final output in const [
          'Plan.\n$qwenXmlCall',
          'Plan.  $qwenXmlCall\nDone.',
          'Plan. <tool_c',
          'Plan. $qwenXmlCall\n</think>\nDone.',
        ]) {
          await _expectStreamMatchesParse(
            ChatFormat.qwen3CoderXml,
            output,
            forcedOpen: true,
            openings: const ['<tool_call>', '</think>'],
          );
        }
      });

      test('Command R holds back a bare JSON call array', () async {
        for (final output in const [
          'Let me check. [{"tool_call_id":"0","tool_name":"weather",'
              '"parameters":{"city":"Paris"}}]',
          'Use [x] or [ {"a": 1}] here.',
          'Let me check. <|START_TEXT|>Sure.<|END_TEXT|>',
        ]) {
          await _expectStreamMatchesParse(
            ChatFormat.commandR7B,
            output,
            openings: const ['[{"tool', '<|START_TEXT|>'],
          );
        }
      });

      test('DeepSeek holds back every tool-call opening', () async {
        for (final opening in const [
          '<｜tool▁calls▁begin｜>',
          '<｜tool_calls_begin｜>',
          '<｜tool calls begin｜>',
          r'<｜tool\_calls\_begin｜>',
          '<｜tool▁calls｜>',
        ]) {
          await _expectStreamMatchesParse(
            ChatFormat.deepseekR1,
            'Let me check.\n$opening<｜tool▁call▁begin｜>function'
            '<｜tool▁sep｜>weather\n```json\n{"city":"Paris"}\n```'
            '<｜tool▁call▁end｜><｜tool▁calls▁end｜>',
            openings: [opening],
          );
        }
      });

      test('Hunyuan V3 holds back a call and the end token', () async {
        for (final output in const [
          'Let me check.\n<tool_call:opensource>weather<tool_sep:opensource>'
              '\n<arg_key:opensource>city</arg_key:opensource>\n'
              '<arg_value:opensource>Paris</arg_value:opensource>\n'
              '</tool_call:opensource>',
          'Done.<｜hy_eos:opensource｜>',
        ]) {
          await _expectStreamMatchesParse(
            ChatFormat.hunyuanV3,
            output,
            openings: const ['<tool_call:opensource>', '<｜hy_eos'],
          );
        }
      });

      group('with a PEG parser', () {
        String parser(
          ChatTemplateHandler handler, {
          String templateSource = '{{ messages[0]["content"] }}',
          bool enableThinking = true,
        }) {
          return handler
              .render(
                templateSource: templateSource,
                messages: const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'hello',
                  ),
                ],
                metadata: const {},
                tools: [_weatherTool],
                enableThinking: enableThinking,
              )
              .parser!;
        }

        test('Qwen3-Coder XML with a PEG-constructed parser', () async {
          for (final format in const [
            ChatFormat.qwen3CoderXml,
            ChatFormat.pegConstructed,
          ]) {
            final withoutThinking = pegConstructedQwenXmlParser([
              _weatherTool,
            ], thinkingForcedOpen: false);
            for (final output in outputs(format, qwenXmlCall).take(6)) {
              await _expectStreamMatchesParse(
                format,
                output,
                parser: withoutThinking,
                openings: const ['<tool_call>'],
              );
            }
            await _expectStreamMatchesParse(
              format,
              'Plan.\n</think>\nLet me check.\n$qwenXmlCall',
              forcedOpen: true,
              parser: pegConstructedQwenXmlParser([
                _weatherTool,
              ], thinkingForcedOpen: true),
              openings: const ['<tool_call>', '</think>'],
            );
          }
        });

        test('a PEG parse with tools and a closed thought streams its call, '
            'not the envelope', () async {
          final withoutThinking = pegConstructedQwenXmlParser([
            _weatherTool,
          ], thinkingForcedOpen: false);
          for (final output in [
            'Let me check.\n$qwenXmlCall',
            ' \n Let me check.\n$qwenXmlCall',
            '<think>Plan.</think>Let me check.\n$qwenXmlCall',
            qwenXmlCall,
          ]) {
            await _expectStreamMatchesParse(
              ChatFormat.pegConstructed,
              output,
              parser: withoutThinking,
              enableThinking: false,
              thinkingForcedClosed: true,
              openings: const ['<tool_call>', '<think>', '</think>'],
              everySplit: true,
            );
          }
        });

        test('Ministral', () async {
          final ministral = parser(MinistralHandler());
          const call = '[TOOL_CALLS]weather[ARGS]{"city":"Paris"}';
          for (final format in const [
            ChatFormat.ministral,
            ChatFormat.pegNative,
          ]) {
            for (final output in [
              ...outputs(format, call).take(6),
              '[THINK]Plan.[/THINK]Let me check.\n$call',
            ]) {
              await _expectStreamMatchesParse(
                format,
                output,
                parser: ministral,
                openings: const ['[TOOL_CALLS]', '[/THINK]'],
              );
            }
          }
        });

        test('Solar Open', () async {
          final solarOpen = parser(SolarOpenHandler());
          for (final output in const [
            '<|content|>Let me check.\n<|end|><|begin|>assistant'
                '<|tool_calls|><|tool_call:begin|>0<|tool_call:name|>weather'
                '<|tool_call:args|>{"city":"Paris"}<|tool_call:end|>',
            '<|content|>If a < b, use {x} or [y].\n',
          ]) {
            await _expectStreamMatchesParse(
              ChatFormat.solarOpen,
              output,
              parser: solarOpen,
              openings: const ['<|end|>', '<|tool_calls|>'],
            );
          }
        });
      });

      test('Qwen3-Coder XML holds back only a possible opening', () {
        return _expectContentAfterEachToken(ChatFormat.qwen3CoderXml, const [
          ('If a', 'If a'),
          (' <', 'If a'),
          (' b,', 'If a < b,'),
          (' use <tool', 'If a < b, use'),
          ('s>.', 'If a < b, use <tools>.'),
          ('\n', 'If a < b, use <tools>.'),
          ('Let me check.\n<tool', 'If a < b, use <tools>.\nLet me check.'),
          ('_call>\n<function=', 'If a < b, use <tools>.\nLet me check.'),
        ]);
      });

      test('Mistral Nemo holds back only a possible opening', () {
        return _expectContentAfterEachToken(ChatFormat.mistralNemo, const [
          ('Use [x]', 'Use [x]'),
          (' or [TOOL', 'Use [x] or'),
          ('S].', 'Use [x] or [TOOLS].'),
          (' Let me check.[TOOL_', 'Use [x] or [TOOLS]. Let me check.'),
          ('CALLS][{"name', 'Use [x] or [TOOLS]. Let me check.'),
        ]);
      });

      group('forced-open thoughts', () {
        const hermesCall =
            '<tool_call>\n'
            '{"name": "weather", "arguments": {"city": "Paris"}}\n'
            '</tool_call>';
        final forcedGatedCalls = <ChatFormat, String>{
          ChatFormat.hermes: hermesCall,
          ...gatedCalls,
        };

        Future<void> expectForced(
          ChatFormat format,
          String output, {
          List<String> openings = const [],
        }) {
          final tags = ChatTemplateEngine.thinkingTagsFor(format.index);
          return _expectStreamMatchesParse(
            format,
            output,
            forcedOpen: true,
            openings: [tags.startTag, tags.endTag, ...openings],
          );
        }

        for (final MapEntry(key: format, value: call)
            in forcedGatedCalls.entries) {
          final tags = ChatTemplateEngine.thinkingTagsFor(format.index);
          final s = tags.startTag;
          final e = tags.endTag;
          test('${format.name} drops a repeated start tag', () async {
            for (final output in [
              '$s\nPlan.\n$e\n\nSure.',
              ' \n$s Plan.$e\nLet me check.\n$call',
              '$s\nPlan.\n$e\n\n$call',
              '$s $e\nSure.${s}More.$e',
              s,
              '$s\nPlan.',
              '$s\nPlan. $call',
              s.substring(0, 3),
            ]) {
              await expectForced(format, output, openings: [call]);
            }
          });

          test('${format.name} keeps a second end tag as content', () async {
            for (final output in [
              'Plan.$e\n${e}Text',
              'Plan.$e Text $e more.',
              'Plan.$e\n${e}Let me check.\n$call',
              '$e$e',
            ]) {
              await expectForced(format, output, openings: [call]);
            }
          });
        }

        test('ends a thought at a stray end tag after a start tag', () async {
          // The parse ends a thought at an end tag that follows a start tag
          // and keeps one as content otherwise. A stream can match only when
          // the tag arrives with the text before it.
          for (final (output, forcedOpen) in const [
            ('<think>\nPlan.</think>\nMore.</think> Sure.', true),
            ('Plan.</think>A<think>B</think>C</think>D', true),
            ('Plan.</think>A</think>B<think>X</think>C', true),
            ('<think>\nPlan.</think>\nMore.</think> Sure.', false),
            ('Plan.</think>A</think>B<think>X</think>C', false),
            ('</think>Text </think> more.', false),
          ]) {
            final parsed = parseRenderedOutput(
              ChatFormat.hermes.index,
              output,
              thinkingForcedOpen: forcedOpen,
              thoughtClosedForThinkingOff: false,
              tools: [_weatherTool],
            );
            final chunks = await ChatCompletionStreamParser.parse(
              tokenStream: Stream.value(output),
              templateResult: LlamaChatTemplateResult(
                prompt: 'prompt',
                format: ChatFormat.hermes.index,
                thinkingForcedOpen: forcedOpen,
              ),
              parseToolCallsEnabled: true,
              enableThinking: true,
              modelName: 'test-model',
              completionId: 'stray-end-tag',
              tools: [_weatherTool],
            ).toList();
            final deltas = chunks.map((chunk) => chunk.choices.single.delta);
            expect(
              deltas.map((delta) => delta.thinking ?? '').join(),
              parsed.reasoningContent ?? '',
              reason: output,
            );
            expect(
              deltas.map((delta) => delta.content ?? '').join(),
              parsed.content,
              reason: output,
            );
          }
        });

        test('the issue chunks stream the parsed reasoning', () async {
          // Qwen3-Coder XML and Hermes keep a repeated start tag, as
          // llama.cpp (`620d2225`) does.
          for (final (format, reasoning) in const [
            (ChatFormat.deepseekR1, 'Plan.'),
            (ChatFormat.qwen3CoderXml, '<think>\nPlan.'),
            (ChatFormat.hermes, '<think>\nPlan.'),
          ]) {
            final chunks = await ChatCompletionStreamParser.parse(
              tokenStream: Stream.fromIterable(const [
                '<think>',
                '\n',
                'Plan',
                '.',
                '\n',
                '</think>',
                '\n\n',
                'Sure',
                '.',
              ]),
              templateResult: LlamaChatTemplateResult(
                prompt: 'prompt',
                format: format.index,
                thinkingForcedOpen: true,
              ),
              parseToolCallsEnabled: true,
              enableThinking: true,
              modelName: 'test-model',
              completionId: 'repeated-start-tag',
              tools: [_weatherTool],
            ).toList();
            final deltas = chunks.map((chunk) => chunk.choices.single.delta);
            expect(
              deltas.map((delta) => delta.thinking ?? '').join(),
              reasoning,
              reason: format.name,
            );
            expect(
              deltas.map((delta) => delta.content ?? '').join(),
              'Sure.',
              reason: format.name,
            );
          }
        });

        test('Qwen3-Coder XML keeps escapes before a call', () async {
          for (final output in [
            r"Split on '\n'. Then call"
                '\n$qwenXmlCall',
            r'Plan \r\n x \\n.'
                ' $qwenXmlCall',
            r'Plan\r x.'
                ' $qwenXmlCall',
            r'Plan \n x.</think>Done.',
            r'Plan.</think>Sure.<think>More \n x.</think>Done.',
            r'<think>A</think>B<think>C \n x</think>D',
            r'Plan \n x.',
            r'Plan \',
            'Plan <tool_call>\n<function=weather>\n<parameter=city>\n'
                r'A\nB'
                '\n</parameter>\n</function>\n</tool_call>',
          ]) {
            await expectForced(
              ChatFormat.qwen3CoderXml,
              output,
              openings: const [r'\n', r'\r', '<tool_call>'],
            );
          }
        });

        test('DeepSeek V3 keeps an unended thought as reasoning', () async {
          final call = gatedCalls[ChatFormat.deepseekV3]!;
          for (final output in [
            'Plan it out',
            'Plan it.\n',
            'Plan. $call',
            'Plan.\n$call\nDone.',
            '<think>\nPlan.',
            '<think>\nPlan.\n</think>\n\nSure.',
          ]) {
            await expectForced(ChatFormat.deepseekV3, output, openings: [call]);
          }
        });

        test('reasoning streams before the end tag', () async {
          final thought = List.generate(
            12,
            (i) => 'Step $i checks the weather',
          ).join(', ');
          for (final (format, output) in [
            (ChatFormat.hermes, '$thought.\n</think>\n\nSunny.'),
            (ChatFormat.deepseekV3, '$thought.\n</think>\n\nSunny.'),
            (ChatFormat.exaoneMoe, '$thought.\n</think>\n\nSunny.'),
            (ChatFormat.qwen3CoderXml, '$thought.\n</think>\n\nSunny.'),
            (
              ChatFormat.qwen3CoderXml,
              "Use '\\n'.join(lines). $thought.\n</think>\n\n$qwenXmlCall",
            ),
            (
              ChatFormat.qwen3CoderXml,
              r'Save C:\Users\me\notes.txt. '
                  '$thought.\n</think>\n\nSunny.',
            ),
          ]) {
            for (final tools in const [true, false]) {
              final end = output.indexOf('</think>');
              final reasoning = await _reasoningBeforeEndTag(
                format,
                RegExp(r'\s+|[^\s]+').allMatches(output).map((m) => m[0]!),
                output.substring(0, end),
                tools: tools,
              );
              final parsed = ChatTemplateEngine.parse(
                format.index,
                output,
                parseToolCalls: tools,
                thinkingForcedOpen: true,
                tools: tools ? [_weatherTool] : null,
              );
              expect(
                reasoning,
                parsed.reasoningContent,
                reason: '${format.name} tools: $tools',
              );
            }
          }
        });

        test('the end of the stream releases a held backslash', () async {
          for (final tokens in const [
            ['Plan', r' \'],
            ['Plan ', r'\'],
            [r'\'],
          ]) {
            final reasoning = await _reasoningBeforeEndTag(
              ChatFormat.exaoneMoe,
              tokens,
              tokens.join(),
            );
            expect(reasoning, tokens.join(), reason: tokens.join('|'));
          }
        });

        test('reasoning streams as each token arrives', () async {
          await _expectStreamedAfterEachToken(
            ChatFormat.hermes,
            forcedOpen: true,
            const [
              ('Plan', 'Plan', ''),
              (' <tool', 'Plan <tool', ''),
              ('> x\n', 'Plan <tool> x', ''),
              ('</think>\n\nSure', 'Plan <tool> x', 'Sure'),
            ],
          );
          await _expectStreamedAfterEachToken(
            ChatFormat.hermes,
            forcedOpen: true,
            const [('<th', '<th', ''), ('ink>\nPlan', '<think>\nPlan', '')],
          );
          await _expectStreamedAfterEachToken(
            ChatFormat.qwen3CoderXml,
            forcedOpen: true,
            const [
              ('Plan', 'Plan', ''),
              (' <tool', 'Plan', ''),
              ('s> x', 'Plan <tools> x', ''),
              (r' \', r'Plan <tools> x \', ''),
              ('n y', r'Plan <tools> x \n y', ''),
              ('</think>', r'Plan <tools> x \n y', ''),
              // After the first end tag, thinking tags are content.
              ('<think>Next', r'Plan <tools> x \n y', '<think>Next'),
              (' <tool', r'Plan <tools> x \n y', '<think>Next'),
            ],
          );
          await _expectStreamedAfterEachToken(
            ChatFormat.qwen3CoderXml,
            forcedOpen: true,
            const [
              ('<think>Plan', '<think>Plan', ''),
              (' <tool', '<think>Plan', ''),
            ],
          );
          await _expectStreamedAfterEachToken(
            ChatFormat.deepseekV3,
            forcedOpen: true,
            const [
              ('Plan', 'Plan', ''),
              (' it.\n', 'Plan it.', ''),
              ('</think>', 'Plan it.', ''),
              ('Sure', 'Plan it.', 'Sure'),
              // After the first end tag, thinking tags are content.
              ('<think>More', 'Plan it.', 'Sure<think>More'),
            ],
          );
          await _expectStreamedAfterEachToken(ChatFormat.deepseekV3, const [
            ('<think>Plan', 'Plan', ''),
            (' it.', 'Plan it.', ''),
          ]);
        });
      });
    });

    // A handler closes a thought its template opened when thinking is off,
    // but the parse still ends a reply's leading thought at the first end
    // tag, so the stream holds text until a thinking tag shows what it is.
    group('a thought closed for thinking off', () {
      const qwenCall =
          '<tool_call>\n<function=weather>\n<parameter=city>\nParis\n'
          '</parameter>\n</function>\n</tool_call>';
      const hermesCall =
          '<tool_call>\n{"name": "weather", "arguments": {"city": "Paris"}}\n'
          '</tool_call>';
      const cohereCall =
          '<|START_ACTION|>[{"tool_call_id": "0", "tool_name": "weather", '
          '"parameters": {"city": "Paris"}}]<|END_ACTION|>';
      const seedCall =
          '<seed:tool_call>\n<function=weather>\n<parameter=city>\nParis\n'
          '</parameter>\n</function>\n</seed:tool_call>';
      for (final (format, call) in const [
        (ChatFormat.qwen3CoderXml, qwenCall),
        (ChatFormat.hermes, hermesCall),
        (ChatFormat.deepseekR1, ''),
        (ChatFormat.minimaxM2, ''),
        (ChatFormat.nemotronV2, ''),
        (ChatFormat.glm45, ''),
        (ChatFormat.cohere2Moe, cohereCall),
        (ChatFormat.commandR7B, cohereCall),
        (ChatFormat.seedOss, seedCall),
      ]) {
        final tags = ChatTemplateEngine.thinkingTagsFor(format.index);
        final s = tags.startTag;
        final e = tags.endTag;
        test('${format.name} streams what the parse keeps', () async {
          for (final output in [
            'Plan\n$e\n\nSunny.',
            '$e\n\nSunny.',
            'Sunny.',
            'Sunny, as ${s}planned$e it is.',
            '${s}Plan$e Sunny.',
            if (format == ChatFormat.cohere2Moe) ...[
              '<|START_TEXT|>Sunny.<|END_TEXT|>',
              'Plan$e<|START_TEXT|>Sunny.<|END_TEXT|>',
            ] else
              'Plan <|START_TEXT|>x$e Sunny.',
            if (call.isNotEmpty) ...[
              'Plan\n$e\n\n$call',
              'Plan\n$e\n\nSunny.\n\n$call',
              'Let me check.\n$call',
              call,
            ],
          ]) {
            for (final tools in [false, if (call.isNotEmpty) true]) {
              for (final enableThinking in const [false, true]) {
                await _expectStreamMatchesParse(
                  format,
                  output,
                  thoughtClosed: true,
                  tools: tools,
                  enableThinking: enableThinking,
                  everySplit: true,
                );
              }
            }
          }
        });
      }

      test('seedOss streams a scope without a line break as content', () async {
        const call =
            '<seed:tool_call><function=weather><parameter=city>Paris'
            '</parameter></function></seed:tool_call>';
        for (final output in [call, 'Let me check.\n$call']) {
          final parsed = parseRenderedOutput(
            ChatFormat.seedOss.index,
            output,
            thoughtClosedForThinkingOff: true,
            tools: [_weatherTool],
          );
          expect(parsed.toolCalls, isEmpty, reason: output);
          expect(parsed.content, output, reason: output);
          for (final enableThinking in const [false, true]) {
            await _expectStreamMatchesParse(
              ChatFormat.seedOss,
              output,
              thoughtClosed: true,
              tools: true,
              enableThinking: enableThinking,
              everySplit: true,
            );
          }
        }
      });

      test('seedOss starts calls at the first line-broken scope', () async {
        String call(String city, [String scopeStart = '<seed:tool_call>\n']) =>
            '$scopeStart<function=weather>\n<parameter=city>\n$city\n'
            '</parameter>\n</function>\n</seed:tool_call>';
        for (final output in [
          'Checking <seed:tool_call>',
          'Checking ${call('Paris')}',
          '${call('Paris', '<seed:tool_call>')}\n${call('Rome')}',
          'Use the <seed:tool_call> tag.\n${call('Rome')}',
          '${call('Paris')}\n${call('Rome', '<seed:tool_call>')}',
        ]) {
          await _expectStreamMatchesParse(
            ChatFormat.seedOss,
            output,
            thoughtClosed: true,
            everySplit: true,
          );
        }
      });

      test('seedOss holds a scope start tag until a line break', () async {
        await _expectStreamedAfterEachToken(ChatFormat.seedOss, [
          ('Checking <seed:tool_call>', '', 'Checking'),
          ('<function=x>', '', 'Checking <seed:tool_call><function=x>'),
          (
            ' and <seed:tool_call>',
            '',
            'Checking <seed:tool_call><function=x> and',
          ),
        ]);
      });

      test('content after the end tag streams as it arrives', () async {
        await _expectStreamedAfterEachToken(
          ChatFormat.qwen3CoderXml,
          thoughtClosed: true,
          tools: false,
          const [
            ('Plan', '', ''),
            ('\n</th', '', ''),
            ('ink>\n\nSun', 'Plan', 'Sun'),
            ('ny.', 'Plan', 'Sunny.'),
          ],
        );
      });

      // llama.cpp keeps the StepFun3.5-Flash thought open, so a reply with no
      // end tag is that thought, start tag included.
      test('a reply with a start tag streams as the thought', () async {
        await _expectStreamedAfterEachToken(
          ChatFormat.qwen3CoderXml,
          thoughtClosed: true,
          tools: false,
          const [('Hi', '', ''), (' <think>Plan', 'Hi <think>Plan', '')],
        );
      });

      // llama.cpp ends the thought it keeps open where Cohere2 MoE text or
      // an action starts.
      test('Cohere2 MoE text streams as it arrives', () async {
        await _expectStreamedAfterEachToken(
          ChatFormat.cohere2Moe,
          thoughtClosed: true,
          tools: false,
          const [
            ('<|START_TE', '', ''),
            ('XT|>Sun', '', 'Sun'),
            ('ny.', '', 'Sunny.'),
          ],
        );
      });

      test('a Cohere2 MoE action streams as it arrives', () async {
        await _expectStreamedAfterEachToken(
          ChatFormat.cohere2Moe,
          thoughtClosed: true,
          tools: false,
          const [('<|START_ACT', '', ''), ('ION|>x', '', '<|START_ACTION|>x')],
        );
      });

      test('an empty reply streams nothing', () async {
        for (final format in const [
          ChatFormat.seedOss,
          ChatFormat.cohere2Moe,
          ChatFormat.qwen3CoderXml,
        ]) {
          final chunks = await ChatCompletionStreamParser.parse(
            tokenStream: const Stream.empty(),
            templateResult: withThoughtClosedForThinkingOff(
              LlamaChatTemplateResult(prompt: 'prompt', format: format.index),
              closed: true,
            ),
            parseToolCallsEnabled: false,
            enableThinking: true,
            modelName: 'test-model',
            completionId: 'empty',
          ).toList();
          final deltas = chunks.map((chunk) => chunk.choices.single.delta);
          expect(
            deltas
                .map((delta) => '${delta.thinking ?? ''}${delta.content ?? ''}')
                .join(),
            isEmpty,
            reason: format.name,
          );
        }
      });

      // The 18-character start tag split after 17 characters is the longest
      // marker held across tokens.
      test('text before a split start tag streams once it ends', () async {
        await _expectStreamedAfterEachToken(
          ChatFormat.commandR7B,
          thoughtClosed: true,
          tools: false,
          const [('Hi <|START_THINKING|', '', ''), ('>Plan', 'Plan', 'Hi')],
        );
      });

      test('Command R7B text waits for a thinking tag', () async {
        await _expectStreamedAfterEachToken(
          ChatFormat.commandR7B,
          thoughtClosed: true,
          tools: false,
          const [('<|START_RESPONSE|>Sun', '', ''), ('ny.', '', '')],
        );
      });

      test('an unmarked result streams content as it arrives', () async {
        await _expectStreamedAfterEachToken(
          ChatFormat.qwen3CoderXml,
          tools: false,
          const [('Plan', '', 'Plan')],
        );
      });

      test('a forced-open thought streams reasoning as it arrives', () async {
        await _expectStreamedAfterEachToken(
          ChatFormat.qwen3CoderXml,
          forcedOpen: true,
          thoughtClosed: true,
          tools: false,
          const [('Plan', 'Plan', ''), ('</think>Sun', 'Plan', 'Sun')],
        );
      });
    });

    group('whitespace matches the final parse', () {
      String pegParser(
        ChatTemplateHandler handler, {
        String templateSource = '{{ messages[0]["content"] }}',
        bool enableThinking = true,
      }) {
        return handler
            .render(
              templateSource: templateSource,
              messages: const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
              ],
              metadata: const {},
              tools: [_weatherTool],
              enableThinking: enableThinking,
            )
            .parser!;
      }

      test('the DeepSeek R1 chunk from #754', () async {
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.value('<think>\nPlan.\n</think>\n\nSure.'),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: ChatFormat.deepseekR1.index,
          ),
          parseToolCallsEnabled: false,
          enableThinking: true,
          modelName: 'test-model',
          completionId: 'issue-754',
        ).toList();

        expect(
          chunks
              .map((chunk) => chunk.choices.single.delta.content ?? '')
              .join(),
          'Sure.',
        );
        expect(
          chunks
              .map((chunk) => chunk.choices.single.delta.thinking ?? '')
              .join(),
          'Plan.',
        );
      });

      test('DeepSeek R1 ends a prompt-opened thought at an end tag split '
          'across chunks (#1582)', () async {
        const call =
            '<｜tool calls begin｜> function<｜tool▁sep｜>weather\n```json\n'
            '{"city": "Paris"}\n```<｜tool▁call▁end｜><｜tool▁calls▁end｜>';
        for (final (output, tools) in const [
          ('</think>\n    $call', true),
          ('\n</think>\n$call', true),
          ('</think>Sunny.', true),
          ('</think>Sunny.', false),
          ('Sunny.</thi', true),
          ('<think>Plan.</think></think>Sunny.', true),
        ]) {
          await _expectStreamMatchesParse(
            ChatFormat.deepseekR1,
            output,
            tools: tools,
            everySplit: true,
          );
        }
        // After the thought ends, an end tag is content, so the start of one
        // streams at once.
        await _expectStreamedAfterEachToken(ChatFormat.deepseekR1, const [
          ('</think>', '', ''),
          ('Sunny.', '', 'Sunny.'),
          (' </', '', 'Sunny. </'),
          ('think>', '', 'Sunny. </think>'),
        ], forcedOpen: true);
      });

      test('every format streams a split end tag as its parse takes it '
          '(#1582)', () async {
        for (final format in ChatFormat.values) {
          if (format.name.startsWith('peg')) {
            continue;
          }
          final tags = ChatTemplateEngine.thinkingTagsFor(format.index);
          final s = tags.startTag;
          final e = tags.endTag;
          for (final output in [
            '${e}Sunny.',
            '$e${e}Sunny.',
            '${s}Plan.$e${e}Sunny.',
          ]) {
            await _expectStreamMatchesParse(
              format,
              output,
              tools: false,
              everySplit: true,
            );
          }
        }
      });

      test('text in every format, with and without tools', () async {
        for (final format in ChatFormat.values) {
          if (format.name.startsWith('peg')) {
            continue;
          }
          for (final output in const [
            ' \n Hi there. \n ',
            '\n\nLine one.\n\nLine two.\n',
            '\u{3000}Lead.\tTab\t\u{3000}',
            ' \n ',
            'Let me check.\n<th',
          ]) {
            for (final tools in const [true, false]) {
              await _expectStreamMatchesParse(format, output, tools: tools);
            }
          }
        }
      });

      test('Cohere response markers without tools', () async {
        const markers = [
          '<|START_TEXT|>',
          '<|END_TEXT|>',
          '<|START_RESPONSE|>',
          '<|END_RESPONSE|>',
        ];
        for (final format in const [
          ChatFormat.commandR7B,
          ChatFormat.cohere2Moe,
        ]) {
          for (final output in const [
            '<|START_TEXT|>Hello, world!<|END_TEXT|>',
            '<|START_RESPONSE|> Hello \n<|END_RESPONSE|>',
            '<|START_THINKING|>Plan.<|END_THINKING|>'
                '<|START_RESPONSE|>Hello<|END_RESPONSE|>',
            '<|START_TEXT|>Hello<|END_TE',
            '<|START_RESPONSE|>Hello',
          ]) {
            await _expectStreamMatchesParse(
              format,
              output,
              tools: false,
              openings: markers,
            );
          }
          // With tools the content gate holds a response at its opening, and
          // a stray marker before it stays content.
          await _expectStreamMatchesParse(
            format,
            'Hi<|END_TEXT|> there',
            openings: markers,
          );
        }
      });

      // Only a thought the prompt opens ends at a content opening.
      test('a content opening in a thought the model opens streams as it '
          'parses', () async {
        for (final (format, outputs) in [
          (
            ChatFormat.cohere2Moe,
            [
              '<|START_THINKING|>Plan <|START_TEXT|>Hi<|END_TEXT|>',
              '<|START_THINKING|>Plan <|START_TEXT|>Hi<|END_THINKING|>Yo',
            ],
          ),
          (ChatFormat.qwen3CoderXml, ['<think>Plan <tool_call>x</think>Hi']),
        ]) {
          for (final output in outputs) {
            for (final tools in const [true, false]) {
              await _expectStreamMatchesParse(format, output, tools: tools);
            }
          }
        }
      });

      // llama.cpp 620d2225 parses this reply after a Cohere2 MoE template
      // that opens the thought; tokens split before the end tag still stream
      // its first characters as content.
      test('a Cohere2 MoE end tag before a body arriving whole streams as it '
          'parses', () async {
        const output =
            'Plan<|END_THINKING|><|START_TEXT|>a<|END_THINKING|>b<|END_TEXT|>';
        final parsed = parseRenderedOutput(
          ChatFormat.cohere2Moe.index,
          output,
          parseToolCalls: false,
          thoughtClosedForThinkingOff: false,
        );
        expect(parsed.reasoningContent, 'Plan');
        expect(parsed.content, 'a<|END_THINKING|>b');
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.value(output),
          templateResult: LlamaChatTemplateResult(
            prompt: 'prompt',
            format: ChatFormat.cohere2Moe.index,
          ),
          parseToolCallsEnabled: false,
          enableThinking: true,
          modelName: 'test-model',
          completionId: 'end-tag-before-body',
        ).toList();
        final deltas = chunks.map((chunk) => chunk.choices.single.delta);
        expect(deltas.map((delta) => delta.thinking ?? '').join(), 'Plan');
        expect(
          deltas.map((delta) => delta.content ?? '').join(),
          'a<|END_THINKING|>b',
        );
      });

      test('text between a Cohere2 MoE thought and its body streams as it '
          'parses', () async {
        for (final output in const [
          '<|START_THINKING|>x<|END_THINKING|> Hi <|START_TEXT|>Sunny.'
              '<|END_TEXT|>',
          '<|START_THINKING|>x<|END_THINKING|> Hi <|START_ACTION|>[]'
              '<|END_ACTION|>',
        ]) {
          for (final tools in const [true, false]) {
            await _expectStreamMatchesParse(
              ChatFormat.cohere2Moe,
              output,
              tools: tools,
              everySplit: true,
            );
          }
        }
      });

      test('thoughts in formats whose tool-call streams are gated', () async {
        const thoughts = [
          '<think>\nPlan.\n</think>\n\nSure.',
          '<think>\n Plan. \n</think>\n\n Sure. \n',
          '\n<think>\nPlan.\n</think>\n\nSure.',
          '<think>\nA.\n</think>\n\n<think>\n B. \n</think>\n\nDone.',
          '<think> \n </think> \n ',
          '<think>\nPlan.\n</think>\n\nSure.\n\n<think>\nLate.\n</think>\n\nOk.',
        ];
        const forcedThoughts = [
          'Plan.\n</think>\n\nSure.',
          ' \n Plan. \n</think> \n Sure. \n ',
        ];
        for (final format in const [
          ChatFormat.hermes,
          ChatFormat.mistralNemo,
          ChatFormat.magistral,
          ChatFormat.qwen3CoderXml,
          ChatFormat.deepseekR1,
          ChatFormat.deepseekV3,
          ChatFormat.commandR7B,
          ChatFormat.cohere2Moe,
          ChatFormat.granite,
          ChatFormat.nemotronV2,
          ChatFormat.apertus,
          ChatFormat.exaoneMoe,
          ChatFormat.minicpm5,
          ChatFormat.hunyuanV3,
          ChatFormat.seedOss,
          ChatFormat.minimaxM2,
          ChatFormat.apriel15,
          ChatFormat.xiaomiMimo,
        ]) {
          final tags = ChatTemplateEngine.thinkingTagsFor(format.index);
          String withTags(String output) => output
              .replaceAll('<think>', tags.startTag)
              .replaceAll('</think>', tags.endTag);
          for (final tools in const [true, false]) {
            for (final forced in const [false, true]) {
              for (final output in [
                ...thoughts,
                if (forced) ...forcedThoughts,
                if (forced) 'Plan it.  \n\n',
                if (!forced) '<think>\n Plan never ends. \n',
                if (!forced) '<think>Plan </thi',
              ]) {
                await _expectStreamMatchesParse(
                  format,
                  withTags(output),
                  forcedOpen: forced,
                  tools: tools,
                  openings: [tags.startTag, tags.endTag],
                );
              }
            }
          }
        }
      });

      test(
        'keeps leading whitespace a PEG parse keeps without tools',
        () async {
          final ministral = pegParser(MinistralHandler());
          final qwen = pegConstructedQwenXmlParser([
            _weatherTool,
          ], thinkingForcedOpen: false);
          final qwenThinking = pegConstructedQwenXmlParser([
            _weatherTool,
          ], thinkingForcedOpen: true);
          for (final (format, parser, forced) in [
            (ChatFormat.ministral, ministral, false),
            (ChatFormat.pegNative, ministral, false),
            (ChatFormat.qwen3CoderXml, qwen, false),
            (ChatFormat.pegConstructed, qwen, false),
            (ChatFormat.qwen3CoderXml, qwenThinking, true),
          ]) {
            final tags = ChatTemplateEngine.thinkingTagsFor(format.index);
            for (final output in [
              ' \n Hi there. \n ',
              '\n\nLine one.\n\nLine two.\n',
              if (forced) ' \n Plan. \n${tags.endTag}\n\n Sure. \n',
            ]) {
              await _expectStreamMatchesParse(
                format,
                output,
                forcedOpen: forced,
                parser: parser,
                tools: false,
              );
            }
          }
        },
      );

      test('whitespace after the last content arrives when the stream '
          'ends', () async {
        for (final format in const [
          ChatFormat.contentOnly,
          ChatFormat.hermes,
          ChatFormat.kimiK3,
        ]) {
          for (final tools in const [true, false]) {
            final tokens = StreamController<String>();
            final content = StringBuffer();
            String? finishReason;
            final subscription =
                ChatCompletionStreamParser.parse(
                  tokenStream: tokens.stream,
                  templateResult: LlamaChatTemplateResult(
                    prompt: 'prompt',
                    format: format.index,
                  ),
                  parseToolCallsEnabled: tools,
                  enableThinking: true,
                  modelName: 'test-model',
                  completionId: 'trailing-whitespace',
                  tools: tools ? [_weatherTool] : null,
                ).listen((chunk) {
                  content.write(chunk.choices.single.delta.content ?? '');
                  finishReason = chunk.choices.single.finishReason;
                });
            addTearDown(subscription.cancel);
            addTearDown(tokens.close);

            for (final token in const ['alpha', ' ', '\n']) {
              tokens.add(token);
              await pumpEventQueue();
              expect(content.toString(), 'alpha', reason: format.name);
            }
            await tokens.close();
            await subscription.asFuture<void>();

            expect(content.toString(), 'alpha \n', reason: format.name);
            expect(finishReason, 'stop');
          }
        }
      });

      test('trailing whitespace of partial parses waits', () async {
        const namespace = ']<]minimax[>[';
        await _expectStreamMatchesParse(
          ChatFormat.minimaxM3,
          'Let me check.\n$namespace<tool_call>\n'
          '$namespace<invoke name="weather">'
          '$namespace<city>Paris$namespace</city>'
          '$namespace</invoke>\n$namespace</tool_call>',
        );
        await _expectStreamMatchesParse(
          ChatFormat.minimaxM3,
          'Plan.\n</mm:think>\n\nSure.\n',
          forcedOpen: true,
        );
      });

      test('without tools, text streams as each token arrives', () async {
        await _expectStreamedAfterEachToken(
          ChatFormat.deepseekR1,
          tools: false,
          const [
            ('<think>', '', ''),
            ('\n', '', ''),
            ('Plan', 'Plan', ''),
            (' it', 'Plan it', ''),
            ('.\n', 'Plan it.', ''),
            ('</think>', 'Plan it.', ''),
            ('\n\n', 'Plan it.', ''),
            ('Sure', 'Plan it.', 'Sure'),
            (' \n', 'Plan it.', 'Sure'),
            ('thing', 'Plan it.', 'Sure \nthing'),
          ],
        );
        await _expectStreamedAfterEachToken(
          ChatFormat.hermes,
          forcedOpen: true,
          tools: false,
          const [
            ('Use ', 'Use', ''),
            (r'\', r'Use \', ''),
            ('n', r'Use \n', ''),
            (' <tool', r'Use \n <tool', ''),
            ('_call>', r'Use \n <tool_call>', ''),
          ],
        );
      });
    });

    test('preserves MiniMax M3 schema types across split tokens', () async {
      const namespace = ']<]minimax[>[';
      const output =
          '$namespace<tool_call>'
          '$namespace<invoke name="inspect">'
          '$namespace<code>123$namespace</code>'
          '$namespace<options>$namespace</options>'
          '$namespace<items>$namespace</items>'
          '$namespace</invoke>$namespace</tool_call>';
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(<String>[
          output.substring(0, 7),
          output.substring(7, 31),
          output.substring(31, 58),
          output.substring(58, 87),
          output.substring(87),
        ]),
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: ChatFormat.minimaxM3.index,
        ),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'test-model',
        completionId: 'm3-typed-split',
        tools: [_typedStreamTool],
      ).toList();

      final content = chunks
          .map((chunk) => chunk.choices.single.delta.content ?? '')
          .join();
      final toolCall = chunks
          .expand((chunk) => chunk.choices.single.delta.toolCalls ?? const [])
          .single;
      expect(content, isEmpty);
      expect(jsonDecode(toolCall.function!.arguments!), {
        'code': '123',
        'options': <String, dynamic>{},
        'items': <Object?>[],
      });
    });

    test('does not stream partial Laguna tool markup as content', () async {
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(<String>[
          'Visible answer.',
          '<',
          'tool_call>weather\n',
          '<arg_key>city</arg_key><arg_value>Seoul</arg_value>',
          '</tool_call>',
        ]),
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: ChatFormat.laguna.index,
        ),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'test-model',
        completionId: 'laguna-partial',
        tools: [_weatherTool],
      ).toList();

      final content = chunks
          .map((chunk) => chunk.choices.single.delta.content ?? '')
          .join();
      final toolCall = chunks
          .expand((chunk) => chunk.choices.single.delta.toolCalls ?? const [])
          .single;
      expect(content, 'Visible answer.');
      expect(content, isNot(contains('<tool')));
      expect(toolCall.function?.name, 'weather');
      expect(jsonDecode(toolCall.function!.arguments!), {'city': 'Seoul'});
    });

    test('does not stream partial GLM tool markup as content', () async {
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(<String>[
          'Visible answer.',
          '<',
          'tool_call>weather\n',
          '<arg_key>city</arg_key><arg_value>Seoul</arg_value>',
          '</tool_call>',
        ]),
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: ChatFormat.glm45.index,
        ),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'test-model',
        completionId: 'glm-partial',
        tools: [_weatherTool],
      ).toList();

      final content = chunks
          .map((chunk) => chunk.choices.single.delta.content ?? '')
          .join();
      final toolCall = chunks
          .expand((chunk) => chunk.choices.single.delta.toolCalls ?? const [])
          .single;
      expect(content, 'Visible answer.');
      expect(content, isNot(contains('<tool')));
      expect(toolCall.function?.name, 'weather');
      expect(jsonDecode(toolCall.function!.arguments!), {'city': 'Seoul'});
    });

    test('streams compact and newline GLM layouts like parse', () async {
      const compact =
          '<tool_call>weather<arg_key>city</arg_key>'
          '<arg_value>Paris</arg_value></tool_call>';
      const newline =
          '<tool_call>weather\n<arg_key>city</arg_key>\n'
          '<arg_value>Paris</arg_value>\n</tool_call>\n';
      for (final format in [ChatFormat.glm45, ChatFormat.laguna]) {
        for (final call in [compact, newline]) {
          final parsed = ChatTemplateEngine.parse(
            format.index,
            call,
            tools: [_weatherTool],
          );
          expect(parsed.content, isEmpty, reason: '${format.name} $call');
          expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
            'city': 'Paris',
          });
          for (final (output, forcedOpen) in [
            (call, false),
            ('Let me check.$call', false),
            ('$call$call', false),
            ('Plan.</think>$call', true),
          ]) {
            for (final ending in ['natural', 'length', 'cancel']) {
              await _expectStreamMatchesParse(
                format,
                output,
                forcedOpen: forcedOpen,
                atLimit: ending == 'length',
                cancelled: ending == 'cancel',
                openings: ['<tool_call>', '<arg_key>', '</arg_value>'],
              );
            }
          }
        }
      }
    });

    test('does not stream partial Muse routing markup as content', () async {
      const atem =
          '<atem:function_calls><atem:invoke name="weather">'
          '<atem:parameter name="city">Seoul</atem:parameter>'
          '</atem:invoke></atem:function_calls>';
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(<String>[
          'Visible answer.',
          '<',
          '|start|>assistant to=weather<|mess',
          'age|>$atem<|eot|>',
        ]),
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: ChatFormat.museGlimmer.index,
        ),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'test-model',
        completionId: 'muse-partial',
        tools: [_weatherTool],
      ).toList();

      final content = chunks
          .map((chunk) => chunk.choices.single.delta.content ?? '')
          .join();
      final toolCall = chunks
          .expand((chunk) => chunk.choices.single.delta.toolCalls ?? const [])
          .single;
      expect(content, 'Visible answer.');
      expect(content, isNot(contains('<|start|>')));
      expect(toolCall.function?.name, 'weather');
      expect(jsonDecode(toolCall.function!.arguments!), {'city': 'Seoul'});
    });

    test('character-split Muse routing never leaks protocol content', () async {
      const atem =
          '<atem:function_calls><atem:invoke name="weather">'
          '<atem:parameter name="city">Seoul</atem:parameter>'
          '</atem:invoke></atem:function_calls>';
      const output =
          'Visible answer.<|start|>assistant to=weather<|message|>'
          '$atem<|eot|>';
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.fromIterable(output.split('')),
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: ChatFormat.museGlimmer.index,
        ),
        parseToolCallsEnabled: true,
        enableThinking: true,
        modelName: 'test-model',
        completionId: 'muse-character-split',
        tools: [_weatherTool],
      ).toList();

      final content = chunks
          .map((chunk) => chunk.choices.single.delta.content ?? '')
          .join();
      expect(content, 'Visible answer.');
      expect(content, isNot(contains('<|')));
      expect(content, isNot(contains('<atem:')));
      expect(
        chunks
            .expand((chunk) => chunk.choices.single.delta.toolCalls ?? const [])
            .single
            .function
            ?.name,
        'weather',
      );
    });

    test(
      'specialized formats suppress split envelopes and reconcile malformed finals',
      () async {
        const namespace = ']<]minimax[>[';
        final cases =
            <
              ({
                String name,
                int format,
                String marker,
                String valid,
                String malformed,
              })
            >[
              (
                name: 'Kimi K3',
                format: ChatFormat.kimiK3.index,
                marker: '<|open|>tools',
                valid:
                    'Visible answer.<|open|>tools<|sep|>'
                    '<|open|>call tool="weather"<|sep|>'
                    '<|open|>argument key="city" type="string"<|sep|>Seoul'
                    '<|close|>argument<|sep|><|close|>call<|sep|>'
                    '<|close|>tools<|sep|><|close|>message<|sep|>',
                malformed:
                    'Visible answer.<|open|>tools<|sep|>'
                    '<|open|>call tool="unknown"<|sep|>'
                    '<|open|>argument key="city" type="string"<|sep|>Seoul'
                    '<|close|>argument<|sep|><|close|>call<|sep|>'
                    '<|close|>tools<|sep|><|close|>message<|sep|>',
              ),
              (
                name: 'MiniMax M1',
                format: ChatFormat.minimaxM1.index,
                marker: '<tool_calls>',
                valid:
                    'Visible answer.<tool_calls>\n'
                    '{"name":"weather","arguments":{"city":"Seoul"}}\n'
                    '</tool_calls>',
                malformed:
                    'Visible answer.<tool_calls>\n'
                    '{"name":"unknown","arguments":{"city":"Seoul"}}\n'
                    '</tool_calls>',
              ),
              (
                name: 'MiniMax M3',
                format: ChatFormat.minimaxM3.index,
                marker: '$namespace<tool_call>',
                valid:
                    'Visible answer.$namespace<tool_call>'
                    '$namespace<invoke name="weather">'
                    '$namespace<city>Seoul$namespace</city>'
                    '$namespace</invoke>$namespace</tool_call>',
                malformed:
                    'Visible answer.$namespace<tool_call>'
                    '$namespace<invoke name="unknown">'
                    '$namespace<city>Seoul$namespace</city>'
                    '$namespace</invoke>$namespace</tool_call>',
              ),
              (
                name: 'DeepSeek V3.2',
                format: ChatFormat.deepseekV32.index,
                marker: '<｜DSML｜function_calls>',
                valid:
                    'Visible answer.<｜DSML｜function_calls>'
                    '<｜DSML｜invoke name="weather">'
                    '<｜DSML｜parameter name="city" string="true">Seoul'
                    '</｜DSML｜parameter></｜DSML｜invoke>'
                    '</｜DSML｜function_calls>',
                malformed:
                    'Visible answer.<｜DSML｜function_calls>'
                    '<｜DSML｜invoke name="unknown">'
                    '<｜DSML｜parameter name="city" string="true">Seoul'
                    '</｜DSML｜parameter></｜DSML｜invoke>'
                    '</｜DSML｜function_calls>',
              ),
              (
                name: 'DeepSeek V4',
                format: ChatFormat.deepseekV4.index,
                marker: '<｜DSML｜tool_calls>',
                valid:
                    'Visible answer.<｜DSML｜tool_calls>'
                    '<｜DSML｜invoke name="weather">'
                    '<｜DSML｜parameter name="city" string="true">Seoul'
                    '</｜DSML｜parameter></｜DSML｜invoke>'
                    '</｜DSML｜tool_calls>',
                malformed:
                    'Visible answer.<｜DSML｜tool_calls>'
                    '<｜DSML｜invoke name="unknown">'
                    '<｜DSML｜parameter name="city" string="true">Seoul'
                    '</｜DSML｜parameter></｜DSML｜invoke>'
                    '</｜DSML｜tool_calls>',
              ),
            ];

        for (final testCase in cases) {
          final markerIndex = testCase.valid.indexOf(testCase.marker);
          final validChunks = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable([
              testCase.valid.substring(0, markerIndex + 1),
              testCase.valid.substring(markerIndex + 1, markerIndex + 3),
              testCase.valid.substring(markerIndex + 3),
            ]),
            templateResult: LlamaChatTemplateResult(
              prompt: 'prompt',
              format: testCase.format,
            ),
            parseToolCallsEnabled: true,
            enableThinking: true,
            modelName: 'test-model',
            completionId: '${testCase.name}-valid',
            tools: [_weatherTool],
          ).toList();
          final validContent = validChunks
              .map((chunk) => chunk.choices.single.delta.content ?? '')
              .join();
          final toolCall = validChunks
              .expand(
                (chunk) => chunk.choices.single.delta.toolCalls ?? const [],
              )
              .single;
          expect(validContent, 'Visible answer.', reason: testCase.name);
          expect(
            validContent,
            isNot(contains(testCase.marker)),
            reason: testCase.name,
          );
          expect(toolCall.function?.name, 'weather', reason: testCase.name);
          expect(jsonDecode(toolCall.function!.arguments!), {
            'city': 'Seoul',
          }, reason: testCase.name);

          final malformedMarkerIndex = testCase.malformed.indexOf(
            testCase.marker,
          );
          final malformedChunks = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable([
              testCase.malformed.substring(0, malformedMarkerIndex + 1),
              testCase.malformed.substring(
                malformedMarkerIndex + 1,
                malformedMarkerIndex + 3,
              ),
              testCase.malformed.substring(malformedMarkerIndex + 3),
            ]),
            templateResult: LlamaChatTemplateResult(
              prompt: 'prompt',
              format: testCase.format,
            ),
            parseToolCallsEnabled: true,
            enableThinking: true,
            modelName: 'test-model',
            completionId: '${testCase.name}-malformed',
            tools: [_weatherTool],
          ).toList();
          final malformedContent = malformedChunks
              .map((chunk) => chunk.choices.single.delta.content ?? '')
              .join();
          final expectedMalformedContent = switch (testCase.format) {
            final format when format == ChatFormat.kimiK3.index =>
              testCase.malformed.replaceAll('<|close|>message<|sep|>', ''),
            _ => testCase.malformed,
          };
          expect(
            malformedContent,
            expectedMalformedContent,
            reason: '${testCase.name} final rollback',
          );
          expect(
            malformedContent,
            contains(testCase.marker),
            reason: '${testCase.name} malformed protocol preservation',
          );
          expect(
            malformedChunks.expand(
              (chunk) => chunk.choices.single.delta.toolCalls ?? const [],
            ),
            isEmpty,
            reason: testCase.name,
          );
          expect(
            malformedChunks.last.choices.single.finishReason,
            'stop',
            reason: testCase.name,
          );
        }
      },
    );

    test(
      'specialized thinking prefixes do not leak following tool markup',
      () async {
        const namespace = ']<]minimax[>[';
        final cases =
            <({String name, int format, String output, String marker})>[
              (
                name: 'Kimi K3',
                format: ChatFormat.kimiK3.index,
                output:
                    'reasoning<|close|>think<|sep|>'
                    '<|open|>tools<|sep|>'
                    '<|open|>call tool="weather"<|sep|>'
                    '<|open|>argument key="city" type="string"<|sep|>Seoul'
                    '<|close|>argument<|sep|><|close|>call<|sep|>'
                    '<|close|>tools<|sep|><|close|>message<|sep|>',
                marker: '<|open|>tools',
              ),
              (
                name: 'MiniMax M3',
                format: ChatFormat.minimaxM3.index,
                output:
                    '<mm:think>reasoning</mm:think>'
                    '$namespace<tool_call>'
                    '$namespace<invoke name="weather">'
                    '$namespace<city>Seoul$namespace</city>'
                    '$namespace</invoke>$namespace</tool_call>',
                marker: '$namespace<tool_call>',
              ),
              (
                name: 'DeepSeek V3.2',
                format: ChatFormat.deepseekV32.index,
                output:
                    'reasoning</think>'
                    '<｜DSML｜function_calls>'
                    '<｜DSML｜invoke name="weather">'
                    '<｜DSML｜parameter name="city" string="true">Seoul'
                    '</｜DSML｜parameter></｜DSML｜invoke>'
                    '</｜DSML｜function_calls>',
                marker: '<｜DSML｜function_calls>',
              ),
            ];

        for (final testCase in cases) {
          final markerIndex = testCase.output.indexOf(testCase.marker);
          final chunks = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable([
              testCase.output.substring(0, markerIndex + 1),
              testCase.output.substring(markerIndex + 1),
            ]),
            templateResult: LlamaChatTemplateResult(
              prompt: 'prompt',
              format: testCase.format,
              thinkingForcedOpen: testCase.name != 'MiniMax M3',
            ),
            parseToolCallsEnabled: true,
            enableThinking: true,
            modelName: 'test-model',
            completionId: '${testCase.name}-thinking',
            tools: [_weatherTool],
          ).toList();
          final content = chunks
              .map((chunk) => chunk.choices.single.delta.content ?? '')
              .join();
          final reasoning = chunks
              .map((chunk) => chunk.choices.single.delta.thinking ?? '')
              .join();

          expect(content, isEmpty, reason: testCase.name);
          expect(reasoning, 'reasoning', reason: testCase.name);
          expect(reasoning, isNot(contains(testCase.marker)));
          expect(
            chunks
                .expand(
                  (chunk) => chunk.choices.single.delta.toolCalls ?? const [],
                )
                .single
                .function
                ?.name,
            'weather',
            reason: testCase.name,
          );
        }
      },
    );

    test(
      'forced-open DSML withholds character-split envelopes from reasoning',
      () async {
        for (final testCase in const [
          (
            name: 'DeepSeek V3.2',
            format: ChatFormat.deepseekV32,
            envelope: 'function_calls',
          ),
          (
            name: 'DeepSeek V4',
            format: ChatFormat.deepseekV4,
            envelope: 'tool_calls',
          ),
        ]) {
          final callsStart = '<｜DSML｜${testCase.envelope}>';
          final callsEnd = '</｜DSML｜${testCase.envelope}>';
          final valid =
              'reasoning$callsStart'
              '<｜DSML｜invoke name="weather">'
              '<｜DSML｜parameter name="city" string="true">Seoul'
              '</｜DSML｜parameter></｜DSML｜invoke>$callsEnd';
          final chunks = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable(valid.split('')),
            templateResult: LlamaChatTemplateResult(
              prompt: 'prompt',
              format: testCase.format.index,
              thinkingForcedOpen: true,
            ),
            parseToolCallsEnabled: true,
            enableThinking: true,
            modelName: 'test-model',
            completionId: '${testCase.name}-split-forced-open',
            tools: [_weatherTool],
          ).toList();
          final reasoning = chunks
              .map((chunk) => chunk.choices.single.delta.thinking ?? '')
              .join();
          final content = chunks
              .map((chunk) => chunk.choices.single.delta.content ?? '')
              .join();

          expect(reasoning, 'reasoning', reason: testCase.name);
          expect(reasoning, isNot(contains('<｜DSML｜')));
          expect(content, isEmpty, reason: testCase.name);
          expect(
            chunks
                .expand(
                  (chunk) => chunk.choices.single.delta.toolCalls ?? const [],
                )
                .single
                .function
                ?.name,
            'weather',
            reason: testCase.name,
          );

          final malformed = valid.replaceFirst('name="weather"', 'name="bad"');
          final malformedChunks = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable(malformed.split('')),
            templateResult: LlamaChatTemplateResult(
              prompt: 'prompt',
              format: testCase.format.index,
              thinkingForcedOpen: true,
            ),
            parseToolCallsEnabled: true,
            enableThinking: true,
            modelName: 'test-model',
            completionId: '${testCase.name}-split-malformed',
            tools: [_weatherTool],
          ).toList();
          expect(
            malformedChunks
                .map((chunk) => chunk.choices.single.delta.thinking ?? '')
                .join(),
            'reasoning',
            reason: '${testCase.name} malformed reasoning',
          );
          expect(
            malformedChunks
                .map((chunk) => chunk.choices.single.delta.content ?? '')
                .join(),
            malformed.substring('reasoning'.length),
            reason: '${testCase.name} malformed content rollback',
          );
          expect(
            malformedChunks.expand(
              (chunk) => chunk.choices.single.delta.toolCalls ?? const [],
            ),
            isEmpty,
            reason: testCase.name,
          );
        }
      },
    );
  });
}

final _weatherTool = ToolDefinition(
  name: 'weather',
  description: 'Weather',
  parameters: [ToolParam.string('city', required: true)],
  handler: (_) async => null,
);

final _typedStreamTool = ToolDefinition(
  name: 'inspect',
  description: 'Inspect typed values',
  parameters: [
    ToolParam.string('code', required: true),
    ToolParam.object('options', properties: const [], required: true),
    ToolParam.array(
      'items',
      itemType: ToolParam.string('item'),
      required: true,
    ),
  ],
  handler: (_) async => null,
);

const _hermesDoubleBrace =
    '<tool_call>\n{{"name": "weather", "arguments": {"city": "Paris"}}\n</tool_call>';

/// Splits [output] whole, into 1- and 2-character pieces, into random pieces,
/// and in two at every index inside each of [openings].
List<List<String>> _chunkings(String output, List<String> openings) {
  final random = Random(output.length);
  List<String> pieces(int Function() size) {
    final result = <String>[];
    for (var i = 0; i < output.length;) {
      final end = min(output.length, i + size());
      result.add(output.substring(i, end));
      i = end;
    }
    return result;
  }

  return [
    [output],
    pieces(() => 1),
    pieces(() => 2),
    for (var run = 0; run < 5; run++) pieces(() => 1 + random.nextInt(7)),
    for (final opening in openings)
      for (
        var at = output.indexOf(opening);
        at >= 0;
        at = output.indexOf(opening, at + 1)
      )
        for (var split = at + 1; split < at + opening.length; split++)
          [output.substring(0, split), output.substring(split)],
  ];
}

/// Expects streamed content, reasoning and calls of [output] to equal
/// [ChatTemplateEngine.parse] for every chunking.
Future<void> _expectStreamMatchesParse(
  ChatFormat format,
  String output, {
  bool forcedOpen = false,
  String? parser,
  List<String> openings = const [],
  bool tools = true,
  bool enableThinking = true,
  bool atLimit = false,
  bool cancelled = false,
  bool thoughtClosed = false,
  bool thinkingForcedClosed = false,
  bool everySplit = false,
}) async {
  var parsed = parseRenderedOutput(
    format.index,
    output,
    parseToolCalls: tools,
    thinkingForcedOpen: forcedOpen,
    thoughtClosedForThinkingOff: thoughtClosed,
    thinkingForcedClosed: thinkingForcedClosed,
    cancelled: cancelled,
    parser: parser,
    tools: tools ? [_weatherTool] : null,
  );
  if (atLimit && !cancelled && tools && format == ChatFormat.lfm2) {
    final partial = parseRenderedOutput(
      format.index,
      output,
      isPartial: true,
      parseToolCalls: true,
      thinkingForcedOpen: forcedOpen,
      thoughtClosedForThinkingOff: thoughtClosed,
      thinkingForcedClosed: thinkingForcedClosed,
      parser: parser,
      tools: [_weatherTool],
    );
    if (partial.partialToolCalls.isNotEmpty) parsed = partial;
  }
  for (final tokens in [
    ..._chunkings(output, openings),
    if (everySplit)
      for (var split = 1; split < output.length; split++)
        [output.substring(0, split), output.substring(split)],
  ]) {
    final chunks = await ChatCompletionStreamParser.parse(
      tokenStream: Stream.fromIterable(tokens),
      templateResult: withThoughtClosedForThinkingOff(
        withThinkingForcedClosed(
          LlamaChatTemplateResult(
            prompt: 'prompt',
            format: format.index,
            thinkingForcedOpen: forcedOpen,
            parser: parser,
          ),
          closed: thinkingForcedClosed,
        ),
        closed: thoughtClosed,
      ),
      parseToolCallsEnabled: tools,
      enableThinking: enableThinking,
      modelName: 'test-model',
      completionId: 'stream-matches-parse',
      stoppedAtLimit: () => atLimit,
      cancelled: () => cancelled,
      tools: tools ? [_weatherTool] : null,
    ).toList();

    final calls = chunks
        .expand((chunk) => chunk.choices.single.delta.toolCalls ?? const [])
        .toList();
    expect(
      chunks.map((chunk) => chunk.choices.single.delta.content ?? '').join(),
      parsed.content,
      reason: '${format.name} tools: $tools $tokens',
    );
    expect(
      chunks.map((chunk) => chunk.choices.single.delta.thinking ?? '').join(),
      enableThinking ? parsed.reasoningContent ?? '' : '',
      reason: '${format.name} tools: $tools $tokens',
    );
    expect(
      [
        for (final call in calls)
          '${call.function?.name} ${call.function?.arguments}',
      ],
      [
        if (!atLimit)
          for (final call in parsed.toolCalls)
            '${call.function?.name} ${call.function?.arguments}',
      ],
      reason: '$tokens',
    );
    expect(
      chunks.last.choices.single.finishReason,
      atLimit
          ? 'length'
          : parsed.hasToolCalls
          ? 'tool_calls'
          : 'stop',
    );
  }
}

/// Feeds each token of [steps] and expects the content streamed so far.
Future<void> _expectContentAfterEachToken(
  ChatFormat format,
  List<(String token, String streamed)> steps,
) async {
  final tokens = StreamController<String>();
  final content = StringBuffer();
  final subscription = ChatCompletionStreamParser.parse(
    tokenStream: tokens.stream,
    templateResult: LlamaChatTemplateResult(
      prompt: 'prompt',
      format: format.index,
    ),
    parseToolCallsEnabled: true,
    enableThinking: true,
    modelName: 'test-model',
    completionId: 'latency',
    tools: [_weatherTool],
  ).listen((chunk) => content.write(chunk.choices.single.delta.content ?? ''));
  addTearDown(subscription.cancel);
  addTearDown(tokens.close);

  for (final (token, streamed) in steps) {
    tokens.add(token);
    await pumpEventQueue();
    expect(content.toString(), streamed, reason: token);
  }
}

/// Streams [tokens] of a forced-open thought and returns the reasoning streamed
/// before the tokens after [thought] arrive.
Future<String> _reasoningBeforeEndTag(
  ChatFormat format,
  Iterable<String> tokens,
  String thought, {
  bool tools = true,
}) async {
  final controller = StreamController<String>();
  final reasoning = StringBuffer();
  final subscription =
      ChatCompletionStreamParser.parse(
        tokenStream: controller.stream,
        templateResult: LlamaChatTemplateResult(
          prompt: 'prompt',
          format: format.index,
          thinkingForcedOpen: true,
        ),
        parseToolCallsEnabled: tools,
        enableThinking: true,
        modelName: 'test-model',
        completionId: 'liveness',
        tools: tools ? [_weatherTool] : null,
      ).listen(
        (chunk) => reasoning.write(chunk.choices.single.delta.thinking ?? ''),
      );
  var fed = 0;
  String? before;
  for (final token in tokens) {
    if (fed >= thought.length) {
      before ??= reasoning.toString();
    }
    controller.add(token);
    fed += token.length;
    await Future<void>.delayed(Duration.zero);
  }
  await controller.close();
  await subscription.asFuture<void>();
  return before ?? reasoning.toString();
}

/// Feeds each token of [steps] and expects the reasoning and content streamed
/// so far.
Future<void> _expectStreamedAfterEachToken(
  ChatFormat format,
  List<(String token, String reasoning, String content)> steps, {
  bool forcedOpen = false,
  bool tools = true,
  bool thoughtClosed = false,
}) async {
  final tokens = StreamController<String>();
  final reasoning = StringBuffer();
  final content = StringBuffer();
  final subscription =
      ChatCompletionStreamParser.parse(
        tokenStream: tokens.stream,
        templateResult: withThoughtClosedForThinkingOff(
          LlamaChatTemplateResult(
            prompt: 'prompt',
            format: format.index,
            thinkingForcedOpen: forcedOpen,
          ),
          closed: thoughtClosed,
        ),
        parseToolCallsEnabled: tools,
        enableThinking: true,
        modelName: 'test-model',
        completionId: 'latency',
        tools: tools ? [_weatherTool] : null,
      ).listen((chunk) {
        reasoning.write(chunk.choices.single.delta.thinking ?? '');
        content.write(chunk.choices.single.delta.content ?? '');
      });
  addTearDown(subscription.cancel);
  addTearDown(tokens.close);

  for (final (token, streamedReasoning, streamedContent) in steps) {
    tokens.add(token);
    await pumpEventQueue();
    expect(reasoning.toString(), streamedReasoning, reason: token);
    expect(content.toString(), streamedContent, reason: token);
  }
}
