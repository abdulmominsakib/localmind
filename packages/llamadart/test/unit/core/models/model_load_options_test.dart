import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('ModelLoadOptions', () {
    test('stores all supplied values', () {
      final token = ModelDownloadCancelToken();
      final checksum = List.filled(64, 'A').join();
      final options = ModelLoadOptions(
        cachePolicy: ModelCachePolicy.refresh,
        cacheDirectory: '/cache',
        sha256: checksum,
        bearerToken: 'token',
        headers: const <String, String>{'x-test': 'true'},
        cancelToken: token,
        resume: false,
        maxRetries: 7,
      );

      expect(options.cachePolicy, ModelCachePolicy.refresh);
      expect(options.cacheDirectory, '/cache');
      expect(options.sha256, List.filled(64, 'a').join());
      expect(options.bearerToken, 'token');
      expect(options.headers, const <String, String>{'x-test': 'true'});
      expect(options.cancelToken, same(token));
      expect(options.resume, isFalse);
      expect(options.maxRetries, 7);
    });

    test('headers are immutable and copied from supplied map', () {
      final headers = <String, String>{'authorization': 'Bearer test'};
      final options = ModelLoadOptions(headers: headers);

      headers['authorization'] = 'Bearer changed';

      expect(options.headers, const <String, String>{
        'authorization': 'Bearer test',
      });
      expect(() => options.headers['x-new'] = 'value', throwsUnsupportedError);
    });

    test('rejects negative maxRetries', () {
      expect(() => ModelLoadOptions(maxRetries: -1), throwsArgumentError);
    });

    test('validates sha256 format', () {
      expect(() => ModelLoadOptions(sha256: 'abc123'), throwsArgumentError);
      expect(
        () => ModelLoadOptions(sha256: List.filled(64, 'g').join()),
        throwsArgumentError,
      );
      expect(
        () => ModelLoadOptions(sha256: List.filled(63, 'a').join()),
        throwsArgumentError,
      );
    });
  });
}
