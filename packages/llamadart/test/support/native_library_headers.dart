import 'dart:io';

import 'package:path/path.dart' as path;

const List<List<int>> _nativeMagics = [
  [0x7f, 0x45, 0x4c, 0x46],
  [0xfe, 0xed, 0xfa, 0xce],
  [0xfe, 0xed, 0xfa, 0xcf],
  [0xce, 0xfa, 0xed, 0xfe],
  [0xcf, 0xfa, 0xed, 0xfe],
  [0xca, 0xfe, 0xba, 0xbe],
  [0x4d, 0x5a],
];

final RegExp _libraryName = RegExp(r'\.(so(\.\d+)*|dylib|dll)$');

/// Files below [root] named like a shared library whose first bytes are not an
/// ELF, Mach-O or PE header, such as the text stubs hook tests write.
List<String> findNonNativeLibraries(Directory root) {
  if (!root.existsSync()) return const [];
  return [
    for (final entity in root.listSync(recursive: true, followLinks: false))
      if (entity is File &&
          _libraryName.hasMatch(path.basename(entity.path)) &&
          !_hasNativeHeader(entity))
        entity.path,
  ]..sort();
}

bool _hasNativeHeader(File file) {
  final handle = file.openSync();
  try {
    final head = handle.readSync(4);
    return _nativeMagics.any((magic) => _startsWith(head, magic));
  } finally {
    handle.closeSync();
  }
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}
