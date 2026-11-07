import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ChatTemplateEngine Integration', () {
    test('End-to-End DeepSeek R1 Flow', () {
      // 1. Mock Metadata for DeepSeek R1 (Valid Jinja string)
      final templateSource = "User: content <｜tool▁calls▁begin｜> ...";
      final metadata = {
        'tokenizer.chat_template': templateSource,
        'tokenizer.ggml.bos_token': '<｜begin▁of▁sentence｜>',
        'tokenizer.ggml.eos_token': '<｜end▁of▁sentence｜>',
      };

      // 2. Initial User Message
      final messages = [
        LlamaChatMessage(role: 'user', content: 'Calculate 2+2'),
      ];

      // 3. Render Prompt
      final result = ChatTemplateEngine.render(
        templateSource: templateSource,
        messages: messages,
        metadata: metadata,
        enableThinking: true,
      );

      expect(result.format, equals(ChatFormat.deepseekR1.index));
      // Simplified check since template is mocked as static string
      expect(result.prompt.contains('User: content'), isTrue);

      // 4. Simulate Partial Output (Thinking)
      // Note: DeepseekR1Handler uses default <think> tags for extraction unless configured otherwise
      final partialOutput = "<think>\nThinking process...\n";
      final parseResult1 = ChatTemplateEngine.parse(
        result.format,
        partialOutput,
        isPartial: true,
      );

      expect(parseResult1.reasoningContent, equals("Thinking process..."));
      expect(parseResult1.content, isEmpty);

      // 5. Simulate Final Output (Tool Call)
      // Must match DeepseekR1Handler regex structure
      final finalOutput =
          "<think>\nThinking done.\n</think>\n"
          "<｜tool▁calls▁begin｜>"
          "<｜tool▁call▁begin｜>function<｜tool▁sep｜>calculator\n"
          "```json\n"
          "{\"op\": \"add\", \"a\": 2, \"b\": 2}\n"
          "```<｜tool▁call▁end｜>"
          "<｜tool▁calls▁end｜>";

      final parseResult2 = ChatTemplateEngine.parse(
        result.format,
        finalOutput,
        isPartial: false,
      );

      expect(parseResult2.reasoningContent, equals("Thinking done."));
      expect(parseResult2.toolCalls.length, equals(1));
      expect(parseResult2.toolCalls[0].function!.name, equals("calculator"));
    });

    test('End-to-End Granite Flow with Tools', () {
      // 1. Mock Metadata for Granite
      final templateSource =
          'elif thinking <|tool_call|><|start_of_role|>user<|end_of_role|>content<think>';
      final metadata = {'tokenizer.chat_template': templateSource};

      final tools = [
        ToolDefinition(
          name: 'weather',
          description: 'Get weather',
          parameters:
              [], // parameters are structurally required in model but empty list is fine?
          handler: (_) async => null,
        ),
      ];

      final messages = [
        LlamaChatMessage(role: 'user', content: 'What is the weather?'),
      ];

      // 2. Render Prompt
      final result = ChatTemplateEngine.render(
        templateSource: templateSource,
        messages: messages,
        metadata: metadata,
        tools: tools,
        enableThinking: true,
      );

      expect(result.format, equals(ChatFormat.granite.index));
      // GraniteHandler appends grammar trigger for tools if they exist
      expect(result.grammarTriggers, isNotEmpty);
      expect(result.grammarTriggers[0].value, equals('<|tool_call|>'));

      // 3. Simulate Output (JSON Tool Call)
      // Granite might output thinking first if enabled, then JSON
      final output =
          "I need to check the weather.\n<|tool_call|>[{\"name\": \"weather\", \"arguments\": {}}]";

      final parseResult = ChatTemplateEngine.parse(
        result.format,
        output,
        isPartial: false,
      );

      // Granite parsing logic: simple JSON finder
      expect(parseResult.toolCalls.length, equals(1));
      expect(parseResult.toolCalls[0].function!.name, equals("weather"));
    });
  });
}
