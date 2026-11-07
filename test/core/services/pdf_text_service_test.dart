import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/services/pdf_text_service.dart';

void main() {
  test(
    'lazy initialization is shared and document reads never overlap',
    () async {
      final dir = await Directory.systemTemp.createTemp('pdf-service-test');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File('${dir.path}/document.pdf').writeAsString('fake');
      var initCalls = 0;
      var reads = 0;
      final firstRead = Completer<void>();
      final service = PdfTextService(
        initialize: () async {
          initCalls++;
        },
        extract: (_) async {
          reads++;
          if (reads == 1) await firstRead.future;
          return 'text';
        },
      );
      expect(initCalls, 0);
      final first = service.read(file.path);
      final second = service.read(file.path);
      await pumpEventQueue();
      expect(initCalls, 1);
      expect(reads, 1);
      firstRead.complete();
      expect(await Future.wait([first, second]), ['text', 'text']);
      expect(initCalls, 1);
      expect(reads, 2);
    },
  );

  test('failed document does not poison subsequent extraction', () async {
    final dir = await Directory.systemTemp.createTemp('pdf-service-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/document.pdf').writeAsString('fake');
    var calls = 0;
    final service = PdfTextService(
      initialize: () async {},
      extract: (_) async {
        if (++calls == 1) throw StateError('invalid document');
        return 'next document';
      },
    );
    expect(await service.read(file.path), isNull);
    expect(await service.read(file.path), 'next document');
  });
}
