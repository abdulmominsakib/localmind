@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_errors.dart';
import 'package:test/test.dart';

void main() {
  test('grammar failures preserve the typed category without loose matching', () {
    for (final (message, matcher) in <(String, Matcher)>[
      (
        'The loaded WebGPU core does not support CompletionOptions.penaltyPromptTokensWithGrammar.',
        isA<LlamaUnsupportedException>(),
      ),
      (
        'The loaded WebGPU core does not support CompletionOptions.grammarLazy.',
        isA<LlamaUnsupportedException>(),
      ),
      (
        'The loaded WebGPU core does not support CompletionOptions.grammarRoot.',
        isA<LlamaUnsupportedException>(),
      ),
      (
        'The loaded WebGPU core does not support CompletionOptions.grammarLazy or CompletionOptions.grammarRoot.',
        isA<LlamaUnsupportedException>(),
      ),
      (
        'The loaded WebGPU core does not support CompletionOptions.minP or CompletionOptions.grammarLazy or CompletionOptions.grammarRoot.',
        isA<LlamaUnsupportedException>(),
      ),
      (
        'Failed to start generation: Failed to initialize sampler chain (invalid grammar)',
        isA<LlamaInferenceException>(),
      ),
      (
        'Generation step failed: The lazy grammar rejected the text that triggered it',
        isA<LlamaInferenceException>(),
      ),
    ]) {
      final error = JSObject()
        ..setProperty('name'.toJS, 'Error'.toJS)
        ..setProperty('message'.toJS, message.toJS);
      expect(webGpuBridgeRequestError(error), matcher);
      error.setProperty('message'.toJS, 'Network failed: $message'.toJS);
      expect(webGpuBridgeRequestError(error), isNull);
    }
  });

  test('preserves typed unsupported errors', () {
    final error = LlamaUnsupportedException('unsupported model');
    expect(webGpuBridgeRequestError(error), same(error));
  });

  test('leaves unknown codes, names and non-JS errors to the operation', () {
    for (final error in <Object>[
      StateError('invalid argument'),
      'TypeError: invalid argument',
      JSObject()..setProperty('code'.toJS, 'INVALID_EMBEDDING_INPUT'.toJS),
      JSObject()..setProperty('name'.toJS, 42.toJS),
    ]) {
      expect(webGpuBridgeRequestError(error), isNull);
    }
  });

  test('does not infer arguments from JS runtime names or unknown options', () {
    for (final name in ['RangeError', 'TypeError', 'Error']) {
      for (final message in [
        'Failed to fetch',
        'Maximum call stack size exceeded',
        'Array buffer allocation failed',
        "Cannot read properties of null (reading 'ccall')",
        'CompletionOptions.futureOption must be a finite number; got NaN.',
        'CompletionOptions.speculativeDecoding.futureOption must be an integer from 0 to 1;',
        'LoRA adapter runtime failed',
        'Next-token candidates allocation failed',
      ]) {
        final error = JSObject()
          ..setProperty('name'.toJS, name.toJS)
          ..setProperty('message'.toJS, message.toJS);
        expect(
          webGpuBridgeRequestError(error),
          isNull,
          reason: '$name: $message',
        );
      }
    }
  });

  test('redacts argument diagnostics', () {
    final error = JSObject()
      ..setProperty('name'.toJS, 'RangeError'.toJS)
      ..setProperty(
        'message'.toJS,
        'CompletionOptions.minP must be a finite number; got https://example.com/model?token=secret'
            .toJS,
      );
    expect(webGpuBridgeRequestError(error)!.message, isNot(contains('secret')));
  });

  test('redacts secrets echoed separately from the source URL', () {
    const source = 'private-adapter.gguf?token=source-secret';
    final error = JSObject()
      ..setProperty('name'.toJS, 'TypeError'.toJS)
      ..setProperty(
        'message'.toJS,
        'LoRA adapter scale must be a finite number, got source-secret.'.toJS,
      );
    final classified = webGpuBridgeRequestError(error, sourceUrls: [source]);
    expect(classified, isA<LlamaArgumentException>());
    expect(classified!.message, isNot(contains('source-secret')));
    expect(
      classified.message,
      startsWith('LoRA adapter scale must be a finite number'),
    );
  });

  test('direct and worker errors recognize pinned validators only', () {
    for (final message in <String>[
      'CompletionOptions.minP must be a finite number from 0 to 1; got 2.',
      'CompletionOptions.presencePenalty must be a finite number; got NaN.',
      'CompletionOptions.grammar contains U+0000, which the core cannot read.',
      'CompletionOptions.grammarRoot contains U+0000, which the core cannot read.',
      'CompletionOptions.grammarRoot must be a non-empty string.',
      'CompletionOptions.grammarLazy must be a boolean; got 1.',
      'CompletionOptions.grammarLazy needs a non-empty CompletionOptions.grammar.',
      'CompletionOptions.grammarRoot needs a non-empty CompletionOptions.grammar.',
      'CompletionOptions.grammarLazy needs at least one CompletionOptions.grammarTriggers entry.',
      'CompletionOptions.grammarTriggers must be an array.',
      'CompletionOptions.grammarTriggers[0] must be an object.',
      'CompletionOptions.grammarTriggers[0].type must be one of token, word, pattern, pattern-full; got 9.',
      'CompletionOptions.grammarTriggers[0].token must be an integer from 0 to 2147483647; got -1.',
      'CompletionOptions.grammarTriggers[0].value must be a non-empty string.',
      'CompletionOptions.grammarTriggers[0].value contains U+0000, which the core cannot read.',
      'CompletionOptions.thinkingBudget must be an object.',
      'CompletionOptions.thinkingBudget.startTag must be a non-empty string.',
      'CompletionOptions.thinkingBudget.endTag must be a non-empty string.',
      'CompletionOptions.thinkingBudget.forcedMessage must be a string.',
      'CompletionOptions.thinkingBudget.maxTokens must be an integer from 0 to 2147483647; got -1.',
      'CompletionOptions.speculativeDecoding must be an object.',
      'CompletionOptions.speculativeDecoding.strategies must be a non-empty array.',
      'CompletionOptions.speculativeDecoding.strategies has an unknown strategy "bogus"; expected one of draft-simple.',
      'CompletionOptions.speculativeDecoding.draftTokenMax must be an integer from 0 to 2147483647; got -1.',
      'CompletionOptions.speculativeDecoding.draftTokenMin must be an integer from 0 to 2147483647; got -1.',
      'CompletionOptions.speculativeDecoding.ngramSizeN must be an integer from 1 to 65535; got -1.',
      'CompletionOptions.speculativeDecoding.ngramSizeM must be an integer from 1 to 65535; got -1.',
      'CompletionOptions.speculativeDecoding.ngramMinHits must be an integer from 1 to 65535; got -1.',
      'CompletionOptions.speculativeDecoding.ngramMatch must be an integer from 1 to 65535; got -1.',
      'CompletionOptions.speculativeDecoding.ngramTokenMin must be an integer from 0 to 2147483647; got -1.',
      'CompletionOptions.speculativeDecoding.ngramTokenMax must be an integer from 0 to 2147483647; got -1.',
      'CompletionOptions.speculativeDecoding.ngramTokenMin (9) must not exceed ngramTokenMax (3).',
      'CompletionOptions.speculativeDecoding.draftTokenMin (9) must not exceed the draft token maximum (3).',
      'CompletionOptions.speculativeDecoding.minProbability must be a number from 0 to 1; got 2.',
      'CompletionOptions.speculativeDecoding.draftSplitProbability must be a number from 0 to 1; got 2.',
      'CompletionOptions.speculativeDecoding.ngramCacheStatic is empty.',
      'CompletionOptions.speculativeDecoding.ngramCacheStatic must be a URL string, an ArrayBuffer or a typed array.',
      'CompletionOptions.speculativeDecoding.ngramCacheDynamic is empty.',
      'CompletionOptions.speculativeDecoding.ngramCacheDynamic must be a URL string, an ArrayBuffer or a typed array.',
      'LoRA adapter handle must be a positive integer, got -1.',
      'LoRA adapter scale must be a finite number, got NaN.',
      'LoRA adapter scale 1e40 is outside the 32-bit float range.',
      'LoRA adapter source must be a URL string, an ArrayBuffer or a typed array.',
      'Next-token candidates must be an array or typed array of token ids.',
      'Next-token candidates[0] is 2147483648; expected a 32-bit integer.',
      'Next-token scoring prompt must be a string.',
      'Next-token topK is 2147483648; expected a 32-bit integer.',
    ]) {
      for (final name in ['RangeError', 'TypeError', 'Error']) {
        final error = JSObject()
          ..setProperty('name'.toJS, name.toJS)
          ..setProperty('message'.toJS, message.toJS);
        expect(
          webGpuBridgeRequestError(error),
          isA<LlamaArgumentException>(),
          reason: message,
        );
        error.setProperty('message'.toJS, 'GPU dispatch failed: $message'.toJS);
        expect(webGpuBridgeRequestError(error), isNull);
        error.setProperty('message'.toJS, message.toJS);
        error.setProperty('name'.toJS, 'RuntimeError'.toJS);
        expect(webGpuBridgeRequestError(error), isNull);
      }
    }
  });
}
