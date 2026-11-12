import 'dart:math' as math;
import 'dart:typed_data';

Uint8List embeddingToneWav() {
  const count = 16000;
  final data = ByteData(44 + count * 2);
  void label(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  label(0, 'RIFF');
  data.setUint32(4, 36 + count * 2, Endian.little);
  label(8, 'WAVE');
  label(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  label(36, 'data');
  data.setUint32(40, count * 2, Endian.little);
  for (var i = 0; i < count; i++) {
    data.setInt16(
      44 + i * 2,
      (6000 * math.sin(2 * math.pi * 440 * i / 16000)).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
