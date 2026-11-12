@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

import '../../../support/gbnf_recognizer.dart';
import '../../../support/qwen3_coder_required_calls.dart';

void main() {
  // For the Qwen3-Coder template, llama.cpp also starts the lazy grammar at
  // `<function=get_weather>` and ends the content there, which loses a reply
  // that writes that tag as text.
  test('without a required call, a bare call is text', () async {
    for (final (:template, :enableThinking, :bareFirstCall)
        in qwen3CoderRequiredTemplates) {
      final rendered = ChatTemplateEngine.render(
        templateSource: File(template).readAsStringSync(),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        metadata: const {},
        tools: [qwen3CoderRequiredTool],
        enableThinking: enableThinking,
      );
      expect(rendered.grammarLazy, isTrue);
      expect(rendered.grammarTriggers.map((trigger) => trigger.value), [
        '<tool_call>',
      ], reason: template);
      final grammar = GbnfRecognizer(rendered.grammar!);
      const bareCall =
          '<function=get_weather>\n<parameter=location>\nParis\n'
          '</parameter>\n</function>\n</tool_call>';
      expect(grammar.accepts(bareCall), isFalse, reason: template);
      expect(grammar.accepts('<tool_call>\n$bareCall'), isTrue);
      if (!bareFirstCall) continue;

      const reply =
          'The literal text <function=get_weather> opens a call. $bareCall '
          'That is all.';
      final parsed = ChatTemplateEngine.parseRendered(
        rendered,
        reply,
        tools: [qwen3CoderRequiredTool],
      );
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, reply);
      for (var split = 0; split <= reply.length; split++) {
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.fromIterable([
            reply.substring(0, split),
            reply.substring(split),
          ]),
          templateResult: rendered,
          parseToolCallsEnabled: true,
          enableThinking: true,
          modelName: 'test-model',
          completionId: 'bare-call-text',
          tools: [qwen3CoderRequiredTool],
        ).toList();
        final deltas = chunks.map((chunk) => chunk.choices.single.delta);
        expect(
          deltas.map((delta) => delta.content ?? '').join(),
          reply,
          reason: 'split $split',
        );
        expect(deltas.expand((delta) => delta.toolCalls ?? const []), isEmpty);
      }
    }
  });

  group('required tool-call grammar takes what llama.cpp takes', () {
    for (final (:template, :enableThinking, :bareFirstCall)
        in qwen3CoderRequiredTemplates) {
      for (final parallel in [false, true]) {
        test('${template.split('/').last}, thinking $enableThinking, '
            'parallel $parallel', () {
          final rendered = renderQwen3CoderRequiredCall(
            template,
            enableThinking: enableThinking,
            parallelToolCalls: parallel,
          );
          expect(rendered.format, ChatFormat.qwen3CoderXml.index);
          expect(rendered.grammarLazy, isFalse);
          expect(rendered.grammarTriggers, isEmpty);
          final grammar = GbnfRecognizer(rendered.grammar!);
          final replies = qwen3CoderRequiredReplies(
            parallelToolCalls: parallel,
            bareFirstCall: bareFirstCall,
          );
          for (final output in replies.valid) {
            expect(grammar.accepts(output), isTrue, reason: output);
          }
          for (final output in replies.invalid) {
            expect(grammar.accepts(output), isFalse, reason: output);
          }

          final bare = ChatTemplateEngine.parseRendered(
            rendered,
            'Let me check.\n<function=get_weather>\n'
            '<parameter=location>\nParis\n</parameter>\n</function>\n'
            '</tool_call>',
            tools: [qwen3CoderRequiredTool],
          );
          expect(bare.toolCalls, hasLength(bareFirstCall ? 1 : 0));
        });
      }
    }
  });
}
