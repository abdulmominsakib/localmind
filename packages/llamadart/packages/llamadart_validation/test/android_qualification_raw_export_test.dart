import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart_validation/src/android_qualification_raw_export.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('raw-export-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('retained JSON journal recovers invalid UTF8 and multiple chunks', () {
    final original = List<int>.generate(80003, (i) => i % 256);
    Directory('${root.path}/child').createSync();
    File('${root.path}/child/stderr.log').writeAsBytesSync(original);
    File('${root.path}/empty').writeAsBytesSync([]);
    final journal = File('${root.path}/diagnostic.jsonl');
    expect(
      exportAndroidQualificationRaw(
        root,
        ['child/stderr.log', 'empty'],
        (row) => journal.writeAsStringSync(
          '${jsonEncode(row)}\n',
          mode: FileMode.append,
          flush: true,
        ),
      ),
      isTrue,
    );
    // Only the journal survives the simulated provider export.
    File('${root.path}/child/stderr.log').deleteSync();
    File('${root.path}/empty').deleteSync();
    final rows = journal
        .readAsLinesSync()
        .map((s) => jsonDecode(s) as Map)
        .toList();
    final starts = rows.where((r) => r['event'] == 'raw_file_start').toList();
    expect(starts.length, 2);
    expect(starts.first['bytes'], original.length);
    expect(starts.first['sha256'], sha256.convert(original).toString());
    expect(starts.first['chunks'], 4);
    final chunks = rows.where((r) => r['event'] == 'raw_file_chunk').toList();
    expect(chunks.map((r) => r['index']), [0, 1, 2, 3]);
    final recovered = chunks
        .expand((r) => base64Decode(r['base64'] as String))
        .toList();
    expect(recovered, original);
    final end = rows.firstWhere((r) => r['event'] == 'raw_file_end');
    expect(end['sha256'], sha256.convert(recovered).toString());
    expect(end['bytes'], recovered.length);
    expect(rows.last['complete'], isTrue);
    expect((rows.last['files'] as List).length, 2);
  });

  test('missing and oversized files make export incomplete', () {
    final f = File('${root.path}/large').openSync(mode: FileMode.write);
    f.truncateSync(4 * 1024 * 1024 + 1);
    f.closeSync();
    final rows = <Map<String, dynamic>>[];
    expect(
      exportAndroidQualificationRaw(root, ['missing', 'large'], rows.add),
      isFalse,
    );
    expect(rows.where((r) => r['event'] == 'raw_file_error').length, 2);
    expect(rows.last['complete'], isFalse);
    expect(rows.last['files'], isEmpty);
  });

  test('symlinks and path traversal cannot export unrelated files', () {
    File('${root.path}/actual').writeAsStringSync('private');
    Link('${root.path}/link').createSync('${root.path}/actual');
    final rows = <Map<String, dynamic>>[];
    expect(exportAndroidQualificationRaw(root, ['link'], rows.add), isFalse);
    expect(
      () => exportAndroidQualificationRaw(root, ['../actual'], rows.add),
      throwsFormatException,
    );
  });

  test('journal write failure cannot produce a complete envelope', () {
    File('${root.path}/stderr').writeAsStringSync('raw');
    final rows = <Map<String, dynamic>>[];
    expect(
      () => exportAndroidQualificationRaw(root, ['stderr'], (row) {
        if (row['event'] == 'raw_file_chunk') throw StateError('disk full');
        rows.add(row);
      }),
      throwsStateError,
    );
    expect(rows.any((r) => r['event'] == 'raw_export_end'), isFalse);
  });
}
