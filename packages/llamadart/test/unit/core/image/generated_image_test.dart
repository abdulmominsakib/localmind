import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/image/generated_image.dart';

void main() {
  test('toPng encodes the pixels at the image dimensions', () {
    final image = GeneratedImage(
      width: 3,
      height: 2,
      channels: 3,
      pixels: Uint8List(18),
    );

    final png = image.toPng();

    final header = ByteData.sublistView(png, 16, 24);
    expect(header.getUint32(0), 3);
    expect(header.getUint32(4), 2);
  });

  test('toPng rejects pixels that do not match the dimensions', () {
    final image = GeneratedImage(
      width: 3,
      height: 2,
      channels: 3,
      pixels: Uint8List(17),
    );

    expect(image.toPng, throwsA(isA<LlamaImageGenerationException>()));
  });
}
