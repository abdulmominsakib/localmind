@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/src/core/template/media_placeholders.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeMediaPlaceholders', () {
    test('rewrites every placeholder in the shared table', () {
      for (final placeholder in mtmdMediaPlaceholders) {
        expect(
          normalizeMediaPlaceholders('before $placeholder after'),
          'before $mtmdMediaMarker after',
          reason: '$placeholder should normalize to the mtmd marker',
        );
      }
    });

    test('rewrites indexed image placeholders', () {
      expect(
        normalizeMediaPlaceholders('a <|image_1|> b <|image_12|> c'),
        'a $mtmdMediaMarker b $mtmdMediaMarker c',
      );
    });

    test('honours a runtime-resolved marker', () {
      expect(
        normalizeMediaPlaceholders('<image>', marker: '<<media>>'),
        '<<media>>',
      );
    });

    test('rewrites every occurrence, not just the first', () {
      expect(
        normalizeMediaPlaceholders('<image><image>'),
        '$mtmdMediaMarker$mtmdMediaMarker',
      );
    });

    // A looser match on `<image` would corrupt `<image_soft_token>`.
    test('matches full literals rather than shared prefixes', () {
      expect(normalizeMediaPlaceholders('<image_soft_token>'), mtmdMediaMarker);
      expect(normalizeMediaPlaceholders('<|image_1|>'), mtmdMediaMarker);
    });

    test('leaves unrelated markup alone', () {
      expect(
        normalizeMediaPlaceholders('<think>text</think> <imagine>'),
        '<think>text</think> <imagine>',
      );
    });

    test('covers the markers that previously differed between layers', () {
      // Each of these lived in only one of the tables before.
      for (final placeholder in <String>[
        '<img>',
        '<|img|>',
        '<start_of_image>',
      ]) {
        expect(mtmdMediaPlaceholders, contains(placeholder));
        expect(normalizeMediaPlaceholders(placeholder), mtmdMediaMarker);
      }
    });
  });

  group('chatPromptForMarkerRuntime', () {
    String forRuntime(String prompt, Pattern placeholders) =>
        chatPromptForMarkerRuntime(
          prompt,
          chatMarker: '<m>',
          marker: mtmdMediaMarker,
          runtimePlaceholders: placeholders,
        );

    test('writes the runtime marker where the chat marker stood', () {
      expect(
        forRuntime('a<m>b<m><m>c', mtmdMediaMarker),
        'a${mtmdMediaMarker}b$mtmdMediaMarker${mtmdMediaMarker}c',
      );
    });

    test('breaks a string the runtime would read as a part with a '
        'zero-width space after its first character', () {
      expect(
        forRuntime('<m>What is <__media__>?', mtmdMediaMarker),
        '<__media__>What is <\u200B__media__>?',
      );
      expect(
        forRuntime('<img><m>[IMG]', RegExp(r'<img>|\[IMG\]')),
        '<\u200Bimg><__media__>[\u200BIMG]',
      );
    });

    test('leaves other placeholder strings as they are', () {
      expect(
        forRuntime('<m><img> <image> [IMG]', mtmdMediaMarker),
        '<__media__><img> <image> [IMG]',
      );
    });
  });

  group('chatPromptAsCallerPrompt', () {
    test('writes the default marker where the chat marker stood', () {
      expect(
        chatPromptAsCallerPrompt('a<m>b<m>', chatMarker: '<m>'),
        'a<__media__>b<__media__>',
      );
    });

    test('breaks every string the llama.cpp service or the WebGPU bridge '
        'reads as a part in a caller prompt', () {
      final quoted = <String>[
        mtmdMediaMarker,
        ...mtmdMediaPlaceholders,
        '<|image_1|>',
        '<|image_12|>',
        '<audio>',
        '<|audio_3|>',
        '<|vision_start|><|image_pad|><|vision_end|>',
        '<|vision_start|><|video_pad|><|vision_end|>',
      ];
      for (final placeholder in quoted) {
        final prompt = chatPromptAsCallerPrompt(
          '<m>before $placeholder after',
          chatMarker: '<m>',
        );

        expect(
          prompt,
          '<__media__>before ${placeholder[0]}\u200B'
          '${placeholder.substring(1)} after',
        );
        expect(
          normalizeMediaPlaceholders(prompt),
          prompt,
          reason: '$placeholder is no longer a placeholder',
        );
        expect(
          webGpuBridgeMediaPlaceholders.allMatches(prompt),
          hasLength(1),
          reason: 'the bridge finds the part marker only',
        );
      }
    });

    test('leaves other text as it is', () {
      expect(
        chatPromptAsCallerPrompt(
          '<m><think>x</think> <imagine> <|im_end|>',
          chatMarker: '<m>',
        ),
        '<__media__><think>x</think> <imagine> <|im_end|>',
      );
    });
  });

  group('chatPromptMediaMarker', () {
    test("is a marker of 32 random characters, as llama-server's is", () {
      expect(
        chatPromptMediaMarker,
        matches(RegExp(r'^<__media_[A-Za-z0-9]{32}__>$')),
      );
    });

    test('is drawn anew for each isolate', () async {
      expect(
        await Isolate.run(() => chatPromptMediaMarker),
        isNot(chatPromptMediaMarker),
      );
    });
  });

  group('shared table adoption', () {
    // The table is for a prompt its caller wrote. A second copy drifts, and
    // a chat template handler that reads it turns message text into media.
    const consumers = <String>[
      'lib/src/backends/llama_cpp/llama_cpp_service.dart',
    ];
    const chatRenderers = <String>[
      'lib/src/core/template/chat_template_engine.dart',
      'lib/src/core/template/chat_template_handler.dart',
      'lib/src/core/template/template_render_context.dart',
      'lib/src/core/template/handlers/function_gemma_handler.dart',
      'lib/src/core/template/handlers/gemma4_handler.dart',
    ];

    for (final path in chatRenderers) {
      test('$path does not rewrite placeholders in a rendered prompt', () {
        expect(
          File(path).readAsStringSync(),
          isNot(contains('normalizeMediaPlaceholders(')),
        );
      });
    }

    for (final path in consumers) {
      test('$path normalizes through the shared helper', () {
        final source = _libraryWithParts(path);
        expect(
          source,
          contains('normalizeMediaPlaceholders('),
          reason: '$path should delegate to the shared helper',
        );
        for (final placeholder in mtmdMediaPlaceholders) {
          for (final literal in ["'$placeholder'", '"$placeholder"']) {
            expect(
              source,
              isNot(contains(literal)),
              reason: '$path should not re-declare $placeholder',
            );
          }
        }
        expect(
          source,
          isNot(contains(mtmdIndexedImagePlaceholder.pattern)),
          reason: '$path should not re-declare the indexed image pattern',
        );
      });
    }
  });
}

String _libraryWithParts(String libraryPath) {
  final library = File(libraryPath).readAsStringSync();
  final parts = RegExp(
    r"^part '([^']+)';",
    multiLine: true,
  ).allMatches(library).map((match) => match.group(1)!);
  return [
    library,
    for (final part in parts)
      File('${File(libraryPath).parent.path}/$part').readAsStringSync(),
  ].join('\n');
}
