import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Preserves binary captures in the diagnostic journal retained by Test Lab.
/// A missing file, overflow or interrupted envelope never counts as complete.
bool exportAndroidQualificationRaw(
  Directory root,
  Iterable<String> names,
  void Function(Map<String, dynamic>) record,
) {
  const maximumFileBytes = 4 * 1024 * 1024;
  const maximumTotalBytes = 32 * 1024 * 1024;
  const chunkBytes = 24 * 1024;
  var total = 0;
  var complete = true;
  final inventory = <Map<String, dynamic>>[];
  for (final name in names.toSet().toList()..sort()) {
    if (!RegExp(r'^[a-zA-Z0-9_.-]+(?:/[a-zA-Z0-9_.-]+)?$').hasMatch(name) ||
        name.split('/').any((part) => part == '.' || part == '..')) {
      throw const FormatException('Unsafe raw capture name');
    }
    final file = File('${root.path}/$name');
    try {
      if (name.contains('/') &&
          FileSystemEntity.typeSync(file.parent.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        throw const FormatException('Invalid raw capture parent');
      }
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Missing regular raw capture');
      }
      final length = file.lengthSync();
      if (length > maximumFileBytes || total + length > maximumTotalBytes) {
        throw const FormatException('Raw capture export limit exceeded');
      }
      final bytes = file.readAsBytesSync();
      if (bytes.length != length) {
        throw const FormatException('Raw capture changed during export');
      }
      total += bytes.length;
      final digest = sha256.convert(bytes).toString();
      final count = (bytes.length + chunkBytes - 1) ~/ chunkBytes;
      record({
        'event': 'raw_file_start',
        'name': name,
        'bytes': bytes.length,
        'sha256': digest,
        'chunks': count,
      });
      for (var index = 0; index < count; index++) {
        final start = index * chunkBytes;
        final end = (start + chunkBytes).clamp(0, bytes.length);
        record({
          'event': 'raw_file_chunk',
          'name': name,
          'index': index,
          'base64': base64Encode(bytes.sublist(start, end)),
        });
      }
      final entry = {
        'name': name,
        'bytes': bytes.length,
        'sha256': digest,
        'chunks': count,
      };
      record({'event': 'raw_file_end', ...entry});
      inventory.add(entry);
    } on FileSystemException {
      complete = false;
      record({'event': 'raw_file_error', 'name': name, 'reason': 'file_io'});
    } on FormatException {
      complete = false;
      record({
        'event': 'raw_file_error',
        'name': name,
        'reason': 'invalid_capture',
      });
    }
  }
  record({
    'event': 'raw_export_end',
    'complete': complete,
    'total_bytes': total,
    'files': inventory,
  });
  return complete;
}
