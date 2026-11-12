@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import 'tool_calling_integration_test.dart';

class _TemplateBackend extends MockLlamaBackend {
  _TemplateBackend(this.template);

  final String template;

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {
    'tokenizer.chat_template': template,
  };
}

final Map<String, dynamic> _fixture =
    jsonDecode(
          File(
            'test/fixtures/hermes_double_brace_tool_call.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
final List<Map<String, dynamic>> _cases = (_fixture['cases'] as List)
    .cast<Map<String, dynamic>>();

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'get_weather',
  description: 'Returns current weather for a city.',
  parameters: [ToolParam.string('city', description: 'City name')],
  handler: (_) async => 'Sunny',
);

void main() {
  final qwen25Template = File(
    _fixture['template'] as String,
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final templates = <String, String>{
    'Qwen2.5': qwen25Template,
    'Qwen3': File('test/fixtures/templates/Qwen3-4B.jinja').readAsStringSync(),
  };

  test('Qwen2.5 template prints the double-brace tool example', () async {
    expect(
      sha256.convert(utf8.encode(qwen25Template)).toString(),
      _fixture['template_sha256'],
    );
    final engine = LlamaEngine(_TemplateBackend(qwen25Template));
    addTearDown(engine.dispose);
    await engine.loadModel('mock-qwen25.gguf');

    final rendered = await engine.chatTemplate(
      [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: _fixture['user_prompt'] as String,
        ),
      ],
      tools: [_weatherTool],
    );

    expect(rendered.format, ChatFormat.hermes.index);
    expect(
      rendered.prompt,
      contains(
        '<tool_call>\n'
        '{{"name": <function-name>, "arguments": <args-json-object>}}\n'
        '</tool_call>',
      ),
    );
  });

  group('text-first Hermes output keeps session history clean', () {
    const call =
        '<tool_call>\n'
        '{"name": "get_weather", "arguments": {"city": "Paris"}}\n'
        '</tool_call>';
    const londonCall =
        '<tool_call>\n'
        '{"name": "get_weather", "arguments": {"city": "London"}}\n'
        '</tool_call>';
    final random = Random(701);
    List<String> pieces(String output, int Function() size) => [
      for (var i = 0, end = 0; i < output.length; i = end)
        output.substring(i, end = min(output.length, i + size())),
    ];

    for (final MapEntry(key: name, value: output) in const {
      'one call': 'Let me check.\n$call',
      'two calls': 'Checking both.\n$call\n$londonCall',
      'text after the call': 'Let me check.\n$call\nOne moment.',
      'a thought then a call': '<think>\nPlan it.\n</think>\n\n$call',
    }.entries) {
      final tag = output.indexOf('<tool_call>');
      for (final MapEntry(key: splitName, value: tokens) in {
        'characters': pieces(output, () => 1),
        'pairs': pieces(output, () => 2),
        'random pieces': pieces(output, () => 1 + random.nextInt(7)),
        'a split tag': [
          output.substring(0, tag + 5),
          output.substring(tag + 5),
        ],
      }.entries) {
        test('$name as $splitName', () async {
          final expected = ChatTemplateEngine.parse(
            ChatFormat.hermes.index,
            output,
            tools: [_weatherTool],
          );
          final backend = _TemplateBackend(templates['Qwen3']!);
          final engine = LlamaEngine(backend);
          addTearDown(engine.dispose);
          await engine.loadModel('mock-qwen3.gguf');
          backend.queueResponse(tokens);
          final session = ChatSession(engine);

          final chunks = await session
              .create(
                [const LlamaTextContent('Weather in Paris?')],
                tools: [_weatherTool],
                toolChoice: ToolChoice.auto,
              )
              .toList();

          expect(
            chunks.map((c) => c.choices.single.delta.content ?? '').join(),
            expected.content,
          );
          final reply = session.history.last;
          expect(
            reply.parts.whereType<LlamaThinkingContent>().map(
              (p) => p.thinking,
            ),
            [?expected.reasoningContent],
          );
          expect(reply.parts.whereType<LlamaTextContent>().map((p) => p.text), [
            if (expected.content.isNotEmpty) expected.content,
          ]);
          expect([
            for (final call in reply.parts.whereType<LlamaToolCallContent>())
              {'name': call.name, 'arguments': call.arguments},
          ], _parsedCalls(expected.toolCalls));
        });
      }
    }
  });

  for (final entry in _cases) {
    final name = entry['name'] as String;
    final prompt = entry['prompt'] as String;
    final emission = entry['emission'] as String;
    final expected = entry['expected'] as Map<String, dynamic>;
    final expectedContent = expected['content'] as String;
    final expectedCalls = _calls(expected);
    final upstream = entry['upstream_result'] as Map<String, dynamic>?;

    ChatParseResult parse() => ChatTemplateEngine.parse(
      ChatFormat.hermes.index,
      emission,
      tools: [_weatherTool],
    );

    test('$name parses to its recorded result', () {
      if (upstream != null) expect(upstream['tool_calls'], isEmpty);

      final parsed = parse();

      expect(parsed.content, expectedContent);
      expect(_parsedCalls(parsed.toolCalls), expectedCalls);
    });

    test('$name keeps every call the base parser kept', () {
      final remaining = _parsedCalls(parse().toolCalls);
      final baseCalls = _calls(entry['base_result'] as Map<String, dynamic>);
      expect(baseCalls, isNotEmpty);
      for (final call in baseCalls) {
        final index = remaining.indexWhere(
          (candidate) =>
              candidate['name'] == call['name'] &&
              equals(call['arguments']).matches(candidate['arguments'], {}),
        );
        expect(index, isNot(-1), reason: '$call');
        remaining.removeAt(index);
      }
    });

    final splits = <String, List<String>>{
      'one piece': [emission],
      if (expectedCalls.length == 1) 'characters': emission.split(''),
      if (entry['pieces'] != null)
        'recorded pieces': (entry['pieces'] as List).cast<String>(),
    };
    for (final MapEntry(key: templateName, value: template)
        in templates.entries) {
      for (final MapEntry(key: splitName, value: pieces) in splits.entries) {
        test(
          '$name on $templateName as $splitName keeps session history clean',
          () async {
            final backend = _TemplateBackend(template);
            final engine = LlamaEngine(backend);
            addTearDown(engine.dispose);
            await engine.loadModel('mock.gguf');
            backend.queueResponse(pieces);
            final session = ChatSession(engine);

            final chunks = await session
                .create(
                  [LlamaTextContent(prompt)],
                  tools: [_weatherTool],
                  toolChoice: ToolChoice.auto,
                )
                .toList();

            expect(
              chunks.map((c) => c.choices.single.delta.content ?? '').join(),
              expectedContent,
            );
            final reply = session.history.last;
            expect(reply.role, LlamaChatRole.assistant);
            expect(
              reply.parts.whereType<LlamaTextContent>().map((p) => p.text),
              expectedContent.isEmpty ? isEmpty : [expectedContent],
            );
            expect([
              for (final call in reply.parts.whereType<LlamaToolCallContent>())
                {'name': call.name, 'arguments': call.arguments},
            ], expectedCalls);
          },
        );
      }
    }

    for (final choice in ToolChoice.values) {
      test('$name after Qwen3 thinking with $choice', () async {
        final backend = _TemplateBackend(templates['Qwen3']!);
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('mock-qwen3.gguf');
        backend.queueResponse([
          '<think>\nWeather lookup.\n</think>\n\n',
          emission,
        ]);

        final chunks = await engine
            .create(
              [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: prompt,
                ),
              ],
              tools: [_weatherTool],
              toolChoice: choice,
            )
            .toList();

        String join(String? Function(LlamaCompletionChunkDelta) field) =>
            chunks.map((c) => field(c.choices.single.delta) ?? '').join();
        final calls = chunks
            .expand(
              (c) =>
                  c.choices.single.delta.toolCalls ??
                  const <LlamaCompletionChunkToolCall>[],
            )
            .toList();
        expect(join((d) => d.thinking).trim(), 'Weather lookup.');
        if (choice == ToolChoice.none) {
          expect(join((d) => d.content).trim(), emission);
          expect(calls, isEmpty);
        } else {
          expect(join((d) => d.content), expectedContent);
          expect(_parsedCalls(calls), expectedCalls);
        }
      });
    }
  }
}

List<Map<String, dynamic>> _calls(Map<String, dynamic> result) =>
    (result['tool_calls'] as List).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> _parsedCalls(
  List<LlamaCompletionChunkToolCall> calls,
) => [
  for (final call in calls)
    {
      'name': call.function?.name,
      'arguments': jsonDecode(call.function!.arguments!),
    },
];
