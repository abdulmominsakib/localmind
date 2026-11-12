@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  final models = Platform.environment['LLAMADART_TEST_MODELS_DIR'];

  test(
    'Qwen2.5 Metal capabilities match the native reasoning-budget export',
    () async {
      final file = File(
        path.join(models ?? 'models', 'qwen2.5-0.5b-instruct-q4_k_m.gguf'),
      );
      if (!Platform.isMacOS || !file.existsSync()) {
        markTestSkipped('Requires macOS and local Qwen2.5-0.5B weights');
        return;
      }
      final backend = NativeLlamaBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      expect((await backend.generationCapabilities()).thinkingBudget, isFalse);
      await engine.loadModel(
        file.path,
        modelParams: const ModelParams(
          preferredBackend: GpuBackend.metal,
          contextSize: 512,
        ),
      );
      expect(await engine.getBackendName(), 'Metal');
      final wrapper = DynamicLibrary.open(
        path.absolute('.dart_tool', 'lib', 'libllamadart.dylib'),
      );
      final hasBudget = wrapper.providesSymbol(
        'llama_dart_sampler_init_reasoning_budget',
      );
      final caps = await engine.capabilities;
      expect(caps.supportsThinkingBudget, hasBudget);
      expect(
        caps.speculativeDecodingStrategies,
        contains(SpeculativeDecodingStrategy.mtp),
      );
      await expectLater(
        engine
            .generate(
              'Hello',
              params: const GenerationParams(
                speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
                  strategies: [SpeculativeDecodingStrategy.draftEagle3],
                ),
              ),
            )
            .drain<void>(),
        throwsA(isA<LlamaArgumentException>()),
      );
      final output = await engine
          .generate(
            'The capital of France is',
            params: const GenerationParams(
              maxTokens: 8,
              temp: 0,
              topK: 1,
              topP: 1,
              penalty: 1,
            ),
          )
          .join();
      expect(output, isNotEmpty);
      final withDraft = await engine
          .generate(
            'The capital of France is',
            params: GenerationParams(
              maxTokens: 8,
              temp: 0,
              topK: 1,
              topP: 1,
              penalty: 1,
              speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
                draftModel: ModelSource.path(file.path),
                draftTokenMax: 1,
              ),
            ),
          )
          .join();
      expect(withDraft, isNotEmpty);
      print(
        'Qwen2.5 Metal: supportsThinkingBudget=$hasBudget; typed missing draft; ordinary and external-draft generation passed',
      );
    },
  );

  test(
    'Gemma 4 Metal accepts external MTP without loading an in-file head',
    () async {
      final target = File(
        path.join(models ?? 'models', 'gemma-4-E2B-it-qat-UD-Q2_K_XL.gguf'),
      );
      final draft = File(
        path.join(models ?? 'models', 'mtp-gemma-4-E2B-it.gguf'),
      );
      if (!Platform.isMacOS || !target.existsSync() || !draft.existsSync()) {
        markTestSkipped(
          'Requires macOS, Gemma 4 E2B and its external MTP draft weights',
        );
        return;
      }
      final engine = LlamaEngine(NativeLlamaBackend());
      addTearDown(engine.dispose);
      await engine.loadModel(
        target.path,
        modelParams: const ModelParams(
          preferredBackend: GpuBackend.metal,
          contextSize: 1024,
          loadMtp: false,
        ),
      );
      expect(await engine.getBackendName(), 'Metal');
      expect(
        (await engine.capabilities).speculativeDecodingStrategies,
        contains(SpeculativeDecodingStrategy.mtp),
      );
      final output = await engine
          .generate(
            'The capital of France is',
            params: GenerationParams(
              maxTokens: 8,
              temp: 0,
              topK: 1,
              topP: 1,
              penalty: 1,
              speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(
                draftModel: ModelSource.path(draft.path),
                draftTokenMax: 1,
              ),
            ),
          )
          .join();
      expect(output, isNotEmpty);
      print(
        'Gemma 4 E2B Metal: external MTP generation passed with loadMtp=false',
      );
    },
  );
}
