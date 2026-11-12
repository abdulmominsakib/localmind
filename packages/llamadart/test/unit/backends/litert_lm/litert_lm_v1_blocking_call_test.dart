@TestOn('vm && (mac-os || linux)')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_blocking_call.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DynamicLibrary library;
  int count(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  void mode(int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_async_mode',
      )(value);
  late Pointer<Void> settings;
  late Pointer<Utf8> model;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('v1_create_scope_');
    final path =
        '${directory.path}/fixture.${Platform.isMacOS ? 'dylib' : 'so'}';
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
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(() {
    library.lookupFunction<Void Function(), void Function()>(
      'fixture_async_reset',
    )();
    model = '/secret/models/m.litertlm'.toNativeUtf8(allocator: calloc);
    final out = calloc<Pointer<Void>>();
    try {
      final status = library
          .lookupFunction<
            Int Function(
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Pointer<Void>>,
            ),
            int Function(
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Pointer<Void>>,
            )
          >(
            'litert_lm_engine_settings_create',
          )(model, nullptr, nullptr, nullptr, out);
      expect(status, 0);
      settings = out.value;
    } finally {
      calloc.free(out);
    }
  });
  tearDown(() {
    library.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)
    >('litert_lm_engine_settings_delete')(settings);
    calloc.free(model);
    expect(count('live'), 0);
  });
  Future<LiteRtLmV1CreateResult> create() async {
    final errors = liteRtLmV1ErrorAddressesForLibrary(library);
    final result = await runLiteRtLmV1CreateFromConfig(
      createAddress: library.lookup<Void>('litert_lm_engine_create').address,
      configAddress: settings.address,
      deleteAddress: library.lookup<Void>('litert_lm_engine_delete').address,
      errors: errors,
      diagnosticPaths: ['/secret/models/m.litertlm', '/secret/cache'],
    );
    expect(result.error, isNull);
    return result.value!;
  }

  for (final missing in ['create', 'config', 'delete', 'message', 'clear']) {
    test(
      'null $missing address refuses before calling native creation',
      () async {
        final errors = liteRtLmV1ErrorAddressesForLibrary(library);
        final completion = await runLiteRtLmV1CreateFromConfig(
          createAddress: missing == 'create'
              ? 0
              : library.lookup<Void>('litert_lm_engine_create').address,
          configAddress: missing == 'config' ? 0 : settings.address,
          deleteAddress: missing == 'delete'
              ? 0
              : library.lookup<Void>('litert_lm_engine_delete').address,
          errors: (
            message: missing == 'message' ? 0 : errors.message,
            clear: missing == 'clear' ? 0 : errors.clear,
          ),
        );
        expect(
          completion.error,
          missing == 'message' || missing == 'clear'
              ? isA<LlamaUnsupportedException>()
              : isA<LlamaStateException>(),
        );
        expect(count('async_calls'), 0);
        expect(count('live'), 1);
      },
    );
  }

  test('signed error addresses reconstruct without changing their bits', () {
    // Construct only: these opaque synthetic function pointers must not run.
    final addresses = (message: 0xb400000000001230, clear: 0xb400000000004560);
    expect(addresses.message, isNegative);
    expect(
      Pointer<Void>.fromAddress(addresses.message).address,
      addresses.message,
    );
    expect(() => liteRtLmV1LastErrorFromAddresses(addresses), returnsNormally);
  });

  test(
    'status/out creation transfers one owner after native completion',
    () async {
      final result = await create();
      expect(result.status, 0);
      expect(result.ownerAddress, isPositive);
      expect(result.nativeError, isNull);
      expect(count('live'), 2);
      library.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('litert_lm_engine_delete')(
        Pointer<Void>.fromAddress(result.ownerAddress),
      );
    },
  );
  test(
    'canonical message/clear TLS copy precedes partial cleanup and uses returned status',
    () async {
      mode(3);
      expect(library.providesSymbol('litert_lm_get_last_error_code'), isFalse);
      final result = await create();
      expect(result.status, 9);
      expect(result.ownerAddress, 0);
      expect(result.nativeError, contains('worker engine failure'));
      expect(result.nativeError, contains('FAILED_PRECONDITION (9)'));
      for (final secret in [
        '/secret/models',
        '/secret/cache',
        'user:secret',
        'token=private',
        'cleanup overwrote',
        'main thread stale',
      ]) {
        expect(result.nativeError, isNot(contains(secret)));
      }
      expect(count('async_engines_deleted'), 1);
      expect(count('live'), 1);
    },
  );
  test(
    'extra stale legacy code getter cannot override canonical returned status',
    () async {
      final path =
          '${directory.path}/legacy-code-trap.${Platform.isMacOS ? 'dylib' : 'so'}';
      final built = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        '-DLEGACY_CODE_TRAP',
        'test/fixtures/litert_lm/c_api_v1_async_create.c',
        '-o',
        path,
      ]);
      expect(built.exitCode, 0, reason: '${built.stderr}');
      final selected = DynamicLibrary.open(path);
      final out = calloc<Pointer<Void>>();
      try {
        final created = selected
            .lookupFunction<
              Int Function(
                Pointer<Utf8>,
                Pointer<Utf8>,
                Pointer<Utf8>,
                Pointer<Utf8>,
                Pointer<Pointer<Void>>,
              ),
              int Function(
                Pointer<Utf8>,
                Pointer<Utf8>,
                Pointer<Utf8>,
                Pointer<Utf8>,
                Pointer<Pointer<Void>>,
              )
            >(
              'litert_lm_engine_settings_create',
            )(model, nullptr, nullptr, nullptr, out);
        expect(created, 0);
        selected.lookupFunction<Void Function(Int), void Function(int)>(
          'fixture_async_mode',
        )(3);
        final completion = await runLiteRtLmV1CreateFromConfig(
          createAddress: selected
              .lookup<Void>('litert_lm_engine_create')
              .address,
          configAddress: out.value.address,
          deleteAddress: selected
              .lookup<Void>('litert_lm_engine_delete')
              .address,
          errors: liteRtLmV1ErrorAddressesForLibrary(selected),
          diagnosticPaths: ['/secret/models/m.litertlm', '/secret/cache'],
        );
        expect(completion.error, isNull);
        expect(
          completion.value!.nativeError,
          contains('FAILED_PRECONDITION (9)'),
        );
        expect(
          selected.lookupFunction<Int Function(), int Function()>(
            'fixture_async_legacy_code_reads',
          )(),
          0,
        );
      } finally {
        selected.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('litert_lm_engine_settings_delete')(out.value);
        calloc.free(out);
      }
    },
  );
  test(
    'failure without an owner reports status and preserves current-thread error',
    () async {
      mode(2);
      final result = await create();
      expect(result.status, 9);
      expect(result.ownerAddress, 0);
      expect(result.nativeError, contains('FAILED_PRECONDITION'));
    },
  );
  test('null success never reads a stale error or invents an owner', () async {
    mode(4);
    final result = await create();
    expect(result.status, 0);
    expect(result.ownerAddress, 0);
    expect(result.nativeError, isNull);
  });
}
