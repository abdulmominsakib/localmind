@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes native backend overrides', () {
    expect(normalizeLiteRtLmNativeBackendOverride(null), isNull);
    expect(normalizeLiteRtLmNativeBackendOverride(''), isNull);
    expect(normalizeLiteRtLmNativeBackendOverride(' GPU '), liteRtLmGpuBackend);
    expect(normalizeLiteRtLmNativeBackendOverride('npu'), liteRtLmNpuBackend);
    expect(
      () => normalizeLiteRtLmNativeBackendOverride('directml'),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('must be cpu, gpu, or npu'),
        ),
      ),
    );
  });

  test('reports current native platform backend defaults', () {
    final available = liteRtLmAvailableNativeBackendsForCurrentPlatform();

    if (Platform.isAndroid) {
      expect(available, const <String>[
        liteRtLmCpuBackend,
        liteRtLmGpuBackend,
        liteRtLmNpuBackend,
      ]);
      expect(liteRtLmDefaultNativeBackendForCurrentPlatform(), 'gpu');
      expect(liteRtLmNativeGpuSupportedOnCurrentPlatform(), isTrue);
      return;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      expect(available, const <String>[liteRtLmCpuBackend, liteRtLmGpuBackend]);
      expect(liteRtLmDefaultNativeBackendForCurrentPlatform(), 'gpu');
      expect(liteRtLmNativeGpuSupportedOnCurrentPlatform(), isTrue);
      return;
    }

    expect(available, const <String>[liteRtLmCpuBackend]);
    expect(liteRtLmDefaultNativeBackendForCurrentPlatform(), 'cpu');
    expect(liteRtLmNativeGpuSupportedOnCurrentPlatform(), isFalse);
  });
}
