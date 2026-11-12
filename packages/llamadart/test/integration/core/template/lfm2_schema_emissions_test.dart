@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:test/test.dart';

import '../../../support/lfm2_schema_replay.dart';

void main() {
  for (final payload in ['f(a=1)', '[f(a=1,)]', '[f(arguments=\'{"a":1}\')]']) {
    test('typed legacy $payload survives split stream boundaries', () async {
      final raw = '<|tool_call_start|>$payload<|tool_call_end|>';
      for (final size in [1, 7]) {
        final completion = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.fromIterable([
            for (var i = 0; i < raw.length; i += size)
              raw.substring(i, i + size < raw.length ? i + size : raw.length),
          ]),
          templateResult: LlamaChatTemplateResult(
            prompt: '',
            format: ChatFormat.lfm2.index,
          ),
          parseToolCallsEnabled: true,
          enableThinking: true,
          modelName: 'lfm-schema-legacy',
          completionId: '$payload/$size',
          tools: [
            ToolDefinition(
              name: 'f',
              description: 'Test',
              parameters: [ToolParam.integer('a', required: true)],
            ),
          ],
        ).collect();
        expect(completion.text, isEmpty);
        expect(completion.toolCalls, hasLength(1), reason: 'chunk size $size');
        expect(completion.toolCalls.single.name, 'f');
        expect(completion.toolCalls.single.arguments, {'a': 1});
      }
    });
  }
  final fixture =
      jsonDecode(
            File('test/fixtures/lfm2_schema_emissions.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in fixture['cases'] as List) {
    final capture = entry as Map<String, dynamic>;
    test(
      '${capture['id']} preserves actual emission schema and streaming',
      () async {
        final raw = capture['raw'] as String;
        expect(
          sha256.convert(utf8.encode(raw)).toString(),
          capture['raw_sha256'],
        );
        expect(replayLfm2Capture(capture), capture['expected']);
        final tool = lfm2CaptureTool(capture);
        final rendered = LlamaChatTemplateResult(
          prompt: '',
          format: ChatFormat.lfm2.index,
        );
        for (final size in [1, 2, 7, raw.length]) {
          final completion = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable([
              for (var i = 0; i < raw.length; i += size)
                raw.substring(i, i + size < raw.length ? i + size : raw.length),
            ]),
            templateResult: rendered,
            parseToolCallsEnabled: true,
            enableThinking: true,
            modelName: 'lfm-schema-fixture',
            completionId: '${capture['id']}/$size',
            tools: [tool],
          ).collect();
          final expected = capture['expected'] as Map;
          expect(
            completion.text,
            expected['content'],
            reason: 'chunk size $size',
          );
          expect(
            completion.thinking,
            expected['reasoning'] ?? '',
            reason: 'chunk size $size',
          );
          expect(
            [
              for (final call in completion.toolCalls)
                {'name': call.name, 'arguments': call.arguments},
            ],
            expected['calls'],
            reason: 'chunk size $size',
          );
        }
      },
    );
  }
}
