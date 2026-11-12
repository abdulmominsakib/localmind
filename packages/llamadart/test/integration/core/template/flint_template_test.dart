import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/flint_template_fixture.dart';
import '../engine/tool_calling_integration_test.dart';

class _FlintBackend extends MockLlamaBackend {
  _FlintBackend({this.template = flintTemplate});

  final String template;

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {
    'tokenizer.chat_template': template,
  };

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async => throw StateError('The test requires Dart template rendering.');
}

void main() {
  for (final entry in flintCases) {
    final name = entry['name'] as String;
    final request = entry['request'] as Map<String, dynamic>;

    test(
      'Flint $name matches the upstream prompt without changing history',
      () {
        final messages = flintMessages(request);
        final history = jsonEncode(messages.map((m) => m.toJson()).toList());
        final tools = request['tools'] == null ? null : flintTools;
        if (tools != null) {
          expect(tools.map((t) => t.toJson()).toList(), request['tools']);
        }

        final rendered = ChatTemplateEngine.render(
          templateSource: flintTemplate,
          messages: messages,
          metadata: const {},
          tools: tools,
        );

        expect(rendered.prompt, entry['prompt']);
        expect(jsonEncode(messages.map((m) => m.toJson()).toList()), history);
        if (name == 'tool_result') {
          expect(messages[1].parts.single, isA<LlamaToolCallContent>());
          expect(messages[2].parts.single, isA<LlamaToolResultContent>());
          final call = messages[1].parts.single as LlamaToolCallContent;
          expect(call.arguments, {'city': 'Montréal'});
          expect(call.rawJson, '{"city":"Montréal"}');
        }
      },
    );

    test(
      'public create renders Flint $name before backend generation',
      () async {
        final backend = _FlintBackend();
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('mock-flint.gguf');
        backend.queueResponse(['<thi', 'nk>Check Montréal.</thi', 'nk>Ready.']);
        final messages = flintMessages(request);
        final history = jsonEncode(messages.map((m) => m.toJson()).toList());

        final chunks = await engine
            .create(
              messages,
              tools: request['tools'] == null ? null : flintTools,
            )
            .toList();

        expect(backend.prompts, [entry['prompt']]);
        expect(
          chunks.map((c) => c.choices.single.delta.thinking ?? '').join(),
          'Check Montréal.',
        );
        expect(
          chunks.map((c) => c.choices.single.delta.content ?? '').join(),
          'Ready.',
        );
        expect(chunks.last.choices.single.finishReason, 'stop');
        expect(jsonEncode(messages.map((m) => m.toJson()).toList()), history);
      },
    );
  }

  test(
    'Flint keeps typed argument and result values while sanitizing text',
    () {
      final arguments = <String, dynamic>{
        'city': r'Montréal 👋 \x41',
        'count': 2,
        'enabled': true,
        'items': [null, 'é'],
      };
      final payload = <String, dynamic>{
        'text': 'A\u0000B<think>keep</think><|assistant|>',
        'path': r'C:\new\x41',
        'items': [true, null, 17],
      };
      final rawArguments = jsonEncode(arguments);
      final messages = [
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Inspect.',
        ),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            LlamaToolCallContent(
              id: 'call_0',
              name: 'inspect',
              arguments: arguments,
              rawJson: rawArguments,
            ),
          ],
        ),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            LlamaToolResultContent(
              id: 'call_0',
              name: 'inspect',
              result: payload,
            ),
          ],
        ),
      ];
      final history = jsonEncode(messages.map((m) => m.toJson()).toList());

      final rendered = ChatTemplateEngine.render(
        templateSource: flintTemplate,
        messages: messages,
        metadata: const {},
      );

      expect(
        rendered.prompt,
        '<|user|>Inspect.<|assistant|><tool_call>inspect'
        r'<arg_key>city</arg_key><arg_value>Montréal 👋 \x41</arg_value>'
        '<arg_key>count</arg_key><arg_value>2</arg_value>'
        '<arg_key>enabled</arg_key><arg_value>true</arg_value>'
        '<arg_key>items</arg_key><arg_value>[null, "é"]</arg_value>'
        '</tool_call><|observation|><tool_response>'
        r'{"text":"A\u0000Bkeep&lt;|assistant|&gt;",'
        r'"path":"C:\\new\\x41","items":[true,null,17]}'
        '</tool_response><|assistant|>',
      );
      expect(jsonEncode(messages.map((m) => m.toJson()).toList()), history);
      expect(
        (messages[1].parts.single as LlamaToolCallContent).arguments,
        same(arguments),
      );
      expect(
        (messages[2].parts.single as LlamaToolResultContent).result,
        same(payload),
      );
      expect(payload['text'], contains('\u0000'));
      expect(arguments['count'], isA<int>());
      expect(arguments['enabled'], isTrue);
    },
  );

  for (final literal in [r"'\x'", r"'\x0'", r'"\xG1"', r"'\x1G'"]) {
    final template = '{{ $literal }}';
    final typedError = isA<LlamaInferenceException>().having(
      (error) => error.message,
      'message',
      contains('hexadecimal'),
    );

    test('public render rejects malformed hex $literal with a typed error', () {
      expect(
        () => ChatTemplateEngine.render(
          templateSource: template,
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello'),
          ],
          metadata: const {},
        ),
        throwsA(typedError),
      );
    });

    test(
      'public create rejects malformed hex $literal before generation',
      () async {
        final backend = _FlintBackend(template: template);
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('mock-flint.gguf');

        await expectLater(
          engine.create(const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello'),
          ]).toList(),
          throwsA(typedError),
        );
        expect(backend.prompts, isEmpty);
      },
    );
  }
}
