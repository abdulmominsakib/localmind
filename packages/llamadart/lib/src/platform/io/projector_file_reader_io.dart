import 'dart:io';
import 'dart:typed_data';

/// Reads [length] bytes of the local projector file at [location] from
/// [offset]; returns fewer at its end.
Uint8List readProjectorFileRange(String location, int offset, int length) {
  final file = File(location).openSync();
  try {
    file.setPositionSync(offset);
    return file.readSync(length);
  } finally {
    file.closeSync();
  }
}
