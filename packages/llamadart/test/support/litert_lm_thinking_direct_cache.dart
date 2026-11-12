import 'dart:io';

/// Prepares a private cache before direct native creation, which cannot mkdir.
/// The outer qualification scratch owner retains it until the child exits.
Directory createThinkingDirectCache(Directory scratch) {
  final root = Directory(scratch.resolveSymbolicLinksSync());
  final cache = root.createTempSync('direct-cache-');
  try {
    final probe = File('${cache.path}/.writable-check');
    probe.writeAsBytesSync(const [0x51], flush: true);
    probe.deleteSync();
    return cache;
  } on Object {
    cache.deleteSync(recursive: true);
    rethrow;
  }
}
