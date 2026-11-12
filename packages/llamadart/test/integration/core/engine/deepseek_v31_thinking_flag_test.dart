@TestOn('vm')
library;

import 'dart:io';

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

const List<LlamaChatMessage> _messages = [
  LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Weather?'),
];

// llama.cpp `620d2225` gives the template `enable_thinking`, and a
// `thinking` kwarg overrides it; the template reads `thinking` first.
const String _openThought = '<｜Assistant｜><think>';
const String _closedThought = '<｜Assistant｜><think></think>';

void main() {
  final template = File(
    'test/fixtures/llama_cpp_templates/deepseek-ai-DeepSeek-V3.1.jinja',
  ).readAsStringSync();

  late _TemplateBackend backend;
  late LlamaEngine engine;

  setUp(() async {
    backend = _TemplateBackend(template);
    engine = LlamaEngine(backend);
    await engine.loadModel('mock-deepseek-v3_1.gguf');
  });

  tearDown(() => engine.dispose());

  Future<({String prompt, bool forcedOpen})> render(
    bool enableThinking, [
    Map<String, dynamic>? chatTemplateKwargs,
  ]) async {
    final rendered = await engine.chatTemplate(
      _messages,
      enableThinking: enableThinking,
      chatTemplateKwargs: chatTemplateKwargs,
      includeTokenCount: false,
    );
    return (prompt: rendered.prompt, forcedOpen: rendered.thinkingForcedOpen);
  }

  Future<({String prompt, String thinking, String content})> generate(
    bool enableThinking, [
    Map<String, dynamic>? chatTemplateKwargs,
  ]) async {
    backend.queueResponse(['Plan', '</think>', 'Sunny.']);
    final chunks = await engine
        .create(
          _messages,
          enableThinking: enableThinking,
          chatTemplateKwargs: chatTemplateKwargs,
        )
        .toList();
    final deltas = chunks.map((chunk) => chunk.choices.single.delta);
    return (
      prompt: backend.prompts.last,
      thinking: deltas.map((delta) => delta.thinking ?? '').join(),
      content: deltas.map((delta) => delta.content ?? '').join(),
    );
  }

  group('DeepSeek V3.1 with enableThinking and no kwargs', () {
    test('true forces the thought open', () async {
      final rendered = await render(true);
      expect(rendered.prompt, endsWith(_openThought));
      expect(rendered.forcedOpen, isTrue);

      final generated = await generate(true);
      expect(generated.prompt, endsWith(_openThought));
      expect(generated.thinking, 'Plan');
      expect(generated.content, 'Sunny.');
    });

    test('false closes the thought', () async {
      final rendered = await render(false);
      expect(rendered.prompt, endsWith(_closedThought));
      expect(rendered.forcedOpen, isFalse);

      final generated = await generate(false);
      expect(generated.prompt, endsWith(_closedThought));
      expect(generated.thinking, isEmpty);
    });
  });

  for (final key in ['thinking', 'enable_thinking']) {
    group('DeepSeek V3.1 with a boolean $key kwarg', () {
      test('true overrides enableThinking: false', () async {
        expect(await render(false, {key: true}), await render(true));

        final generated = await generate(false, {key: true});
        expect(generated.prompt, endsWith(_openThought));
        expect(generated.thinking, 'Plan');
        expect(generated.content, 'Sunny.');
      });

      test('false overrides enableThinking: true', () async {
        expect(await render(true, {key: false}), await render(false));

        final generated = await generate(true, {key: false});
        expect(generated.prompt, endsWith(_closedThought));
        expect(generated.thinking, isEmpty);
      });
    });
  }
}
