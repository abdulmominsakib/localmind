import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/template/chat_format_registry.dart';
import 'package:test/test.dart';

import '../../../support/chat_format_triggers.dart';

final _schemaTool = ToolDefinition.fromJsonSchema(
  name: 'inspect',
  description: 'Inspect a value',
  schema: {
    'type': 'object',
    'properties': {
      'value': {'type': 'string'},
    },
    'required': ['value'],
    'additionalProperties': false,
  },
);

const _qualified = {
  ChatFormat.generic,
  ChatFormat.hermes,
  ChatFormat.mistralNemo,
  ChatFormat.glm45,
  ChatFormat.laguna,
  ChatFormat.hunyuanV3,
};

LlamaChatTemplateResult _render(String? source, ToolChoice choice) =>
    ChatTemplateEngine.render(
      templateSource: source,
      messages: [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Inspect'),
      ],
      metadata: const {},
      tools: [_schemaTool],
      toolChoice: choice,
    );

void main() {
  test(
    'every registration preserves schema qualification and callback presence',
    () {
      for (final registration in chatFormatRegistrations) {
        expect(
          registration.traits.qualifiesJsonSchemaTools,
          _qualified.contains(registration.format),
          reason: registration.format.name,
        );
        expect(
          registration.traits.leavesIncompleteToolCall != null,
          _qualified.contains(registration.format),
          reason: registration.format.name,
        );
      }
    },
  );

  for (final choice in [ToolChoice.auto, ToolChoice.required]) {
    test('generic fallback admits schema tools with $choice', () {
      final rendered = _render(null, choice);
      expect(rendered.format, ChatFormat.generic.index);
      expect(rendered.grammar, isNotEmpty);
    });
    for (final MapEntry(key: name, value: trigger)
        in chatFormatTriggers.entries) {
      test('$name preserves public schema admission with $choice', () {
        final effectiveFormat = switch (trigger.format) {
          ChatFormat.contentOnly || ChatFormat.gemma => ChatFormat.generic,
          _ => trigger.format,
        };
        if (_qualified.contains(effectiveFormat)) {
          final rendered = _render(trigger.source, choice);
          expect(rendered.format, effectiveFormat.index);
          expect(rendered.grammar, isNotEmpty);
        } else {
          expect(
            () => _render(trigger.source, choice),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'qualification diagnostic',
                contains('Canonical JSON Schema tools are not qualified'),
              ),
            ),
          );
        }
      });
    }
  }

  for (final (format, output) in [
    (ChatFormat.generic, '{"tool_call": {"name": "inspect"'),
    (ChatFormat.hermes, '<tool_call>{"name":"inspect"'),
    (ChatFormat.mistralNemo, '[TOOL_CALLS]'),
    (ChatFormat.glm45, '<tool_call>'),
    (ChatFormat.laguna, '<tool_call>'),
    (ChatFormat.hunyuanV3, '<tool_call:opensource>'),
  ]) {
    test('$format retains its malformed-call final parse check', () {
      expect(
        () => ChatTemplateEngine.parse(
          format.index,
          output,
          tools: [_schemaTool],
        ),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'incomplete call diagnostic',
            contains('malformed or incomplete tool call'),
          ),
        ),
      );
      for (final (partial, calls) in [(true, true), (false, false)]) {
        expect(
          () => ChatTemplateEngine.parse(
            format.index,
            output,
            tools: [_schemaTool],
            isPartial: partial,
            parseToolCalls: calls,
          ),
          returnsNormally,
          reason: 'partial=$partial parseToolCalls=$calls',
        );
      }
    });
  }
}
