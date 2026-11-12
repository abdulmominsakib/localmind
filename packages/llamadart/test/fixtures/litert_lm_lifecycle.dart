// Real-model subprocess fixture. The parent enforces the process deadline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> args) async {
  final model = args[0];
  final backend = LiteRtLmBackendPreference.values.byName(args[1]);
  final mode = args[2];
  final engine = LlamaEngine(LlamaBackend());
  final params = ModelParams(
    contextSize: 1024,
    numberOfThreads: backend == LiteRtLmBackendPreference.cpu ? 2 : 0,
    liteRtLmBackend: backend,
  );
  void event(String stage, [Map<String, Object?> values = const {}]) {
    stdout.writeln(jsonEncode({'stage': stage, ...values}));
  }

  Future<void> generate(int cycle) async {
    final watch = Stopwatch()..start();
    final content = StringBuffer();
    await for (final chunk
        in engine
            .create(
              [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'Reply with one short sentence saying hello.',
                ),
              ],
              params: const GenerationParams(maxTokens: 32, temp: 0, seed: 1),
              enableThinking: false,
            )
            .timeout(const Duration(seconds: 60))) {
      for (final choice in chunk.choices) {
        content.write(choice.delta.content ?? '');
      }
    }
    if (!RegExp(
      r'\bhello\b',
      caseSensitive: false,
    ).hasMatch(content.toString())) {
      throw StateError('Recovery did not produce the hello fixture: $content');
    }
    event('generation', {
      'cycle': cycle,
      'elapsed_ms': watch.elapsedMilliseconds,
      'content': content.toString(),
    });
  }

  try {
    await LlamaLogging.configure(level: LlamaLogLevel.info);
    await engine.loadModel(model, modelParams: params);
    event('loaded', {
      'requested_backend': backend.name,
      'accelerator_execution_verified': false,
    });
    if (mode == 'timeout') {
      final pending = engine.tokenize('hello', addSpecial: false);
      try {
        await pending.timeout(const Duration(milliseconds: 1));
        throw StateError('Expected initialization timeout was not reached');
      } on TimeoutException {
        event('operation_timeout');
      }
      var cleanupFailed = false;
      try {
        await engine.dispose();
        event('cleanup_pass');
      } on LlamaException catch (error) {
        cleanupFailed = true;
        event('cleanup_error', {
          'type': error.runtimeType.toString(),
          'message': error.message,
        });
      }
      try {
        await pending.timeout(const Duration(seconds: 1));
        if (cleanupFailed) {
          throw StateError('Abandoned request unexpectedly succeeded');
        }
        event('pending_completed');
      } on LlamaException catch (error) {
        event('pending_failed', {'type': error.runtimeType.toString()});
      }
      if (cleanupFailed) {
        exitCode = 1;
      }
      event('run_end');
      return;
    }
    await generate(0).timeout(const Duration(seconds: 60));
    await engine.unloadModel();
    try {
      await engine.generate('hello').drain<void>();
      throw StateError('Unloaded engine accepted generation');
    } on LlamaContextException {
      event('unloaded_rejected');
    }
    await engine.loadModel(model, modelParams: params);
    await generate(1).timeout(const Duration(seconds: 60));
    await engine.unloadModel();
    try {
      final missingModel = '$model.missing.litertlm';
      await engine.loadModel(missingModel, modelParams: params);
      throw StateError('Missing model unexpectedly loaded');
    } on LlamaModelException {
      event('missing_model_rejected');
    }
    await engine.unloadModel();
    await engine.loadModel(model, modelParams: params);
    await generate(2).timeout(const Duration(seconds: 60));
    await engine.dispose();
    event('cleanup_pass');
    event('run_end');
  } catch (error) {
    event('failure', {
      'type': error.runtimeType.toString(),
      'message': '$error',
    });
    exitCode = 1;
    try {
      await engine.dispose().timeout(const Duration(seconds: 10));
    } catch (cleanupError) {
      event('cleanup_error', {'message': '$cleanupError'});
    }
  }
}
