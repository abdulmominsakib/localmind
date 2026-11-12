@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  final modelsDir = Platform.environment['LLAMADART_TEST_MODELS_DIR'];
  final skip = !Platform.isMacOS
      ? 'Requires macOS Metal.'
      : modelsDir == null
      ? 'Set LLAMADART_TEST_MODELS_DIR to the local GGUF directory.'
      : null;

  for (final mainGpu in [-1, 0]) {
    test(
      'auto single-device reporting with mainGpu $mainGpu',
      skip: skip,
      () async {
        await LlamaLogging.configure(nativeLevel: LlamaLogLevel.info);
        final engine = await LlamaEngine.load(
          LlamaModel(
            ModelSource.path('$modelsDir/qwen2.5-0.5b-instruct-q4_k_m.gguf'),
          ),
          params: ModelParams(
            contextSize: 256,
            splitMode: ModelSplitMode.none,
            mainGpu: mainGpu,
            numberOfThreads: 2,
            numberOfThreadsBatch: 2,
          ),
        );
        addTearDown(engine.dispose);

        final backendName = await engine.getBackendName();
        final capabilities = await engine.capabilities;
        final layers = await engine.getResolvedGpuLayers();
        print(
          'mainGpu=$mainGpu backend=$backendName '
          'capabilities=${capabilities.backendName} layers=$layers',
        );
        final expectedBackend = mainGpu < 0 ? 'CPU' : 'Metal';
        expect(backendName, expectedBackend);
        expect(capabilities.backendName, expectedBackend);
        expect(layers, mainGpu < 0 ? 0 : ModelParams.maxGpuLayers);

        final reply = await engine.complete(const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Say hello.',
          ),
        ], params: const GenerationParams(maxTokens: 8, temp: 0));
        expect(reply.text, isNotEmpty);
      },
    );
  }
}
