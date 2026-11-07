import 'package:dinja/dinja.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:llamadart/src/core/template/chat_template_handler.dart';
import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:test/test.dart';

void main() {
  test('ChatTemplateHandler type is available', () {
    expect(ChatTemplateHandler, isNotNull);
  });

  test('renderTemplate injects chat_template_kwargs metadata', () {
    final handler = _FakeHandler();
    final output = handler.renderTemplate(
      Template('{{ foo }} {{ bar }}'),
      metadata: const {
        internalChatTemplateKwargsMetadataKey: '{"foo":"from-metadata"}',
      },
      context: const {'bar': 'from-context'},
    );

    expect(output, 'from-metadata from-context');
  });

  test('renderTemplate ignores invalid chat_template_kwargs metadata', () {
    final handler = _FakeHandler();
    final output = handler.renderTemplate(
      Template('{{ bar }}'),
      metadata: const {internalChatTemplateKwargsMetadataKey: '{not-json'},
      context: const {'bar': 'from-context'},
    );

    expect(output, 'from-context');
  });
}

class _FakeHandler extends ChatTemplateHandler {
  @override
  List<String> get additionalStops => const <String>[];

  @override
  ChatFormat get format => ChatFormat.generic;

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    return ChatParseResult(content: output);
  }

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    throw UnimplementedError();
  }
}
