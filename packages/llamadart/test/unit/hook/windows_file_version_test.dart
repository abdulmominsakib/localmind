@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:llamadart/src/hook/windows_file_version.dart';
import 'package:test/test.dart';

import '../../support/windows_version_resource.dart';

void main() {
  test('reads the VS_FIXEDFILEINFO file version', () {
    expect(windowsFileVersion(windowsDllWithVersion((14, 51, 36247, 0))), (
      14,
      51,
      36247,
      0,
    ));
    expect(
      windowsFileVersion(windowsDllWithVersion((14, 52, 1, 3), label: 'a')),
      (14, 52, 1, 3),
    );
  });

  test('skips a VS_VERSION_INFO string that heads no fixed file info', () {
    final key = [
      for (final unit in 'VS_VERSION_INFO\u0000'.codeUnits) ...[unit, 0],
    ];
    final bytes = Uint8List.fromList([
      ...key,
      ...List.filled(20, 0),
      ...windowsDllWithVersion((14, 44, 35211, 0)),
    ]);
    expect(windowsFileVersion(bytes), (14, 44, 35211, 0));
  });

  test('reads fixed file info that follows the key without padding', () {
    final key = [
      for (final unit in 'VS_VERSION_INFO\u0000'.codeUnits) ...[unit, 0],
    ];
    final fixedInfo = ByteData(16)
      ..setUint32(0, 0xFEEF04BD, Endian.little)
      ..setUint32(8, 14 << 16 | 50, Endian.little)
      ..setUint32(12, 35710 << 16, Endian.little);
    final bytes = Uint8List.fromList([
      ...key,
      ...fixedInfo.buffer.asUint8List(),
      ...List.filled(8, 0),
    ]);
    expect(windowsFileVersion(bytes), (14, 50, 35710, 0));
  });

  test('a resource cut off inside its fixed file info has no version', () {
    final key = [
      for (final unit in 'VS_VERSION_INFO\u0000'.codeUnits) ...[unit, 0],
    ];
    final signature = ByteData(4)..setUint32(0, 0xFEEF04BD, Endian.little);
    expect(
      windowsFileVersion(
        Uint8List.fromList([...key, ...signature.buffer.asUint8List()]),
      ),
      isNull,
    );
    expect(windowsFileVersion(Uint8List.fromList(key)), isNull);
  });

  test('a file without a version resource has no version', () {
    expect(
      windowsFileVersion(Uint8List.fromList('fake-x.dll'.codeUnits)),
      isNull,
    );
    expect(windowsFileVersion(Uint8List(0)), isNull);
  });

  test('compares versions field by field', () {
    expect(
      isNewerWindowsFileVersion((14, 51, 0, 0), (14, 50, 99999, 9)),
      isTrue,
    );
    expect(
      isNewerWindowsFileVersion((14, 51, 36247, 1), (14, 51, 36247, 0)),
      isTrue,
    );
    expect(
      isNewerWindowsFileVersion((14, 51, 36247, 0), (14, 51, 36247, 0)),
      isFalse,
    );
    expect(
      isNewerWindowsFileVersion((14, 44, 35211, 0), (14, 51, 36247, 0)),
      isFalse,
    );
    expect(formatWindowsFileVersion((14, 51, 36247, 0)), '14.51.36247.0');
  });
}
