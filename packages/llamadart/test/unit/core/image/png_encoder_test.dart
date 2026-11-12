import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/image/png_encoder.dart';

void main() {
  test('writes a signature, IHDR, IDAT and IEND with valid CRCs', () {
    final pixels = Uint8List.fromList([
      255, 0, 0, 0, 255, 0, //
      0, 0, 255, 255, 255, 255,
    ]);

    final png = encodePng(width: 2, height: 2, channels: 3, pixels: pixels);
    final chunks = _chunks(png);

    expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(chunks.map((c) => c.type), ['IHDR', 'IDAT', 'IEND']);
    final header = ByteData.sublistView(chunks.first.data);
    expect(header.getUint32(0), 2);
    expect(header.getUint32(4), 2);
    expect(chunks.first.data.sublist(8), [8, 2, 0, 0, 0]);
    // Each scanline is filter byte 0 followed by the row.
    expect(const ZLibDecoder().decodeBytes(chunks[1].data), [
      0, 255, 0, 0, 0, 255, 0, //
      0, 0, 0, 255, 255, 255, 255,
    ]);
  });

  test('uses the PNG color type for 1, 3 and 4 channels', () {
    for (final (channels, colorType) in [(1, 0), (3, 2), (4, 6)]) {
      final png = encodePng(
        width: 1,
        height: 1,
        channels: channels,
        pixels: Uint8List(channels),
      );
      expect(_chunks(png).first.data[9], colorType, reason: '$channels');
    }
  });

  test('matches the standard CRC-32 of the IEND chunk', () {
    final png = encodePng(
      width: 1,
      height: 1,
      channels: 3,
      pixels: Uint8List(3),
    );

    expect(png.sublist(png.length - 4), [0xAE, 0x42, 0x60, 0x82]);
  });

  test('rejects a buffer that does not match the dimensions', () {
    for (final (width, height, channels, length) in [
      (2, 2, 3, 11),
      (2, 2, 2, 8),
      (0, 2, 3, 0),
    ]) {
      expect(
        () => encodePng(
          width: width,
          height: height,
          channels: channels,
          pixels: Uint8List(length),
        ),
        throwsA(isA<LlamaImageGenerationException>()),
        reason: '${width}x$height@$channels/$length',
      );
    }
  });
}

List<({String type, Uint8List data})> _chunks(Uint8List png) {
  final view = ByteData.sublistView(png);
  final chunks = <({String type, Uint8List data})>[];
  var offset = 8;
  while (offset < png.length) {
    final length = view.getUint32(offset);
    final type = String.fromCharCodes(png.sublist(offset + 4, offset + 8));
    final data = png.sublist(offset + 8, offset + 8 + length);
    final crc = view.getUint32(offset + 8 + length);
    expect(crc, _crc(png.sublist(offset + 4, offset + 8 + length)));
    chunks.add((type: type, data: data));
    offset += 12 + length;
  }
  return chunks;
}

int _crc(List<int> bytes) => getCrc32(bytes);
