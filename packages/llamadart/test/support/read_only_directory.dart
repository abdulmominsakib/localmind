import 'dart:io';

import 'package:test/test.dart';

/// Removes write permission from [directory] until the current test ends.
///
/// Returns whether that stops this process creating files there, which it
/// does not for root.
bool makeReadOnly(Directory directory) {
  Process.runSync('chmod', ['a-w', directory.path]);
  addTearDown(() => Process.runSync('chmod', ['u+w', directory.path]));
  try {
    File('${directory.path}/write_probe')
      ..createSync()
      ..deleteSync();
    return false;
  } on FileSystemException {
    return true;
  }
}
