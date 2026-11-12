import 'dart:convert';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:test/test.dart';

// tokenizer.chat_template from the issue #517 pinned Qwen3-ASR GGUF.
const _qwenAsrTemplate =
    r"{% for message in messages %}{{'<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>' + '\n'}}{% endfor %}{% if add_generation_prompt %}{{ '<|im_start|>assistant\n' }}{% endif %}";

void main() {
  test('Qwen3-ASR renders identical bounded prompts for file, bytes and PCM', () {
    final bytes = Uint8List.fromList(
      List<int>.generate(352078, (i) => i % 256),
    );
    final parts = <LlamaAudioContent>[
      const LlamaAudioContent(path: '/private/audio.wav'),
      LlamaAudioContent(bytes: bytes),
      LlamaAudioContent(samples: Float32List.fromList([0.1, -0.1])),
    ];
    for (final audio in parts) {
      final message = LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [
          const LlamaTextContent('Transcribe this audio accurately.'),
          audio,
        ],
      );
      final result = ChatTemplateEngine.render(
        templateSource: _qwenAsrTemplate,
        messages: [message],
        metadata: const {},
        enableThinking: false,
      );
      expect(
        result.prompt,
        '<|im_start|>user\nTranscribe this audio accurately.<__media__><|im_end|>\n<|im_start|>assistant\n',
      );
      expect(
        result.prompt,
        isNot(contains(base64Encode(bytes).substring(0, 80))),
      );
      expect(message.parts.last, same(audio));
      expect(audio.bytes, audio == parts[1] ? same(bytes) : isNull);
    }
  });

  test(
    'string templates preserve media order, text, reasoning and tool calls',
    () {
      final message = LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          const LlamaTextContent('before'),
          LlamaAudioContent(bytes: Uint8List.fromList([1, 2, 3])),
          const LlamaTextContent('between'),
          const LlamaImageContent(path: '/private/image.png'),
          const LlamaTextContent('after'),
          const LlamaThinkingContent('reason'),
          const LlamaToolCallContent(
            name: 'lookup',
            arguments: {'key': 'value'},
            rawJson: '{"key":"value"}',
          ),
        ],
      );
      final result = ChatTemplateEngine.render(
        templateSource:
            '{{ messages[0].content }}|{{ messages[0].reasoning_content }}|{{ messages[0].tool_calls[0].function.name }}',
        messages: [message],
        metadata: const {},
      );
      expect(
        result.prompt,
        'before<__media__>between<__media__>after|reason|lookup',
      );
      expect(message.parts.whereType<LlamaAudioContent>(), hasLength(1));
      expect(message.parts.whereType<LlamaImageContent>(), hasLength(1));
    },
  );

  const typedAudioParts =
      '{% for part in messages[0].content %}{% if part.type == "text" %}{{ part.text }}{% elif part.type == "audio" %}<audio_start><|audio|><audio_end>{% endif %}{% endfor %}';

  String renderListen(String template, LlamaAudioContent audio) =>
      ChatTemplateEngine.render(
        templateSource: template,
        messages: [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [const LlamaTextContent('listen'), audio],
          ),
        ],
        metadata: const {},
      ).prompt;

  final audios = <LlamaAudioContent>[
    const LlamaAudioContent(path: '/private/audio.wav'),
    LlamaAudioContent(bytes: Uint8List.fromList([1, 2, 3])),
  ];

  test('typed audio templates get the audio marker without their own '
      'wrappers', () {
    const template =
        '{% if messages[0].content is string %}{{ messages[0].content }}'
        '{% else %}$typedAudioParts{% endif %}';
    for (final audio in audios) {
      expect(renderListen(template, audio), 'listen<__media__>');
    }
  });

  test('typed-only templates get the audio marker in a text part', () {
    for (final audio in audios) {
      expect(renderListen(typedAudioParts, audio), 'listen<__media__>');
    }
  });

  test(
    'audio preprocessing preserves tool choice and thinking configuration',
    () {
      for (final choice in ToolChoice.values) {
        for (final thinking in [true, false]) {
          final rendered = _renderAudioTools(choice, thinking: thinking);
          final control = _renderAudioTools(
            choice,
            thinking: thinking,
            markerControl: true,
          );
          expect(rendered.prompt, control.prompt);
          expect(rendered.prompt, contains('inspect<__media__>'));
          expect(rendered.prompt, isNot(contains('input_audio')));
          expect(rendered.format, control.format);
          expect(rendered.grammar, control.grammar);
          expect(rendered.grammarLazy, choice == ToolChoice.auto);
          expect(
            rendered.grammar,
            choice == ToolChoice.none ? isNull : isNotNull,
          );
          expect(rendered.thinkingForcedOpen, thinking);
          expect(rendered.thinkingForcedOpen, control.thinkingForcedOpen);
          expect(rendered.additionalStops, control.additionalStops);
        }
      }
    },
  );

  test(
    'audio render feeds typed split output and malformed rollback',
    () async {
      final rendered = _renderAudioTools(ToolChoice.required);
      expect(rendered.prompt, 'inspect<__media__><mm:think>');
      const ns = ']<]minimax[>[';
      const envelope =
          '$ns<tool_call>$ns<invoke name="inspect">'
          '$ns<code>123$ns</code>'
          '$ns<options>$ns</options>$ns<items>$ns</items>'
          '$ns<count>7$ns</count>$ns<active>true$ns</active>'
          '$ns<empty>null$ns</empty>$ns</invoke>$ns</tool_call>';
      for (final malformed in [false, true]) {
        final body = malformed
            ? envelope.replaceFirst('name="inspect"', 'name="unknown"')
            : envelope;
        final chunks = await ChatCompletionStreamParser.parse(
          tokenStream: Stream.fromIterable([
            'reason</mm:think>',
            ...body.split(''),
          ]),
          templateResult: rendered,
          parseToolCallsEnabled: true,
          enableThinking: true,
          modelName: 'audio-template-pipeline',
          completionId: 'audio-$malformed',
          tools: [_audioTool],
        ).toList();
        final content = chunks
            .map((chunk) => chunk.choices.single.delta.content ?? '')
            .join();
        final reasoning = chunks
            .map((chunk) => chunk.choices.single.delta.thinking ?? '')
            .join();
        final calls = chunks
            .expand(
              (chunk) =>
                  chunk.choices.single.delta.toolCalls ??
                  const <LlamaCompletionChunkToolCall>[],
            )
            .toList();
        expect(reasoning, 'reason');
        if (malformed) {
          expect(content, body);
          expect(calls, isEmpty);
          expect(
            chunks
                .map((chunk) => chunk.choices.single.delta.content ?? '')
                .where((content) => content.isNotEmpty),
            [body],
          );
        } else {
          expect(content, isEmpty);
          expect(calls, hasLength(1));
          expect(jsonDecode(calls.single.function!.arguments!), {
            'code': '123',
            'options': <String, dynamic>{},
            'items': <Object?>[],
            'count': 7,
            'active': true,
            'empty': null,
          });
          expect(chunks.last.choices.single.finishReason, 'tool_calls');
        }
      }
    },
  );

  test('text-only Qwen3-ASR rendering is unchanged', () {
    final result = ChatTemplateEngine.render(
      templateSource: _qwenAsrTemplate,
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
    );
    expect(
      result.prompt,
      '<|im_start|>user\nhello<|im_end|>\n<|im_start|>assistant\n',
    );
  });
}

