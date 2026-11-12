import 'dart:typed_data';

Future<Uint8List> readAudioFile(String path, int maxBytes) async =>
    throw UnsupportedError('Local audio files require a native platform.');
