@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/media_placeholders.dart';
import 'package:test/test.dart';

import '../../../support/fake_mtmd.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _params = ModelParams(
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
  gpuLayers: 0,
  contextSize: 64,
);
const _greedy = GenerationParams(maxTokens: 1, temp: 0, topK: 1, seed: 1);

final Map<String, dynamic> _fixture =
    jsonDecode(
          File(
            'test/fixtures/media_marker_render_upstream.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

final LlamaImageContent _image = LlamaImageContent(
  bytes: base64Decode(_fixture['image_png_base64'] as String),
);

List<LlamaChatMessage> _conversation(String name) => [
  for (final message
      in ((_fixture['conversations'] as Map<String, dynamic>)[name] as List)
          .cast<Map<String, dynamic>>())
    LlamaChatMessage.withContent(
      role: LlamaChatRole.values.byName(message['role'] as String),
      content: [
        for (final part
            in (message['parts'] as List).cast<Map<String, dynamic>>())
          part['image'] == true
              ? _image
              : LlamaTextContent(part['text'] as String),
      ],
    ),
];

Future<void> _drain(
  Stream<List<int>> Function(int cancelToken) generate,
) async {
  final cancel = calloc<Int8>();
  try {
    await generate(cancel.address).drain<void>();
  } finally {
    calloc.free(cancel);
  }
}

// Runs the real llama.cpp runtime on the CPU and reads the prompt the service
// hands to a fake projector's mtmd_tokenize.
void main() {
  late Directory dir;
  late String modelPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_media_prompt_');
    addTearDown(() => dir.deleteSync(recursive: true));
    modelPath = writeSyntheticLlamaGguf('${dir.path}/model.gguf').path;
  });

  group('with a projector', () {
    late LlamaCppService service;
    late FakeMtmd fake;
    late int context;

    setUp(() {
      service = LlamaCppService(objectCalls: LlamaCppObjectCalls.upstream)
        ..initializeBackend();
      final model = service.loadModel(modelPath, _params);
      fake = FakeMtmd.install(
        service,
        tokens: service.tokenize(model, 'ab', true),
      );
      addTearDown(fake.dispose);
      addTearDown(service.dispose);
      context = service.createContext(model, _params);
      final projectorPath = '${dir.path}/mmproj.gguf';
      File(projectorPath).writeAsStringSync('GGUF');
      service.createMultimodalContext(model, projectorPath);
    });

    Future<String> chatPromptAtMtmd(String prompt, int images) async {
      await _drain(
        (cancel) => service.generateChatPrompt(
          context,
          prompt,
          _greedy,
          cancel,
          mediaMarker: chatPromptMediaMarker,
          parts: List.filled(images, _image),
        ),
      );
      return fake.prompts.single;
    }

    Future<String> callerPromptAtMtmd(String prompt, int images) async {
      await _drain(
        (cancel) => service.generate(
          context,
          prompt,
          _greedy,
          cancel,
          parts: List.filled(images, _image),
        ),
      );
      return fake.prompts.single;
    }

    for (final template in const ['Qwen3_5-0_8B', 'Qwen2_5-Omni-3B']) {
      final cases = (_fixture['cases'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (entry) =>
                (entry['template'] as String).endsWith('$template.jinja') &&
                entry['media_model'] == 'vision',
          );

      for (final upstream in cases) {
        final conversation = upstream['conversation'] as String;

        test('hands mtmd the $template $conversation prompt llama-server '
            'renders', () async {
          final messages = _conversation(conversation);
          final rendered = ChatTemplateEngine.render(
            templateSource: File(
              upstream['template'] as String,
            ).readAsStringSync(),
            messages: messages,
            metadata: {
              'tokenizer.ggml.bos_token': '',
              'tokenizer.ggml.eos_token': upstream['eos_token'] as String,
            },
            mediaMarker: chatPromptMediaMarker,
          );

          // mtmd would read the `<__media__>` a message quotes as a part,
          // so that one string reaches it with a zero-width space in it.
          final expected = (upstream['prompt'] as String)
              .replaceAll('<__media__>', '<\u200B__media__>')
              .replaceAll(upstream['media_marker'] as String, '<__media__>');
          expect(
            await chatPromptAtMtmd(
              rendered.prompt,
              messages
                  .expand((message) => message.parts)
                  .whereType<LlamaImageContent>()
                  .length,
            ),
            expected,
          );
        });

        test('hands mtmd the $template $conversation prompt llama-server '
            'renders when it comes as a caller prompt', () async {
          final messages = _conversation(conversation);
          final rendered = ChatTemplateEngine.render(
            templateSource: File(
              upstream['template'] as String,
            ).readAsStringSync(),
            messages: messages,
            metadata: {
              'tokenizer.ggml.bos_token': '',
              'tokenizer.ggml.eos_token': upstream['eos_token'] as String,
            },
            mediaMarker: chatPromptMediaMarker,
          );

          // The caller path reads each of these as a part, so each reaches
          // mtmd with a zero-width space in it.
          var expected = upstream['prompt'] as String;
          for (final quoted in const [
            '<__media__>',
            '<img>',
            '<image>',
            '[IMG]',
          ]) {
            expected = expected.replaceAll(
              quoted,
              '${quoted[0]}\u200B${quoted.substring(1)}',
            );
          }
          expect(
            await callerPromptAtMtmd(
              chatPromptAsCallerPrompt(
                rendered.prompt,
                chatMarker: chatPromptMediaMarker,
              ),
              messages
                  .expand((message) => message.parts)
                  .whereType<LlamaImageContent>()
                  .length,
            ),
            expected.replaceAll(
              upstream['media_marker'] as String,
              '<__media__>',
            ),
          );
        });
      }
    }

    test('puts a part the chat prompt has no marker for before the '
        'prompt', () async {
      expect(
        await chatPromptAtMtmd('${chatPromptMediaMarker}a <img> b', 2),
        '<__media__>\n<__media__>a <img> b',
      );
    });

    for (final (prompt, images, expected) in const [
      ('<__media__>a', 1, '<__media__>a'),
      ('<image>a', 1, '<__media__>a'),
      ('<img>a[IMG]b<|image_2|>', 3, '<__media__>a<__media__>b<__media__>'),
      ('a', 1, '<__media__>\na'),
      ('a', 2, '<__media__> <__media__>\na'),
      ('<image>a', 2, '<__media__>\n<__media__>a'),
      ('User: a\nAssistant:', 1, 'User: <__media__>  a\nAssistant:'),
      ('user: a', 2, 'user: <__media__> <__media__>  a'),
    ]) {
      test('hands mtmd ${jsonEncode(expected)} for the caller prompt '
          '${jsonEncode(prompt)} with $images parts', () async {
        expect(await callerPromptAtMtmd(prompt, images), expected);
      });
    }
  });
}
