@TestOn('vm && (mac-os || linux)')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_legacy_service_client.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:test/test.dart';

void main() {
  test(
    'service boundary retains real legacy stream ownership and metric defaults',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'litert_legacy_client_',
      );
      final path =
          '${directory.path}/legacy.${Platform.isMacOS ? 'dylib' : 'so'}';
      final compiled = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        'test/fixtures/litert_lm/c_api_legacy_service.c',
        '-o',
        path,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      final library = DynamicLibrary.open(path);
      final LiteRtLmRuntimeClientContract client = LiteRtLmLegacyServiceClient(
        LiteRtLmRuntimeClient(libraryPath: path),
      );
      try {
        await client.initialize(
          modelPath: '${directory.path}/model.litertlm',
          backend: 'cpu',
        );
        client.createConversation(npuBackend: true);
        final output = client.generate('prompt').toList();
        final emit = library
            .lookupFunction<Void Function(Int), void Function(int)>(
              'fixture_emit',
            );
        expect(client.nativeSettlement, LiteRtLmNativeSettlement.pending);
        emit(0);
        emit(2);
        expect((await output).join(), 'late');
        expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(client.readMetrics(wallMilliseconds: 123).toJson(), {
          'inputTokens': 0,
          'outputTokens': 0,
          'timeToFirstTokenSeconds': null,
          'initSeconds': null,
          'prefillTokensPerSecond': null,
          'decodeTokensPerSecond': null,
          'wallMilliseconds': 123,
        });
        for (final symbol in ['fixture_copied_strings', 'fixture_proxies']) {
          expect(
            library.lookupFunction<Int Function(), int Function()>(symbol)(),
            0,
          );
        }
      } finally {
        client.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
