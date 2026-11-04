import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:test/test.dart';

void main() {
  group('ChatCompletionStreamParser', () {
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
      expect(chunks.last.model, 'test-model');
    });

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
  });
}
