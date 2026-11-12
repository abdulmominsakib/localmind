@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_last_error.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

int _code = 0;
Pointer<Utf8> _message = nullptr;
int _clears = 0;

Pointer<Utf8> _getMessage() => _message;
int _getCode() => _code;
void _clear() {
  _clears += 1;
  _code = 0;
  _message = nullptr;
}

final Map<String, Pointer<Void>> _symbols = <String, Pointer<Void>>{
  LiteRtLmLastError.messageSymbol:
      Pointer.fromFunction<Pointer<Utf8> Function()>(_getMessage).cast(),
  LiteRtLmLastError.codeSymbol: Pointer.fromFunction<Int Function()>(
    _getCode,
    0,
  ).cast(),
  LiteRtLmLastError.clearSymbol: Pointer.fromFunction<Void Function()>(
    _clear,
  ).cast(),
};

void main() {
  final allocated = <Pointer<NativeType>>[];

  void record(int code, String? message) {
    _code = code;
    _message = message == null ? nullptr : message.toNativeUtf8();
    if (message != null) allocated.add(_message);
  }

  setUp(() {
    _code = 0;
    _message = nullptr;
    _clears = 0;
  });

  tearDown(() {
    for (final pointer in allocated) {
      malloc.free(pointer);
    }
    allocated.clear();
  });

  LiteRtLmLastError probeAll() => LiteRtLmLastError.probe(_symbols.lookup)!;

  test('a runtime exporting the three symbols reports the native error', () {
    final lastError = probeAll();
    record(5, 'NOT_FOUND: Failed to open model.litertlm');

    expect(
      lastError.describe(),
      'LiteRT-LM reported NOT_FOUND (5): Failed to open model.litertlm.',
    );
  });

  test('clear resets the error so a later describe reports none', () {
    final lastError = probeAll();
    record(13, 'stale failure');

    lastError.clear();

    expect(_clears, 1);
    expect(lastError.describe(), isNull);
  });

  test('a runtime without the symbols has no last-error API', () {
    expect(LiteRtLmLastError.probe((_) => null), isNull);
    // Not the process: other suites in this VM may have loaded LiteRT-LM.
    final systemLibrary = DynamicLibrary.open(
      switch (Platform.operatingSystem) {
        'macos' => '/usr/lib/libSystem.B.dylib',
        'windows' => 'kernel32.dll',
        _ => 'libc.so.6',
      },
    );
    expect(LiteRtLmLastError.probeLibrary(systemLibrary), isNull);
  });

  for (final missing in _symbols.keys) {
    test('a runtime missing $missing has no last-error API', () {
      expect(
        LiteRtLmLastError.probe(
          (symbol) => symbol == missing ? null : _symbols[symbol],
        ),
        isNull,
      );
    });
  }

  test('a code without a message reports the status alone', () {
    final lastError = probeAll();
    record(13, null);
    expect(lastError.describe(), 'LiteRT-LM reported INTERNAL (13).');

    record(13, '  ');
    expect(lastError.describe(), 'LiteRT-LM reported INTERNAL (13).');
  });

  test('no recorded code or message reports no error', () {
    final lastError = probeAll();
    expect(lastError.describe(), isNull);

    record(0, '');
    expect(lastError.describe(), isNull);
  });

  test('a message without a code is reported without a status', () {
    record(0, 'something failed');
    expect(probeAll().describe(), 'LiteRT-LM reported: something failed.');
  });

  test('an unknown code is reported by number', () {
    record(42, 'from a newer runtime');
    expect(
      probeAll().describe(),
      'LiteRT-LM reported code 42: from a newer runtime.',
    );
  });

  test('a malformed UTF-8 message is decoded leniently', () {
    final bytes = malloc<Uint8>(4);
    allocated.add(bytes);
    bytes.asTypedList(4).setAll(0, <int>[0x61, 0xff, 0x62, 0]);
    _code = 2;
    _message = bytes.cast();

    expect(probeAll().describe(), 'LiteRT-LM reported UNKNOWN (2): a\ufffdb.');
  });

  group('liteRtLmNativeErrorDetail', () {
    test('cuts known paths and their directories to base names', () {
      expect(
        liteRtLmNativeErrorDetail(
          code: 7,
          message:
              'PERMISSION_DENIED: cannot write '
              '/data/user/0/app/models/gemma.litertlm.xnnpack_cache and '
              '/data/user/0/app/models/tokenizer.bin for '
              '/data/user/0/app/models/gemma.litertlm',
          paths: <String?>['/data/user/0/app/models/gemma.litertlm', null],
        ),
        'LiteRT-LM reported PERMISSION_DENIED (7): cannot write '
        'gemma.litertlm.xnnpack_cache and models/tokenizer.bin for '
        'gemma.litertlm.',
      );
    });

    test('redacts URL credentials and signed query values', () {
      final detail = liteRtLmNativeErrorDetail(
        code: 3,
        message:
            'INVALID_ARGUMENT: bad source '
            'https://user:secret@example.com/model.litertlm?token=abc123def456',
      );

      expect(detail, isNot(contains('secret')));
      expect(detail, isNot(contains('abc123def456')));
      expect(detail, contains('https://example.com/model.litertlm'));
    });

    test('collapses whitespace runs to single spaces', () {
      expect(
        liteRtLmNativeErrorDetail(
          code: 13,
          message: ' INTERNAL: first line\n\n  second\tline \r\n',
        ),
        'LiteRT-LM reported INTERNAL (13): first line second line.',
      );
    });

    test('ends with a single sentence stop', () {
      for (final (message, expected) in <(String, String)>[
        ('done.', 'done.'),
        ('done!', 'done!'),
        ('done?', 'done?'),
        ('failed:', 'failed.'),
        ('failed: ;', 'failed.'),
        ('failed,', 'failed.'),
        (':', ''),
      ]) {
        expect(
          liteRtLmNativeErrorDetail(code: 2, message: message),
          expected.isEmpty
              ? 'LiteRT-LM reported UNKNOWN (2).'
              : 'LiteRT-LM reported UNKNOWN (2): $expected',
          reason: message,
        );
      }
    });

    test('cuts a path written with the other separator', () {
      const posix = '/srv/secret/models/gemma.litertlm';
      const windows = r'C:\Users\secret\models\gemma.litertlm';
      for (final (known, written) in <(String, String)>[
        (posix, r'\srv\secret\models\gemma.litertlm'),
        (windows, 'C:/Users/secret/models/gemma.litertlm'),
        (windows, windows),
      ]) {
        if (known == windows && !Platform.isWindows) {
          continue;
        }
        final detail = liteRtLmNativeErrorDetail(
          code: 5,
          message: 'open($written) failed',
          paths: <String>[known],
        );
        expect(
          detail,
          'LiteRT-LM reported NOT_FOUND (5): open(gemma.litertlm) '
          'failed.',
        );
      }
    });

    test('cuts the resolved path of a symbolic link with either '
        'separator', () async {
      final root = await Directory.systemTemp.createTemp('litert_last_error_');
      addTearDown(() => root.delete(recursive: true));
      final real = await Directory(
        path.join(root.path, 'secret_real'),
      ).create();
      final link = await Link(
        path.join(root.path, 'secret_link'),
      ).create(real.path);
      final resolved = real.resolveSymbolicLinksSync();
      File(path.join(resolved, 'present.litertlm')).writeAsStringSync('x');

      for (final model in <String>['present.litertlm', 'missing.litertlm']) {
        for (final directory in <String>{
          resolved,
          resolved.replaceAll(r'\', '/'),
        }) {
          final separator = directory == resolved ? path.separator : '/';
          final detail = liteRtLmNativeErrorDetail(
            code: 5,
            message:
                'open $directory$separator$model and '
                '$directory${separator}other.bin failed',
            paths: <String>[path.join(link.path, model)],
          );
          expect(
            detail,
            'LiteRT-LM reported NOT_FOUND (5): open $model and '
            'secret_link${separator}other.bin failed.',
            reason: '$model in $directory',
          );
        }
      }
    });

    test('cuts a path containing whitespace runs before collapsing them', () {
      for (final model in <String>[
        '/Users/alice/My  Models/secret_dir/gemma.litertlm',
        '/srv/a\tb/secret_dir/gemma.litertlm',
        '/srv/a \n b/secret_dir/gemma.litertlm',
      ]) {
        final detail = liteRtLmNativeErrorDetail(
          code: 5,
          message: 'open $model  failed\n',
          paths: <String>[model],
        );
        expect(
          detail,
          'LiteRT-LM reported NOT_FOUND (5): open gemma.litertlm failed.',
          reason: model,
        );
      }
    });
  });
}

extension on Map<String, Pointer<Void>> {
  Pointer<Void>? lookup(String symbol) => this[symbol];
}
