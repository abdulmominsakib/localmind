import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart' as llama;

/// Opt-in end-to-end smoke test proving the bundled llama.cpp runtime (v0.9.0)
/// runs LFM3-series GGUF models, which require upstream llama.cpp b11960+.
///
/// Run with a local LFM3 GGUF file, e.g.:
///   LFM3_GGUF_PATH=I:/ai/models/.../LFM3-1.7B-Q4_K_M.gguf flutter test \
///     test/features/on_device/lfm3_smoke_test.dart
///
/// On Windows host runs (`flutter test`), the Dart VM may not resolve the
/// hook-provisioned backend modules via native-asset URIs; point
/// LLAMADART_NATIVE_LIB_DIR at the hook output directory containing
/// `llamadart.dll`/`ggml-cpu.dll`, e.g.
///   .dart_tool/hooks_runner/shared/llamadart/build/`<build-hash>`/llamadart_bin
/// Device builds (Android/iOS) bundle the assets through the normal Flutter
/// build and need no override.
///
/// Set LFM3_VL_MMPROJ_PATH (and optionally LFM3_VL_GGUF_PATH) to also exercise
/// the multimodal projector path of the LFM3 series, e.g. LFM3-VL-2B.
///
/// Without the environment variables the tests exit immediately so regular
/// CI stays hermetic.
void main() {
  test(
    'LFM3 GGUF loads and generates with the bundled llama.cpp runtime',
    () async {
      final modelPath = Platform.environment['LFM3_GGUF_PATH'];
      if (modelPath == null || modelPath.isEmpty) {
        // ignore: avoid_print
        print('LFM3_GGUF_PATH not set; skipping LFM3 smoke test.');
        return;
      }
      final modelFile = File(modelPath);
      if (!await modelFile.exists()) {
        // ignore: avoid_print
        print('LFM3_GGUF_PATH points at a missing file; skipping.');
        return;
      }

      // CPU-only load keeps the smoke test independent of GPU availability.
      final engine = llama.LlamaEngine(llama.LlamaBackend());
      try {
        await engine.setModel(
          llama.LlamaModel(llama.ModelSource.path(modelPath)),
          params: const llama.ModelParams(contextSize: 2048, gpuLayers: 0),
        );
        final session = llama.ChatSession(engine, maxContextTokens: 2048);
        final reply = StringBuffer();
        await for (final chunk in session.create(
          const [llama.LlamaTextContent('Reply with exactly: LFM3 OK')],
          enableThinking: false,
          params: const llama.GenerationParams(maxTokens: 48, temp: 0.0),
        )) {
          for (final choice in chunk.choices) {
            final delta = choice.delta.content;
            if (delta != null) reply.write(delta);
          }
        }
        // ignore: avoid_print
        print('LFM3 smoke reply: ${reply.toString().trim()}');
        expect(reply.toString().trim(), isNotEmpty);
      } finally {
        await engine.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'LFM3-VL loads with its mmproj projector and keeps vision support',
    () async {
      final projectorPath = Platform.environment['LFM3_VL_MMPROJ_PATH'];
      if (projectorPath == null || projectorPath.isEmpty) {
        // ignore: avoid_print
        print('LFM3_VL_MMPROJ_PATH not set; skipping LFM3-VL smoke test.');
        return;
      }
      final modelPath =
          Platform.environment['LFM3_VL_GGUF_PATH'] ?? projectorPath;
      final modelFile = File(modelPath);
      final projectorFile = File(projectorPath);
      if (!await modelFile.exists() || !await projectorFile.exists()) {
        // ignore: avoid_print
        print('LFM3-VL model or projector file missing; skipping.');
        return;
      }

      final engine = llama.LlamaEngine(llama.LlamaBackend());
      try {
        await engine.setModel(
          llama.LlamaModel(
            llama.ModelSource.path(modelPath),
            projector: llama.ModelSource.path(projectorPath),
          ),
          params: const llama.ModelParams(contextSize: 2048, gpuLayers: 0),
        );
        final hasVision = await engine.supportsVision;
        // ignore: avoid_print
        print('LFM3-VL projector loaded (supportsVision=$hasVision)');
        expect(hasVision, isTrue);
      } finally {
        await engine.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
