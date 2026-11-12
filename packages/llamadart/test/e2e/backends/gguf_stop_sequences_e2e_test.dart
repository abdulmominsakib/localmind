@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('public GGUF chat suppresses caller marker and recovers', () async {
    final model = Platform.environment['GGUF_STOP_MODEL'];
    expect(model, isNotNull, reason: 'Set GGUF_STOP_MODEL to a chat GGUF');
    final backendName = Platform.environment['GGUF_STOP_BACKEND'] ?? 'cpu';
    final backend = GpuBackend.values.byName(backendName);
    final engine = LlamaEngine(LlamaBackend());
    addTearDown(engine.dispose);
    await LlamaLogging.configure(nativeLevel: LlamaLogLevel.info);
    final checksum = await sha256.bind(File(model!).openRead()).first;
    print(
      jsonEncode({
        'model_sha256': '$checksum',
        'backend': backendName,
        'dart': Platform.version,
        'os': Platform.operatingSystemVersion,
      }),
    );
    await engine.loadModel(
      model,
      modelParams: ModelParams(
        contextSize: 1024,
        gpuLayers: backend == GpuBackend.cpu ? 0 : 99,
        preferredBackend: backend,
        numberOfThreads: 4,
        numberOfThreadsBatch: 4,
      ),
    );
    Future<String> run(List<String> stops, int batching) async {
      final text = StringBuffer();
      await for (final chunk in engine.create(
        [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Reply with exactly: alpha cedar17 omega',
          ),
        ],
        enableThinking: false,
        params: GenerationParams(
          temp: 0,
          seed: 1,
          maxTokens: 32,
          stopSequences: stops,
          streamBatchTokenThreshold: batching,
          streamBatchByteThreshold: batching == 1 ? 1 : 512,
        ),
      )) {
        for (final choice in chunk.choices) {
          text.write(choice.delta.content ?? '');
        }
      }
      return text.toString();
    }

    final control = await run([], 8);
    print(jsonEncode({'control': control}));
    expect(control, 'alpha cedar17 omega');
    for (final batching in [1, 8]) {
      final stopped = await run(['cedar17'], batching);
      print(jsonEncode({'batch_tokens': batching, 'stopped': stopped}));
      expect(stopped, 'alpha ');
    }
    expect(await run([], 8), control);
  });
}
