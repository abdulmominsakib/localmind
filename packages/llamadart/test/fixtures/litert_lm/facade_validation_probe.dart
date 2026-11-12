import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';

void _namedError(String name, void Function() action) {
  try {
    action();
  } on ArgumentError catch (error) {
    if (error.name == name) return;
    rethrow;
  }
  throw StateError('$name did not throw synchronously.');
}

Future<void> _namedFutureError(
  String name,
  Future<void> Function() action,
) async {
  // Creation must preserve the asynchronous error contract.
  final result = action();
  try {
    await result;
  } on ArgumentError catch (error) {
    if (error.name == name) return;
    rethrow;
  }
  throw StateError('$name did not fail its Future.');
}

Future<void> main(List<String> arguments) async {
  final mode = arguments[0];
  final client = mode == 'legacy-disabled'
      ? createLiteRtLmSelectedRuntimeClient(
          libraryPath: arguments[1],
          allowV1: false,
        )
      : LiteRtLmRuntimeClient(
          libraryPath: mode == 'default' ? null : arguments[1],
        );
  try {
    for (final entry in <String, Future<void> Function()>{
      'maxTokens': () => client.initialize(modelPath: 'fixture', maxTokens: 0),
      'outputTokens': () =>
          client.initialize(modelPath: 'fixture', outputTokens: 0),
      'prefillTokens': () =>
          client.initialize(modelPath: 'fixture', prefillTokens: -1),
      'maxNumImages': () =>
          client.initialize(modelPath: 'fixture', maxNumImages: 0),
      'prefillChunkSize': () =>
          client.initialize(modelPath: 'fixture', prefillChunkSize: 0),
      'dispatchLibDir': () =>
          client.initialize(modelPath: 'fixture', dispatchLibDir: '  '),
      'numberOfThreads': () =>
          client.initialize(modelPath: 'fixture', numberOfThreads: 0),
      'backend': () => client.initialize(modelPath: 'fixture', backend: 'dsp'),
      'visionBackend': () =>
          client.initialize(modelPath: 'fixture', visionBackend: 'dsp'),
      'audioBackend': () =>
          client.initialize(modelPath: 'fixture', audioBackend: 'dsp'),
    }.entries) {
      await _namedFutureError(entry.key, entry.value);
    }
    for (final entry in <String, void Function()>{
      'visualTokenBudget': () =>
          client.generateMessageJson('{}', visualTokenBudget: 0),
      'maxOutputTokens': () =>
          client.generateMessageJson('{}', maxOutputTokens: 0),
      'repetitionPenalty': () =>
          client.generateMessageJson('{}', repetitionPenalty: double.nan),
      'presencePenalty': () =>
          client.generateMessageJson('{}', presencePenalty: double.infinity),
      'thinkingTokenBudget': () =>
          client.generateMessageJson('{}', thinkingTokenBudget: 0),
    }.entries) {
      _namedError(entry.key, entry.value);
    }
    _namedError(
      'maxOutputTokens',
      () => client.generate('hello', maxOutputTokens: 0),
    );
    _namedError(
      'repetitionPenalty',
      () => client.generate('hello', repetitionPenalty: 0.5),
    );
    _namedError(
      'presencePenalty',
      () => client.generate('hello', presencePenalty: double.nan),
    );
    await _namedFutureError(
      'warmupRuns',
      () => client.run(prompt: 'hello', warmupRuns: -1),
    );
    await _namedFutureError(
      'measuredRuns',
      () => client.run(prompt: 'hello', measuredRuns: 0),
    );
    stderr.writeln('FACADE_INVALID_COMPLETE');
    await stderr.flush();
    await client.initialize(
      modelPath: 'fixture',
      backend: 'cpu',
      speculativeDecoding: false,
    );
    stderr.writeln('FACADE_VALID_COMPLETE');
    await stderr.flush();
  } finally {
    client.dispose();
  }
}
