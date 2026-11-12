import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/template/chat_format_registry.dart';
import 'package:test/test.dart';

const _end = '<|end|><|begin|>assistant<|content|>';
// Browser routing fixture; the VM oracle test binds the real model template.
const _template =
    '{# <|tool_response:begin|> <|tool_response:name|> <|tool_response:result|> #}'
    '{% for message in messages %}{{ message.content }}{% endfor %}'
    '<|begin|>assistant';
final _tool = ToolDefinition(
  name: 'weather',
  description: 'Weather',
  parameters: [ToolParam.string('city', required: true)],
);
const _call =
    '<|end|><|begin|>assistant<|tool_calls|>'
    '<|tool_call:begin|>0<|tool_call:name|>weather'
    '<|tool_call:args|>{"city":"Seoul"}<|tool_call:end|>';

LlamaChatTemplateResult _render(bool tools, ToolChoice choice) =>
    ChatTemplateEngine.render(
      templateSource: _template,
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello'),
      ],
      metadata: const {},
      tools: tools ? [_tool] : null,
      toolChoice: choice,
    );

Future<void> _expectStream(
  String output,
  LlamaChatTemplateResult rendered, {
  required bool parseTools,
  required bool thinking,
  bool atLimit = false,
}) async {
  expect(rendered.format, ChatFormat.solarOpen.index);
  final parsed = ChatTemplateEngine.parseRendered(
    rendered,
    output,
    parseToolCalls: parseTools,
    tools: [_tool],
  );
  final direct = ChatTemplateEngine.parse(
    rendered.format,
    output,
    parser: rendered.parser,
    parseToolCalls: parseTools,
    tools: [_tool],
  );
  expect(direct.content, parsed.content);
  expect(direct.reasoningContent, parsed.reasoningContent);
  for (final tokens in [
    [output],
    output.split(''),
    for (var split = 1; split < output.length; split++)
      [output.substring(0, split), output.substring(split)],
  ]) {
    final chunks = await ChatCompletionStreamParser.parse(
      tokenStream: Stream.fromIterable(tokens),
      templateResult: rendered,
      parseToolCallsEnabled: parseTools,
      enableThinking: thinking,
      modelName: 'Solar Open fixture',
      completionId: 'solar-content',
      tools: [_tool],
      stoppedAtLimit: () => atLimit,
    ).toList();
    expect(
      chunks.map((c) => c.choices.single.delta.content ?? '').join(),
      parsed.content,
      reason: '$tokens',
    );
    expect(
      chunks.map((c) => c.choices.single.delta.thinking ?? '').join(),
      thinking ? parsed.reasoningContent ?? '' : '',
      reason: '$tokens',
    );
    expect(
      [
        for (final chunk in chunks)
          for (final call in chunk.choices.single.delta.toolCalls ?? const [])
            (call.function?.name, call.function?.arguments),
      ],
      [
        if (!atLimit)
          for (final call in parsed.toolCalls)
            (call.function?.name, call.function?.arguments),
      ],
    );
  }
}

