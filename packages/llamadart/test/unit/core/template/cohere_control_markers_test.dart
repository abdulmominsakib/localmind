@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

import '../../../support/control_token_decode.dart';
import '../../../support/forced_open_required_calls.dart';

const _call =
    '[{"tool_call_id": "0", "tool_name": "get_weather", '
    '"parameters": {"location": "Paris"}}]';

// Converted Cohere GGUFs mark every `<|NAME|>` marker as a control token, so
// only the preserved ones reach the parser.
void main() {
  final families =
      <
        ({
          String template,
          ChatFormat format,
          List<String> preserved,
          String thought,
          String text,
        })
      >[
        (
          template: 'Cohere2MoE.jinja',
          format: ChatFormat.cohere2Moe,
          // llama.cpp 620d2225 common/parsers/cohere2moe.cpp.
          preserved: const [
            '<|START_OF_TURN_TOKEN|>',
            '<|END_OF_TURN_TOKEN|>',
            '<|CHATBOT_TOKEN|>',
            '<|USER_TOKEN|>',
            '<|SYSTEM_TOKEN|>',
            '<|START_THINKING|>',
            '<|END_THINKING|>',
            '<|START_TEXT|>',
            '<|END_TEXT|>',
            '<|START_ACTION|>',
            '<|END_ACTION|>',
            '<|START_TOOL_RESULT|>',
            '<|END_TOOL_RESULT|>',
          ],
          // The prompt opens the thought.
          thought: 'plan<|END_THINKING|>',
          text: '<|START_TEXT|>Hello<|END_TEXT|>',
        ),
        (
          template: 'CohereForAI-c4ai-command-r7b-12-2024-tool_use.jinja',
          format: ChatFormat.commandR7B,
          // What llama.cpp 620d2225's autoparser preserves for this template.
          preserved: const [
            '<|START_THINKING|>',
            '<|END_THINKING|>',
            '<|START_RESPONSE|>',
            '<|END_RESPONSE|>',
            '<|START_ACTION|>',
            '<|END_ACTION|>',
          ],
          thought: '<|START_THINKING|>plan<|END_THINKING|>',
          text: '<|START_RESPONSE|>Hello<|END_RESPONSE|>',
        ),
      ];

  for (final (:template, :format, :preserved, :thought, :text) in families) {
    final source = File(
      'test/fixtures/llama_cpp_templates/$template',
    ).readAsStringSync();

    group(format.name, () {
      for (final choice in [null, ToolChoice.auto, ToolChoice.required]) {
        final tools = choice == null ? null : [forcedOpenRequiredTool];
        final rendered = ChatTemplateEngine.render(
          templateSource: source,
          messages: const [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'Weather in Paris?',
            ),
          ],
          metadata: const {},
          tools: tools,
          toolChoice: choice ?? ToolChoice.auto,
        );
        final label = 'tool choice: ${choice?.name ?? 'no tools'}';

        test('preserves the markers llama.cpp preserves, $label', () {
          expect(rendered.format, format.index);
          expect(rendered.preservedTokens, preserved);
        });

        final outputs = [
          if (choice != ToolChoice.required) (output: text, calls: 0),
          if (choice != null)
            (output: '<|START_ACTION|>$_call<|END_ACTION|>', calls: 1),
        ];
        for (final (:output, :calls) in outputs) {
          test('parses and streams decoded control tokens, $label, '
              '${calls == 0 ? 'text' : 'call'}', () async {
            final pieces = decodeControlMarkedPieces(
              '$thought$output',
              preservedTokens: rendered.preservedTokens,
            );

            final parsed = ChatTemplateEngine.parse(
              rendered.format,
              pieces.join(),
              thinkingForcedOpen: rendered.thinkingForcedOpen,
              parseToolCalls: tools != null,
              tools: tools,
              parser: rendered.parser,
            );
            expect(parsed.reasoningContent, 'plan');
            expect(parsed.content, calls == 0 ? 'Hello' : isEmpty);
            expect(parsed.toolCalls.map((call) => call.function?.name), [
              if (calls == 1) 'get_weather',
            ]);

            final chunks = await ChatCompletionStreamParser.parse(
              tokenStream: Stream.fromIterable([
                for (final piece in pieces)
                  ...(piece.startsWith('<|') ? [piece] : piece.split('')),
              ]),
              templateResult: rendered,
              parseToolCallsEnabled: tools != null,
              enableThinking: true,
              modelName: format.name,
              completionId: label,
              tools: tools,
            ).toList();
            expect(
              chunks.map((c) => c.choices.single.delta.thinking ?? '').join(),
              'plan',
            );
            expect(
              chunks.map((c) => c.choices.single.delta.content ?? '').join(),
              calls == 0 ? 'Hello' : isEmpty,
            );
            expect(
              chunks.last.choices.single.finishReason,
              calls == 0 ? 'stop' : 'tool_calls',
            );
          });
        }
      }
    });
  }
}
