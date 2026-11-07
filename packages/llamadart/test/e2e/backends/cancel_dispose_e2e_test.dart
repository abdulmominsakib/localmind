@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Real-native regression coverage for the cross-isolate cancel/dispose
/// lifecycle fixes (cancel-token use-after-free and dispose abandoning an
/// in-flight generation). These exercise the actual worker isolate + FFI path,
/// so they are local-only and require a small GGUF in `models/`.
void main() {
  final candidates = <String>[
    'functiongemma-270m-it-Q4_K_M.gguf',
    'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    'llama3.2-1b.gguf',
  ];

  String? resolveModel() {
    final modelsDir = Directory(path.join(Directory.current.path, 'models'));
    for (final name in candidates) {
      final file = File(path.join(modelsDir.path, name));
      if (file.existsSync()) {
        return file.path;
      }
    }
    return null;
  }

  group('cancel/dispose lifecycle (native)', () {
    late String modelPath;

    setUpAll(() {
      final resolved = resolveModel();
      if (resolved == null) {
        markTestSkipped(
          'No local GGUF found in models/ for cancel/dispose e2e',
        );
      }
      modelPath = resolved ?? '';
    });

    Future<LlamaEngine> loadEngine() async {
      final engine = LlamaEngine(LlamaBackend());
      await engine.loadModel(
        modelPath,
        modelParams: const ModelParams(
          contextSize: 512,
          gpuLayers: 0,
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
        ),
      );
      return engine;
    }

    test('cancel mid-stream then regenerate does not crash', () async {
      if (modelPath.isEmpty) {
        return;
      }
      final engine = await loadEngine();
      try {
        // Start a generation and cancel it after the first emitted chunk. The
        // cancel token must survive until the worker stops reading it; a UAF or
        // double free would crash the VM here.
        final stream = engine.create([
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Write a long story about a robot.',
          ),
        ], params: const GenerationParams(maxTokens: 256));

        var received = 0;
        final sub = stream.listen((_) => received += 1);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        engine.cancelGeneration();
        await sub.cancel();

        // A second generation on the same engine must still succeed.
        final buffer = StringBuffer();
        await for (final chunk in engine.create([
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Say hello.',
          ),
        ], params: const GenerationParams(maxTokens: 16))) {
          if (chunk.choices.isNotEmpty) {
            buffer.write(chunk.choices.first.delta.content ?? '');
          }
        }
        expect(buffer.toString(), isNotEmpty);
        expect(received, greaterThanOrEqualTo(0));
      } finally {
        await engine.dispose();
      }
    });

    test('dispose while a generation is in flight completes cleanly', () async {
      if (modelPath.isEmpty) {
        return;
      }
      final engine = await loadEngine();
      var disposed = false;
      try {
        final stream = engine.create([
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Write a very long story about the ocean.',
          ),
        ], params: const GenerationParams(maxTokens: 512));

        final sub = stream.listen((_) {}, onError: (_) {});
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // Dispose mid-generation. The worker must let the in-flight generation
        // emit its terminal response (so the token is freed) before tearing the
        // isolate down. This should complete promptly without hanging.
        await engine.dispose().timeout(const Duration(seconds: 15));
        disposed = true;
        await sub.cancel();
      } finally {
        if (!disposed) {
          await engine.dispose();
        }
      }
      expect(disposed, isTrue);
    });
  });
}
