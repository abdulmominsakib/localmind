import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

const _defaultPrompt = 'What is 2+2? Answer only with the number.';

Future<void> main(List<String> args) async {
  final modelPath = args.isNotEmpty ? args[0] : _env('LITERT_LM_MODEL');
  if (modelPath == null || modelPath.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/litert_lm_engine_smoke.dart '
      '<model.litertlm> [cpu|gpu|npu|auto] [prompt] [outputTokens] '
      '[contextSize]\n'
      'Optional env: LITERT_LM_ACTIVATION_DATA_TYPE=float32|float16|int16|int8, '
      'LITERT_LM_PREFILL_CHUNK_SIZE=<positive int>, '
      'LITERT_LM_PARALLEL_FILE_SECTION_LOADING=true|false, '
      'LITERT_LM_DISPATCH_LIB_DIR=<dir>',
    );
    exitCode = 64;
    return;
  }

  final backendArg = args.length > 1
      ? args[1]
      : _env('LITERT_LM_BACKEND') ?? 'cpu';
  final prompt = args.length > 2 ? args[2] : _defaultPrompt;
  final outputTokens = args.length > 3 ? int.parse(args[3]) : 16;
  final contextSize = args.length > 4 ? int.parse(args[4]) : 1024;
  final activationDataType = _parseActivationDataType(
    _env('LITERT_LM_ACTIVATION_DATA_TYPE'),
  );
  final prefillChunkSize = _parseOptionalPositiveInt(
    _env('LITERT_LM_PREFILL_CHUNK_SIZE'),
    'LITERT_LM_PREFILL_CHUNK_SIZE',
  );
  final parallelFileSectionLoading = _parseOptionalBool(
    _env('LITERT_LM_PARALLEL_FILE_SECTION_LOADING'),
    'LITERT_LM_PARALLEL_FILE_SECTION_LOADING',
  );
  final dispatchLibDir = _env('LITERT_LM_DISPATCH_LIB_DIR');

  final backend = _parseBackend(backendArg);
  final engine = LlamaEngine(LlamaBackend());
  try {
    final loadSw = Stopwatch()..start();
    await engine.loadModel(
      modelPath,
      modelParams: ModelParams(
        contextSize: contextSize,
        liteRtLmBackend: backend,
        liteRtLmActivationDataType: activationDataType,
        liteRtLmPrefillChunkSize: prefillChunkSize,
        liteRtLmParallelFileSectionLoading: parallelFileSectionLoading,
        liteRtLmDispatchLibDir: dispatchLibDir,
      ),
    );
    loadSw.stop();

    final promptTokens = await engine.tokenize(prompt, addSpecial: false);
    final promptTokensWithSpecial = await engine.tokenize(
      prompt,
      addSpecial: true,
    );
    final promptRoundTrip = await engine.detokenize(promptTokens);
    final buffer = StringBuffer();
    final generateSw = Stopwatch()..start();
    await for (final chunk in engine.generate(
      prompt,
      params: GenerationParams(maxTokens: outputTokens, seed: 1),
    )) {
      buffer.write(chunk);
    }
    generateSw.stop();

    final perf = await engine.getPerformanceContext();
    final metrics = {
      'loadMilliseconds': loadSw.elapsedMilliseconds,
      'wallMilliseconds': generateSw.elapsedMilliseconds,
      'backendName': await engine.getBackendName(),
      'requestedLiteRtLmBackend': backend.name,
      'contextSize': contextSize,
      'liteRtLmActivationDataType': activationDataType?.optionName,
      'liteRtLmPrefillChunkSize': prefillChunkSize,
      'liteRtLmParallelFileSectionLoading': parallelFileSectionLoading,
      'liteRtLmDispatchLibDir': dispatchLibDir,
      'targetDecodeTokens': outputTokens,
      'promptTokenCount': promptTokens.length,
      'promptTokenCountWithSpecial': promptTokensWithSpecial.length,
      'promptRoundTripLength': promptRoundTrip.length,
      'backendInitMilliseconds': perf?.loadMs,
      'promptEvalTokens': perf?.promptEvalTokens,
      'evalTokens': perf?.evalTokens,
      'hitEosBeforeTarget': perf == null
          ? null
          : perf.evalTokens < outputTokens,
      'promptEvalMs': perf?.promptEvalMs,
      'evalMs': perf?.evalMs,
      'prefillTokensPerSecond': perf == null || perf.promptEvalMs <= 0
          ? null
          : perf.promptEvalTokens / (perf.promptEvalMs / 1000.0),
      'decodeTokensPerSecond': perf == null || perf.evalMs <= 0
          ? null
          : perf.evalTokens / (perf.evalMs / 1000.0),
    };

    print('RESULT litert_lm_engine ${jsonEncode(metrics)}');
    print('LAST_TEXT ${jsonEncode(buffer.toString())}');
  } finally {
    await engine.dispose();
  }
}

String? _env(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value;
}

LiteRtLmActivationDataType? _parseActivationDataType(String? value) {
  if (value == null) {
    return null;
  }
  final normalized = value.trim().toLowerCase();
  for (final type in LiteRtLmActivationDataType.values) {
    if (type.optionName == normalized) {
      return type;
    }
  }
  throw ArgumentError.value(
    value,
    'LITERT_LM_ACTIVATION_DATA_TYPE',
    'Expected float32, float16, int16, or int8.',
  );
}

int? _parseOptionalPositiveInt(String? value, String name) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  final parsed = int.parse(trimmed);
  if (parsed <= 0) {
    throw ArgumentError.value(value, name, 'Expected a positive integer.');
  }
  return parsed;
}

bool? _parseOptionalBool(String? value, String name) {
  if (value == null) {
    return null;
  }
  switch (value.trim().toLowerCase()) {
    case 'true':
    case '1':
    case 'yes':
      return true;
    case 'false':
    case '0':
    case 'no':
      return false;
    default:
      throw ArgumentError.value(value, name, 'Expected true or false.');
  }
}

LiteRtLmBackendPreference _parseBackend(String value) {
  switch (value.trim().toLowerCase()) {
    case 'auto':
      return LiteRtLmBackendPreference.auto;
    case 'cpu':
      return LiteRtLmBackendPreference.cpu;
    case 'gpu':
      return LiteRtLmBackendPreference.gpu;
    case 'npu':
      return LiteRtLmBackendPreference.npu;
    default:
      throw ArgumentError.value(
        value,
        'backend',
        'Expected auto, cpu, gpu, or npu.',
      );
  }
}
