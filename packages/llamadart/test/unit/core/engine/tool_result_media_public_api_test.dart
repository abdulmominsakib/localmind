@TestOn('vm')
library;

import 'dart:convert';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/qwen3_vl_tool_media_fixture.dart';
import 'engine_test.dart' show MockLlamaBackend, NativeChatMockBackend;

Future<LlamaEngine> _loaded(
  LlamaBackend backend, {
  String? template,
  bool projector = true,
}) async {
  final engine = LlamaEngine(backend);
  addTearDown(engine.dispose);
  await engine.loadModel(
    'model.gguf',
    modelParams: ModelParams(
      chatTemplate: template ?? Qwen3VlToolMediaFixture.template,
    ),
  );
  if (projector) await engine.loadMultimodalProjector('mmproj.gguf');
  return engine;
}

LlamaChatMessage _toolWith(List<LlamaContentPart> content) =>
    LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: [
        LlamaToolResultContent(
          id: 'call_0',
          name: 'take_photo',
          result: null,
          content: content,
        ),
      ],
    );

Matcher _unsupported(Object fragment) => throwsA(
  isA<LlamaUnsupportedException>().having(
    (error) => error.message,
    'message',
    fragment is Matcher ? fragment : contains(fragment),
  ),
);

void main() {
  final upstream = Qwen3VlToolMediaFixture.load();

  group('capabilities.toolResultMedia', () {
    test('reports images for native llama.cpp, a vision projector and a '
        'Hermes template', () async {
      final engine = await _loaded(_ToolMediaBackend());
      expect((await engine.capabilities).toolResultMedia, {
        LlamaToolResultMedia.image,
      });
    });

    test('is empty without a projector', () async {
      final engine = await _loaded(_ToolMediaBackend(), projector: false);
      expect((await engine.capabilities).toolResultMedia, isEmpty);
    });

    test('is empty when the backend places no tool-result media', () async {
      final engine = await _loaded(_CaptureBackend());
      expect((await engine.capabilities).supportsVision, isTrue);
      expect((await engine.capabilities).toolResultMedia, isEmpty);
    });

    test('is empty for a template format not qualified for it', () async {
      final engine = await _loaded(
        _ToolMediaBackend(),
        template: '{% for m in messages %}{{ m.content }}{% endfor %}',
      );
      expect((await engine.capabilities).toolResultMedia, isEmpty);
    });

    for (final audio in [false, true]) {
      test('reports audio only when the projector takes audio '
          '(projector audio: $audio)', () async {
        final engine = await _loaded(_AudioToolMediaBackend(audio: audio));
        expect((await engine.capabilities).toolResultMedia, {
          LlamaToolResultMedia.image,
          if (audio) LlamaToolResultMedia.audio,
        });
      });
    }

    test('omits audio the backend does not place, whatever the projector '
        'takes', () async {
      final engine = await _loaded(_ImageOnlyAudioProjectorBackend());
      expect((await engine.capabilities).supportsAudio, isTrue);
      expect((await engine.capabilities).toolResultMedia, {
        LlamaToolResultMedia.image,
      });
    });

    for (final (parsing, runtime, reported) in [
      (Qwen3VlToolMediaFixture.template, '{{ messages }}', true),
      ('{{ messages }}', Qwen3VlToolMediaFixture.template, false),
    ]) {
      test('follows the parsing template, not the runtime one '
          '(reported: $reported)', () async {
        final engine = LlamaEngine(
          _MetadataToolMediaBackend({
            'tokenizer.chat_template': runtime,
            'llamadart.chat_template.parsing': parsing,
          }),
        );
        addTearDown(engine.dispose);
        await engine.loadModel('model.gguf');
        await engine.loadMultimodalProjector('mmproj.gguf');
        expect(
          (await engine.capabilities).toolResultMedia,
          reported ? {LlamaToolResultMedia.image} : isEmpty,
        );
      });
    }

    test('is empty before a model loads', () async {
      final engine = LlamaEngine(_ToolMediaBackend());
      addTearDown(engine.dispose);
      expect((await engine.capabilities).toolResultMedia, isEmpty);
    });
  });

  for (final (name, messages, media) in [
    (
      'two_results',
      Qwen3VlToolMediaFixture.twoResults(),
      [Qwen3VlToolMediaFixture.red, Qwen3VlToolMediaFixture.blue],
    ),
    (
      'user_image_then_tool_image',
      Qwen3VlToolMediaFixture.userImageThenToolImage(),
      [Qwen3VlToolMediaFixture.blue, Qwen3VlToolMediaFixture.red],
    ),
  ]) {
    test('chatTemplate renders $name as llama-server does', () async {
      final engine = await _loaded(_ToolMediaBackend());
      final rendered = await engine.chatTemplate(messages);
      expect(rendered.prompt, upstream.prompt(name));
    });

    test('create sends $name media in prompt order at their markers', () async {
      final backend = _ToolMediaBackend();
      final engine = await _loaded(backend);

      await engine.create(messages).drain<void>();

      expect(
        backend.chatPrompt,
        upstream.prompt(name).replaceAll('<__media__>', backend.marker!),
      );
      final sent = backend.parts!.whereType<LlamaImageContent>().toList();
      expect(sent, hasLength(media.length));
      for (final (index, part) in media.indexed) {
        expect(sent[index], same(part), reason: 'media $index');
      }
    });
  }

  group('create and chatTemplate refuse before rendering', () {
    for (final renderOnly in [false, true]) {
      final call = renderOnly ? 'chatTemplate' : 'create';
      Future<void> run(LlamaEngine engine, List<LlamaChatMessage> messages) =>
          renderOnly
          ? engine.chatTemplate(messages)
          : engine.create(messages).drain<void>();

      Future<void> expectRefused(
        LlamaBackend backend,
        List<LlamaChatMessage> messages,
        Matcher matcher, {
        bool projector = true,
      }) async {
        final engine = await _loaded(backend, projector: projector);
        final mock = backend as MockLlamaBackend;
        final metadataBefore = mock.modelMetadataCalls;
        final tokensBefore = mock.tokenizeCalls;
        await expectLater(run(engine, messages), matcher);
        expect(mock.modelMetadataCalls, metadataBefore);
        expect(mock.tokenizeCalls, tokensBefore);
        if (backend is _CaptureBackend) expect(backend.chatPrompt, isNull);
        expect(mock.lastGenerationPrompt, isNull);
      }

      test('$call: an image on a backend that places none', () async {
        await expectRefused(
          _CaptureBackend(),
          Qwen3VlToolMediaFixture.twoResults(),
          _unsupported('Tool-result image'),
        );
      });

      test('$call: an image without a vision projector', () async {
        await expectRefused(
          _ToolMediaBackend(),
          Qwen3VlToolMediaFixture.twoResults(),
          _unsupported('loaded multimodal projector'),
          projector: false,
        );
      });

      test('$call: audio, which no backend places', () async {
        await expectRefused(_ToolMediaBackend(), [
          _toolWith(const [LlamaAudioContent(path: '/a.wav')]),
        ], _unsupported('Tool-result audio'));
      });

      test('$call: audio the projector does not take', () async {
        await expectRefused(_AudioToolMediaBackend(audio: false), [
          _toolWith(const [LlamaAudioContent(path: '/a.wav')]),
        ], _unsupported('Tool-result audio'));
      });

      test('$call: a URL-only image, without echoing the URL', () async {
        await expectRefused(
          _ToolMediaBackend(),
          [
            _toolWith(const [
              LlamaImageContent(url: 'https://x.test/p.png?sig=secret'),
            ]),
          ],
          _unsupported(
            allOf(contains('path or bytes'), isNot(contains('secret'))),
          ),
        );
      });

      test('$call: a nested thinking part', () async {
        await expectRefused(_ToolMediaBackend(), [
          _toolWith(const [LlamaThinkingContent('hidden')]),
        ], throwsA(isA<LlamaArgumentException>()));
      });

      test('$call: media beside a typed result still throws', () async {
        await expectRefused(_ToolMediaBackend(), [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              const LlamaToolResultContent(name: 't', result: 'r'),
              Qwen3VlToolMediaFixture.red,
            ],
          ),
        ], _unsupported('Tool-role image/audio'));
      });
    }
  });

  test('a template that is not qualified refuses after metadata', () async {
    final backend = _ToolMediaBackend();
    final engine = await _loaded(
      backend,
      template: '{% for m in messages %}{{ m.content }}{% endfor %}',
    );
    await expectLater(
      engine.create(Qwen3VlToolMediaFixture.twoResults()).drain<void>(),
      _unsupported('not qualified'),
    );
    expect(backend.chatPrompt, isNull);
  });

  test('backends that take chat natively refuse text content', () async {
    final backend = NativeChatMockBackend();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel(
      'model.gguf',
      modelParams: ModelParams(chatTemplate: Qwen3VlToolMediaFixture.template),
    );

    await expectLater(
      engine.create([
        const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'q'),
        _toolWith(const [LlamaTextContent('caption')]),
      ]).drain<void>(),
      _unsupported('take chat messages natively'),
    );
    expect(backend.nativeGenerateChatCalls, 0);
  });

  test('text-only content renders on a backend without media', () async {
    final backend = _CaptureBackend();
    final engine = await _loaded(backend, projector: false);
    final messages = [
      const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'q'),
      _toolWith(const [LlamaTextContent('caption')]),
    ];

    await engine.create(messages).drain<void>();

    expect(
      backend.lastGenerationPrompt,
      contains('<tool_response>\ncaption\n</tool_response>'),
    );
  });

  group('tool loop', () {
    final photos = {
      'front': Qwen3VlToolMediaFixture.red,
      'back': Qwen3VlToolMediaFixture.blue,
    };
    ToolDefinition camera({bool withHandler = true}) => ToolDefinition(
      name: 'take_photo',
      description: 'Takes a photo.',
      parameters: [ToolParam.string('camera')],
      handler: withHandler
          ? (params) async {
              final side = params.getRequiredString('camera');
              return LlamaToolOutput(
                output: const {'ok': true},
                content: [LlamaTextContent('$side camera'), photos[side]!],
              );
            }
          : null,
    );
    String call(String side) =>
        '<tool_call>\n{"name": "take_photo", "arguments": '
        '{"camera": "$side"}}\n</tool_call>';

    test('a handler output reaches the next turn with its media', () async {
      final backend = _ScriptedBackend([
        '${call('front')}\n${call('back')}',
        'Red, then blue.',
      ]);
      final engine = await _loaded(backend);
      final session = ChatSession(engine, maxContextTokens: 0);

      final result = await session.sendWithTools(
        'Take a photo with each camera.',
        tools: [camera()],
        parallelToolCalls: true,
      );

      expect(result.stopReason, LlamaToolLoopStopReason.completed);
      expect(result.completion.text, 'Red, then blue.');
      final results = [
        for (final message in session.history)
          ...message.parts.whereType<LlamaToolResultContent>(),
      ];
      expect(
        [for (final r in results) r.result],
        [
          {'ok': true},
          {'ok': true},
        ],
      );
      expect(results.first.content.last, same(photos['front']));
      expect(results.last.content.last, same(photos['back']));
      final m = backend.marker!;
      expect(
        backend.prompts.last,
        contains(
          '<tool_response>\n{"ok":true}\nfront camera$m\n</tool_response>\n'
          '<tool_response>\n{"ok":true}\nback camera$m\n</tool_response>',
        ),
      );
      expect(backend.media.last, [same(photos['front']), same(photos['back'])]);
    });

    test('app results resume an interrupted turn with their media', () async {
      final backend = _ScriptedBackend([call('front'), 'It is red.']);
      final engine = await _loaded(backend);
      final session = ChatSession(engine, maxContextTokens: 0);
      final tool = camera(withHandler: false);

      final interrupted = await session.sendWithTools(
        'Take a photo.',
        tools: [tool],
      );
      expect(
        interrupted.stopReason,
        LlamaToolLoopStopReason.unhandledToolCalls,
      );
      final pending = interrupted.pendingToolCalls.single;
      session.addMessage(
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            LlamaToolResultContent(
              id: pending.id,
              name: pending.name,
              result: null,
              content: [photos['front']!],
            ),
          ],
        ),
      );

      final resumed = await session.completeWithTools(const [], tools: [tool]);

      expect(resumed.completion.text, 'It is red.');
      expect(
        backend.prompts.last,
        contains('<tool_response>\n${backend.marker}\n</tool_response>'),
      );
      expect(backend.media.last, [same(photos['front'])]);
    });

    test('an onToolCall output is stored with its content', () async {
      final backend = _ScriptedBackend([call('back'), 'Blue.']);
      final engine = await _loaded(backend);
      final session = ChatSession(engine, maxContextTokens: 0);

      await session.sendWithTools(
        'Take a photo.',
        tools: [camera(withHandler: false)],
        onToolCall: (call) =>
            LlamaToolOutput(output: 'saved', content: [photos['back']!]),
      );

      final stored = session.history
          .expand((message) => message.parts)
          .whereType<LlamaToolResultContent>()
          .single;
      expect(stored.result, 'saved');
      expect(stored.content.single, same(photos['back']));
      expect(backend.media.last, [same(photos['back'])]);
    });
  });
}

