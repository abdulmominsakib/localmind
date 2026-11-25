import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../exceptions.dart';

const List<int> _pngSignature = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// Encodes row-major 8-bit grayscale (1), RGB (3) or RGBA (4) [pixels] as a
/// PNG. Throws [LlamaImageGenerationException] when the buffer does not match
/// the dimensions.
Uint8List encodePng({
  required int width,
  required int height,
  required int channels,
  required Uint8List pixels,
}) {
  final colorType = switch (channels) {
    1 => 0,
    3 => 2,
    4 => 6,
    _ => throw LlamaImageGenerationException(
      'PNG encoding supports 1, 3 or 4 channels.',
      channels,
    ),
  };
  if (width <= 0 || height <= 0) {
    throw LlamaImageGenerationException(
      'PNG encoding needs a positive width and height.',
      '${width}x$height',
    );
  }
  final rowBytes = width * channels;
  if (pixels.length != rowBytes * height) {
    throw LlamaImageGenerationException(
      'Pixel buffer length does not match ${width}x$height with $channels '
      'channels.',
      pixels.length,
    );
  }

  // Each scanline starts with filter type 0 (None).
  final scanlines = Uint8List((rowBytes + 1) * height);
  for (var y = 0; y < height; y++) {
    scanlines.setRange(
      y * (rowBytes + 1) + 1,
      (y + 1) * (rowBytes + 1),
      pixels,
      y * rowBytes,
    );
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, colorType);

  final out = BytesBuilder(copy: false)..add(_pngSignature);
  _writeChunk(out, 'IHDR', header.buffer.asUint8List());
  _writeChunk(out, 'IDAT', const ZLibEncoder().encodeBytes(scanlines));
  _writeChunk(out, 'IEND', Uint8List(0));
  return out.takeBytes();
}

void _writeChunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final crc = _crc32(_crc32(0xFFFFFFFF, typeBytes), data) ^ 0xFFFFFFFF;
  out
    ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
    ..add(typeBytes)
    ..add(data)
    ..add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

int _crc32(int crc, Uint8List bytes) {
  var c = crc;
  for (final byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return c;
}
