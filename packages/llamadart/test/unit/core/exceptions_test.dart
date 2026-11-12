import 'package:test/test.dart';
import 'package:llamadart/src/core/exceptions.dart';

void main() {
  test(
    'embedding overflow remains an inference error with optional exact count',
    () {
      final error = LlamaEmbeddingInputTooLongException(
        'too long',
        maxInputTokens: 64,
      );
      expect(error, isA<LlamaInferenceException>());
      expect(error.maxInputTokens, 64);
      expect(error.actualTokens, isNull);
      expect(
        LlamaEmbeddingInputTooLongException(
          'too long',
          maxInputTokens: 64,
          actualTokens: 65,
        ).actualTokens,
        65,
      );
    },
  );

  test('a cache entry in use is a state error that keeps its paths out of '
      'the message', () {
    final directories = <String>['/cache/model-0123456789ab'];
    final error = ModelCacheEntryInUseException(
      '1 model cache entry is in use and was not removed.',
      entryDirectories: directories,
    );
    directories.clear();

    expect(error, isA<LlamaStateException>());
    expect(error.entryDirectories, <String>['/cache/model-0123456789ab']);
    expect(() => error.entryDirectories.add('/other'), throwsUnsupportedError);
    expect(error.toString(), isNot(contains('/cache')));
  });

  group('LlamaException Tests', () {
    test('LlamaModelException properties', () {
      final ex = LlamaModelException('Fail to load', 'err_code_1');
      expect(ex.message, 'Fail to load');
      expect(ex.details, 'err_code_1');
      expect(
        ex.toString(),
        contains('LlamaException: Fail to load (err_code_1)'),
      );
    });

    test('LlamaContextException properties', () {
      final ex = LlamaContextException('Context full');
      expect(ex.message, 'Context full');
      expect(ex.details, isNull);
      expect(ex.toString(), 'LlamaException: Context full');
    });
  });
}