class _CaptureBackend extends MockLlamaBackend
    implements BackendChatPromptGeneration {
  String? chatPrompt;
  String? marker;
  List<LlamaContentPart>? parts;

  @override
  Stream<List<int>> generateChatPrompt(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    required String mediaMarker,
    List<LlamaContentPart>? parts,
  }) async* {
    chatPrompt = prompt;
    marker = mediaMarker;
    this.parts = parts;
    yield utf8.encode('response');
  }
}

class _ToolMediaBackend extends _CaptureBackend
    implements BackendToolResultMedia {
  @override
  Set<LlamaToolResultMedia> get toolResultMedia => const {
    LlamaToolResultMedia.image,
  };
}

class _MetadataToolMediaBackend extends _ToolMediaBackend {
  _MetadataToolMediaBackend(this.metadata);

  final Map<String, String> metadata;

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => metadata;
}

class _AudioToolMediaBackend extends _CaptureBackend
    implements BackendToolResultMedia {
  _AudioToolMediaBackend({required this.audio});

  final bool audio;

  @override
  Set<LlamaToolResultMedia> get toolResultMedia => const {
    LlamaToolResultMedia.image,
    LlamaToolResultMedia.audio,
  };

  @override
  Future<bool> supportsAudio(int mmContextHandle) async => audio;
}

class _ImageOnlyAudioProjectorBackend extends _ToolMediaBackend {
  @override
  Future<bool> supportsAudio(int mmContextHandle) async => true;
}

/// Replies with [replies] in order, recording each prompt and its media.
class _ScriptedBackend extends _ToolMediaBackend {
  _ScriptedBackend(this.replies);

  final List<String> replies;
  final List<String> prompts = [];
  final List<List<LlamaContentPart>> media = [];

  Stream<List<int>> _reply(String prompt, List<LlamaContentPart>? parts) {
    prompts.add(prompt);
    media.add([
      for (final part in parts ?? const <LlamaContentPart>[])
        if (part is LlamaImageContent || part is LlamaAudioContent) part,
    ]);
    return Stream.value(utf8.encode(replies.removeAt(0)));
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) => _reply(prompt, parts);

  @override
  Stream<List<int>> generateChatPrompt(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    required String mediaMarker,
    List<LlamaContentPart>? parts,
  }) {
    marker = mediaMarker;
    return _reply(prompt, parts);
  }
}
