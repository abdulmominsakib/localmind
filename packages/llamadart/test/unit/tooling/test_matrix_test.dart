@TestOn('vm')
library;

import 'package:test/test.dart';

import '../../../tool/testing/test_matrix.dart';

void main() {
  group('test_matrix', () {
    test('has unique row ids', () {
      final ids = testMatrixRows.map((row) => row.id).toList();

      expect(ids.toSet(), hasLength(ids.length));
    });

    test('has stable essential rows for baseline PR validation', () {
      final ids = testMatrixRows.map((row) => row.id).toSet();

      expect(ids, contains('static-format-analyze'));
      expect(ids, contains('root-vm'));
      expect(ids, contains('root-chrome'));
      expect(ids, contains('coverage-lib'));
    });

    test('includes targeted local model smoke rows', () {
      final ids = testMatrixRows.map((row) => row.id).toSet();

      expect(ids, contains('gguf-chat-features-smoke'));
      expect(ids, contains('litert-lm-chat-features-smoke'));
      expect(ids, contains('native-inference-benchmark'));
      expect(ids, contains('llama-cpp-speculative-benchmark'));
      expect(ids, contains('web-mock-chat-smoke'));
      expect(ids, contains('web-real-model-smoke'));
      expect(ids, contains('webgpu-multimodal-regression'));
      expect(ids, contains('gemma4-webgpu-mem64'));
    });

    test('includes explicit platform coverage rows', () {
      final ids = testMatrixRows.map((row) => row.id).toSet();

      expect(ids, contains('linux-x64-ci-runtime'));
      expect(ids, contains('linux-arm64-runtime-smoke'));
      expect(ids, contains('windows-x64-ci-runtime'));
      expect(ids, contains('windows-arm64-hook-coverage'));
      expect(ids, contains('macos-arm64-runtime-smoke'));
      expect(ids, contains('macos-x64-runtime-smoke'));
      expect(ids, contains('ios-arm64-device-smoke'));
      expect(ids, contains('ios-simulator-smoke'));
      expect(ids, contains('android-arm64-device-smoke'));
      expect(ids, contains('android-x64-emulator-smoke'));
      expect(ids, contains('web-chrome-runtime-smoke'));
    });

    test('includes release gate for companion pub packages', () {
      final releaseTable = formatTestMatrix(tier: 'release');

      expect(releaseTable, contains('release-companion-pub-gate'));
      expect(releaseTable, contains('publish_companion_pubdev.yml'));
      expect(releaseTable, contains('pub.dev/api/packages'));
    });

    test('formats PR evidence template with matrix ids', () {
      final template = formatPrEvidenceTemplate(tier: 'essential');

      expect(template, contains('| Matrix row |'));
      expect(template, contains('`root-vm`'));
      expect(template, contains('PASS / FAIL / N/A'));
      expect(template, isNot(contains('`android-arm64-device-smoke`')));
    });

    test('formats targeted matrix table with commands', () {
      final table = formatTestMatrix(tier: 'targeted');

      expect(table, contains('| ID | Tier | Mode |'));
      expect(table, contains('gguf-chat-features-smoke'));
      expect(table, contains('llama-cpp-chat-template-smoke'));
      expect(
        table,
        contains(
          'run_local_e2e.dart --scenario llama-cpp-speculative-benchmark',
        ),
      );
      expect(
        table,
        contains(
          '--speculative-cases baseline,ngram-simple,ngram-map-k,ngram-map-k4v,'
          'ngram-mod,ngram-cache,mixed-ngram',
        ),
      );
      expect(
        table,
        contains(
          '--draft-token-max 1,2 --ngram-size-m 8,16 --benchmark-warmups 1',
        ),
      );
      expect(
        table,
        contains(
          '--ngram-cache-build-static-path /tmp/llamadart-ngram-cache.bin',
        ),
      );
      expect(
        table,
        contains('External draft-model strategies require --draft-model-path'),
      );
      expect(table, contains('bundled MTP omits it'));
      expect(table, contains('ngram-cache can use'));
      expect(table, isNot(contains('LLAMADART_MTP_BENCHMARK')));
      expect(table, isNot(contains('llama_cpp_mtp_benchmark.dart')));
      expect(table, contains('run_local_e2e.dart'));
      expect(table, isNot(contains('static-format-analyze')));
    });

    test('formats platform matrix table separately from targeted rows', () {
      final table = formatTestMatrix(tier: 'platform');

      expect(table, contains('linux-x64-ci-runtime'));
      expect(table, contains('ios-arm64-device-smoke'));
      expect(table, contains('web-chrome-runtime-smoke'));
      expect(table, isNot(contains('gguf-chat-features-smoke')));
    });
  });
}
