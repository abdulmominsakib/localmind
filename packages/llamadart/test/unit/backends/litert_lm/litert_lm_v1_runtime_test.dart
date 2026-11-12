@TestOn('vm && (mac-os || linux)')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DynamicLibrary library;
  late void Function(int) failAt;
  late int Function() live;
  final incompatible = <String, DynamicLibrary>{};
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_v1_text_');
    final output = '${directory.path}/v1.${Platform.isMacOS ? 'dylib' : 'so'}';
    final result = await Process.run('cc', [
      '-shared',
      '-fPIC',
      'test/fixtures/litert_lm/c_api_v1_text.c',
      '-o',
      output,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    library = DynamicLibrary.open(output);
    failAt = library.lookupFunction<Void Function(Int), void Function(int)>(
      'fixture_fail',
    );
    live = library.lookupFunction<Int Function(), int Function()>(
      'fixture_live',
    );
    for (final entry in <String, List<String>>{
      'legacy': ['-DOMIT_API_VERSION'],
      'future': ['-DAPI_MAJOR=2'],
      'failed': ['-DAPI_STATUS=13'],
      'missing': [],
    }.entries) {
      final output =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        ...entry.value,
        'test/fixtures/litert_lm/c_api_version.c',
        '-o',
        output,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      incompatible[entry.key] = DynamicLibrary.open(output);
    }
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(() {
    failAt(0);
    expect(live(), 0);
  });

  for (final name in ['legacy', 'future', 'failed', 'missing']) {
    test('$name runtime refuses before incompatible operation lookup', () {
      expect(
        () => LiteRtLmV1Runtime(incompatible[name]!),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(live(), 0);
    });
  }

  test('status/out handles generate UTF8 and free every temporary', () {
    final runtime = LiteRtLmV1Runtime(library);
    runtime.load('/secret/models/m.litertlm', cacheDir: '/secret/cache');
    expect(live(), 1);
    expect(runtime.generateText('Hello 世界'), 'Hello 世界');
    expect(live(), 1);
    expect(runtime.generateText('Second'), 'Second');
    expect(live(), 1);
    runtime.dispose();
    runtime.dispose();
    expect(live(), 0);
    expect(
      () => runtime.generateText('after disposal'),
      throwsA(isA<LlamaStateException>()),
    );
  });

  test(
    'CPU load wrapper preserves measured metrics and speculation defaults',
    () {
      final runtime = LiteRtLmV1Runtime(library);
      runtime.load('/secret/models/m.litertlm', cacheDir: '/secret/cache');
      int setting(int field) =>
          library.lookupFunction<Int Function(Int), int Function(int)>(
            'fixture_value',
          )(field);
      expect(setting(0), 4096);
      expect(setting(1), 4);
      expect(setting(5), 1);
      expect(setting(7), 0);
      runtime.dispose();
      expect(live(), 0);
    },
  );

  for (final stage in [1, 2, 3]) {
    test('load failure $stage releases settings and preserves old engine', () {
      final runtime = LiteRtLmV1Runtime(library);
      runtime.load('/secret/models/m.litertlm', cacheDir: '/secret/cache');
      failAt(stage);
      expect(
        () => runtime.load(
          '/secret/models/m.litertlm',
          cacheDir: '/secret/cache',
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (e) => e.message,
            'redacted',
            isNot(contains('/secret')),
          ),
        ),
      );
      expect(live(), 1);
      failAt(0);
      expect(runtime.generateText('recovered'), 'recovered');
      runtime.dispose();
      expect(live(), 0);
    });
  }
  for (final stage in [4, 5, 6, 7, 8, 9, 10, 11, 12]) {
    test(
      'generation failure $stage frees partial objects and permits fresh session',
      () {
        final runtime = LiteRtLmV1Runtime(library);
        runtime.load('/secret/models/m.litertlm', cacheDir: '/secret/cache');
        failAt(stage);
        expect(
          () => runtime.generateText('fail'),
          throwsA(isA<LlamaException>()),
        );
        expect(live(), 1);
        failAt(0);
        expect(runtime.generateText('recovered'), 'recovered');
        runtime.dispose();
        expect(live(), 0);
      },
    );
  }
  test('invalid arguments and unloaded use avoid native objects', () {
    final runtime = LiteRtLmV1Runtime(library);
    expect(
      () => runtime.generateText('unloaded'),
      throwsA(isA<LlamaStateException>()),
    );
    expect(
      () => runtime.load('', cacheDir: '/cache'),
      throwsA(isA<LlamaArgumentException>()),
    );
    expect(live(), 0);
    runtime.dispose();
    expect(
      () => runtime.load('/model', cacheDir: '/cache'),
      throwsA(isA<LlamaStateException>()),
    );
  });
}
