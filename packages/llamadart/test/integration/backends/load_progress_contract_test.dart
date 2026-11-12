import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

typedef _LoadFromUrl =
    Future<int> Function(
      String url,
      ModelParams params, {
      void Function(double progress)? onProgress,
    });

void main() {
  test(
    'public backend load accepts a void progress callback and delivers fractions',
    () async {
      final LlamaBackend backend = _ProgressBackend();
      final load = backend.modelLoadFromUrl;
      expect(load, isA<_LoadFromUrl>());
      final progress = <double>[];
      void record(double value) {
        progress.add(value);
      }

      final handle = await load(
        'https://example.invalid/model.gguf',
        const ModelParams(),
        onProgress: record,
      );
      expect(handle, 42);
      expect(progress, [0.0, 0.5, 1.0]);
      expect(
        await load('https://example.invalid/model.gguf', const ModelParams()),
        42,
      );
    },
  );
}

// The generated forwarder uses the actual public interface signature.
class _ProgressBackend implements LlamaBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #modelLoadFromUrl) {
      final callback =
          invocation.namedArguments[#onProgress] as void Function(double)?;
      for (final fraction in [0.0, 0.5, 1.0]) {
        callback?.call(fraction);
      }
      return Future<int>.value(42);
    }
    return super.noSuchMethod(invocation);
  }
}
