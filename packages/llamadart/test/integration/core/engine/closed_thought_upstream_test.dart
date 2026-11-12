@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/engine/chat_template_renderer.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_format_registry.dart';
import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/chat_template_handler.dart';
import 'package:llamadart/src/core/template/handlers/deepseek_v3_handler.dart';
import 'package:llamadart/src/core/template/handlers/hermes_handler.dart';
import 'package:llamadart/src/core/template/handlers/qwen3_coder_xml_handler.dart';
import 'package:llamadart/src/core/template/thinking_utils.dart';
import 'package:test/test.dart';

final Map<String, dynamic> _fixture =
    jsonDecode(
          File('test/fixtures/closed_thought_upstream.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'weather',
  description: 'w',
  parameters: [ToolParam.string('city', required: true)],
  handler: (_) async => 'Sunny',
);

List<String> _calls(Iterable<({String? name, String? arguments})> calls) => [
  for (final call in calls) '${call.name} ${jsonDecode(call.arguments!)}',
];

/// [output] whole, bytewise, in 3-character chunks and split in two at every
/// point.
List<List<String>> _chunkings(String output) => [
  [output],
  output.split(''),
  [
    for (var i = 0; i < output.length; i += 3)
      output.substring(i, i + 3 > output.length ? output.length : i + 3),
  ],
  for (var split = 1; split < output.length; split++)
    [output.substring(0, split), output.substring(split)],
];

// With thinking off, these templates end the prompt with an empty thought,
// and llama.cpp then parses the reply as content, thinking tags included.
void main() {
  for (final entry
      in (_fixture['templates'] as List).cast<Map<String, dynamic>>()) {
    final templatePath = entry['template'] as String;
    group(templatePath.split('/').last, () {
      late LlamaChatTemplateResult rendered;

      setUpAll(
        () => rendered = ChatTemplateEngine.render(
          templateSource: File(templatePath).readAsStringSync(),
          messages: [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: _fixture['user_prompt'] as String,
            ),
          ],
          metadata: const {},
          tools: [_weatherTool],
          enableThinking: false,
        ),
      );

      test('closes the thought as llama.cpp does', () {
        expect(
          rendered.format,
          ChatFormat.values.byName(entry['format'] as String).index,
        );
        expect(rendered.prompt, endsWith(entry['generation_prompt'] as String));
        expect(rendered.thinkingForcedOpen, isFalse);
        expect(thinkingForcedClosedOf(rendered), isTrue);
      });

      test(
        'keeps the closed thought through grammar and token counts',
        () async {
          final source = File(templatePath).readAsStringSync();
          final messages = [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: _fixture['user_prompt'] as String,
            ),
          ];
          final results = [
            ChatTemplateEngine.render(
              templateSource: source,
              messages: messages,
              metadata: const {},
              tools: [_weatherTool],
              toolChoice: ToolChoice.required,
              enableThinking: false,
            ),
            ChatTemplateEngine.render(
              templateSource: source,
              messages: messages,
              metadata: const {},
              responseFormat: const {
                'type': 'json_schema',
                'json_schema': {
                  'schema': {'type': 'object'},
                },
              },
              enableThinking: false,
            ),
            await ChatTemplateRenderer.render(
              loadMetadata: () async => {'tokenizer.chat_template': source},
              tokenize: (text, {bool addSpecial = true}) async => const [1],
              messages: messages,
              enableThinking: false,
            ),
          ];
          for (final (index, result) in results.indexed) {
            // A response schema renders DeepSeek V3 and Hermes templates as
            // content-only, where the closed thought does not apply.
            if (result.format == ChatFormat.contentOnly.index) continue;
            expect(result.format, rendered.format, reason: '$index');
            expect(thinkingForcedClosedOf(result), isTrue, reason: '$index');
          }
        },
      );

      for (final c in (entry['cases'] as List).cast<Map<String, dynamic>>()) {
        final output = c['output'] as String;
        final upstream = c['upstream'] as Map<String, dynamic>;
        test('${c['name']} parses and streams as llama.cpp parses', () async {
          final parsed = ChatTemplateEngine.parse(
            rendered.format,
            output,
            thinkingForcedClosed: true,
            tools: [_weatherTool],
          );
          // llamadart trims some whitespace around content that llama.cpp
          // keeps.
          expect(parsed.content.trim(), (upstream['content'] as String).trim());
          expect(parsed.reasoningContent, isNull);
          final upstreamCalls = _calls([
            for (final call
                in (upstream['tool_calls'] as List)
                    .cast<Map<String, dynamic>>())
              (
                name: call['name'] as String,
                arguments: call['arguments'] as String,
              ),
          ]);
          expect(
            _calls([
              for (final call in parsed.toolCalls)
                (
                  name: call.function?.name,
                  arguments: call.function?.arguments,
                ),
            ]),
            upstreamCalls,
          );

          final textParse = ChatTemplateEngine.parse(
            rendered.format,
            output,
            parseToolCalls: false,
            thinkingForcedClosed: true,
          );
          expect(textParse.reasoningContent, isNull);

          // A thinking kwarg can turn thinking on for a prompt that closes
          // the thought; the reply still has none.
          for (final (withTools, enableThinking) in const [
            (true, false),
            (false, false),
            (true, true),
          ]) {
            for (final tokens in [
              [output],
              output.split(''),
            ]) {
              final chunks = await ChatCompletionStreamParser.parse(
                tokenStream: Stream.fromIterable(tokens),
                templateResult: rendered,
                parseToolCallsEnabled: withTools,
                enableThinking: enableThinking,
                modelName: 'test-model',
                completionId: 'closed-thought-upstream',
                tools: withTools ? [_weatherTool] : null,
              ).toList();
              final deltas = chunks.map((chunk) => chunk.choices.single.delta);
              final reason =
                  '${tokens.length} tokens, tools: $withTools, '
                  'enableThinking: $enableThinking';
              expect(
                deltas.map((delta) => delta.content ?? '').join(),
                withTools ? parsed.content : textParse.content,
                reason: reason,
              );
              expect(
                deltas.map((delta) => delta.thinking ?? '').join(),
                isEmpty,
                reason: reason,
              );
              expect(
                _calls([
                  for (final delta in deltas)
                    for (final call in delta.toolCalls ?? const [])
                      (
                        name: call.function?.name,
                        arguments: call.function?.arguments,
                      ),
                ]),
                withTools ? upstreamCalls : isEmpty,
                reason: reason,
              );
            }
          }
        });
      }

      // The template closed the thought, so no reply text waits for a tag.
      test('streams a reply as it arrives', () async {
        for (final enableThinking in const [false, true]) {
          final tokens = StreamController<String>();
          final content = StringBuffer();
          final subscription =
              ChatCompletionStreamParser.parse(
                tokenStream: tokens.stream,
                templateResult: rendered,
                parseToolCallsEnabled: false,
                enableThinking: enableThinking,
                modelName: 'test-model',
                completionId: 'template-closed-latency',
              ).listen(
                (chunk) =>
                    content.write(chunk.choices.single.delta.content ?? ''),
              );
          for (final (token, streamed) in const [
            ('Sunny', 'Sunny'),
            (' today.', 'Sunny today.'),
          ]) {
            tokens.add(token);
            await pumpEventQueue();
            expect(
              content.toString(),
              streamed,
              reason: 'enableThinking: $enableThinking',
            );
          }
          await tokens.close();
          await subscription.asFuture<void>();
        }
      });

      // With thinking on, the same templates leave the thought open.
      test('streams each reply with thinking on as it parses', () async {
        final forcedOpen = ChatTemplateEngine.render(
          templateSource: File(templatePath).readAsStringSync(),
          messages: [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: _fixture['user_prompt'] as String,
            ),
          ],
          metadata: const {},
          tools: [_weatherTool],
        );
        // Qwen3-4B leaves opening a thought to the model.
        final opensThought = !templatePath.endsWith('/Qwen3-4B.jinja');
        expect(forcedOpen.thinkingForcedOpen, opensThought);
        if (!opensThought) return;
        for (final c in (entry['cases'] as List).cast<Map<String, dynamic>>()) {
          final output = c['output'] as String;
          for (final withTools in const [true, false]) {
            final parsed = ChatTemplateEngine.parse(
              forcedOpen.format,
              output,
              parseToolCalls: withTools,
              thinkingForcedOpen: true,
              tools: withTools ? [_weatherTool] : null,
            );
            for (final tokens in _chunkings(output)) {
              final deltas = (await ChatCompletionStreamParser.parse(
                tokenStream: Stream.fromIterable(tokens),
                templateResult: forcedOpen,
                parseToolCallsEnabled: withTools,
                enableThinking: true,
                modelName: 'test-model',
                completionId: 'forced-open-upstream',
                tools: withTools ? [_weatherTool] : null,
              ).toList()).map((chunk) => chunk.choices.single.delta);
              final reason = '${c['name']} $tokens, tools: $withTools';
              expect(
                deltas.map((delta) => delta.content ?? '').join(),
                parsed.content,
                reason: reason,
              );
              expect(
                deltas.map((delta) => delta.thinking ?? '').join(),
                parsed.reasoningContent ?? '',
                reason: reason,
              );
              expect(
                _calls([
                  for (final delta in deltas)
                    for (final call in delta.toolCalls ?? const [])
                      (
                        name: call.function?.name,
                        arguments: call.function?.arguments,
                      ),
                ]),
                _calls([
                  for (final call in parsed.toolCalls)
                    (
                      name: call.function?.name,
                      arguments: call.function?.arguments,
                    ),
                ]),
                reason: reason,
              );
            }
          }
        }
      });
    });
  }

  // With thinking off, these templates still leave the thought open, so
  // llama.cpp parses the reply's leading thought as reasoning. llamadart
  // closes that thought in the prompt, which must not make the reply content.
  for (final entry
      in (_fixture['open_thought_templates'] as List)
          .cast<Map<String, dynamic>>()) {
    final templatePath = entry['template'] as String;
    final closedSuffix = entry['closed_prompt_suffix'] as String;
    group(templatePath.split('/').last, () {
      late LlamaChatTemplateResult rendered;

      setUpAll(
        () => rendered = ChatTemplateEngine.render(
          templateSource: File(templatePath).readAsStringSync(),
          messages: [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: _fixture['user_prompt'] as String,
            ),
          ],
          metadata: const {},
          tools: [_weatherTool],
          enableThinking: false,
        ),
      );

      test('leaves the thought open in the template render', () {
        expect(
          rendered.format,
          ChatFormat.values.byName(entry['format'] as String).index,
        );
        final generationPrompt = (entry['generation_prompt'] as String)
            .trimRight();
        expect(rendered.prompt, endsWith('$generationPrompt$closedSuffix'));
        expect(rendered.thinkingForcedOpen, isFalse);
        expect(thinkingForcedClosedOf(rendered), isFalse);
        expect(thoughtClosedForThinkingOffOf(rendered), isTrue);
      });

      test('keeps the mark through grammar and token counts', () async {
        final source = File(templatePath).readAsStringSync();
        final messages = [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: _fixture['user_prompt'] as String,
          ),
        ];
        final results = [
          ChatTemplateEngine.render(
            templateSource: source,
            messages: messages,
            metadata: const {},
            tools: [_weatherTool],
            toolChoice: ToolChoice.required,
            enableThinking: false,
          ),
          ChatTemplateEngine.render(
            templateSource: source,
            messages: messages,
            metadata: const {},
            responseFormat: const {
              'type': 'json_schema',
              'json_schema': {
                'schema': {'type': 'object'},
              },
            },
            enableThinking: false,
          ),
          await ChatTemplateRenderer.render(
            loadMetadata: () async => {'tokenizer.chat_template': source},
            tokenize: (text, {bool addSpecial = true}) async => const [1],
            messages: messages,
            enableThinking: false,
          ),
        ];
        for (final (index, result) in results.indexed) {
          // A response schema renders Cohere2 MoE templates as content-only.
          if (result.format == ChatFormat.contentOnly.index) continue;
          expect(result.prompt, endsWith(closedSuffix), reason: '$index');
          expect(
            thoughtClosedForThinkingOffOf(result),
            isTrue,
            reason: '$index',
          );
        }
      });

      for (final c in (entry['cases'] as List).cast<Map<String, dynamic>>()) {
        final output = c['output'] as String;
        test('${c['name']} parses and streams as llama.cpp parses', () async {
          for (final withTools in const [true, false]) {
            // llama.cpp rejects some Cohere2 MoE replies without tools.
            final upstream =
                c[withTools ? 'upstream' : 'upstream_without_tools']
                    as Map<String, dynamic>?;
            if (upstream == null) continue;
            final upstreamCalls = _calls([
              for (final call
                  in (upstream['tool_calls'] as List)
                      .cast<Map<String, dynamic>>())
                (
                  name: call['name'] as String,
                  arguments: call['arguments'] as String,
                ),
            ]);
            final parsed = parseRenderedOutput(
              rendered.format,
              output,
              parseToolCalls: withTools,
              thoughtClosedForThinkingOff: thoughtClosedForThinkingOffOf(
                rendered,
              ),
              thinkingForcedClosed: thinkingForcedClosedOf(rendered),
              tools: withTools ? [_weatherTool] : null,
            );
            final reason = 'tools: $withTools';
            expect(
              parsed.content.trim(),
              (upstream['content'] as String).trim(),
              reason: reason,
            );
            expect(
              parsed.reasoningContent?.trim() ?? '',
              (upstream['reasoning_content'] as String).trim(),
              reason: reason,
            );
            expect(
              _calls([
                for (final call in parsed.toolCalls)
                  (
                    name: call.function?.name,
                    arguments: call.function?.arguments,
                  ),
              ]),
              upstreamCalls,
              reason: reason,
            );

            for (final tokens in _chunkings(output)) {
              for (final enableThinking in const [false, true]) {
                final chunks = await ChatCompletionStreamParser.parse(
                  tokenStream: Stream.fromIterable(tokens),
                  templateResult: rendered,
                  parseToolCallsEnabled: withTools,
                  enableThinking: enableThinking,
                  modelName: 'test-model',
                  completionId: 'open-thought-upstream',
                  tools: withTools ? [_weatherTool] : null,
                ).toList();
                final deltas = chunks.map(
                  (chunk) => chunk.choices.single.delta,
                );
                final streamReason =
                    '$tokens, thinking: $enableThinking, $reason';
                expect(
                  deltas.map((delta) => delta.content ?? '').join().trim(),
                  (upstream['content'] as String).trim(),
                  reason: streamReason,
                );
                expect(
                  deltas.map((delta) => delta.thinking ?? '').join(),
                  enableThinking
                      ? (upstream['reasoning_content'] as String).trim()
                      : isEmpty,
                  reason: streamReason,
                );
                expect(
                  _calls([
                    for (final delta in deltas)
                      for (final call in delta.toolCalls ?? const [])
                        (
                          name: call.function?.name,
                          arguments: call.function?.arguments,
                        ),
                  ]),
                  upstreamCalls,
                  reason: streamReason,
                );
              }
            }
          }
        });
      }
    });
  }

  // These renders leave no thought open: Seed-OSS's template never opens one,
  // and Cohere2 MoE's closes its own with `reasoning_effort: none`. llama.cpp
  // then takes a Seed-OSS thought only from the start of the reply, and keeps
  // thinking tags in a Cohere2 MoE text as text. Nor do the Hermes 2 Pro and
  // Qwen3-Coder templates, or Qwen3's with thinking on, where an end tag
  // before any start tag is text, as is every thinking tag after it (#1858).
  // An entry's `enable_thinking` limits it to the flag it was recorded with.
  for (final entry
      in (_fixture['no_thought_templates'] as List)
          .cast<Map<String, dynamic>>()) {
    final templatePath = entry['template'] as String;
    final kwargs = (entry['chat_template_kwargs'] as Map)
        .cast<String, dynamic>();
    final thinkingFlag = entry['enable_thinking'] as bool?;
    for (final enableThinking
        in thinkingFlag == null ? const [false, true] : [thinkingFlag]) {
      group('${templatePath.split('/').last}, thinking: $enableThinking', () {
        late LlamaChatTemplateResult rendered;
        // Without tools, as `upstream_without_tools` was recorded, so a
        // generic template renders content-only. Hermes 2 Pro needs tools to
        // render, and keeps its render with them.
        late LlamaChatTemplateResult renderedWithoutTools;

        setUpAll(() {
          LlamaChatTemplateResult render(List<ToolDefinition>? tools) =>
              ChatTemplateEngine.render(
                templateSource: File(templatePath).readAsStringSync(),
                messages: [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: _fixture['user_prompt'] as String,
                  ),
                ],
                metadata: const {},
                tools: tools,
                chatTemplateKwargs: kwargs,
                enableThinking: enableThinking,
              );
          rendered = render([_weatherTool]);
          try {
            renderedWithoutTools = render(null);
          } on LlamaException {
            renderedWithoutTools = rendered;
          }
        });

        test('leaves no thought open', () {
          expect(
            rendered.format,
            ChatFormat.values.byName(entry['format'] as String).index,
          );
          for (final result in [rendered, renderedWithoutTools]) {
            expect(result.thinkingForcedOpen, isFalse);
            expect(thoughtClosedForThinkingOffOf(result), isFalse);
          }
        });

        for (final c in (entry['cases'] as List).cast<Map<String, dynamic>>()) {
          final output = c['output'] as String;
          final upstreamPartial =
              c['upstream_partial'] as Map<String, dynamic>?;
          if (upstreamPartial != null) {
            // While output may still follow, llama.cpp drops the start of a
            // tag that it may complete.
            test('${c['name']} parses as llama.cpp while partial', () {
              final parsed = ChatTemplateEngine.parseRendered(
                rendered,
                output,
                isPartial: true,
                tools: [_weatherTool],
              );
              expect(
                parsed.content.trim(),
                (upstreamPartial['content'] as String).trim(),
              );
              expect(
                parsed.reasoningContent?.trim() ?? '',
                (upstreamPartial['reasoning_content'] as String).trim(),
              );
              expect(parsed.toolCalls, isEmpty);
            });
          }
          test('${c['name']} parses and streams as llama.cpp parses', () async {
            for (final withTools in const [true, false]) {
              final upstream =
                  c[withTools ? 'upstream' : 'upstream_without_tools']
                      as Map<String, dynamic>;
              final upstreamCalls = _calls([
                for (final call
                    in (upstream['tool_calls'] as List)
                        .cast<Map<String, dynamic>>())
                  (
                    name: call['name'] as String,
                    arguments: call['arguments'] as String,
                  ),
              ]);
              final upstreamReasoning =
                  (upstream['reasoning_content'] as String).trim();
              final render = withTools ? rendered : renderedWithoutTools;
              final parsed = parseRenderedOutput(
                render.format,
                output,
                parseToolCalls: withTools,
                thoughtClosedForThinkingOff: false,
                tools: withTools ? [_weatherTool] : null,
              );
              final reason = 'tools: $withTools';
              expect(
                parsed.content.trim(),
                (upstream['content'] as String).trim(),
                reason: reason,
              );
              expect(
                parsed.reasoningContent?.trim() ?? '',
                upstreamReasoning,
                reason: reason,
              );
              expect(
                _calls([
                  for (final call in parsed.toolCalls)
                    (
                      name: call.function?.name,
                      arguments: call.function?.arguments,
                    ),
                ]),
                upstreamCalls,
                reason: reason,
              );

              for (final tokens in _chunkings(output)) {
                final deltas = (await ChatCompletionStreamParser.parse(
                  tokenStream: Stream.fromIterable(tokens),
                  templateResult: render,
                  parseToolCallsEnabled: withTools,
                  enableThinking: enableThinking,
                  modelName: 'test-model',
                  completionId: 'no-thought-upstream',
                  tools: withTools ? [_weatherTool] : null,
                ).toList()).map((chunk) => chunk.choices.single.delta);
                final streamReason = '$tokens, $reason';
                expect(
                  deltas.map((delta) => delta.content ?? '').join().trim(),
                  (upstream['content'] as String).trim(),
                  reason: streamReason,
                );
                expect(
                  deltas.map((delta) => delta.thinking ?? '').join(),
                  enableThinking ? upstreamReasoning : isEmpty,
                  reason: streamReason,
                );
                expect(
                  _calls([
                    for (final delta in deltas)
                      for (final call in delta.toolCalls ?? const [])
                        (
                          name: call.function?.name,
                          arguments: call.function?.arguments,
                        ),
                  ]),
                  upstreamCalls,
                  reason: streamReason,
                );
              }
            }
          });
        }

        // llama.cpp drops these leading thoughts with thinking off; the
        // engine drops reasoning then, while parseRendered still returns it.
        for (final c
            in (entry['dropped_thought_cases'] as List? ?? const [])
                .cast<Map<String, dynamic>>()) {
          test('${c['name']} streams as llama.cpp parses', () async {
            final output = c['output'] as String;
            for (final withTools in const [true, false]) {
              final upstream =
                  c[withTools ? 'upstream' : 'upstream_without_tools']
                      as Map<String, dynamic>;
              expect(upstream['reasoning_content'], isEmpty);
              final upstreamCalls = _calls([
                for (final call
                    in (upstream['tool_calls'] as List)
                        .cast<Map<String, dynamic>>())
                  (
                    name: call['name'] as String,
                    arguments: call['arguments'] as String,
                  ),
              ]);
              final render = withTools ? rendered : renderedWithoutTools;
              final reason = 'tools: $withTools';
              final parsed = ChatTemplateEngine.parseRendered(
                render,
                output,
                parseToolCalls: withTools,
                tools: withTools ? [_weatherTool] : null,
              );
              expect(
                parsed.content.trim(),
                (upstream['content'] as String).trim(),
                reason: reason,
              );
              expect(parsed.reasoningContent, 'Plan.', reason: reason);
              for (final tokens in _chunkings(output)) {
                final deltas = (await ChatCompletionStreamParser.parse(
                  tokenStream: Stream.fromIterable(tokens),
                  templateResult: render,
                  parseToolCallsEnabled: withTools,
                  enableThinking: false,
                  modelName: 'test-model',
                  completionId: 'dropped-thought-upstream',
                  tools: withTools ? [_weatherTool] : null,
                ).toList()).map((chunk) => chunk.choices.single.delta);
                final streamReason = '$tokens, $reason';
                expect(
                  deltas.map((delta) => delta.content ?? '').join().trim(),
                  (upstream['content'] as String).trim(),
                  reason: streamReason,
                );
                expect(
                  deltas.map((delta) => delta.thinking ?? '').join(),
                  isEmpty,
                  reason: streamReason,
                );
                expect(
                  _calls([
                    for (final delta in deltas)
                      for (final call in delta.toolCalls ?? const [])
                        (
                          name: call.function?.name,
                          arguments: call.function?.arguments,
                        ),
                  ]),
                  upstreamCalls,
                  reason: streamReason,
                );
              }
            }
          });
        }
      });
    }
  }

  // The stream keeps thinking tags as content for exactly these formats.
  test('only formats with the trait parse no thought after a closed one', () {
    for (final registration in chatFormatRegistrations) {
      final index = registration.format.index;
      final tags = ChatTemplateEngine.thinkingTagsFor(index);
      final output = '${tags.startTag}Plan${tags.endTag}Sunny.';
      final keepsTags = registration.traits.closedThoughtKeepsTagsAsContent;
      final ChatParseResult open;
      try {
        open = ChatTemplateEngine.parse(index, output, parseToolCalls: false);
      } on StateError {
        // PEG formats parse only with the parser their render returns.
        expect(keepsTags, isFalse, reason: registration.format.name);
        continue;
      }
      final closed = ChatTemplateEngine.parse(
        index,
        output,
        parseToolCalls: false,
        thinkingForcedClosed: true,
      );
      expect(open.reasoningContent, keepsTags ? 'Plan' : anything);
      expect(
        closed.reasoningContent,
        keepsTags ? isNull : open.reasoningContent,
        reason: registration.format.name,
      );
    }
  });

  test(
    'only formats with the trait take a thought only at the reply start',
    () {
      for (final registration in chatFormatRegistrations) {
        final name = registration.format.name;
        final index = registration.format.index;
        final tags = ChatTemplateEngine.thinkingTagsFor(index);
        final output = 'Answer ${tags.startTag}X${tags.endTag} more.';
        final takesLeadingOnly =
            registration.traits.takesThoughtOnlyAtReplyStart;
        final ChatParseResult public;
        try {
          public = ChatTemplateEngine.parse(
            index,
            output,
            parseToolCalls: false,
          );
        } on StateError {
          // PEG formats parse only with the parser their render returns.
          expect(takesLeadingOnly, isFalse, reason: name);
          continue;
        }
        ChatParseResult rendered({bool thinkingForcedOpen = false}) =>
            parseRenderedOutput(
              index,
              output,
              parseToolCalls: false,
              thinkingForcedOpen: thinkingForcedOpen,
              thoughtClosedForThinkingOff: false,
            );
        if (takesLeadingOnly) {
          expect(public.reasoningContent, 'X', reason: name);
          expect(rendered().reasoningContent, isNull, reason: name);
          expect(rendered().content, output, reason: name);
        } else if (registration.format != ChatFormat.seedOss) {
          expect(rendered().content, public.content, reason: name);
          expect(rendered().reasoningContent, public.reasoningContent);
        }
        final forced = ChatTemplateEngine.parse(
          index,
          output,
          parseToolCalls: false,
          thinkingForcedOpen: true,
        );
        expect(
          rendered(thinkingForcedOpen: true).reasoningContent,
          forced.reasoningContent,
          reason: name,
        );
      }
    },
  );

  // With thinking off, a handler closes a thought its template opened. The
  // stream then holds a reply's leading text where the parse may still end
  // that thought at an end tag.
  test('marks a thought a handler closes where the parse ends it', () {
    for (final registration in chatFormatRegistrations) {
      final format = registration.format;
      final handler = registration.createHandler();
      final opened = '<|im_start|>assistant\n${handler.thinkingStartTag}';
      LlamaChatTemplateResult render(
        String prompt, {
        required bool enableThinking,
      }) => handler.render(
        templateSource: '{{ ${jsonEncode(prompt)} }}',
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
        ],
        metadata: const {},
        enableThinking: enableThinking,
      );
      final closed = render(opened, enableThinking: false);
      final handlerClosed =
          closed.prompt != opened && !closed.thinkingForcedOpen;
      var parsesThought = false;
      try {
        parsesThought =
            parseRenderedOutput(
              format.index,
              'Plan${handler.thinkingEndTag}Sunny.',
              parseToolCalls: false,
              thoughtClosedForThinkingOff: true,
              parser: closed.parser,
            ).reasoningContent ==
            'Plan';
      } on StateError {
        // PEG formats parse only with the parser their render returns.
        expect(handlerClosed, isFalse, reason: format.name);
        expect(thoughtClosedForThinkingOffOf(closed), isFalse);
        continue;
      } on LlamaInferenceException {
        // Solar Open's parse rejects a reply that opens with neither tag.
      }
      expect(
        thoughtClosedForThinkingOffOf(closed),
        handlerClosed && parsesThought,
        reason: format.name,
      );
      expect(
        thoughtClosedForThinkingOffOf(render(opened, enableThinking: true)),
        isFalse,
        reason: format.name,
      );
      expect(
        thoughtClosedForThinkingOffOf(
          render('<|im_start|>assistant\n', enableThinking: false),
        ),
        isFalse,
        reason: '${format.name} without an open thought',
      );
      expect(
        thoughtClosedForThinkingOffOf(
          render('$opened${handler.thinkingEndTag}', enableThinking: true),
        ),
        isFalse,
        reason: '${format.name} with a closed thought and thinking on',
      );
    }
  });

  // llama.cpp parses no leading thought when the caller's own `reasoning`
  // setting closes the Cohere2 MoE thought; `reasoning: true` opens it.
  test('marks a Cohere thought only where llamadart closes it', () {
    for (final (kwargs, marked) in const [
      (<String, Object>{'reasoning': false}, false),
      (<String, Object>{'reasoning_effort': 'none'}, false),
      (<String, Object>{'reasoning': true}, true),
    ]) {
      final rendered = ChatTemplateEngine.render(
        templateSource: File(
          'test/fixtures/llama_cpp_templates/Cohere2MoE.jinja',
        ).readAsStringSync(),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
        ],
        metadata: const {},
        chatTemplateKwargs: kwargs,
        enableThinking: false,
      );
      expect(
        rendered.prompt,
        endsWith('<|START_THINKING|><|END_THINKING|>'),
        reason: '$kwargs',
      );
      expect(
        thoughtClosedForThinkingOffOf(rendered),
        marked,
        reason: '$kwargs',
      );
    }

    // Command R7B's template closes the thought with thinking off, as it
    // does in llama.cpp.
    final commandR7B = ChatTemplateEngine.render(
      templateSource: File(
        'test/fixtures/llama_cpp_templates/'
        'CohereForAI-c4ai-command-r7b-12-2024-tool_use.jinja',
      ).readAsStringSync(),
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
      ],
      metadata: const {},
      enableThinking: false,
    );
    expect(commandR7B.prompt, endsWith('<|START_THINKING|><|END_THINKING|>'));
    expect(thoughtClosedForThinkingOffOf(commandR7B), isFalse);
  });

  // A response schema renders Cohere2 MoE through another handler, which
  // must close the thought for thinking off as the Cohere2 MoE handler does.
  LlamaChatTemplateResult renderWithSchema(
    String source, {
    required bool withTools,
    required bool withMedia,
    required bool enableThinking,
  }) => ChatTemplateEngine.render(
    templateSource: source,
    messages: [
      LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [
          if (withMedia) const LlamaImageContent(path: '/tmp/photo.png'),
          const LlamaTextContent('Hi'),
        ],
      ),
    ],
    metadata: const {},
    tools: withTools ? [_weatherTool] : null,
    responseFormat: const {
      'type': 'json_schema',
      'json_schema': {
        'schema': {'type': 'object'},
      },
    },
    enableThinking: enableThinking,
  );

  test('closes a Cohere thought for a response schema with thinking off', () {
    final source = File(
      'test/fixtures/llama_cpp_templates/Cohere2MoE.jinja',
    ).readAsStringSync();
    for (final withTools in const [false, true]) {
      for (final withMedia in const [false, true]) {
        for (final enableThinking in const [false, true]) {
          final rendered = renderWithSchema(
            source,
            withTools: withTools,
            withMedia: withMedia,
            enableThinking: enableThinking,
          );
          final reason =
              'tools: $withTools, media: $withMedia, '
              'thinking: $enableThinking';
          expect(
            rendered.format,
            withTools ? ChatFormat.generic.index : ChatFormat.contentOnly.index,
            reason: reason,
          );
          expect(
            rendered.prompt,
            endsWith(
              enableThinking
                  ? '<|CHATBOT_TOKEN|><|START_THINKING|>'
                  : '<|CHATBOT_TOKEN|><|START_THINKING|><|END_THINKING|>',
            ),
            reason: reason,
          );
        }
      }
    }
  });

  test('leaves an R7B thought open for a response schema', () {
    final source = File(
      'test/fixtures/llama_cpp_templates/'
      'CohereForAI-c4ai-command-r7b-12-2024-tool_use.jinja',
    ).readAsStringSync();
    const closedWhenOff =
        '{%- if not enable_thinking -%}<|START_THINKING|><|END_THINKING|>'
        '{%- endif %}';
    expect(source, contains(closedWhenOff));
    final opened = source.replaceFirst(closedWhenOff, '<|START_THINKING|>');
    for (final withTools in const [false, true]) {
      final rendered = renderWithSchema(
        opened,
        withTools: withTools,
        withMedia: false,
        enableThinking: false,
      );
      expect(
        rendered.prompt,
        endsWith('<|START_THINKING|>'),
        reason: 'tools: $withTools',
      );
    }
  });

  // The caller of the public parse cannot see the mark, so a Seed-OSS reply
  // that ends a thought it did not open parses as llama.cpp parses it after
  // a template that opens the thought, and one that starts with a thought as
  // after the stock template, which opens none.
  test('a public Seed-OSS parse matches llama.cpp for either template', () {
    final source = File(
      'test/fixtures/llama_cpp_templates/ByteDance-Seed-OSS.jinja',
    ).readAsStringSync();
    const prompt = '{{ bos_token+"assistant\\n" }}';
    expect(source, contains(prompt));
    LlamaChatTemplateResult render(String source) => ChatTemplateEngine.render(
      templateSource: source,
      messages: [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: _fixture['user_prompt'] as String,
        ),
      ],
      metadata: const {},
      tools: [_weatherTool],
      enableThinking: false,
    );
    final opened = render(
      source.replaceFirst(
        prompt,
        '{{ bos_token+"assistant\\n" + think_begin_token }}',
      ),
    );
    final stock = render(source);
    expect(thoughtClosedForThinkingOffOf(opened), isTrue);
    expect(thoughtClosedForThinkingOffOf(stock), isFalse);
    // Values from llama.cpp 620d2225.
    for (final (rendered, output, reasoning, content) in [
      (opened, 'Plan</seed:think>Sunny.', 'Plan', 'Sunny.'),
      (opened, '</seed:think>Sunny.', null, 'Sunny.'),
      (
        opened,
        'Plan.</seed:think>Use </seed:think> tag.',
        'Plan.',
        'Use </seed:think> tag.',
      ),
      (opened, 'Plan.</seed:think>\n', 'Plan.', ''),
      (opened, 'Sunny.', null, 'Sunny.'),
      (
        stock,
        '<seed:think>Plan</seed:think>A<seed:think>B</seed:think>C',
        'Plan',
        'A<seed:think>B</seed:think>C',
      ),
      (stock, '\n<seed:think>Plan</seed:think>Sunny.', 'Plan', 'Sunny.'),
    ]) {
      for (final withTools in const [false, true]) {
        final parsed = ChatTemplateEngine.parse(
          rendered.format,
          output,
          parseToolCalls: withTools,
          thinkingForcedOpen: rendered.thinkingForcedOpen,
          parser: rendered.parser,
          tools: withTools ? [_weatherTool] : null,
        );
        expect(parsed.content.trim(), content, reason: output);
        expect(parsed.reasoningContent, reasoning, reason: output);
      }
    }
  });

  // Values from llama.cpp 620d2225: after a template that opens the thought,
  // the reasoning is the reply up to the first end tag as generated, so it
  // keeps a start tag, and whatever precedes one, instead of dropping it.
  test('a forced-open Seed-OSS thought keeps a repeated start tag', () async {
    final source = File(
      'test/fixtures/llama_cpp_templates/ByteDance-Seed-OSS.jinja',
    ).readAsStringSync();
    const prompt = '{{ bos_token+"assistant\\n" }}';
    expect(source, contains(prompt));
    for (final withTools in const [false, true]) {
      final rendered = ChatTemplateEngine.render(
        templateSource: source.replaceFirst(
          prompt,
          '{{ bos_token+"assistant\\n" + think_begin_token }}',
        ),
        messages: [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: _fixture['user_prompt'] as String,
          ),
        ],
        metadata: const {},
        tools: withTools ? [_weatherTool] : null,
        enableThinking: true,
      );
      expect(rendered.thinkingForcedOpen, isTrue);
      for (final (output, reasoning, content) in const [
        ('\u00a0<seed:think>P</seed:think>S', '\u00a0<seed:think>P', 'S'),
        ('<seed:think>P</seed:think>S', '<seed:think>P', 'S'),
        (' \u000b\f\r\n\t<seed:think>P</seed:think>S', '<seed:think>P', 'S'),
        ('x<seed:think>P</seed:think>S', 'x<seed:think>P', 'S'),
        ('Plan<seed:think>Q</seed:think>R', 'Plan<seed:think>Q', 'R'),
        (
          '<seed:think>P</seed:think>S</seed:think>T',
          '<seed:think>P',
          'S</seed:think>T',
        ),
        ('\u00a0<seed:think>Plan', '\u00a0<seed:think>Plan', ''),
      ]) {
        final parsed = ChatTemplateEngine.parseRendered(
          rendered,
          output,
          parseToolCalls: withTools,
          tools: withTools ? [_weatherTool] : null,
        );
        // llama.cpp strips no leading space; llamadart trims the reasoning.
        expect(parsed.reasoningContent, reasoning.trim(), reason: output);
        expect(parsed.content, content, reason: output);

        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.fromIterable(output.split('')),
          templateResult: rendered,
          parseToolCallsEnabled: withTools,
          enableThinking: true,
          tools: withTools ? [_weatherTool] : null,
          modelName: 'test-model',
          completionId: 'seed-forced-open',
        ).toList();
        final deltas = chunks.map((chunk) => chunk.choices.single.delta);
        expect(
          deltas.map((delta) => delta.thinking ?? '').join().trim(),
          reasoning.trim(),
          reason: output,
        );
        expect(
          deltas.map((delta) => delta.content ?? '').join().trim(),
          content,
          reason: output,
        );
      }
    }
  });

  // The public parse cannot see the template: ASCII space before a start tag
  // leaves it a reply that starts with a thought, as the stock template
  // renders, while NBSP does not and parses as after a template that opens one.
  test('a public Seed-OSS parse skips only ASCII space before a thought', () {
    for (final withTools in const [false, true]) {
      for (final (output, reasoning) in const [
        (' <seed:think>Plan</seed:think>Sunny.', 'Plan'),
        ('\n\t <seed:think>Plan</seed:think>Sunny.', 'Plan'),
        ('\u00a0<seed:think>Plan</seed:think>Sunny.', '<seed:think>Plan'),
      ]) {
        final parsed = ChatTemplateEngine.parse(
          ChatFormat.seedOss.index,
          output,
          parseToolCalls: withTools,
          tools: withTools ? [_weatherTool] : null,
        );
        expect(parsed.content, 'Sunny.', reason: 'tools: $withTools');
        expect(parsed.reasoningContent, reasoning, reason: output);
      }
    }
  });

  test('a forced-open thought keeps the reasoning', () async {
    expect(
      ChatTemplateEngine.parse(
        ChatFormat.hermes.index,
        'Plan</think>Sunny.',
        thinkingForcedOpen: true,
        thinkingForcedClosed: true,
      ).reasoningContent,
      'Plan',
    );
    final chunks = await ChatCompletionStreamParser.parse(
      tokenStream: Stream.fromIterable('Plan</think>Sunny.'.split('')),
      templateResult: withThinkingForcedClosed(
        LlamaChatTemplateResult(
          prompt: '<|im_start|>assistant\n<think>\n',
          format: ChatFormat.hermes.index,
          thinkingForcedOpen: true,
        ),
        closed: true,
      ),
      parseToolCallsEnabled: false,
      enableThinking: true,
      modelName: 'test-model',
      completionId: 'forced-open',
    ).toList();
    final deltas = chunks.map((chunk) => chunk.choices.single.delta);
    expect(deltas.map((delta) => delta.thinking ?? '').join(), 'Plan');
    expect(deltas.map((delta) => delta.content ?? '').join(), 'Sunny.');
  });

  // llama.cpp still parses a leading thought after a prompt that does not
  // close one, such as Bielik's with thinking off. Only the template's own
  // render decides: llamadart closing an open thought does not count.
  test('a result without a closed thought keeps the reasoning', () async {
    for (final closed in const [false, true]) {
      final chunks = await ChatCompletionStreamParser.parse(
        tokenStream: Stream.value('<think>Plan</think>Sunny.'),
        templateResult: withThinkingForcedClosed(
          LlamaChatTemplateResult(
            prompt: '<|im_start|>assistant\n<think></think>\n',
            format: ChatFormat.hermes.index,
          ),
          closed: closed,
        ),
        parseToolCallsEnabled: false,
        enableThinking: false,
        modelName: 'test-model',
        completionId: 'open-prompt',
      ).toList();
      expect(
        chunks.map((chunk) => chunk.choices.single.delta.content ?? '').join(),
        closed ? '<think>Plan</think>Sunny.' : 'Sunny.',
        reason: 'thinkingForcedClosed: $closed',
      );
    }
  });

  // A template that always opens the thought, as StepFun's does, renders no
  // empty thought; the handler's own close with thinking off must not count.
  test(
    'a thought the handler closes keeps parsing the reply thought',
    () async {
      for (final (ChatTemplateHandler handler, templateSource) in [
        (HermesHandler(), '<|im_start|>assistant\n<think>\n'),
        (DeepseekV3Handler(), '<｜Assistant｜><think>'),
        (Qwen3CoderXmlHandler(), '<|im_start|>assistant\n<think>\n'),
      ]) {
        final rendered = handler.render(
          templateSource: templateSource,
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
          ],
          metadata: const {},
          enableThinking: false,
        );
        expect(rendered.prompt, endsWith('<think></think>\n'));
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.value('<think>Plan</think>Sunny.'),
          templateResult: rendered,
          parseToolCallsEnabled: false,
          enableThinking: false,
          modelName: 'test-model',
          completionId: 'handler-closed',
        ).toList();
        expect(
          chunks
              .map((chunk) => chunk.choices.single.delta.content ?? '')
              .join(),
          'Sunny.',
          reason: handler.format.name,
        );
      }
    },
  );
}