// Synthetic MiniMax M3 routing fixture: pipeline coverage, not model/audio support.
LlamaChatTemplateResult _renderAudioTools(
  ToolChoice choice, {
  bool thinking = true,
  bool markerControl = false,
}) => ChatTemplateEngine.render(
  templateSource:
      '{# ]<]minimax[>[ <tool_call> <invoke name= #}'
      '{{ messages[0].content }}{{ "<mm:think>" }}',
  messages: [
    LlamaChatMessage.withContent(
      role: LlamaChatRole.user,
      content: [
        const LlamaTextContent('inspect'),
        markerControl
            ? const LlamaTextContent('<__media__>')
            : LlamaAudioContent(bytes: Uint8List.fromList([1, 2, 3])),
      ],
    ),
  ],
  metadata: const {},
  tools: [_audioTool],
  toolChoice: choice,
  enableThinking: thinking,
);

final _audioTool = ToolDefinition(
  name: 'inspect',
  description: 'Inspect schema values',
  parameters: [
    ToolParam.string('code', required: true),
    ToolParam.object('options', properties: const [], required: true),
    ToolParam.array(
      'items',
      itemType: ToolParam.string('item'),
      required: true,
    ),
    ToolParam.integer('count', required: true),
    ToolParam.boolean('active', required: true),
    ToolParam.nullType('empty', required: true),
  ],
  handler: (_) async => null,
);
