@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 20))
/// Manual macOS-only regression harness for reproducing multimodal failures.
///
/// This test intentionally stays tagged `local-only`, so CI will skip it by
/// default. Use it when investigating native regressions on local Apple
/// hardware with real model/mmproj/image inputs.
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const String _defaultModelUrl =
    'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf?download=true';
const String _defaultModelFileName = 'Qwen3.5-0.8B-Q4_K_M.gguf';
const String _defaultMmprojUrl =
    'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/mmproj-F16.gguf?download=true';
const String _defaultMmprojFileName = 'Qwen3.5-0.8B-mmproj-F16.gguf';
const String _defaultPrompt =
    'Describe this image in one short paragraph, including the main subject and any notable details.';
const String _defaultBackends = 'cpu,metal';
const String _fallbackImageBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl7sY4AAAAASUVORK5CYII=';

const String _modelPathEnv = 'LLAMADART_QWEN35_REPRO_MODEL_PATH';
const String _mmprojPathEnv = 'LLAMADART_QWEN35_REPRO_MMPROJ_PATH';
const String _imagePathEnv = 'LLAMADART_QWEN35_REPRO_IMAGE_PATH';
const String _promptEnv = 'LLAMADART_QWEN35_REPRO_PROMPT';
const String _followupTextEnv = 'LLAMADART_QWEN35_REPRO_FOLLOWUP_TEXT';
const String _backendsEnv = 'LLAMADART_QWEN35_REPRO_BACKENDS';
const String _contextSizeEnv = 'LLAMADART_QWEN35_REPRO_CONTEXT_SIZE';
const String _maxTokensEnv = 'LLAMADART_QWEN35_REPRO_MAX_TOKENS';

void main() {
  test(
    'reproduces Qwen3.5 0.8B multimodal macOS crash path',
    () async {
      final File modelFile = await _resolveModelFile();
      final File mmprojFile = await _resolveMmprojFile();
      final File imageFile = await _resolveImageFile();
      final List<GpuBackend> backends = _resolveBackends();
      final int contextSize = _readPositiveIntEnv(_contextSizeEnv) ?? 4096;
      final int maxTokens = _readPositiveIntEnv(_maxTokensEnv) ?? 128;
      final String prompt = _readNonEmptyEnv(_promptEnv) ?? _defaultPrompt;
      final String? followupText = _readNonEmptyEnv(_followupTextEnv);

      stdout.writeln('Qwen multimodal repro assets:');
      stdout.writeln('  model: ${modelFile.path}');
      stdout.writeln('  mmproj: ${mmprojFile.path}');
      stdout.writeln('  image: ${imageFile.path}');
      stdout.writeln(
        '  backends: ${backends.map((GpuBackend b) => b.name).join(', ')}',
      );
      stdout.writeln('  contextSize: $contextSize');
      stdout.writeln('  maxTokens: $maxTokens');

      for (final GpuBackend backend in backends) {
        await _runScenario(
          backend: backend,
          modelFile: modelFile,
          mmprojFile: mmprojFile,
          imageFile: imageFile,
          prompt: prompt,
          followupText: followupText,
          contextSize: contextSize,
          maxTokens: maxTokens,
        );
      }
    },
    skip: Platform.isMacOS
        ? false
        : 'This repro harness is intended for macOS native runs.',
  );
}

Future<void> _runScenario({
  required GpuBackend backend,
  required File modelFile,
  required File mmprojFile,
  required File imageFile,
  required String prompt,
  required String? followupText,
  required int contextSize,
  required int maxTokens,
}) async {
  final LlamaEngine engine = LlamaEngine(LlamaBackend());
  final String backendLabel = backend.name.toUpperCase();
  stdout.writeln('');
  stdout.writeln('=== Qwen multimodal repro: $backendLabel ===');

  try {
    await engine.setDartLogLevel(LlamaLogLevel.info);
    await engine.setNativeLogLevel(LlamaLogLevel.info);

    final int gpuLayers = backend == GpuBackend.cpu
        ? 0
        : ModelParams.maxGpuLayers;
    final ModelParams modelParams = ModelParams(
      preferredBackend: backend,
      gpuLayers: gpuLayers,
      contextSize: contextSize,
    );

    stdout.writeln('Loading model...');
    await engine.loadModel(modelFile.path, modelParams: modelParams);
    final String activeBackend = await engine.getBackendName();
    final int? resolvedGpuLayers = await engine.getResolvedGpuLayers();
    stdout.writeln('  activeBackend: $activeBackend');
    stdout.writeln('  resolvedGpuLayers: ${resolvedGpuLayers ?? 'unknown'}');

    stdout.writeln('Loading multimodal projector...');
    await engine.loadMultimodalProjector(mmprojFile.path);
    final bool supportsVision = await engine.supportsVision;
    stdout.writeln('  supportsVision: $supportsVision');
    expect(
      supportsVision,
      isTrue,
      reason: 'Expected Qwen3.5 0.8B + mmproj to report vision support.',
    );

    final GenerationParams generationParams = GenerationParams(
      maxTokens: maxTokens,
      temp: 0.2,
      topK: 20,
      topP: 0.8,
      penalty: 1.0,
    );

    final ChatSession session = ChatSession(
      engine,
      maxContextTokens: contextSize,
    );

    final String result = await _runSessionTurn(
      session: session,
      parts: <LlamaContentPart>[
        LlamaImageContent(path: imageFile.path),
        LlamaTextContent(prompt),
      ],
      generationParams: generationParams,
      label: 'turn1',
    );
    expect(
      result,
      isNotEmpty,
      reason:
          'Expected multimodal generation to emit some text before exiting.',
    );

    if (followupText != null) {
      final String secondResult = await _runSessionTurn(
        session: session,
        parts: <LlamaContentPart>[LlamaTextContent(followupText)],
        generationParams: generationParams,
        label: 'turn2',
      );
      expect(
        secondResult,
        isNotEmpty,
        reason: 'Expected the follow-up text turn to emit some text.',
      );
    }
  } finally {
    await engine.dispose();
  }
}

