import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/utils/attachment_helpers.dart';

void main() {
  test('recognizes supported text documents and PDFs', () {
    expect(AttachmentHelpers.isDocumentPath('/tmp/notes.md'), isTrue);
    expect(AttachmentHelpers.isDocumentPath('/tmp/data.json'), isTrue);
    expect(AttachmentHelpers.isDocumentPath('/tmp/table.csv'), isTrue);
    expect(AttachmentHelpers.isDocumentPath('/tmp/report.PDF'), isTrue);
    expect(AttachmentHelpers.isDocumentPath('/tmp/archive.zip'), isFalse);
  });

  test('document picker extensions include PDF and common text formats', () {
    expect(
      AttachmentHelpers.supportedDocumentExtensions,
      containsAll(['txt', 'md', 'pdf', 'json', 'csv', 'yaml']),
    );
  });
}
