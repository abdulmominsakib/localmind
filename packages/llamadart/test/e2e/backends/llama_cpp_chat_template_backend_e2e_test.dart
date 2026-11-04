@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const String _modelPathEnv = 'LLAMADART_LLAMA_CPP_TEMPLATE_MODEL_PATH';
const String _defaultModelFileName = 'Qwen3.5-0.8B-Q4_K_M.gguf';

void main() {
  group('llama.cpp direct chat-template backend', () {
    late String modelPath;

    setUpAll(() {
      final resolved = _resolveModelPath();
      if (resolved == null) {
        markTestSkipped(
          'Set $_modelPathEnv or place $_defaultModelFileName in the default '
          'llamadart cache to run llama.cpp chat-template backend E2E.',
        );
      }
      modelPath = resolved ?? '';
    });

    test(
      'renders default, custom, and unsupported multimodal templates',
      () async {
        if (modelPath.isEmpty) {
          return;
        }

        final backend = LlamaBackend();
        int? modelHandle;
        try {
          await backend.setLogLevel(LlamaLogLevel.warn);
          modelHandle = await backend.modelLoad(
            modelPath,
            const ModelParams(
              contextSize: 512,
              preferredBackend: GpuBackend.cpu,
              gpuLayers: 0,
              numberOfThreads: 2,
              numberOfThreadsBatch: 2,
            ),
          );

          final rendered = await backend.applyChatTemplate(modelHandle, const [
            {'role': 'user', 'content': 'Say hello.'},
          ]);
          expect(rendered, contains('Say hello.'));
          expect(rendered, isNot(equals('Say hello.')));

          final custom = await backend.applyChatTemplate(
            modelHandle,
            const [
              {'role': 'user', 'content': 'Say hello.'},
            ],
            customTemplate: '{{ "CUSTOM:" ~ messages[0]["content"] }}',
          );
          expect(custom, contains('CUSTOM:Say hello.'));

          await backend.modelFree(modelHandle);
          modelHandle = null;
          modelHandle = await backend.modelLoad(
            modelPath,
            const ModelParams(
              contextSize: 512,
              preferredBackend: GpuBackend.cpu,
              gpuLayers: 0,
              numberOfThreads: 2,
              numberOfThreadsBatch: 2,
              chatTemplate: '{{ "MODELPARAM:" ~ messages[0]["content"] }}',
            ),
          );

          final modelParamRendered = await backend.applyChatTemplate(
            modelHandle,
            const [
              {'role': 'user', 'content': 'Use the configured template.'},
            ],
          );
          expect(
            modelParamRendered,
            contains('MODELPARAM:Use the configured template.'),
          );

          final perCallCustom = await backend.applyChatTemplate(
            modelHandle,
            const [
              {'role': 'user', 'content': 'Use the per-call template.'},
            ],
            customTemplate: '{{ "PERCALL:" ~ messages[0]["content"] }}',
          );
          expect(perCallCustom, contains('PERCALL:Use the per-call template.'));
          expect(perCallCustom, isNot(contains('MODELPARAM:')));

          await backend.modelFree(modelHandle);
          modelHandle = null;
          modelHandle = await backend.modelLoad(
            modelPath,
            const ModelParams(
              contextSize: 512,
              preferredBackend: GpuBackend.cpu,
              gpuLayers: 0,
              numberOfThreads: 2,
              numberOfThreadsBatch: 2,
              chatTemplate: '',
            ),
          );

          final emptyTemplateRendered = await backend.applyChatTemplate(
            modelHandle,
            const [
              {'role': 'user', 'content': 'Say hello.'},
            ],
          );
          expect(emptyTemplateRendered, rendered);

          await expectLater(
            backend.applyChatTemplate(modelHandle, const [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'file:///tmp/image.png'},
                  },
                  {'type': 'text', 'text': 'Describe it.'},
                ],
              },
            ]),
            throwsA(
              isA<Exception>().having(
                (error) => error.toString(),
                'message',
                contains('multimodal chat-template content'),
              ),
            ),
          );
        } finally {
          if (modelHandle != null) {
            await backend.modelFree(modelHandle);
          }
          await backend.dispose();
        }
      },
    );
  });
}

String? _resolveModelPath() {
  final explicit = Platform.environment[_modelPathEnv];
  if (explicit != null && explicit.isNotEmpty) {
    if (File(explicit).existsSync()) {
      return explicit;
    }
    throw StateError('$_modelPathEnv does not exist: $explicit');
  }

  final candidates = <String>[
    path.join(Directory.current.path, 'models', _defaultModelFileName),
    if (Platform.environment['HOME'] case final home?)
      path.join(
        home,
        'Library',
        'Caches',
        'llamadart',
        'models',
        _defaultModelFileName,
      ),
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}
