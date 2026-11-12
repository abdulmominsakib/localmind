import 'dart:typed_data';

import 'package:llamadart/src/hook/windows_file_version.dart';

/// A stand-in Windows DLL whose only content is [label] and a
/// `VS_VERSION_INFO` resource laid out as the linker writes it, carrying
/// [version].
Uint8List windowsDllWithVersion(
  WindowsFileVersion version, {
  String label = '',
}) {
  final key = [
    for (final unit in 'VS_VERSION_INFO\u0000'.codeUnits) ...[unit, 0],
  ];
  final builder = BytesBuilder()
    ..add('MZ'.codeUnits)
    ..add(List.filled(62, 0))
    ..add(label.codeUnits);
  builder.add(List.filled(-builder.length % 4, 0));
  final fixedInfo = ByteData(52)
    ..setUint32(0, 0xFEEF04BD, Endian.little)
    ..setUint32(4, 0x10000, Endian.little)
    ..setUint32(8, version.$1 << 16 | version.$2, Endian.little)
    ..setUint32(12, version.$3 << 16 | version.$4, Endian.little);
  final header = ByteData(6)
    ..setUint16(0, 6 + key.length + 2 + 52, Endian.little)
    ..setUint16(2, 52, Endian.little);
  builder
    ..add(header.buffer.asUint8List())
    ..add(key)
    ..add([0, 0])
    ..add(fixedInfo.buffer.asUint8List());
  return builder.toBytes();
}
