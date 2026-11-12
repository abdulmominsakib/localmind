@TestOn('vm && (mac-os || linux)')
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

import '../../../support/dart_script_snapshot.dart';

void main() {
  late Directory directory;
  late String path, script;
  late DynamicLibrary library;
  int count(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  void set(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_$name',
      )(value);
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('v1_async_create_');
    path = '${directory.path}/fixture.${Platform.isMacOS ? 'dylib' : 'so'}';
    final built = await Process.run('cc', [
      '-shared',
      '-fPIC',
      '-pthread',
      'test/fixtures/litert_lm/c_api_v1_async_create.c',
      '-o',
      path,
    ]);
    expect(built.exitCode, 0, reason: '${built.stderr}');
    library = DynamicLibrary.open(path);
    script = await compileDartScript(
      'test/fixtures/litert_lm_v1_async_creation.dart',
    );
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(
    () => library.lookupFunction<Void Function(), void Function()>(
      'fixture_async_reset',
    )(),
  );
  for (final mode in [2, 3, 4]) {
    test(
      'client engine failure $mode preserves typed service retry classification',
      () async {
        set('async_mode', mode);
        final client = LiteRtLmV1RuntimeClient(library);
        addTearDown(client.dispose);
        await expectLater(
          client.initialize(
            modelPath: '/secret/models/m.litertlm',
            backend: 'cpu',
            cacheDir: '/secret/cache',
            numberOfThreads: 2,
            speculativeDecoding: false,
          ),
          throwsA(
            isA<LiteRtLmEngineCreateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('engine creation failed'),
                isNot(contains('/secret/')),
              ),
            ),
          ),
        );
        expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(count('live'), 0);
        expect(count('async_settings_deleted'), 1);
      },
    );
  }
  test('settled failure retains automatic GPU-to-CPU retry behavior', () async {
    debugLiteRtLmAbiOverride = Abi.macosArm64;
    addTearDown(() => debugLiteRtLmAbiOverride = null);
    set('async_mode', 5);
    final model = File('${directory.path}/retry.litertlm')
      ..writeAsStringSync('model-free fixture');
    var attempts = 0;
    final service = LiteRtLmService(
      runtimeClientFactory: () {
        attempts++;
        return LiteRtLmV1RuntimeClient(library);
      },
      useTempCacheDir: false,
      readBundleFirstChannel: (_) => null,
      readBundleChatTemplate: (_) => null,
    );
    addTearDown(service.dispose);
    final params = ModelParams(
      contextSize: 64,
      liteRtLmCacheDir: '${directory.path}/retry-cache',
    );
    final handle = await service.loadModel(model.path, params);
    service.createContext(handle, params);
    expect(await service.tokenize(handle, 'fixture', false), isNotEmpty);
    expect(attempts, 2);
    expect(count('async_calls'), 2);
    expect(service.nativeSettlement, LiteRtLmNativeSettlement.settled);
    service.dispose();
    expect(count('live'), 0);
  });
  test(
    'missing canonical clear export refuses before native configuration',
    () async {
      final output =
          '${directory.path}/missing-clear.${Platform.isMacOS ? 'dylib' : 'so'}';
      final built = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        '-DOMIT_CLEAR_LAST_ERROR',
        'test/fixtures/litert_lm/c_api_v1_client.c',
        '-o',
        output,
      ]);
      expect(built.exitCode, 0, reason: '${built.stderr}');
      final selected = DynamicLibrary.open(output);
      final client = LiteRtLmV1RuntimeClient(selected);
      addTearDown(client.dispose);
      await expectLater(
        client.initialize(modelPath: '/fixture/model', backend: 'cpu'),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            contains('litert_lm_clear_last_error'),
          ),
        ),
      );
      expect(
        selected.lookupFunction<Int Function(), int Function()>(
          'fixture_live',
        )(),
        0,
      );
      expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);
    },
  );
  Future<Map<String, dynamic>> child(String mode, {bool retain = false}) async {
    final scratch = await Directory.systemTemp.createTemp('v1_async_child_');
    final process = await Process.start(Platform.resolvedExecutable, [
      script,
      path,
      mode,
      scratch.path,
    ]);
    final output = StringBuffer(), errors = StringBuffer();
    final received = Completer<Map<String, dynamic>>();
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          output.writeln(line);
          if (line.startsWith('ASYNC_CREATION ') && !received.isCompleted) {
            received.complete(
              jsonDecode(line.substring('ASYNC_CREATION '.length))
                  as Map<String, dynamic>,
            );
          }
        })
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(errors.write)
        .asFuture<void>();
    try {
      final result = await received.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw StateError(
          'Child $mode timed out. stdout=$output stderr=$errors',
        ),
      );
      if (retain) process.kill(ProcessSignal.sigkill);
      final code = await process.exitCode.timeout(const Duration(seconds: 3));
      if (!retain) expect(code, 0, reason: '$output\n$errors');
      return result;
    } finally {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await stdoutDone;
      await stderrDone;
      await scratch.delete(recursive: true);
    }
  }

  test(
    'actual native barrier permits timer progress and forbids early disposal',
    () async {
      final result = await child('responsive');
      expect(result['timerProgressed'], isTrue);
      expect(result['live'], 0);
      expect(result['settingsDeleted'], 1);
      expect(result['engineCalls'], 1);
    },
  );
  for (final mode in ['lost-before', 'lost-after']) {
    test(
      '$mode retains settings/library and refuses native-family disposal',
      () async {
        final result = await child(mode, retain: true);
        expect(result['state'], 'quarantined');
        expect(result['settingsDeleted'], 0);
        expect(result['live'], mode == 'lost-before' ? 1 : 2);
      },
    );
  }
  test(
    'service retains model/cache lease and suppresses retries after lost creation',
    () async {
      final result = await child('service-lost', retain: true);
      expect(result['state'], 'quarantined');
      expect(result['leaseFiles'], 2);
      expect(result['factoryCalls'], 1);
      expect(result['modelLinkRetained'], isTrue);
      expect(result['settingsDeleted'], 0);
    },
  );
}
