/// Windows DLL file versions, so the build hook keeps the newest copy of a
/// Visual C++ runtime DLL that more than one native runtime bundles.
library;

import 'dart:typed_data';

/// A `VS_FIXEDFILEINFO` file version: major, minor, build and revision.
typedef WindowsFileVersion = (int, int, int, int);

/// The file version in the `VS_VERSION_INFO` resource of the Windows image
/// [bytes], or null when it has none.
WindowsFileVersion? windowsFileVersion(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  for (
    var key = _indexOf(bytes, _versionInfoKey, 0);
    key >= 0;
    key = _indexOf(bytes, _versionInfoKey, key + 2)
  ) {
    // VS_FIXEDFILEINFO follows the key after padding to a 32-bit boundary.
    for (final info in [key + _versionInfoKey.length, key + 34]) {
      if (info + 16 > bytes.length ||
          data.getUint32(info, Endian.little) != _fixedFileInfoSignature) {
        continue;
      }
      final most = data.getUint32(info + 8, Endian.little);
      final least = data.getUint32(info + 12, Endian.little);
      return (most >> 16, most & 0xFFFF, least >> 16, least & 0xFFFF);
    }
  }
  return null;
}

/// Whether [version] is newer than [other].
bool isNewerWindowsFileVersion(
  WindowsFileVersion version,
  WindowsFileVersion other,
) {
  final a = [version.$1, version.$2, version.$3, version.$4];
  final b = [other.$1, other.$2, other.$3, other.$4];
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return a[index] > b[index];
    }
  }
  return false;
}

/// Formats [version] the way Windows shows it, such as `14.51.36247.0`.
String formatWindowsFileVersion(WindowsFileVersion version) =>
    '${version.$1}.${version.$2}.${version.$3}.${version.$4}';

const int _fixedFileInfoSignature = 0xFEEF04BD;

/// `VS_VERSION_INFO` and its terminator in UTF-16LE.
final Uint8List _versionInfoKey = Uint8List.fromList([
  for (final unit in 'VS_VERSION_INFO\u0000'.codeUnits) ...[unit, 0],
]);

int _indexOf(Uint8List haystack, Uint8List needle, int start) {
  final last = haystack.length - needle.length;
  outer:
  for (var index = start; index <= last; index++) {
    for (var offset = 0; offset < needle.length; offset++) {
      if (haystack[index + offset] != needle[offset]) {
        continue outer;
      }
    }
    return index;
  }
  return -1;
}
