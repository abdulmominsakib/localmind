import 'dart:convert';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart'
    show BackendChatMessageValidation;
import 'package:test/test.dart';

import 'engine_test.dart' show MockLlamaBackend;

const _template =
    '{% for message in messages %}'
    '{{message.role}}: {{message.content}}\n'
    '{% endfor %}'
    '{% if add_generation_prompt %}assistant: {% endif %}';
const _result = LlamaToolResultContent(
  id: 'inspect_1',
  name: 'inspect',
  result: 'tool result',
);

Future<LlamaEngine> _loaded(_CaptureBackend backend) async {
  final engine = LlamaEngine(backend);
  addTearDown(engine.dispose);
  await engine.loadModel(
    'model.gguf',
    modelParams: const ModelParams(chatTemplate: _template),
  );
  return engine;
}

final _toolMediaError = isA<LlamaUnsupportedException>().having(
  (error) => error.message,
  'actionable tool media error',
  allOf(
    contains('Tool-role image/audio'),
    contains('all runtimes'),
    contains('text or JSON tool results'),
    contains('separate user message'),
  ),
);

void main() {
  for (final (kind, media) in <(String, LlamaContentPart)>[
    ('image', const LlamaImageContent(path: '/unused-image.png')),
    ('audio', const LlamaAudioContent(path: '/unused-audio.wav')),
  ]) {
    final invalid = <String, LlamaChatMessage>{
      for (final role in LlamaChatRole.values)
        'typed result under ${role.name}': LlamaChatMessage.withContent(
          role: role,
          content: [_result, media],
        ),
      'tool role without typed result': LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: [const LlamaTextContent('legacy tool result'), media],
      ),
    };
    for (final entry in invalid.entries) {
      for (final renderOnly in [false, true]) {
        test('${renderOnly ? 'chatTemplate' : 'create'} refuses $kind '
            '${entry.key} before render or dispatch', () async {
          final backend = _CaptureBackend();
          final engine = await _loaded(backend);
          final metadataBefore = backend.modelMetadataCalls;
          final tokensBefore = backend.tokenizeCalls;
          final messages = [entry.value];

          await expectLater(
            renderOnly
                ? engine.chatTemplate(messages)
                : engine.create(messages).drain<void>(),
            throwsA(_toolMediaError),
          );

          expect(backend.modelMetadataCalls, metadataBefore);
          expect(backend.tokenizeCalls, tokensBefore);
          expect(backend.chatPrompt, isNull);
          expect(backend.lastGenerationPrompt, isNull);
        });
      }
    }

    test('session budget refuses $kind tool history before tokenization '
        'and restores its new user turn', () async {
      final backend = _CaptureBackend();
      final engine = await _loaded(backend);
      final session = ChatSession(engine, maxContextTokens: 2048);
      final prior = LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: [_result, media],
      );
      session.addMessage(prior);
      final metadataBefore = backend.modelMetadataCalls;
      final tokensBefore = backend.tokenizeCalls;

      await expectLater(session.send('next'), throwsA(_toolMediaError));

      expect(session.history, [same(prior)]);
      expect(backend.modelMetadataCalls, metadataBefore);
      expect(backend.tokenizeCalls, tokensBefore);
      expect(backend.chatPrompt, isNull);
      expect(backend.lastGenerationPrompt, isNull);
    });

    test('$kind in a separate user message keeps its marker and backend part '
        'alongside text tool history', () async {
      final backend = _CaptureBackend();
      final engine = await _loaded(backend);
      final messages = [
        const LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [_result],
        ),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [media, const LlamaTextContent('describe')],
        ),
      ];

      final rendered = await engine.chatTemplate(messages);
      expect(
        rendered.prompt,
        contains('tool: tool result\nuser: <__media__>describe'),
      );
      expect(rendered.tokenCount, 3);
      await engine.create(messages).drain<void>();
      expect(
        backend.chatPrompt,
        contains('tool: tool result\nuser: ${backend.marker}describe'),
      );
      expect(backend.parts, contains(same(media)));
      expect(
        backend.parts!.where((part) => identical(part, media)),
        hasLength(1),
      );
      expect(backend.lastGenerationPrompt, isNull);
    });
  }

  test(
    'text-only typed and legacy tool messages still render and generate',
    () async {
      final backend = _CaptureBackend();
      final engine = await _loaded(backend);
      const messages = [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [_result],
        ),
        LlamaChatMessage(role: 'tool', content: 'legacy result'),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'continue'),
      ];

      final rendered = await engine.chatTemplate(messages);
      expect(
        rendered.prompt,
        'tool: tool result\ntool: legacy result\nuser: continue\nassistant: ',
      );
      await engine.create(messages).drain<void>();
      expect(backend.lastGenerationPrompt, rendered.prompt);
      expect(backend.chatPrompt, isNull);
    },
  );

  test('readiness errors still precede unsupported tool media', () async {
    final engine = LlamaEngine(_CaptureBackend());
    addTearDown(engine.dispose);
    const messages = [
      LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: [
          _result,
          LlamaImageContent(path: '/unused-image.png'),
        ],
      ),
    ];
    await expectLater(
      engine.create(messages).drain<void>(),
      throwsA(isA<LlamaContextException>()),
    );
    await expectLater(
      engine.chatTemplate(messages),
      throwsA(isA<LlamaContextException>()),
    );
  });

  test(
    'backend message validation still precedes shared create refusal',
    () async {
      final backend = _ValidatingBackend();
      final engine = await _loaded(backend);
      await expectLater(
        engine.create(const [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              _result,
              LlamaImageContent(path: '/unused-image.png'),
            ],
          ),
        ]).drain<void>(),
        throwsA(same(backend.error)),
      );
      expect(backend.validations, 1);
      expect(backend.chatPrompt, isNull);
    },
  );

  test('video tool requests retain the existing typed video refusal', () async {
    final backend = _CaptureBackend();
    final engine = await _loaded(backend);
    await expectLater(
      engine.create([
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            _result,
            LlamaVideoContent(path: '/unused-video.mp4'),
          ],
        ),
      ]).drain<void>(),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'video reason',
          contains('video'),
        ),
      ),
    );
    expect(backend.chatPrompt, isNull);
    expect(backend.lastGenerationPrompt, isNull);
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

class _ValidatingBackend extends _CaptureBackend
    implements BackendChatMessageValidation {
  final LlamaUnsupportedException error = LlamaUnsupportedException(
    'Backend-specific message refusal.',
  );
  int validations = 0;

  @override
  bool get requiresStructuredChatInput => false;

  @override
  void validateChatMessages(List<LlamaChatMessage> messages) {
    validations++;
    throw error;
  }
}
