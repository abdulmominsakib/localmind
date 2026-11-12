import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readAudioFile(String path, int maxBytes) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in File(path).openRead()) {
    if (bytes.length + chunk.length > maxBytes) {
      throw const FormatException('Audio exceeds the encoded byte limit.');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}