void main() {
  test('only Solar opts into repeated content channels', () {
    expect(
      [
        for (final registration in chatFormatRegistrations)
          if (registration.traits.hasRepeatedContentChannels)
            registration.format,
      ],
      [ChatFormat.solarOpen],
    );
  });
  for (final tools in [false, true]) {
    for (final choice in [ToolChoice.auto, ToolChoice.none]) {
      final rendered = _render(tools, choice);
      for (final thinking in [false, true]) {
        for (final (output, content, reasoning) in [
          ('<|content|>Sunny. $_end more', 'Sunny.  more', ''),
          ('<|think|>Plan.${_end}Sunny. $_end more', 'Sunny.  more', 'Plan.'),
          ('<|content|>${_end}A$_end${_end}B', 'AB', ''),
          ('<|content|>A \t$_end\n B', 'A \t\n B', ''),
          ('<|content|>Sunny.', 'Sunny.', ''),
          ('<|think|>Plan.${_end}Sunny.', 'Sunny.', 'Plan.'),
        ]) {
          test(
            'tools=$tools choice=$choice thinking=$thinking $output',
            () async {
              final parsed = ChatTemplateEngine.parseRendered(
                rendered,
                output,
                parseToolCalls: tools && choice != ToolChoice.none,
                tools: [_tool],
              );
              expect(parsed.content, content);
              expect(parsed.reasoningContent ?? '', reasoning);
              await _expectStream(
                output,
                rendered,
                parseTools: tools && choice != ToolChoice.none,
                thinking: thinking,
              );
            },
          );
        }
      }
    }
  }
  for (final thinking in [false, true]) {
    test('repeated content before a call thinking=$thinking', () async {
      const output = '<|think|>Plan.${_end}Sunny. $_end more$_call';
      final rendered = _render(true, ToolChoice.auto);
      final parsed = ChatTemplateEngine.parseRendered(
        rendered,
        output,
        tools: [_tool],
      );
      expect(parsed.content, 'Sunny.  more');
      expect(parsed.reasoningContent, 'Plan.');
      expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
        'city': 'Seoul',
      });
      await _expectStream(
        output,
        rendered,
        parseTools: true,
        thinking: thinking,
      );
    });
  }
  for (final tools in [false, true]) {
    for (final thinking in [false, true]) {
      test(
        'public engine preserves channels tools=$tools thinking=$thinking',
        () async {
          final engine = LlamaEngine(_RawSolarBackend());
          addTearDown(engine.dispose);
          await engine.loadModel('Solar-Open-fixture.gguf');
          final completion = await engine
              .create(
                const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'Hello',
                  ),
                ],
                tools: tools ? [_tool] : null,
                enableThinking: thinking,
              )
              .collect();
          expect(completion.text, 'Sunny.  more');
          expect(completion.thinking, thinking ? 'Plan.' : '');
          expect(completion.toolCalls, isEmpty);
        },
      );
    }
  }
  for (final (output, content) in [
    ('<|content|>A ${_end}B  ', 'A B  '),
    ('<|content|>  $_end B\t\n', '   B\t\n'),
    ('<|content|>A $_end  ', 'A   '),
    ('<|content|>A $_end B<|en', 'A  B'),
    ('<|content|>B  ', 'B  '),
  ]) {
    for (final tools in [false, true]) {
      test(
        'final whitespace survives parsed channels tools=$tools $output',
        () async {
          final rendered = _render(tools, ToolChoice.auto);
          final parsed = ChatTemplateEngine.parseRendered(
            rendered,
            output,
            parseToolCalls: tools,
            tools: [_tool],
          );
          expect(parsed.content, content);
          await _expectStream(
            output,
            rendered,
            parseTools: tools,
            thinking: false,
          );
          final engine = LlamaEngine(_RawSolarBackend(output));
          addTearDown(engine.dispose);
          await engine.loadModel('Solar-Open-fixture.gguf');
          final completion = await engine
              .create(
                const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'Hello',
                  ),
                ],
                tools: tools ? [_tool] : null,
                enableThinking: false,
              )
              .collect();
          expect(completion.text, content);
        },
      );
    }
  }
  test('required grammar admission stays strict', () {
    final rendered = _render(true, ToolChoice.required);
    expect(
      () => ChatTemplateEngine.parseRendered(
        rendered,
        '<|think|>Plan.${_end}Sunny. $_end more$_call',
        tools: [_tool],
      ),
      throwsA(isA<LlamaInferenceException>()),
    );
  });
  test('other PEG formats retain their existing last-fragment mapping', () {
    final rendered = _render(false, ToolChoice.auto);
    for (final format in [
      ChatFormat.pegSimple,
      ChatFormat.pegNative,
      ChatFormat.pegConstructed,
      ChatFormat.ministral,
      ChatFormat.qwen3CoderXml,
    ]) {
      final parsed = ChatTemplateEngine.parse(
        format.index,
        '<|think|>Plan.${_end}Sunny. $_end more',
        parser: rendered.parser,
        parseToolCalls: false,
      );
      expect(parsed.content, ' more', reason: format.name);
      expect(parsed.reasoningContent, 'Plan.', reason: format.name);
    }
  });
  for (final output in [
    '<|content|>A $_end',
    '<|content|>A ${_end}B<|end|>',
    '<|content|>A ${_end}B<|en',
  ]) {
    test('accepted truncated channel stays consistent: $output', () async {
      await _expectStream(
        output,
        _render(false, ToolChoice.auto),
        parseTools: false,
        thinking: false,
      );
    });
  }
}

class _RawSolarBackend implements LlamaBackend {
  _RawSolarBackend([this.output = '<|think|>Plan.${_end}Sunny. $_end more']);

  final String output;

  @override
  bool get supportsUrlLoading => false;
  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;
  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;
  @override
  Future<int> getContextSize(int contextHandle) async => 2048;
  @override
  Future<void> modelFree(int modelHandle) async {}
  @override
  Future<void> contextFree(int contextHandle) async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}
  @override
  Future<String> getBackendName() async => 'RawSolar';
  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {
    'tokenizer.chat_template': _template,
  };
  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async => [1];
  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    for (final character in output.split('')) {
      yield utf8.encode(character);
    }
  }

  @override
  void cancelGeneration() {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