Future<String> _runSessionTurn({
  required ChatSession session,
  required List<LlamaContentPart> parts,
  required GenerationParams generationParams,
  required String label,
}) async {
  stdout.writeln('Starting generation for $label...');
  final StringBuffer output = StringBuffer();
  await for (final LlamaCompletionChunk chunk
      in session
          .create(parts, params: generationParams, enableThinking: false)
          .timeout(const Duration(minutes: 5))) {
    final String? delta = chunk.choices.first.delta.content;
    if (delta != null && delta.isNotEmpty) {
      output.write(delta);
    }
  }

  final String result = output.toString().trim();
  stdout.writeln('  $label.outputLength: ${result.length}');
  if (result.isNotEmpty) {
    stdout.writeln('  $label.outputPreview: ${_truncateForLog(result)}');
  }

  final BackendPerfContextData? perf = await session.engine
      .getPerformanceContext();
  if (perf != null) {
    stdout.writeln(
      '  $label.perf: loadMs=${perf.loadMs} promptEvalMs=${perf.promptEvalMs} '
      'evalMs=${perf.evalMs} sampleMs=${perf.sampleMs}',
    );
  }

  return result;
}

Future<File> _resolveModelFile() async {
  final File? configured = _resolveExistingFileFromEnv(
    _modelPathEnv,
    label: 'Qwen model',
  );
  if (configured != null) {
    return configured;
  }
  return _ensureDownloadedFile(
    url: _defaultModelUrl,
    fileName: _defaultModelFileName,
  );
}

Future<File> _resolveMmprojFile() async {
  final File? configured = _resolveExistingFileFromEnv(
    _mmprojPathEnv,
    label: 'Qwen mmproj',
  );
  if (configured != null) {
    return configured;
  }
  return _ensureDownloadedFile(
    url: _defaultMmprojUrl,
    fileName: _defaultMmprojFileName,
  );
}

Future<File> _resolveImageFile() async {
  final File? configured = _resolveExistingFileFromEnv(
    _imagePathEnv,
    label: 'repro image',
  );
  if (configured != null) {
    return configured;
  }

  final File file = File(
    path.join(
      Directory.systemTemp.path,
      'llamadart_qwen35_multimodal_repro_fallback.png',
    ),
  );
  if (!file.existsSync() || file.lengthSync() == 0) {
    await file.writeAsBytes(base64Decode(_fallbackImageBase64), flush: true);
  }
  return file;
}

File? _resolveExistingFileFromEnv(String envKey, {required String label}) {
  final String? raw = _readNonEmptyEnv(envKey);
  if (raw == null) {
    return null;
  }

  final String resolvedPath = path.isAbsolute(raw)
      ? raw
      : path.normalize(path.join(Directory.current.path, raw));
  final File file = File(resolvedPath);
  if (!file.existsSync()) {
    throw StateError('$label file does not exist: $resolvedPath');
  }
  return file;
}

Future<File> _ensureDownloadedFile({
  required String url,
  required String fileName,
}) async {
  final Directory modelsDir = Directory(
    path.join(Directory.current.path, 'models'),
  );
  if (!modelsDir.existsSync()) {
    modelsDir.createSync(recursive: true);
  }

  final File file = File(path.join(modelsDir.path, fileName));
  if (file.existsSync() && file.lengthSync() > 0) {
    return file;
  }

  if (file.existsSync()) {
    file.deleteSync();
  }

  stdout.writeln('Downloading $fileName...');
  final HttpClient client = HttpClient();
  final IOSink sink = file.openWrite();
  try {
    final HttpClientRequest request = await client.getUrl(Uri.parse(url));
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Failed to download $fileName: HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }

    await for (final List<int> chunk in response) {
      sink.add(chunk);
    }
  } catch (_) {
    if (file.existsSync()) {
      file.deleteSync();
    }
    rethrow;
  } finally {
    await sink.close();
    client.close(force: true);
  }

  stdout.writeln('Downloaded $fileName to ${file.path}');
  return file;
}

List<GpuBackend> _resolveBackends() {
  final String raw = _readNonEmptyEnv(_backendsEnv) ?? _defaultBackends;
  final List<GpuBackend> backends = <GpuBackend>[];

  for (final String token in raw.split(',')) {
    final String normalized = token.trim().toLowerCase();
    if (normalized.isEmpty) {
      continue;
    }

    final GpuBackend backend = switch (normalized) {
      'cpu' => GpuBackend.cpu,
      'metal' => GpuBackend.metal,
      'auto' => GpuBackend.auto,
      _ => throw StateError(
        'Unsupported backend "$normalized" in $_backendsEnv. '
        'Use a comma-separated subset of: cpu, metal, auto.',
      ),
    };

    if (!backends.contains(backend)) {
      backends.add(backend);
    }
  }

  if (backends.isEmpty) {
    throw StateError('No usable backends were configured for the repro test.');
  }
  return backends;
}

String? _readNonEmptyEnv(String key) {
  final String? value = Platform.environment[key]?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

int? _readPositiveIntEnv(String key) {
  final String? raw = _readNonEmptyEnv(key);
  if (raw == null) {
    return null;
  }
  final int? value = int.tryParse(raw);
  if (value == null || value <= 0) {
    throw StateError('Environment variable $key must be a positive integer.');
  }
  return value;
}

String _truncateForLog(String value, {int maxChars = 240}) {
  if (value.length <= maxChars) {
    return value;
  }
  return '${value.substring(0, maxChars)}...';
}
