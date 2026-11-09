import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/services/generated_image_files.dart';

void main() {
  test('resolves a generated image after the app container moves', () {
    final storage = GeneratedImageFiles(Directory('/new/Documents'));
    const original = '/old/Documents/attachments/generated-image-abcdef.png';
    expect(
      storage.resolvePath(original),
      '/new/Documents/attachments/generated-image-abcdef.png',
    );
    const userAttachment = '/old/Documents/attachments/photo.png';
    expect(storage.resolvePath(userAttachment), userAttachment);
    const outsideAttachments = '/old/Documents/generated-image-abcdef.png';
    expect(storage.resolvePath(outsideAttachments), outsideAttachments);
  });

  test('publishes a completed image under the attachment directory', () async {
    final directory = await Directory.systemTemp.createTemp(
      'generated-images-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = GeneratedImageFiles(directory);
    final bytes = Uint8List.fromList([1, 2, 3]);

    final file = await storage.write(
      messageId: 'abcdef',
      bytes: bytes,
      extension: 'png',
      isCancelled: () => false,
    );
    expect(file?.path, endsWith('/attachments/generated-image-abcdef.png'));
    expect(await file!.readAsBytes(), bytes);
    expect(await storage.directory.list().length, 1);
  });

  for (final cancelCheck in [2, 3]) {
    test(
      'discards staging or final files when cancelled at check $cancelCheck',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'generated-images-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final storage = GeneratedImageFiles(directory);
        var checks = 0;

        final file = await storage.write(
          messageId: 'abcdef',
          bytes: Uint8List.fromList([1, 2, 3]),
          extension: 'png',
          isCancelled: () => ++checks >= cancelCheck,
        );
        expect(file, isNull);
        expect(await storage.directory.list().isEmpty, isTrue);
      },
    );
  }
}
