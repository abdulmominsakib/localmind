@TestOn('vm && (mac-os || linux)')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:test/test.dart';

Future<String> _compileFixture(
  Directory dir,
  String name,
  List<String> defines,
) async {
  final library = '${dir.path}/$name.${Platform.isMacOS ? 'dylib' : 'so'}';
  final result = await Process.run('cc', [
    '-shared',
    '-fPIC',
    ...defines,
    'test/fixtures/litert_lm/generation_controls.c',
    '-o',
    library,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return library;
}

void main() {
  late Directory dir;
  late String reporting;
  late String abiZero;
  late String futureAbi;
  late String noGetter;
  late String noAbi;
  late String blocking;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('litert_finish_reason_');
    reporting = await _compileFixture(dir, 'reporting', [
      '-DWITH_STREAM_PROXY',
      '-DFINISH_REASON_ABI=1',
    ]);
    abiZero = await _compileFixture(dir, 'abi_zero', [
      '-DWITH_STREAM_PROXY',
      '-DFINISH_REASON_ABI=0',
    ]);
    futureAbi = await _compileFixture(dir, 'future_abi', [
      '-DWITH_STREAM_PROXY',
      '-DFINISH_REASON_ABI=2',
    ]);
    noGetter = await _compileFixture(dir, 'no_getter', [
      '-DWITH_STREAM_PROXY',
      '-DFINISH_REASON_ABI=1',
      '-DOMIT_FINISH_REASON_GETTER',
    ]);
    noAbi = await _compileFixture(dir, 'no_abi', ['-DWITH_STREAM_PROXY']);
    blocking = await _compileFixture(dir, 'blocking', [
      '-DFINISH_REASON_ABI=1',
    ]);
  });

  tearDownAll(() => dir.delete(recursive: true));

  Future<LiteRtLmRuntimeClient> open(String library) async {
    final client = LiteRtLmRuntimeClient(libraryPath: library);
    addTearDown(client.dispose);
    await client.initialize(
      modelPath: '${dir.path}/model.litertlm',
      backend: 'cpu',
    );
    client.createConversation(npuBackend: true);
    return client;
  }

  void setFinishReason(String library, int value) =>
      DynamicLibrary.open(
        library,
      ).lookupFunction<Void Function(Int32), void Function(int)>(
        'fixture_set_finish_reason',
      )(value);

  const message = '{"role":"user","content":[{"type":"text","text":"Hello"}]}';

  test('reports finish reasons only for an understood ABI with its reader', () {
    for (final (library, supported) in [
      (reporting, true),
      (abiZero, false),
      (futureAbi, false),
      (noGetter, false),
      (noAbi, false),
      (blocking, false),
    ]) {
      final client = LiteRtLmRuntimeClient(libraryPath: library);
      expect(client.supportsFinishReasons, supported, reason: library);
    }
  });

  test('the service probes a fresh client of the runtime for finish '
      'reasons', () {
    for (final (library, supported) in [
      (reporting, true),
      (abiZero, false),
      (futureAbi, false),
      (noAbi, false),
      ('${Directory.systemTemp.path}/missing_litert_lm.dylib', false),
    ]) {
      final service = LiteRtLmService(
        clientFactory: () => throw StateError(
          'the probe must not create '
          'the generation client',
        ),
        finishReasonProbeLibraryPath: library,
      );
      try {
        expect(service.reportsFinishReasons(), supported, reason: library);
      } finally {
        service.dispose();
      }
    }
  });

  test('a runtime that fails to load reports no finish reasons', () {
    final client = LiteRtLmRuntimeClient(
      libraryPath: '${Directory.systemTemp.path}/missing_litert_lm.dylib',
    );

    expect(client.supportsFinishReasons, isFalse);
  });

  test('looks the reader up only behind an understood ABI', () {
    for (final (library, found) in [
      (reporting, true),
      (abiZero, false),
      (futureAbi, false),
      (noGetter, false),
      (noAbi, false),
    ]) {
      expect(
        liteRtLmFinishReasonReader(DynamicLibrary.open(library)) != null,
        found,
        reason: library,
      );
    }
  });

  for (final reason in LiteRtLmFinishReason.values) {
    test(
      'reads ${reason.name} from the proxy before the stream closes',
      () async {
        final client = await open(reporting);
        setFinishReason(reporting, reason.index);

        final text = await client.generateMessageJson(message).join();

        expect(text, 'ok');
        expect(client.lastFinishReason, reason);
      },
    );
  }

  test('reads a cancellation that ends the stream with an error', () async {
    final client = await open(reporting);
    setFinishReason(reporting, LiteRtLmFinishReason.length.index);
    DynamicLibrary.open(
      reporting,
    ).lookupFunction<Void Function(), void Function()>('fixture_cancel_next')();

    expect(await client.generateMessageJson(message).join(), isEmpty);
    expect(client.lastFinishReason, LiteRtLmFinishReason.cancelled);
  });

  test('clears the previous reason when a send starts', () async {
    final client = await open(reporting);
    setFinishReason(reporting, LiteRtLmFinishReason.length.index);
    await client.generate('Hi').drain<void>();
    expect(client.lastFinishReason, LiteRtLmFinishReason.length);

    final stream = client.generate('Hi');
    expect(client.lastFinishReason, isNull);
    await stream.drain<void>();
  });

  for (final (name, library) in [
    ('ABI 0', () => abiZero),
    ('a newer ABI', () => futureAbi),
    ('no reader', () => noGetter),
    ('no ABI export', () => noAbi),
    ('a blocking send', () => blocking),
  ]) {
    test('reports no reason for $name', () async {
      final client = await open(library());
      if (library() != blocking) {
        setFinishReason(library(), LiteRtLmFinishReason.length.index);
      }

      expect(await client.generateMessageJson(message).join(), 'ok');
      expect(client.lastFinishReason, isNull);
    });
  }
}
